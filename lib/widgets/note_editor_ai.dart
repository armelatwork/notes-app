part of 'note_editor.dart';

// ── AI helper ─────────────────────────────────────────────────────────────────

extension _NoteAiHelper on _NoteEditorState {
  Future<void> _onAiHelper() async {
    if (_controller == null) return;
    final plainText = _controller!.document.toPlainText().trim();
    if (plainText.isEmpty && _sessionAiDocument == null) return;
    FocusScope.of(context).unfocus();
    _rebuild(() => _isAiSheetOpen = true);
    final result = await showModalBottomSheet<AiSheetResult>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => AiSuggestionSheet(
        noteContent: plainText,
        initialDocument: _sessionAiDocument,
        initialPlainText: _sessionAiBaseContent,
        onSuggestionGenerated: (r) {
          _sessionAiDocument = r.document;
          _sessionAiBaseContent = r.baseContent;
        },
      ),
    );
    if (!mounted) return;
    _rebuild(() => _isAiSheetOpen = false);
    if (result?.applied == true) _applyAiSuggestion(result!.document);
  }

  void _applyAiSuggestion(Document doc) {
    // Replace content via compose so the controller instance is preserved.
    // Replacing the controller entirely disposes it mid-frame, causing the
    // QuillEditor to lose its binding and ignore edits until re-focused.
    // compose() also records the replacement as one undoable action.
    final currentLength = _controller!.document.length;
    final replaceDelta = Delta()..delete(currentLength);
    for (final op in doc.toDelta().toList()) {
      if (op.isInsert) replaceDelta.insert(op.data, op.attributes);
    }
    _controller!.compose(
      replaceDelta,
      const TextSelection.collapsed(offset: 0),
      ChangeSource.local,
    );
    _scheduleSave();
  }
}
