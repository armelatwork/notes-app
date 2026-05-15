import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import '../models/app_user.dart';
import '../providers/app_provider.dart';
import '../services/database_service.dart';
import '../services/device_service.dart';
import '../services/drive_sync_service.dart';
import '../services/encryption_service.dart';
import '../services/app_logger.dart';
import '../services/persistence_service.dart';
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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _restoreSession());
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
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

  Future<void> _checkDriveForFirstSync() async {
    final user = ref.read(appUserProvider);
    if (user?.type != AuthType.google) return;
    final lastModTime =
        await SyncLogService.instance.loadLogModTime(user!.id);
    if (lastModTime != null) return;
    final drv = DriveSyncService.instance;
    final api = await drv.getApi();
    if (api == null || !mounted) return;
    try {
      final appFolderId = await drv.getOrCreateAppFolder(api);
      final count = await drv.countNotes(api, appFolderId);
      if (count == 0 || !mounted) return;
      final syncNow = await _showFirstSyncDialog(count);
      if (syncNow == true && mounted) {
        await _fullSync(api, appFolderId, user.id);
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

  @override
  Widget build(BuildContext context) {
    final selectedNote = ref.watch(selectedNoteProvider);
    if (selectedNote != null && _page == 0) {
      WidgetsBinding.instance
          .addPostFrameCallback((_) => setState(() => _page = 1));
    }
    return Scaffold(
      appBar: AppBar(
        title: _page == 0 ? const Text('Notes') : const Text('Edit'),
        leading: _page == 1
            ? BackButton(onPressed: () {
                ref.read(selectedNoteProvider.notifier).state = null;
                setState(() => _page = 0);
              })
            : null,
        actions: [
          if (_page == 0)
            Builder(
              builder: (ctx) => IconButton(
                icon: const Icon(Icons.menu),
                onPressed: () => Scaffold.of(ctx).openDrawer(),
              ),
            ),
        ],
      ),
      drawer: const Drawer(child: FolderSidebar()),
      body: _page == 0 ? const NotesListPanel() : const NoteEditor(),
    );
  }
}
