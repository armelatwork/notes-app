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
import '../widgets/notes_list_panel.dart';

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
      final local =
          await DatabaseService.instance.getNotes(allNotes: true);
      if (local.isEmpty) await _checkDriveForFirstSync();
      _startPolling();
    }
  }

  Future<void> _checkDriveForFirstSync() async {
    final drv = DriveSyncService.instance;
    final api = await drv.getApi();
    if (api == null || !mounted) return;
    try {
      final appFolderId = await drv.getOrCreateAppFolder(api);
      final count = await drv.countNotes(api, appFolderId);
      if (count > 0 && mounted) await _showFirstSyncDialog(count);
    } catch (e) {
      AppLogger.instance.error('HomeScreen', 'first-sync check failed', e);
    }
  }

  Future<void> _showFirstSyncDialog(int count) async {
    final syncNow = await showDialog<bool>(
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
    if (syncNow == true && mounted) _pollCycle();
  }

  // ── Poll cycle ────────────────────────────────────────────────────────────

  Future<void> _pollCycle() async {
    final user = ref.read(appUserProvider);
    if (user?.type != AuthType.google) return;
    if (mounted) {
      ref.read(syncStatusProvider.notifier).state = SyncStatus.syncing;
    }
    try {
      final drv = DriveSyncService.instance;
      final api = await drv.getApi();
      if (api == null) {
        if (mounted) {
          ref.read(syncStatusProvider.notifier).state = SyncStatus.idle;
        }
        return;
      }
      final appFolderId = await drv.getOrCreateAppFolder(api);
      final userId = user!.id;

      final lastModTime =
          await SyncLogService.instance.loadLogModTime(userId);
      final currentModTime =
          await SyncLogService.instance.fetchLogModifiedTime(api, appFolderId);
      if (currentModTime == null || currentModTime == lastModTime) {
        if (mounted) {
          ref.read(syncStatusProvider.notifier).state = SyncStatus.success;
        }
        return;
      }

      final lastSeq = await SyncLogService.instance.loadLastSeq(userId);
      final hasGap = await SyncLogService.instance
          .hasLogGap(api, appFolderId, lastSeq);
      if (hasGap) {
        await _fullSync(api, appFolderId, userId);
        await SyncLogService.instance.saveLogModTime(userId, currentModTime);
        return;
      }

      final myDeviceId = await DeviceService.instance.id;
      final result = await SyncLogService.instance
          .fetchEntriesSince(api, appFolderId, lastSeq, myDeviceId);
      if (result == null) {
        if (mounted) {
          ref.read(syncStatusProvider.notifier).state = SyncStatus.success;
        }
        return;
      }

      if (result.entries.isNotEmpty) {
        await _applyEntries(api, appFolderId, result.entries);
        if (mounted) {
          ref.invalidate(notesProvider);
          ref.invalidate(foldersProvider);
          ref.read(noteReloadTriggerProvider.notifier).state++;
        }
      }
      await SyncLogService.instance.saveLastSeq(userId, result.maxSeq);
      await SyncLogService.instance.saveLogModTime(userId, currentModTime);
      if (mounted) {
        ref.read(syncStatusProvider.notifier).state = SyncStatus.success;
      }
    } catch (e) {
      final isNetworkHiccup = e.toString().contains('Connection reset') ||
          e.toString().contains('SocketException') ||
          e.toString().contains('Connection refused') ||
          e.toString().contains('Network is unreachable');
      if (isNetworkHiccup) {
        // Transient connectivity drop — next poll will retry silently.
        AppLogger.instance.warn('HomeScreen', 'poll skipped (network)', e);
        if (mounted) {
          ref.read(syncStatusProvider.notifier).state = SyncStatus.idle;
        }
      } else {
        AppLogger.instance.error('HomeScreen', 'poll failed', e);
        if (mounted) {
          ref.read(syncStatusProvider.notifier).state = SyncStatus.error;
        }
      }
    }
  }

  Future<void> _applyEntries(drive.DriveApi api, String appFolderId,
      List<SyncLogEntry> entries) async {
    final drv = DriveSyncService.instance;
    for (final entry in entries) {
      try {
        switch (entry.type) {
          case 'note':
            await _applyNote(drv, api, appFolderId, entry);
          case 'folder':
            await _applyFolder(drv, api, appFolderId, entry);
          case 'image':
            await _applyImage(drv, entry);
        }
      } catch (e) {
        AppLogger.instance.error('HomeScreen', 'entry ${entry.seq} (${entry.type}) failed', e);
      }
    }
  }

  Future<void> _applyNote(DriveSyncService drv, drive.DriveApi api,
      String appFolderId, SyncLogEntry entry) async {
    if (entry.op == 'delete' && entry.entityId != null) {
      await DatabaseService.instance.deleteNote(entry.entityId!);
    } else if (entry.entityId != null) {
      final note =
          await drv.downloadNote(api, appFolderId, entry.entityId!);
      if (note != null) await DatabaseService.instance.upsertNote(note);
    }
  }

  Future<void> _applyFolder(DriveSyncService drv, drive.DriveApi api,
      String appFolderId, SyncLogEntry entry) async {
    if (entry.op == 'delete' && entry.entityId != null) {
      await DatabaseService.instance.deleteFolder(entry.entityId!);
    } else {
      final folders = await drv.downloadFolderIndex(api, appFolderId);
      if (folders == null) return;
      final driveIds = folders.map((f) => f.id).toSet();
      for (final f in folders) {
        await DatabaseService.instance.upsertFolder(f);
      }
      for (final lf in await DatabaseService.instance.getFolders()) {
        if (!driveIds.contains(lf.id)) {
          await DatabaseService.instance.deleteFolder(lf.id);
        }
      }
    }
  }

  Future<void> _applyImage(DriveSyncService drv, SyncLogEntry entry) async {
    if (entry.filename == null) return;
    if (entry.op == 'delete') {
      final path = await imageLocalPath(entry.filename!);
      final f = File(path);
      if (await f.exists()) await f.delete();
    } else {
      final path = await imageLocalPath(entry.filename!);
      if (!await File(path).exists()) {
        await drv.downloadImage(entry.filename!, path);
      }
    }
  }

  // ── Full sync (first time or log gap) ─────────────────────────────────────

  Future<void> _fullSync(
      drive.DriveApi api, String appFolderId, String userId) async {
    if (!EncryptionService.instance.isInitialized) return;
    final drv = DriveSyncService.instance;
    ref.read(syncStatusProvider.notifier).state = SyncStatus.syncing;
    try {
      await DatabaseService.instance.clearAll();
      final folders =
          await drv.downloadFolderIndex(api, appFolderId) ?? [];
      for (final f in folders) {
        await DatabaseService.instance.upsertFolder(f);
      }
      final fileIds = await drv.listNoteFileIds(api, appFolderId);
      for (final fileId in fileIds) {
        final note = await drv.downloadNoteById(api, fileId);
        if (note != null) await DatabaseService.instance.upsertNote(note);
      }
      if (mounted) {
        ref.invalidate(notesProvider);
        ref.invalidate(foldersProvider);
        ref.read(syncStatusProvider.notifier).state = SyncStatus.success;
        ref.read(noteReloadTriggerProvider.notifier).state++;
      }
    } catch (e) {
      AppLogger.instance.error('HomeScreen', 'fullSync failed', e);
      if (mounted) {
        ref.read(syncStatusProvider.notifier).state = SyncStatus.error;
      }
    }
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    ref.listen(appUserProvider, (_, next) {
      if (next?.type == AuthType.google) {
        _maybeStartPolling();
      } else {
        _stopPolling();
      }
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

    final width = MediaQuery.of(context).size.width;
    if (width >= 800) {
      return const Scaffold(
        body: Row(children: [
          FolderSidebar(),
          NotesListPanel(),
          Expanded(child: NoteEditor()),
        ]),
      );
    }
    return const _NarrowLayout();
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
