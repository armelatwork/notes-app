part of 'note_editor.dart';

// ── Format painter ────────────────────────────────────────────────────────────

extension _FormatPainter on _NoteEditorState {
  // Controller listener: debounce for keyboard-driven selection changes only.
  // Suppressed while a pointer button is held (_primaryPointerDown) because
  // pointer-based selection is handled by _onPrimaryPointerUp instead.
  void _applyFormatPainterIfActive() {
    if (!mounted || _controller == null) return;
    if (ref.read(formatPainterProvider) == null) return;
    if (_primaryPointerDown) return;
    final sel = _controller!.selection;
    if (!sel.isValid || sel.isCollapsed) return;
    _formatPainterTimer?.cancel();
    _formatPainterTimer =
        Timer(const Duration(milliseconds: 300), _applyFormatPainterNow);
  }

  // Called on primary pointer-up. Listener.onPointerUp fires before Quill's
  // gesture recognizer so the controller selection already reflects the drag.
  void _onPrimaryPointerUp() {
    if (ref.read(formatPainterProvider) == null) return;
    final sel = _controller?.selection;
    if (sel == null || !sel.isValid || sel.isCollapsed) return;
    _formatPainterTimer?.cancel();
    _formatPainterTimer = null;
    _applyFormatPainterToRange(sel.start, sel.end - sel.start);
  }

  void _applyFormatPainterNow() {
    _formatPainterTimer = null;
    if (!mounted || _controller == null) return;
    final sel = _controller!.selection;
    if (!sel.isValid || sel.isCollapsed) return;
    _applyFormatPainterToRange(sel.start, sel.end - sel.start);
  }

  void _applyFormatPainterToRange(int start, int len) {
    if (!mounted || _controller == null) return;
    final attrs = ref.read(formatPainterProvider);
    if (attrs == null) return;
    final ctrl = _controller!;
    if (attrs.isEmpty) {
      _clearTextStyle(ctrl, start, len);
    } else {
      for (final attr in attrs.values) {
        ctrl.formatText(start, len, attr);
      }
    }
    ref.read(formatPainterProvider.notifier).clear();
  }

  // Removes all common inline and block formatting from [start, start+len).
  // Used when the painter was activated on plain (unstyled) text.
  void _clearTextStyle(QuillController ctrl, int start, int len) {
    for (final attr in <Attribute>[
      Attribute.bold, Attribute.italic, Attribute.underline,
      Attribute.strikeThrough, Attribute.inlineCode, Attribute.subscript,
    ]) {
      ctrl.formatText(start, len, Attribute.clone(attr, null));
    }
    ctrl.formatText(start, len, Attribute.clone(Attribute.h1, null));
  }
}
