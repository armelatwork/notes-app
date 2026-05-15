part of 'note_editor.dart';

// ── Android / other platforms context menu ────────────────────────────────────

extension _AndroidMenu on _NoteEditorState {
  Widget _buildContextMenu(
      BuildContext ctx, QuillRawEditorState rawEditorState) {
    final sel = rawEditorState.textEditingValue.selection;
    final hasSelection = sel.isValid && !sel.isCollapsed;
    final hasLink =
        _controller != null && getLinkAtSelection(_controller!) != null;
    return AdaptiveTextSelectionToolbar.buttonItems(
      anchors: rawEditorState.contextMenuAnchors,
      buttonItems: _androidContextMenuItems(hasSelection, hasLink, rawEditorState),
    );
  }

  List<ContextMenuButtonItem> _androidContextMenuItems(
      bool hasSelection, bool hasLink, QuillRawEditorState rawEditorState) {
    return [
      if (hasSelection)
        ContextMenuButtonItem(
          label: 'Cut',
          onPressed: () =>
              rawEditorState.cutSelection(SelectionChangedCause.toolbar),
        ),
      if (hasSelection)
        ContextMenuButtonItem(
          label: 'Copy',
          onPressed: () =>
              rawEditorState.copySelection(SelectionChangedCause.toolbar),
        ),
      ContextMenuButtonItem(
        label: 'Paste',
        onPressed: () {
          if (_controller != null) {
            RichClipboardService.instance.paste(_controller!);
          }
        },
      ),
      ContextMenuButtonItem(
        label: 'Select All',
        onPressed: () =>
            rawEditorState.selectAll(SelectionChangedCause.toolbar),
      ),
      ContextMenuButtonItem(
        label: hasLink ? 'Edit Link' : 'Insert Link',
        onPressed: () => _showInsertLinkFromMenu(rawEditorState),
      ),
    ];
  }

  void _showInsertLinkFromMenu(QuillRawEditorState rawEditorState) {
    final savedSelection = _controller!.selection;
    rawEditorState.hideToolbar();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _controller == null) return;
      _controller!.updateSelection(savedSelection, ChangeSource.local);
      _onInsertLink();
    });
  }
}

// ── Drag-and-drop overlay ─────────────────────────────────────────────────────

class _DragOverlay extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      color: Theme.of(context)
          .colorScheme
          .primary
          .withValues(alpha: _kDragOverlayOpacity),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.image_outlined,
                size: 48, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 8),
            Text(
              'Drop image to insert',
              style: TextStyle(
                color: Theme.of(context).colorScheme.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
