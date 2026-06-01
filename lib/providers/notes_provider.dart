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
  late final _driveOps = _NotesDriveOps(ref);
  late final _sharedNoteOpener = _SharedNoteOpener(
    ref: ref,
    reload: reload,
    scheduleSync: _scheduleSharedNoteSync,
  );

  @override
  Future<List<Note>> build() => _load();

  Future<List<Note>> _load() async {
    final folderId = ref.watch(selectedFolderProvider);
    final query = ref.watch(searchQueryProvider);
    if (query.isNotEmpty) return DatabaseService.instance.searchNotes(query);
    if (folderId == kFolderPinnedNotes) {
      final all = await DatabaseService.instance.getNotes(allNotes: true);
      return all.where((n) => n.isPinned).toList();
    }
    if (folderId == kFolderAllNotes) return DatabaseService.instance.getNotes(allNotes: true);
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

  Future<Note> duplicateNote(Note note) async {
    final sourceTitle = note.title.isEmpty ? 'New Note' : note.title;
    final copy = Note.create(
      title: 'Copy - $sourceTitle',
      content: note.content,
      preview: note.preview,
      folderId: note.folderId,
    );
    // Get a DB-assigned ID first, then go through saveNote so the copy is
    // added to pendingNotes and scheduled for Drive sync like any other save.
    final id = await DatabaseService.instance.saveNote(copy);
    copy.id = id;
    await saveNote(copy);
    return copy;
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

  Future<void> togglePin(int noteId) async {
    final note = await DatabaseService.instance.getNote(noteId);
    if (note == null) return;
    note.isPinned = !note.isPinned;
    await DatabaseService.instance.saveNote(note);
    await reload();
    if (ref.read(selectedNoteProvider)?.id == noteId) {
      ref.read(selectedNoteProvider.notifier).state = note;
    }
    if (ref.read(appUserProvider)?.type != AuthType.google) return;
    ref.read(syncStatusProvider.notifier).state = SyncStatus.idle;
    pendingNotes[noteId] = note;
    pushTimer?.cancel();
    pushTimer =
        Timer(const Duration(milliseconds: _kFastPushDebounceMs), _flushPush);
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
    _driveOps.run(() => _driveOps.pushMovedNotes(notes));
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
      _driveOps.run(() => _driveOps.pushDelete(note!));
    }
  }

  Future<Note> openSharedNote(SharedNoteData data) =>
      _sharedNoteOpener.open(data);

  void _scheduleSharedNoteSync(Note note) {
    pendingNotes[note.id] = note;
    pushTimer?.cancel();
    pushTimer =
        Timer(const Duration(milliseconds: _kFastPushDebounceMs), _flushPush);
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

  bool get hasPendingSync =>
      pendingNotes.isNotEmpty || _pendingMoves.isNotEmpty;

  /// Bypasses all debounce timers and waits for every queued Drive upload to
  /// complete. Used by sign-out to avoid losing notes edited just before logout.
  Future<void> flushAndDrain() {
    _flushPush();
    _flushMoves();
    return _driveOps.drainQueue;
  }

  /// Bypasses the debounce — used by folder cascade and sync button.
  Future<void> pushNoteNow(Note note) =>
      _driveOps.pushNoteAndImages(note, []);

  void flushPendingPush() => _flushPush();

  void _flushPush() {
    final notes = Map<int, Note>.from(pendingNotes);
    final deleted = Map<int, List<String>>.from(pendingDeletedImages);
    pendingNotes.clear();
    pendingDeletedImages.clear();
    pushTimer = null;
    for (final entry in notes.entries) {
      final imgs = deleted[entry.key] ?? [];
      _driveOps.run(() => performPush(entry.value, imgs));
    }
  }

  @visibleForTesting
  Future<void> performPush(Note note, List<String> deletedImages) =>
      _driveOps.pushNoteAndImages(note, deletedImages);
}

final notesProvider =
    AsyncNotifierProvider<NotesNotifier, List<Note>>(NotesNotifier.new);
