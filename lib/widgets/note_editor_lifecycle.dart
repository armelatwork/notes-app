part of 'note_editor.dart';

// ── Note lifecycle ────────────────────────────────────────────────────────────

extension _NoteLifecycle on _NoteEditorState {
  void _clearNoteSession() {
    _formatPainterTimer?.cancel();
    _formatPainterTimer = null;
    _sessionAiDocument = null;
    _sessionAiBaseContent = null;
    ref.read(formatPainterProvider.notifier).clear();
  }

  void _updateTitleController(Note note) {
    if (isDefaultNoteTitle(note.title)) {
      _hintTitle = note.title;
      _titleController.text = '';
    } else {
      _hintTitle = 'New Note';
      _titleController.text = note.title;
    }
  }

  Document _parseNoteDocument(String content) {
    try {
      final json = jsonDecode(content) as List;
      return Document.fromJson(json);
    } catch (e) {
      AppLogger.instance.warn('NoteEditor', 'failed to parse note content', e);
      return Document();
    }
  }

  void _loadNote(Note note) {
    if (_currentNote?.id == note.id) return;
    _clearNoteSession();
    if (_isNewEmptyNote()) {
      ref.read(notesProvider.notifier).deleteNote(_currentNote!.id);
    } else {
      _saveCurrentNote();
    }
    _currentNote = note;
    _isDirty = false;
    _imagesAtLoad = extractImageFilenames(note.content);
    _updateTitleController(note);
    _initNoteController(_parseNoteDocument(note.content));
    _rebuild(() {});
    if (defaultTargetPlatform == TargetPlatform.macOS) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _focusNode.requestFocus();
      });
    }
  }

  void _initNoteController(Document doc) {
    _controller?.dispose();
    _controller = QuillController(
      document: doc,
      selection: const TextSelection.collapsed(offset: 0),
    );
    _controller!.document.changes.listen((_) => _scheduleSave());
    _controller!.addListener(_applyFormatPainterIfActive);
    ref.read(editorMenuProvider.notifier).state = _controller;
  }

  void _scheduleSave() {
    _isDirty = true;
    if (_saving) return;
    _saving = true;
    Future.delayed(
        const Duration(milliseconds: _kSaveDebounceMs), _saveCurrentNote);
  }

  Future<void> _saveCurrentNote() async {
    _saving = false;
    if (!_isDirty) return;
    _isDirty = false;
    final note = _currentNote;
    if (note == null || _controller == null) return;
    final delta = _controller!.document.toDelta();
    final contentJson = jsonEncode(delta.toJson());
    final plainText = _controller!.document.toPlainText();
    final preview = plainText.trim().replaceAll('\n', ' ');
    final typedTitle = _titleController.text.trim();
    note.title = typedTitle.isEmpty ? _hintTitle : typedTitle;
    note.content = contentJson;
    note.preview = preview.length > _kPreviewMaxLength
        ? preview.substring(0, _kPreviewMaxLength)
        : preview;
    final currentImages = extractImageFilenames(contentJson);
    final deletedImages =
        _imagesAtLoad.where((f) => !currentImages.contains(f)).toList();
    _imagesAtLoad = currentImages;
    await ref
        .read(notesProvider.notifier)
        .saveNote(note, deletedImageFilenames: deletedImages);
    await _pushSharedNoteUpdate(note);
  }

  Future<void> _pushSharedNoteUpdate(Note note) async {
    if (note.firestoreId == null) return;
    final user = ref.read(appUserProvider);
    final inlinedContent = await inlineImagesForSharing(note.content);
    SharingService.instance.pushUpdate(
      firestoreId: note.firestoreId!,
      note: note,
      contentOverride: inlinedContent,
      editorUid: user?.id ?? '',
      editorEmail: user?.email ?? '',
    ).catchError((e) {
      AppLogger.instance.warn('NoteEditor', 'Firestore push failed', e);
    });
  }

  void _applyRemoteContent(String content, String title) {
    try {
      final json = jsonDecode(content) as List;
      // Replace controller with a new one built from the remote document so
      // that Quill's internal delta state is fully consistent.
      _initNoteController(Document.fromJson(json));
      if (title != _titleController.text) _titleController.text = title;
      if (_currentNote != null) {
        _currentNote!.content = content;
        _currentNote!.title = title;
      }
      if (mounted) _rebuild(() {});
      AppLogger.instance.info('NoteEditor', 'applied remote update');
    } catch (e) {
      AppLogger.instance.warn('NoteEditor', 'failed to apply remote update', e);
    }
  }

  Future<void> _pickAndInsertImage() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery);
    if (picked == null || _controller == null) return;
    await embedImageFile(_controller!, picked.path);
    if (mounted) _rebuild(() {});
  }

  void _onInsertLink() {
    if (_controller == null) return;
    showInsertLinkDialog(context, _controller!);
  }
}
