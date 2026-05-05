part of 'app_provider.dart';

// ── Notes ─────────────────────────────────────────────────────────────────────

class NotesNotifier extends AsyncNotifier<List<Note>> {
  @visibleForTesting
  Timer? pushTimer;
  @visibleForTesting
  Note? pendingNote;
  @visibleForTesting
  List<String> pendingDeletedImages = [];
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
      content: '{"ops":[{"insert":"\\n"}]}',
      preview: '',
      folderId: folderId,
    );
    final id = await DatabaseService.instance.saveNote(note);
    note.id = id;
    await reload();
    return note;
  }

  /// Saves locally and schedules a 15 s push. Tracks images deleted this edit.
  Future<void> saveNote(Note note,
      {List<String> deletedImageFilenames = const []}) async {
    await DatabaseService.instance.saveNote(note);
    await reload();
    if (ref.read(appUserProvider)?.type != AuthType.google) return;
    ref.read(syncStatusProvider.notifier).state = SyncStatus.idle;
    pendingNote = note;
    pendingDeletedImages = [...pendingDeletedImages, ...deletedImageFilenames];
    pushTimer?.cancel();
    pushTimer = Timer(
        const Duration(milliseconds: _kPushDebounceMs), _flushPush);
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
    if (pendingNote?.id == id) cancelPendingPush();
    await DatabaseService.instance.deleteNote(id);
    await reload();
    if (note?.driveFileId != null &&
        ref.read(appUserProvider)?.type == AuthType.google) {
      ref.read(syncStatusProvider.notifier).state = SyncStatus.idle;
      _run(() => _pushDelete(note!));
    }
  }

  Note? cancelPendingPush() {
    pushTimer?.cancel();
    pushTimer = null;
    _moveTimer?.cancel();
    _moveTimer = null;
    _pendingMoves.clear();
    final note = pendingNote;
    pendingNote = null;
    pendingDeletedImages = [];
    return note;
  }

  /// Bypasses the debounce — used by folder cascade and sync button.
  Future<void> pushNoteNow(Note note) => _pushNoteAndImages(note, []);

  /// Flushes any pending debounce immediately (sync button / poll trigger).
  void flushPendingPush() => _flushPush();

  void _flushPush() {
    final note = pendingNote;
    final deleted = List<String>.from(pendingDeletedImages);
    pendingNote = null;
    pendingDeletedImages = [];
    if (note == null) return;
    _run(() => performPush(note, deleted));
  }

  @visibleForTesting
  Future<void> performPush(Note note, List<String> deletedImages) =>
      _pushNoteAndImages(note, deletedImages);

  void _run(Future<void> Function() task) {
    ref.read(syncStatusProvider.notifier).state = SyncStatus.syncing;
    _pushQueue = _pushQueue.then((_) => task()).then((_) {
      ref.read(syncStatusProvider.notifier).state = SyncStatus.success;
    }).catchError((Object e) {
      AppLogger.instance.error('NotesNotifier', 'push failed', e);
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
