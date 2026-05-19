import 'dart:async';
import 'dart:io';
import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import '../models/app_user.dart';
import '../providers/app_provider.dart';
import '../providers/sharing_provider.dart';
import '../services/app_logger.dart';
import '../services/database_service.dart';
import '../services/device_service.dart';
import '../services/drive_sync_service.dart';
import '../services/encryption_service.dart';
import '../services/persistence_service.dart';
import '../services/sharing_service.dart';
import '../services/sync_log_service.dart';
import '../utils/image_utils.dart';
import '../widgets/folder_sidebar.dart';
import '../widgets/note_editor.dart';
import '../widgets/macos_edit_menu.dart';
import '../widgets/notes_list_panel.dart';

part 'home_screen_sync.dart';

const _kPollIntervalSeconds = 5;

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen>
    with WidgetsBindingObserver {
  bool _sessionRestored = false;
  Timer? _pollTimer;
  bool _pollRunning = false;
  bool _warningShownThisSession = false;
  StreamSubscription<Uri>? _linkSubscription;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _restoreSession();
      await _initDeepLinks();
    });
  }

  @override
  void dispose() {
    _linkSubscription?.cancel();
    _pollTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // ── Deep links ────────────────────────────────────────────────────────────

  Future<void> _initDeepLinks() async {
    final appLinks = AppLinks();
    final initialUri = await appLinks.getInitialLink();
    if (initialUri != null) await _handleDeepLink(initialUri);
    _linkSubscription = appLinks.uriLinkStream.listen(_handleDeepLink);
  }

  Future<void> _handleDeepLink(Uri uri) async {
    final segments = uri.pathSegments;
    if (segments.length < 2 || segments[0] != 'note') return;
    final noteId = segments[1];
    if (noteId.isEmpty) return;
    if (ref.read(appUserProvider)?.type != AuthType.google) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Sign in with Google to view shared notes')));
      }
      return;
    }
    try {
      final data = await SharingService.instance.fetchNote(noteId);
      if (data == null || !mounted) return;
      final note =
          await ref.read(notesProvider.notifier).openSharedNote(data);
      if (!mounted) return;
      ref.read(selectedNoteProvider.notifier).state = note;
      AppLogger.instance.info('HomeScreen', 'opened shared note $noteId');
    } catch (e) {
      AppLogger.instance.warn('HomeScreen', 'deep link open failed', e);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not open shared note')));
      }
    }
  }

  // ── App lifecycle ─────────────────────────────────────────────────────────

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _maybeStartPolling();
    } else if (state == AppLifecycleState.paused) {
      _stopPolling();
    }
  }

  void _maybeStartPolling() {
    if (ref.read(appUserProvider)?.type == AuthType.google) _startPolling();
  }

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(
      const Duration(seconds: _kPollIntervalSeconds),
      (_) => _pollCycle(),
    );
  }

  void _stopPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  // ── Session restore ────────────────────────────────────────────────────────

  Future<void> _restoreSession() async {
    if (_sessionRestored) return;
    _sessionRestored = true;
    final lastFolderId = await PersistenceService.instance.loadLastFolder();
    final lastNoteId = await PersistenceService.instance.loadLastNote();
    ref.read(selectedFolderProvider.notifier).state = lastFolderId ?? -1;
    if (lastNoteId != null) {
      final note = await DatabaseService.instance.getNote(lastNoteId);
      if (note != null && mounted) {
        ref.read(selectedNoteProvider.notifier).state = note;
      }
    }
    if (ref.read(appUserProvider)?.type == AuthType.google) {
      final local = await DatabaseService.instance.getNotes(allNotes: true);
      if (local.isEmpty) await _checkDriveForFirstSync();
      _startPolling();
    }
  }

  Future<void> _reconcileSharedNotes(Set<String> validFirestoreIds) async {
    final all = await DatabaseService.instance.getNotes(allNotes: true);
    for (final note in all) {
      if (note.sharedByEmail != null &&
          note.firestoreId != null &&
          !validFirestoreIds.contains(note.firestoreId)) {
        await _removeRevokedSharedNote(note.firestoreId!);
      }
    }
  }

  Future<void> _removeRevokedSharedNote(String firestoreId) async {
    final note =
        await DatabaseService.instance.getNoteByFirestoreId(firestoreId);
    if (note == null || note.isSharedByMe) return;
    if (ref.read(selectedNoteProvider)?.firestoreId == firestoreId) {
      ref.read(selectedNoteProvider.notifier).state = null;
    }
    await ref.read(notesProvider.notifier).deleteNote(note.id);
  }

  Future<void> _checkDriveForFirstSync() async {
    final user = ref.read(appUserProvider);
    if (user?.type != AuthType.google) return;
    // Do not bail on a stale lastModTime — if Isar is empty (either first
    // install or cleared on sign-out) we must check Drive regardless.
    final drv = DriveSyncService.instance;
    final api = await drv.getApi();
    if (api == null || !mounted) return;
    try {
      final appFolderId = await drv.getOrCreateAppFolder(api);
      final count = await drv.countNotes(api, appFolderId);
      if (count == 0 || !mounted) return;
      final syncNow = await _showFirstSyncDialog(count);
      if (syncNow == true && mounted) {
        await _fullSync(api, appFolderId, user!.id);
        final modTime = await SyncLogService.instance
            .fetchLogModifiedTime(api, appFolderId);
        if (modTime != null) {
          await SyncLogService.instance.saveLogModTime(user.id, modTime);
        }
      }
    } catch (e) {
      AppLogger.instance.error('HomeScreen', 'first-sync check failed', e);
    }
  }

  Future<bool?> _showFirstSyncDialog(int count) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Notes found on Drive'),
        content: Text(
          'Found $count note${count == 1 ? '' : 's'} in your Drive backup. '
          'Sync now, or they will appear automatically within 5 s.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Later'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Sync now'),
          ),
        ],
      ),
    );
  }

  Future<void> _checkStorageQuota(drive.DriveApi api) async {
    if (_warningShownThisSession) return;
    try {
      final about = await api.about.get($fields: 'storageQuota');
      final limit = int.tryParse(about.storageQuota?.limit ?? '');
      final usage = int.tryParse(about.storageQuota?.usage ?? '');
      if (limit == null || limit <= 0 || usage == null) return;
      final percent = (usage * 100 ~/ limit).clamp(0, 100);
      if (percent < 90 || !mounted) return;
      _warningShownThisSession = true;
      ref.read(driveStorageAlertProvider.notifier).state = DriveStorageAlert(
        severity: DriveStorageSeverity.warning,
        usagePercent: percent,
      );
    } catch (e) {
      AppLogger.instance.warn('HomeScreen', 'quota check failed', e);
    }
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    ref.listen(appUserProvider, (_, next) {
      if (next?.type == AuthType.google) { _maybeStartPolling(); } else { _stopPolling(); }
    });
    // Auto-mirror notes shared with the current user into Isar whenever
    // Firestore emits an update (new share or revoked share).
    ref.listen<AsyncValue<List<SharedNoteData>>>(
      sharedWithMeProvider,
      (prev, next) {
        final notes = next.valueOrNull;
        if (notes == null) return;
        final prevIds = (prev?.valueOrNull ?? [])
            .map((n) => n.firestoreId)
            .toSet();
        final currentIds = notes.map((n) => n.firestoreId).toSet();
        // Mirror newly shared notes into Isar.
        for (final data in notes) {
          if (!prevIds.contains(data.firestoreId)) {
            unawaited(ref.read(notesProvider.notifier).openSharedNote(data));
          }
        }
        // Delete Isar mirrors for shares that were revoked.
        for (final id in prevIds) {
          if (!currentIds.contains(id)) {
            unawaited(_removeRevokedSharedNote(id));
          }
        }
        // On first emission, reconcile orphaned mirrors from previous sessions
        // where the share was revoked while the app was closed.
        if (prev?.valueOrNull == null) {
          unawaited(_reconcileSharedNotes(currentIds));
        }
      },
    );
    ref.listen(selectedFolderProvider,
        (_, next) => PersistenceService.instance.saveLastFolder(next));
    ref.listen(selectedNoteProvider,
        (_, next) => PersistenceService.instance.saveLastNote(next?.id));
    ref.listen(pollTriggerProvider, (prev, next) {
      if (next > (prev ?? 0)) {
        ref.read(notesProvider.notifier).flushPendingPush();
        _pollCycle();
      }
    });
    _listenToStorageAlert();
    final width = MediaQuery.of(context).size.width;
    // MacOSEditMenu must always be the root widget so PlatformMenuBar's
    // element is never torn down and recreated. Swapping it in and out when
    // the window crosses the 800 px threshold causes the _lockedContext
    // assertion in platform_menu_bar.dart during rapid resizing.
    return MacOSEditMenu(
      child: width >= 800
          ? const Scaffold(
              body: Row(children: [
                FolderSidebar(),
                SizedBox(width: 260, child: NotesListPanel()),
                Expanded(child: NoteEditor()),
              ]),
            )
          : const _NarrowLayout(),
    );
  }

  void _listenToStorageAlert() {
    ref.listen(driveStorageAlertProvider, (_, alert) {
      if (alert.severity == DriveStorageSeverity.none) return;
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(SnackBar(
          content: Text(alert.message),
          duration: const Duration(hours: 24),
          action: SnackBarAction(
            label: 'Dismiss',
            onPressed: () {
              ref.read(driveStorageAlertProvider.notifier).state =
                  DriveStorageAlert.none;
              ScaffoldMessenger.of(context).clearSnackBars();
            },
          ),
        ));
    });
  }
}

// ── Narrow (mobile) layout ────────────────────────────────────────────────────

class _NarrowLayout extends ConsumerStatefulWidget {
  const _NarrowLayout();

  @override
  ConsumerState<_NarrowLayout> createState() => _NarrowLayoutState();
}

class _NarrowLayoutState extends ConsumerState<_NarrowLayout> {
  int _page = 0;
  bool _drawerOpen = false;
  final _scaffoldKey = GlobalKey<ScaffoldState>();

  void _handleBack() {
    if (_page == 1) {
      ref.read(selectedNoteProvider.notifier).state = null;
      setState(() => _page = 0);
    } else if (_drawerOpen) {
      SystemNavigator.pop();
    } else {
      _scaffoldKey.currentState?.openDrawer();
    }
  }

  @override
  Widget build(BuildContext context) {
    final selectedNote = ref.watch(selectedNoteProvider);
    if (selectedNote != null && _page == 0) {
      WidgetsBinding.instance
          .addPostFrameCallback((_) => setState(() => _page = 1));
    }
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _handleBack();
      },
      child: Scaffold(
        key: _scaffoldKey,
        onDrawerChanged: (isOpen) => setState(() => _drawerOpen = isOpen),
        appBar: AppBar(
          title: _page == 0 ? const Text('Notes') : const Text('Edit'),
          leading: _page == 1
              ? BackButton(onPressed: _handleBack)
              : null,
          actions: [
            if (_page == 0)
              IconButton(
                icon: const Icon(Icons.menu),
                onPressed: () => _scaffoldKey.currentState?.openDrawer(),
              ),
          ],
        ),
        drawer: const Drawer(child: FolderSidebar()),
        body: _page == 0 ? const NotesListPanel() : const NoteEditor(),
      ),
    );
  }
}
