part of 'note_editor.dart';

// ── Clipboard ─────────────────────────────────────────────────────────────────

extension _NoteClipboard on _NoteEditorState {
  void _handleCopy() {
    final ctrl = _controller;
    if (ctrl == null) return;
    RichClipboardService.instance.copy(ctrl);
  }

  void _handleCut() {
    final ctrl = _controller;
    if (ctrl == null) return;
    RichClipboardService.instance.copy(ctrl);
    final sel = ctrl.selection;
    if (sel.isValid && !sel.isCollapsed) {
      ctrl.replaceText(sel.start, sel.end - sel.start, '', null);
    }
  }

  Future<void> _handlePaste() async {
    final ctrl = _controller;
    if (ctrl == null) return;
    // Set the flag synchronously before any await so the macOS native Paste
    // menu action (which fires almost simultaneously) is suppressed.
    RichClipboardService.instance.beginKeyboardPaste();
    try {
      final imagePasted = await pasteImageFromClipboard(ctrl);
      if (!imagePasted) {
        await RichClipboardService.instance.paste(ctrl, fromKeyboard: true);
      }
    } finally {
      RichClipboardService.instance.endKeyboardPaste();
    }
  }

  void _insertTab() {
    if (_controller == null) return;
    final sel = _controller!.selection;
    if (!sel.isCollapsed) {
      _controller!.replaceText(sel.start, sel.end - sel.start, '', null);
    }
    _controller!.document.insert(sel.start, const Embeddable(kTabEmbedType, ''));
    _controller!.updateSelection(
      TextSelection.collapsed(offset: sel.start + 1),
      ChangeSource.local,
    );
  }
}
