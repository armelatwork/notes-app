part of 'note_editor.dart';

// ── macOS context menu ────────────────────────────────────────────────────────

enum _MacMenuAction { openLink, cut, copy, paste, selectAll, link }

extension _MacMenu on _NoteEditorState {
  Future<void> _showMacContextMenu(Offset globalPos) async {
    final ctrl = _controller;
    if (ctrl == null) return;
    final sel = ctrl.selection;
    final hasSelection = sel.isValid && !sel.isCollapsed;
    final linkUrl = getLinkAtSelection(ctrl);
    final overlayBox =
        Overlay.of(context).context.findRenderObject()! as RenderBox;
    final position = RelativeRect.fromRect(
      globalPos & const Size(1, 1),
      Offset.zero & overlayBox.size,
    );
    final choice = await showMenu<_MacMenuAction>(
      context: context,
      position: position,
      items: _buildMacMenuItems(hasSelection, linkUrl != null, linkUrl),
    );
    if (!mounted || choice == null) return;
    _handleMacMenuChoice(choice, ctrl, sel, linkUrl);
  }

  List<PopupMenuEntry<_MacMenuAction>> _buildMacMenuItems(
      bool hasSelection, bool hasLink, String? linkUrl) {
    return [
      if (hasLink) ...[
        const PopupMenuItem(
            height: 32, value: _MacMenuAction.openLink, child: Text('Open Link')),
        const PopupMenuDivider(height: 8),
      ],
      if (hasSelection)
        const PopupMenuItem(
            height: 32, value: _MacMenuAction.cut, child: Text('Cut')),
      if (hasSelection)
        const PopupMenuItem(
            height: 32, value: _MacMenuAction.copy, child: Text('Copy')),
      const PopupMenuItem(
          height: 32, value: _MacMenuAction.paste, child: Text('Paste')),
      const PopupMenuItem(
          height: 32, value: _MacMenuAction.selectAll, child: Text('Select All')),
      PopupMenuItem(
        height: 32,
        value: _MacMenuAction.link,
        child: Text(hasLink ? 'Edit Link' : 'Insert Link'),
      ),
    ];
  }

  void _handleMacMenuChoice(_MacMenuAction choice, QuillController ctrl,
      TextSelection sel, String? linkUrl) {
    switch (choice) {
      case _MacMenuAction.openLink:
        final uri = Uri.tryParse(linkUrl ?? '');
        if (uri != null) launchUrl(uri, mode: LaunchMode.externalApplication);
      case _MacMenuAction.cut:
        _handleCopy();
        ctrl.replaceText(sel.start, sel.end - sel.start, '', null);
      case _MacMenuAction.copy:
        _handleCopy();
      case _MacMenuAction.paste:
        RichClipboardService.instance.paste(ctrl);
      case _MacMenuAction.selectAll:
        ctrl.updateSelection(
          TextSelection(baseOffset: 0, extentOffset: ctrl.document.length - 1),
          ChangeSource.local,
        );
      case _MacMenuAction.link:
        final savedSel = ctrl.selection;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || _controller == null) return;
          _controller!.updateSelection(savedSel, ChangeSource.local);
          _onInsertLink();
        });
    }
  }

  void _trackPrimaryTap() {
    final now = DateTime.now();
    final last = _lastPrimaryTapTime;
    if (last != null && now.difference(last) < _NoteEditorState._kTripleTapMaxGap) {
      _primaryTapCount++;
    } else {
      _primaryTapCount = 1;
    }
    _lastPrimaryTapTime = now;
    if (_primaryTapCount >= 3) {
      _primaryTapCount = 0;
      // Signal _onEditorTapUp to apply the paragraph selection synchronously
      // once the tap settles. Using a flag avoids the addPostFrameCallback race
      // with Quill's own post-frame callbacks (which can reset the selection,
      // especially on heading blocks).
      _pendingTripleTap = true;
    }
  }

  void _selectParagraphAt(int offset) {
    final ctrl = _controller;
    if (ctrl == null) return;
    final text = ctrl.document.toPlainText();
    final clamped = offset.clamp(0, text.length);
    var start = clamped;
    while (start > 0 && text[start - 1] != '\n') {
      start--;
    }
    var end = clamped;
    while (end < text.length && text[end] != '\n') {
      end++;
    }
    ctrl.updateSelection(
      TextSelection(baseOffset: start, extentOffset: end),
      ChangeSource.local,
    );
  }
}
