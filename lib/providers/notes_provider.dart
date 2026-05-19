part of 'app_provider.dart';

// ── Notes ─────────────────────────────────────────────────────────────────────

class NotesNotifier extends AsyncNotifier<List<Note>> {
  @visibleForTesting
  Timer? pushTimer;
  @visibleForTesting
  final Map<int, Note> pendingNotes = {};
  @visibleForTesting
  final Map<int, List<String>> pendingDeletedImages = {};
  final List<Note> _pendingMoves = [];
  Timer? _moveTimer;
  Future<void> _pushQueue = Future.value();

  @override
  Future<List<Note>> build() => _load();

  Future<List<Note>> _load() {
    final folderId = ref.watch(selectedFolderProvider);
    final query = ref.watch(searchQueryProvider);
    if (query.isNotEmpty) return DatabaseService.instance.searchNotes(query);
    if (folderId == -1) return DatabaseService.instance.getNotes(allNotes: true);
    return DatabaseService.instance.getNotes(folderId: folderId);
  }

  Future<void> reload() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(_load);
  }

  /// Creates an empty note locally. Timer starts only on the first edit.
  Future<Note> createNote({int? folderId}) async {
    final title = computeDefaultNoteTitle(state.valueOrNull ?? []);
    final note = Note.create(
      title: title,
      content: '[{"insert":"\\n"}]',
      preview: '',
      folderId: folderId,
    );
    final id = await DatabaseService.instance.saveNote(note);
    note.id = id;
    await reload();
    return note;
  }

  /// Saves locally and schedules a push. Title changes use 5 s; content edits 15 s.
  Future<void> saveNote(Note note,
      {List<String> deletedImageFilenames = const []}) async {
    final previousTitle = state.valueOrNull
        ?.firstWhere((n) => n.id == note.id, orElse: () => note)
        .title;
    final titleChanged = previousTitle != null && previousTitle != note.title;
    await DatabaseService.instance.saveNote(note);
    await reload();
    if (ref.read(appUserProvider)?.type != AuthType.google) return;
    ref.read(syncStatusProvider.notifier).state = SyncStatus.idle;
    pendingNotes[note.id] = note;
    pendingDeletedImages[note.id] = [
      ...(pendingDeletedImages[note.id] ?? []),
      ...deletedImageFilenames,
    ];
    pushTimer?.cancel();
    final debounce = titleChanged ? _kFastPushDebounceMs : _kPushDebounceMs;
    pushTimer = Timer(Duration(milliseconds: debounce), _flushPush);
  }

  Future<void> moveNote(Note note, int? folderId) async {
    note.folderId = folderId;
    await DatabaseService.instance.saveNote(note);
    await reload();
    if (ref.read(appUserProvider)?.type != AuthType.google) return;
    ref.read(syncStatusProvider.notifier).state = SyncStatus.idle;
    _pendingMoves.removeWhere((n) => n.id == note.id);
    _pendingMoves.add(note);
    _moveTimer?.cancel();
    _moveTimer = Timer(
        const Duration(milliseconds: _kFastPushDebounceMs), _flushMoves);
  }

  void _flushMoves() {
    final notes = List<Note>.from(_pendingMoves);
    _pendingMoves.clear();
    if (notes.isEmpty) return;
    _run(() => _pushMovedNotes(notes));
  }

  Future<void> _pushMovedNotes(List<Note> notes) async {
    final drv = DriveSyncService.instance;
    final api = await drv.getApi();
    if (api == null) return;
    final appFolderId = await drv.getOrCreateAppFolder(api);
    final modTimes = await Future.wait(
      notes.map((n) => drv.uploadNote(api, appFolderId, n)),
    );
    final deviceId = await DeviceService.instance.id;
    final userId = ref.read(appUserProvider)?.id;
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

  Future<void> deleteNote(int id) async {
    final note = await DatabaseService.instance.getNote(id);
    pendingNotes.remove(id);
    pendingDeletedImages.remove(id);
    if (pendingNotes.isEmpty) { pushTimer?.cancel(); pushTimer = null; }
    await DatabaseService.instance.deleteNote(id);
    await reload();
    if (note?.driveFileId != null &&
        ref.read(appUserProvider)?.type == AuthType.google) {
      ref.read(syncStatusProvider.notifier).state = SyncStatus.idle;
      _run(() => _pushDelete(note!));
    }
  }

  Future<Note> openSharedNote(SharedNoteData data) async {
    final existing =
        await DatabaseService.instance.getNoteByFirestoreId(data.firestoreId);
    final note = existing ?? (Note()
      ..folderId = null
      ..createdAt = data.updatedAt
      ..firestoreId = data.firestoreId);
    final currentEmail = ref.read(appUserProvider)?.email;
    final directSharer = currentEmail != null
        ? data.collaboratorSharedBy[currentEmail]
        : null;
    note
      ..title = data.title
      ..content = data.content
      ..preview = data.preview
      ..sharedByEmail = directSharer ?? data.ownerEmail
      ..updatedAt = data.updatedAt;
    await DatabaseService.instance.upsertNote(note);
    await reload();
    // Queue a Drive push so the sharing metadata survives full syncs.
    if (ref.read(appUserProvider)?.type == AuthType.google) {
      ref.read(syncStatusProvider.notifier).state = SyncStatus.idle;
      pendingNotes[note.id] = note;
      pushTimer?.cancel();
      pushTimer = Timer(
          const Duration(milliseconds: _kFastPushDebounceMs), _flushPush);
    }
    return note;
  }

  void cancelPendingPush() {
    pushTimer?.cancel();
    pushTimer = null;
    _moveTimer?.cancel();
    _moveTimer = null;
    _pendingMoves.clear();
    pendingNotes.clear();
    pendingDeletedImages.clear();
  }

  /// Bypasses the debounce — used by folder cascade and sync button.
  Future<void> pushNoteNow(Note note) => _pushNoteAndImages(note, []);

  /// Flushes any pending debounce immediately (sync button / poll trigger).
  void flushPendingPush() => _flushPush();

  void _flushPush() {
    final notes = Map<int, Note>.from(pendingNotes);
    final deleted = Map<int, List<String>>.from(pendingDeletedImages);
    pendingNotes.clear();
    pendingDeletedImages.clear();
    pushTimer = null;
    for (final entry in notes.entries) {
      final imgs = deleted[entry.key] ?? [];
      _run(() => performPush(entry.value, imgs));
    }
  }

  @visibleForTesting
  Future<void> performPush(Note note, List<String> deletedImages) =>
      _pushNoteAndImages(note, deletedImages);

  void _run(Future<void> Function() task) {
    ref.read(syncStatusProvider.notifier).state = SyncStatus.syncing;
    _pushQueue = _pushQueue.then((_) => task()).then((_) {
      ref.read(syncStatusProvider.notifier).state = SyncStatus.success;
    }).catchError((Object e) {
      if (isStorageQuotaExceeded(e)) {
        ref.read(driveStorageAlertProvider.notifier).state =
            const DriveStorageAlert(severity: DriveStorageSeverity.exceeded);
      } else {
        AppLogger.instance.error('NotesNotifier', 'push failed', e);
      }
      ref.read(syncStatusProvider.notifier).state = SyncStatus.error;
    });
  }

  Future<void> _pushNoteAndImages(
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
      await _appendLog(api, appFolderId, op: 'delete', type: 'image',
          filename: fname, modifiedTime: DateTime.now().toIso8601String());
    }
    await _appendLog(api, appFolderId, op: 'upsert', type: 'note',
        entityId: note.id, modifiedTime: modTime);
  }

  Future<void> _pushDelete(Note note) async {
    final drv = DriveSyncService.instance;
    final api = await drv.getApi();
    if (api == null) return;
    final appFolderId = await drv.getOrCreateAppFolder(api);
    await drv.deleteNoteFile(api, note.driveFileId!);
    await _appendLog(api, appFolderId, op: 'delete', type: 'note',
        entityId: note.id, modifiedTime: DateTime.now().toIso8601String());
  }

  Future<void> _appendLog(drive.DriveApi api, String appFolderId,
      {required String op,
      required String type,
      int? entityId,
      String? filename,
      required String modifiedTime}) async {
    final deviceId = await DeviceService.instance.id;
    final userId = ref.read(appUserProvider)?.id;
    if (userId == null) return;
    final seq = await SyncLogService.instance.appendEntry(
      api, appFolderId,
      op: op, type: type, entityId: entityId,
      filename: filename, deviceId: deviceId, modifiedTime: modifiedTime,
    );
    await SyncLogService.instance.saveLastSeq(userId, seq);
  }
}

final notesProvider =
    AsyncNotifierProvider<NotesNotifier, List<Note>>(NotesNotifier.new);
