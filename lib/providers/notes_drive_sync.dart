part of 'app_provider.dart';

// ── Drive API helpers for NotesNotifier ───────────────────────────────────────
// Pure Drive/SyncLog operations, separated from orchestration in NotesNotifier.

class _NotesDriveOps {
  final Ref _ref;
  Future<void> _queue = Future.value();

  _NotesDriveOps(this._ref);

  Future<void> get drainQueue => _queue;

  void run(Future<void> Function() task) {
    _ref.read(syncStatusProvider.notifier).state = SyncStatus.syncing;
    _queue = _queue.then((_) => task()).then((_) {
      _ref.read(syncStatusProvider.notifier).state = SyncStatus.success;
    }).catchError((Object e) {
      if (isStorageQuotaExceeded(e)) {
        _ref.read(driveStorageAlertProvider.notifier).state =
            const DriveStorageAlert(severity: DriveStorageSeverity.exceeded);
      } else if (e.toString().contains('status: 404')) {
        DriveSyncService.instance.clearCache();
        AppLogger.instance.warn(
            'NotesNotifier', 'push failed (stale folder), cache cleared', e);
      } else {
        AppLogger.instance.error('NotesNotifier', 'push failed', e);
      }
      _ref.read(syncStatusProvider.notifier).state = SyncStatus.error;
    });
  }

  Future<void> pushNoteAndImages(
      Note note, List<String> deletedImages) async {
    final drv = DriveSyncService.instance;
    final api = await drv.getApi();
    if (api == null) return;
    final appFolderId = await drv.getOrCreateAppFolder(api);
    final modTime = await drv.uploadNote(api, appFolderId, note);
    for (final fname in extractImageFilenames(note.content)) {
      final path = await imageLocalPath(fname);
      if (await File(path).exists()) {
        await drv.uploadImage(api, appFolderId, fname, path);
      }
    }
    for (final fname in deletedImages) {
      await drv.deleteImageFile(api, appFolderId, fname);
      await _appendLog(api, appFolderId,
          op: 'delete', type: 'image',
          filename: fname, modifiedTime: DateTime.now().toIso8601String());
    }
    await _appendLog(api, appFolderId,
        op: 'upsert', type: 'note',
        entityId: note.id, modifiedTime: modTime);
  }

  Future<void> pushDelete(Note note) async {
    final drv = DriveSyncService.instance;
    final api = await drv.getApi();
    if (api == null) return;
    final appFolderId = await drv.getOrCreateAppFolder(api);
    await drv.deleteNoteFile(api, note.driveFileId!);
    await _appendLog(api, appFolderId,
        op: 'delete', type: 'note',
        entityId: note.id, modifiedTime: DateTime.now().toIso8601String());
  }

  Future<void> pushMovedNotes(List<Note> notes) async {
    final drv = DriveSyncService.instance;
    final api = await drv.getApi();
    if (api == null) return;
    final appFolderId = await drv.getOrCreateAppFolder(api);
    final modTimes =
        await Future.wait(notes.map((n) => drv.uploadNote(api, appFolderId, n)));
    final deviceId = await DeviceService.instance.id;
    final userId = _ref.read(appUserProvider)?.id;
    if (userId == null) return;
    final lastSeq = await SyncLogService.instance.appendEntries(
      api, appFolderId,
      [for (var i = 0; i < notes.length; i++)
        (op: 'upsert', type: 'note', entityId: notes[i].id,
         filename: null as String?, deviceId: deviceId,
         modifiedTime: modTimes[i])],
    );
    await SyncLogService.instance.saveLastSeq(userId, lastSeq);
  }

  Future<void> _appendLog(drive.DriveApi api, String appFolderId,
      {required String op,
      required String type,
      int? entityId,
      String? filename,
      required String modifiedTime}) async {
    final deviceId = await DeviceService.instance.id;
    final userId = _ref.read(appUserProvider)?.id;
    if (userId == null) return;
    final seq = await SyncLogService.instance.appendEntry(
      api, appFolderId,
      op: op, type: type, entityId: entityId,
      filename: filename, deviceId: deviceId, modifiedTime: modifiedTime,
    );
    await SyncLogService.instance.saveLastSeq(userId, seq);
  }
}

// ── Shared note opener ────────────────────────────────────────────────────────

class _SharedNoteOpener {
  final Ref _ref;
  final Future<void> Function() _reload;
  final void Function(Note) _scheduleSync;
  // Guards against duplicate Isar records when open() is called concurrently
  // for the same firestoreId (e.g. ref.listen + user tap).
  final Map<String, Future<Note>> _cache = {};

  _SharedNoteOpener({
    required Ref ref,
    required Future<void> Function() reload,
    required void Function(Note) scheduleSync,
  })  : _ref = ref,
        _reload = reload,
        _scheduleSync = scheduleSync;

  Future<Note> open(SharedNoteData data) {
    final fid = data.firestoreId;
    if (_cache.containsKey(fid)) return _cache[fid]!;
    final future = _doOpen(data);
    _cache[fid] = future;
    future.whenComplete(() => _cache.remove(fid));
    return future;
  }

  Future<Note> _doOpen(SharedNoteData data) async {
    final existing =
        await DatabaseService.instance.getNoteByFirestoreId(data.firestoreId);
    final note = existing ??
        (Note()
          ..folderId = null
          ..createdAt = data.updatedAt
          ..firestoreId = data.firestoreId);
    final currentEmail = _ref.read(appUserProvider)?.email;
    final directSharer =
        currentEmail != null ? data.collaboratorSharedBy[currentEmail] : null;
    note
      ..title = data.title
      ..content = data.content
      ..preview = data.preview
      ..sharedByEmail = directSharer ?? data.ownerEmail
      ..updatedAt = data.updatedAt;
    await DatabaseService.instance.upsertNote(note);
    await _reload();
    if (_ref.read(appUserProvider)?.type == AuthType.google) {
      _ref.read(syncStatusProvider.notifier).state = SyncStatus.idle;
      _scheduleSync(note);
    }
    return note;
  }
}
