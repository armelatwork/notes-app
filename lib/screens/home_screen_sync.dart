part of 'home_screen.dart';

// ── Drive sync helpers ────────────────────────────────────────────────────────

extension _HomeSync on _HomeScreenState {
  Future<void> _pollCycle() async {
    if (_pollRunning) return;
    _pollRunning = true;
    final user = ref.read(appUserProvider);
    if (user?.type != AuthType.google) { _pollRunning = false; return; }
    try {
      final drv = DriveSyncService.instance;
      final api = await drv.getApi();
      if (api == null) return;
      await _checkStorageQuota(api);
      final appFolderId = await drv.getOrCreateAppFolder(api);
      await _runPollSync(api, appFolderId, user!.id);
    } catch (e) {
      _handlePollError(e);
    } finally {
      _pollRunning = false;
    }
  }

  Future<void> _runPollSync(
      drive.DriveApi api, String appFolderId, String userId) async {
    final lastModTime = await SyncLogService.instance.loadLogModTime(userId);
    final currentModTime =
        await SyncLogService.instance.fetchLogModifiedTime(api, appFolderId);
    if (currentModTime == null || currentModTime == lastModTime) return;
    if (mounted) {
      ref.read(syncStatusProvider.notifier).state = SyncStatus.syncing;
    }
    final lastSeq = await SyncLogService.instance.loadLastSeq(userId);
    final hasGap =
        await SyncLogService.instance.hasLogGap(api, appFolderId, lastSeq);
    if (hasGap) {
      await _fullSync(api, appFolderId, userId);
      await SyncLogService.instance.saveLogModTime(userId, currentModTime);
      return;
    }
    await _applyIncrementalSync(api, appFolderId, userId, currentModTime, lastSeq);
  }

  Future<void> _applyIncrementalSync(drive.DriveApi api, String appFolderId,
      String userId, String currentModTime, int lastSeq) async {
    final myDeviceId = await DeviceService.instance.id;
    final result = await SyncLogService.instance
        .fetchEntriesSince(api, appFolderId, lastSeq, myDeviceId);
    if (result == null) {
      if (mounted) ref.read(syncStatusProvider.notifier).state = SyncStatus.success;
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
    if (mounted) ref.read(syncStatusProvider.notifier).state = SyncStatus.success;
  }

  void _handlePollError(Object e) {
    final s = e.toString();
    final isNetworkHiccup = s.contains('Connection reset') ||
        s.contains('SocketException') ||
        s.contains('Connection refused') ||
        s.contains('Network is unreachable');
    if (isNetworkHiccup) {
      AppLogger.instance.warn('HomeScreen', 'poll skipped (network)', e);
      if (mounted) ref.read(syncStatusProvider.notifier).state = SyncStatus.idle;
    } else if (isStorageQuotaExceeded(e)) {
      if (mounted) {
        ref.read(driveStorageAlertProvider.notifier).state =
            const DriveStorageAlert(severity: DriveStorageSeverity.exceeded);
        ref.read(syncStatusProvider.notifier).state = SyncStatus.error;
      }
    } else {
      AppLogger.instance.error('HomeScreen', 'poll failed', e);
      if (mounted) ref.read(syncStatusProvider.notifier).state = SyncStatus.error;
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
        AppLogger.instance.error(
            'HomeScreen', 'entry ${entry.seq} (${entry.type}) failed', e);
      }
    }
  }

  Future<void> _applyNote(DriveSyncService drv, drive.DriveApi api,
      String appFolderId, SyncLogEntry entry) async {
    if (entry.op == 'delete' && entry.entityId != null) {
      await DatabaseService.instance.deleteNote(entry.entityId!);
    } else if (entry.entityId != null) {
      final note = await drv.downloadNote(api, appFolderId, entry.entityId!);
      if (note != null) await DatabaseService.instance.upsertNote(note);
    }
  }

  Future<void> _applyFolder(DriveSyncService drv, drive.DriveApi api,
      String appFolderId, SyncLogEntry entry) async {
    if (entry.op == 'delete' && entry.entityId != null) {
      await DatabaseService.instance.deleteFolder(entry.entityId!);
      return;
    }
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

  Future<void> _applyImage(DriveSyncService drv, SyncLogEntry entry) async {
    if (entry.filename == null) return;
    final path = await imageLocalPath(entry.filename!);
    if (entry.op == 'delete') {
      final f = File(path);
      if (await f.exists()) await f.delete();
    } else if (!await File(path).exists()) {
      await drv.downloadImage(entry.filename!, path);
    }
  }

  Future<void> _fullSync(
      drive.DriveApi api, String appFolderId, String userId) async {
    if (!EncryptionService.instance.isInitialized) return;
    final drv = DriveSyncService.instance;
    if (mounted) ref.read(syncStatusProvider.notifier).state = SyncStatus.syncing;
    try {
      await DatabaseService.instance.clearAll();
      final foldersFuture = drv.downloadFolderIndex(api, appFolderId);
      final fileIdsFuture = drv.listNoteFileIds(api, appFolderId);
      final folders = (await foldersFuture) ?? [];
      final fileIds = await fileIdsFuture;
      for (final f in folders) {
        await DatabaseService.instance.upsertFolder(f);
      }
      final notes = await Future.wait(
        fileIds.map((id) => drv.downloadNoteById(api, id)),
      );
      for (final note in notes) {
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
      if (mounted) ref.read(syncStatusProvider.notifier).state = SyncStatus.error;
    }
  }
}
