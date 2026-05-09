import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';

// ── Config builder ─────────────────────────────────────────────────────────────

QuillSimpleToolbarConfig _cfg({
  bool undo = false, bool redo = false, bool search = false,
  bool bold = false, bool italic = false, bool underline = false,
  bool inlineCode = false, bool subscript = false, bool superscript = false,
  bool color = false, bool background = false, bool clearFormat = false,
  bool alignment = false, bool header = false,
  bool numberedList = false, bool bulletList = false, bool checkList = false,
  bool indent = false, bool fontFamily = false, bool fontSize = false,
  List<QuillToolbarCustomButtonOptions> customButtons = const [],
}) =>
    QuillSimpleToolbarConfig(
      showUndo: undo, showRedo: redo, showSearchButton: search,
      showBoldButton: bold, showItalicButton: italic, showUnderLineButton: underline,
      showStrikeThrough: false,
      showInlineCode: inlineCode, showSubscript: subscript, showSuperscript: superscript,
      showColorButton: color, showBackgroundColorButton: background,
      showClearFormat: clearFormat,
      showAlignmentButtons: alignment,
      showLeftAlignment: true, showCenterAlignment: true, showRightAlignment: true,
      showHeaderStyle: header,
      showListNumbers: numberedList, showListBullets: bulletList, showListCheck: checkList,
      showCodeBlock: false, showQuote: false,
      showIndent: indent, showLink: false,
      showFontFamily: fontFamily, showFontSize: fontSize,
      customButtons: customButtons,
    );

// ── Group model ────────────────────────────────────────────────────────────────

class _ToolbarGroup {
  final IconData icon;
  final String tooltip;
  final Widget Function(BuildContext context) content;
  const _ToolbarGroup({
    required this.icon,
    required this.tooltip,
    required this.content,
  });
}

// ── Group sheet builders ───────────────────────────────────────────────────────

Widget _quillSheet(BuildContext context, QuillController ctrl, QuillSimpleToolbarConfig cfg) =>
    SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: QuillSimpleToolbar(controller: ctrl, config: cfg),
        ),
      ),
    );

// Header rendered first, then the rest — overrides QuillSimpleToolbar's internal order.
Widget _headerFirstSheet(BuildContext context, QuillController ctrl,
    QuillSimpleToolbarConfig restCfg) =>
    SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              QuillSimpleToolbar(controller: ctrl, config: _cfg(header: true)),
              QuillSimpleToolbar(controller: ctrl, config: restCfg),
            ],
          ),
        ),
      ),
    );

Widget _insertSheet(BuildContext context, VoidCallback onLink, VoidCallback onImage) =>
    SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.link),
            title: const Text('Insert link'),
            onTap: () { Navigator.pop(context); onLink(); },
          ),
          ListTile(
            leading: const Icon(Icons.image_outlined),
            title: const Text('Insert image'),
            onTap: () { Navigator.pop(context); onImage(); },
          ),
        ],
      ),
    );

// ── Dynamic group list ─────────────────────────────────────────────────────────

List<_ToolbarGroup> _buildGroups(double width, QuillController ctrl,
    VoidCallback onLink, VoidCallback onImage) {
  final fontsSplit = width >= 600;
  final paragraphSplit = width >= 700;
  return [
    _ToolbarGroup(
      icon: Icons.history,
      tooltip: 'History',
      content: (ctx) => _quillSheet(ctx, ctrl,
          _cfg(undo: true, redo: true, search: true)),
    ),
    _ToolbarGroup(
      icon: Icons.format_bold,
      tooltip: 'Text style',
      content: (ctx) => _quillSheet(ctx, ctrl, _cfg(
          bold: true, italic: true, underline: true,
          inlineCode: true, subscript: true, superscript: true)),
    ),
    if (fontsSplit) ...[
      _ToolbarGroup(
        icon: Icons.text_fields,
        tooltip: 'Text',
        content: (ctx) => _headerFirstSheet(ctx, ctrl,
            _cfg(fontFamily: true, fontSize: true)),
      ),
      _ToolbarGroup(
        icon: Icons.palette_outlined,
        tooltip: 'Colors',
        content: (ctx) => _quillSheet(ctx, ctrl,
            _cfg(color: true, background: true, clearFormat: true)),
      ),
    ] else
      _ToolbarGroup(
        icon: Icons.text_format,
        tooltip: 'Fonts',
        content: (ctx) => _headerFirstSheet(ctx, ctrl, _cfg(
          fontFamily: true, fontSize: true,
          color: true, background: true, clearFormat: true,
        )),
      ),
    if (paragraphSplit) ...[
      _ToolbarGroup(
        icon: Icons.format_align_left,
        tooltip: 'Alignment',
        content: (ctx) => _quillSheet(ctx, ctrl, _cfg(alignment: true)),
      ),
      _ToolbarGroup(
        icon: Icons.format_indent_increase,
        tooltip: 'Indent',
        content: (ctx) => _quillSheet(ctx, ctrl, _cfg(indent: true)),
      ),
    ] else
      _ToolbarGroup(
        icon: Icons.segment,
        tooltip: 'Paragraph',
        content: (ctx) =>
            _quillSheet(ctx, ctrl, _cfg(alignment: true, indent: true)),
      ),
    _ToolbarGroup(
      icon: Icons.format_list_bulleted,
      tooltip: 'Lists',
      content: (ctx) => _quillSheet(ctx, ctrl,
          _cfg(numberedList: true, bulletList: true, checkList: true)),
    ),
    _ToolbarGroup(
      icon: Icons.add_photo_alternate_outlined,
      tooltip: 'Insert',
      content: (ctx) => _insertSheet(ctx, onLink, onImage),
    ),
  ];
}

// ── NoteFormattingToolbar ──────────────────────────────────────────────────────

class NoteFormattingToolbar extends StatelessWidget {
  final QuillController quillController;
  final VoidCallback onInsertImage;
  final VoidCallback onInsertLink;

  const NoteFormattingToolbar({
    super.key,
    required this.quillController,
    required this.onInsertImage,
    required this.onInsertLink,
  });

  @override
  Widget build(BuildContext context) {
    if (defaultTargetPlatform == TargetPlatform.macOS) {
      return _MacOSToolbar(
        controller: quillController,
        onInsertImage: onInsertImage,
        onInsertLink: onInsertLink,
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) => _AndroidGroupBar(
        groups: _buildGroups(
            constraints.maxWidth, quillController, onInsertLink, onInsertImage),
      ),
    );
  }
}

// ── macOS: full scrollable toolbar at top ──────────────────────────────────────

class _MacOSToolbar extends StatelessWidget {
  final QuillController controller;
  final VoidCallback onInsertImage;
  final VoidCallback onInsertLink;
  const _MacOSToolbar({
    required this.controller,
    required this.onInsertImage,
    required this.onInsertLink,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
              color: Theme.of(context).colorScheme.outlineVariant),
        ),
        color: Theme.of(context).colorScheme.surfaceContainerLow,
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: QuillSimpleToolbar(
          controller: controller,
          config: _cfg(
            undo: true, redo: true,
            bold: true, italic: true, underline: true,
            header: true, fontFamily: true, fontSize: true,
            color: true, background: true, clearFormat: true,
            alignment: true, indent: true,
            numberedList: true, bulletList: true, checkList: true,
            customButtons: [
              QuillToolbarCustomButtonOptions(
                icon: const Icon(Icons.link, size: 18),
                tooltip: 'Insert / edit link',
                onPressed: onInsertLink,
              ),
              QuillToolbarCustomButtonOptions(
                icon: const Icon(Icons.image_outlined, size: 18),
                tooltip: 'Insert image',
                onPressed: onInsertImage,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Android: group icons bar at bottom ────────────────────────────────────────

class _AndroidGroupBar extends StatelessWidget {
  final List<_ToolbarGroup> groups;
  const _AndroidGroupBar({required this.groups});

  void _openGroup(BuildContext context, _ToolbarGroup group) {
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => group.content(ctx),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(
              color: Theme.of(context).colorScheme.outlineVariant),
        ),
        color: Theme.of(context).colorScheme.surfaceContainerLow,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: groups
            .map((g) => IconButton(
                  icon: Icon(g.icon, size: 22),
                  tooltip: g.tooltip,
                  onPressed: () => _openGroup(context, g),
                ))
            .toList(),
      ),
    );
  }
}

// ── Shared widgets ─────────────────────────────────────────────────────────────

class NoteTitleField extends StatelessWidget {
  final TextEditingController controller;
  final String hintText;
  final VoidCallback onChanged;

  const NoteTitleField({
    super.key,
    required this.controller,
    required this.hintText,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
      child: TextField(
        controller: controller,
        onChanged: (_) => onChanged(),
        style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
        decoration: InputDecoration(
          border: InputBorder.none,
          hintText: hintText,
          hintStyle: const TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: Colors.grey,
          ),
        ),
      ),
    );
  }
}

class NoteEmptyPlaceholder extends StatelessWidget {
  const NoteEmptyPlaceholder({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.edit_note, size: 64, color: Colors.grey[300]),
          const SizedBox(height: 12),
          Text(
            'Select a note or create a new one',
            style: TextStyle(color: Colors.grey[400], fontSize: 16),
          ),
        ],
      ),
    );
  }
}
