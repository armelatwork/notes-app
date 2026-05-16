import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'format_painter_button.dart';

// ── Config builder ─────────────────────────────────────────────────────────────

QuillSimpleToolbarConfig _cfg({
  bool undo = false, bool redo = false, bool search = false,
  bool bold = false, bool italic = false, bool underline = false,
  bool strikeThrough = false,
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
      showStrikeThrough: strikeThrough,
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
      toolbarSectionSpacing: 0,
      sectionDividerSpace: 4,
      customButtons: customButtons,
    );

// ── Group model ────────────────────────────────────────────────────────────────

class _ToolbarGroup {
  final IconData icon;
  final String tooltip;
  // True for groups whose content needs full screen height (colour pickers).
  // On Android these use a modal sheet so the keyboard is dismissed first.
  final bool hidesKeyboard;
  // Android: content builder receives a close callback for programmatic dismiss.
  final Widget Function(BuildContext, VoidCallback close) content;
  // macOS: raw widget for the dropdown card, receives a close callback.
  final Widget Function(BuildContext, VoidCallback close) macContent;

  const _ToolbarGroup({
    required this.icon,
    required this.tooltip,
    required this.content,
    required this.macContent,
    this.hidesKeyboard = false,
  });
}

// ── Heading / font-size sub-menu buttons ──────────────────────────────────────
//
// Quill's built-in heading and font-size buttons use MenuController.open()
// inside a StatefulWidget that also calls controller.addListener(setState).
// The setState rebuild races with the pending open and drops it on real Android
// hardware. Font family is unaffected because its implementation has no such
// listener. These replacements mirror font family exactly — MenuAnchor +
// MenuController, NO controller listener — so the sub-menus open without
// hiding the keyboard, matching font family behaviour.

class _HeadingMenuButton extends StatefulWidget {
  const _HeadingMenuButton({required this.ctrl});
  final QuillController ctrl;
  @override
  State<_HeadingMenuButton> createState() => _HeadingMenuButtonState();
}

class _HeadingMenuButtonState extends State<_HeadingMenuButton> {
  final _menu = MenuController();

  @override
  Widget build(BuildContext context) {
    return MenuAnchor(
      controller: _menu,
      menuChildren: [
        MenuItemButton(child: const Text('Normal'), onPressed: () => widget.ctrl.formatSelection(Attribute.clone(Attribute.header, null))),
        MenuItemButton(child: const Text('Heading 1'), onPressed: () => widget.ctrl.formatSelection(Attribute.h1)),
        MenuItemButton(child: const Text('Heading 2'), onPressed: () => widget.ctrl.formatSelection(Attribute.h2)),
        MenuItemButton(child: const Text('Heading 3'), onPressed: () => widget.ctrl.formatSelection(Attribute.h3)),
      ],
      child: Builder(
        builder: (ctx) => QuillToolbarIconButton(
          onPressed: () {
            if (_menu.isOpen) {
              _menu.close();
            } else {
              // MenuAnchor positions the menu using the full overlay height
              // (full screen) without knowing the keyboard occupies the bottom.
              // A 4-item menu (~200 dp) fits in the apparent gap below the
              // button and opens downward into the keyboard — invisible.
              // Font family's long list (~400 dp) does not fit below so it
              // naturally flips above with menu.bottom = anchor.top.
              // Replicating that flip: position.y = −menu_height places the
              // menu's bottom exactly at the anchor's top (flush to button),
              // regardless of keyboard height. Only apply when keyboard is up.
              final kb = MediaQuery.viewInsetsOf(ctx).bottom;
              _menu.open(position: kb > 0 ? const Offset(0, -200) : null);
            }
          },
          isSelected: false,
          iconTheme: null,
          icon: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Heading', style: TextStyle(
                color: IconTheme.of(ctx).color, fontSize: 13)),
              Icon(Icons.arrow_drop_down, size: 18),
            ],
          ),
        ),
      ),
    );
  }
}

class _FontSizeMenuButton extends StatefulWidget {
  const _FontSizeMenuButton({required this.ctrl});
  final QuillController ctrl;
  @override
  State<_FontSizeMenuButton> createState() => _FontSizeMenuButtonState();
}

class _FontSizeMenuButtonState extends State<_FontSizeMenuButton> {
  final _menu = MenuController();

  @override
  Widget build(BuildContext context) {
    return MenuAnchor(
      controller: _menu,
      menuChildren: [
        MenuItemButton(child: const Text('Small'), onPressed: () => widget.ctrl.formatSelection(const SizeAttribute('small'))),
        MenuItemButton(child: const Text('Normal'), onPressed: () => widget.ctrl.formatSelection(const SizeAttribute(null))),
        MenuItemButton(child: const Text('Large'), onPressed: () => widget.ctrl.formatSelection(const SizeAttribute('large'))),
        MenuItemButton(child: const Text('Huge'), onPressed: () => widget.ctrl.formatSelection(const SizeAttribute('huge'))),
      ],
      child: Builder(
        builder: (ctx) => QuillToolbarIconButton(
          onPressed: () {
            if (_menu.isOpen) {
              _menu.close();
            } else {
              // MenuAnchor positions the menu using the full overlay height
              // (full screen) without knowing the keyboard occupies the bottom.
              // A 4-item menu (~200 dp) fits in the apparent gap below the
              // button and opens downward into the keyboard — invisible.
              // Font family's long list (~400 dp) does not fit below so it
              // naturally flips above with menu.bottom = anchor.top.
              // Replicating that flip: position.y = −menu_height places the
              // menu's bottom exactly at the anchor's top (flush to button),
              // regardless of keyboard height. Only apply when keyboard is up.
              final kb = MediaQuery.viewInsetsOf(ctx).bottom;
              _menu.open(position: kb > 0 ? const Offset(0, -200) : null);
            }
          },
          isSelected: false,
          iconTheme: null,
          icon: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Font size', style: TextStyle(
                color: IconTheme.of(ctx).color, fontSize: 13)),
              Icon(Icons.arrow_drop_down, size: 18),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Android sheet helpers ──────────────────────────────────────────────────────

Widget _textStyleSheet(BuildContext _, QuillController ctrl) =>
    SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              FormatPainterButton(controller: ctrl),
              QuillSimpleToolbar(
                controller: ctrl,
                config: _cfg(
                  bold: true, italic: true, underline: true,
                  strikeThrough: true, inlineCode: true,
                  subscript: true, superscript: true,
                ),
              ),
            ],
          ),
        ),
      ),
    );

Widget _quillSheet(BuildContext _, QuillController ctrl, QuillSimpleToolbarConfig cfg) =>
    SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: QuillSimpleToolbar(controller: ctrl, config: cfg),
        ),
      ),
    );

Widget _headerFirstSheet(BuildContext _, QuillController ctrl,
    QuillSimpleToolbarConfig restCfg) =>
    SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              QuillSimpleToolbar(
                controller: ctrl,
                config: _cfg(customButtons: [
                  QuillToolbarCustomButtonOptions(
                    icon: const Icon(Icons.text_format),
                    childBuilder: (dynamic opt, dynamic extra) =>
                        _HeadingMenuButton(ctrl: ctrl),
                  ),
                  QuillToolbarCustomButtonOptions(
                    icon: const Icon(Icons.format_size),
                    childBuilder: (dynamic opt, dynamic extra) =>
                        _FontSizeMenuButton(ctrl: ctrl),
                  ),
                ]),
              ),
              QuillSimpleToolbar(controller: ctrl, config: restCfg),
            ],
          ),
        ),
      ),
    );

Widget _insertSheet(VoidCallback close, VoidCallback onLink, VoidCallback onImage) =>
    SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.link),
            title: const Text('Insert link'),
            onTap: () { close(); onLink(); },
          ),
          ListTile(
            leading: const Icon(Icons.image_outlined),
            title: const Text('Insert image'),
            onTap: () { close(); onImage(); },
          ),
        ],
      ),
    );

// ── macOS dropdown helpers (no sheet chrome) ───────────────────────────────────

Widget _macQuill(QuillController ctrl, QuillSimpleToolbarConfig cfg) =>
    SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: QuillSimpleToolbar(controller: ctrl, config: cfg),
    );

Widget _macHeaderFirst(QuillController ctrl, QuillSimpleToolbarConfig restCfg) =>
    SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          QuillSimpleToolbar(controller: ctrl, config: _cfg(header: true)),
          QuillSimpleToolbar(controller: ctrl, config: restCfg),
        ],
      ),
    );

Widget _macInsert(VoidCallback close, VoidCallback onLink, VoidCallback onImage) =>
    IntrinsicWidth(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.link),
            title: const Text('Insert link'),
            onTap: () { close(); onLink(); },
          ),
          ListTile(
            leading: const Icon(Icons.image_outlined),
            title: const Text('Insert image'),
            onTap: () { close(); onImage(); },
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
      icon: Icons.history, tooltip: 'History',
      content: (ctx, _) => _quillSheet(ctx, ctrl,
          _cfg(undo: true, redo: true, search: true)),
      macContent: (_, _) => _macQuill(ctrl,
          _cfg(undo: true, redo: true, search: true)),
    ),
    _ToolbarGroup(
      icon: Icons.format_bold, tooltip: 'Text style',
      content: (ctx, _) => _textStyleSheet(ctx, ctrl),
      macContent: (_, _) => _macQuill(ctrl, _cfg(
          bold: true, italic: true, underline: true, strikeThrough: true,
          inlineCode: true, subscript: true, superscript: true)),
    ),
    if (fontsSplit) ...[
      _ToolbarGroup(
        icon: Icons.text_fields, tooltip: 'Text',
        content: (ctx, _) => _headerFirstSheet(ctx, ctrl,
            _cfg(fontFamily: true)),
        macContent: (_, _) => _macHeaderFirst(ctrl,
            _cfg(fontFamily: true, fontSize: true)),
      ),
      _ToolbarGroup(
        icon: Icons.palette_outlined, tooltip: 'Colors',
        hidesKeyboard: true,
        content: (ctx, _) => _quillSheet(ctx, ctrl,
            _cfg(color: true, background: true, clearFormat: true)),
        macContent: (_, _) => _macQuill(ctrl,
            _cfg(color: true, background: true, clearFormat: true)),
      ),
    ] else
      _ToolbarGroup(
        icon: Icons.text_format, tooltip: 'Fonts',
        content: (ctx, _) => _headerFirstSheet(ctx, ctrl, _cfg(
            fontFamily: true,
            color: true, background: true, clearFormat: true)),
        macContent: (_, _) => _macHeaderFirst(ctrl, _cfg(
            fontFamily: true, fontSize: true,
            color: true, background: true, clearFormat: true)),
      ),
    if (paragraphSplit) ...[
      _ToolbarGroup(
        icon: Icons.format_align_left, tooltip: 'Alignment',
        content: (ctx, _) => _quillSheet(ctx, ctrl, _cfg(alignment: true)),
        macContent: (_, _) => _macQuill(ctrl, _cfg(alignment: true)),
      ),
      _ToolbarGroup(
        icon: Icons.format_indent_increase, tooltip: 'Indent',
        content: (ctx, _) => _quillSheet(ctx, ctrl, _cfg(indent: true)),
        macContent: (_, _) => _macQuill(ctrl, _cfg(indent: true)),
      ),
    ] else
      _ToolbarGroup(
        icon: Icons.segment, tooltip: 'Paragraph',
        content: (ctx, _) => _quillSheet(ctx, ctrl,
            _cfg(alignment: true, indent: true)),
        macContent: (_, _) => _macQuill(ctrl,
            _cfg(alignment: true, indent: true)),
      ),
    _ToolbarGroup(
      icon: Icons.format_list_bulleted, tooltip: 'Lists',
      content: (ctx, _) => _quillSheet(ctx, ctrl,
          _cfg(numberedList: true, bulletList: true, checkList: true)),
      macContent: (_, _) => _macQuill(ctrl,
          _cfg(numberedList: true, bulletList: true, checkList: true)),
    ),
    _ToolbarGroup(
      icon: Icons.add_photo_alternate_outlined, tooltip: 'Insert',
      content: (_, close) => _insertSheet(close, onLink, onImage),
      macContent: (_, close) => _macInsert(close, onLink, onImage),
    ),
  ];
}

// ── NoteFormattingToolbar ──────────────────────────────────────────────────────

class NoteFormattingToolbar extends StatelessWidget {
  final QuillController quillController;
  final VoidCallback onInsertImage;
  final VoidCallback onInsertLink;
  final FocusNode? editorFocusNode;

  const NoteFormattingToolbar({
    super.key,
    required this.quillController,
    required this.onInsertImage,
    required this.onInsertLink,
    this.editorFocusNode,
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
        editorFocusNode: editorFocusNode,
      ),
    );
  }
}

// ── macOS: Basic Font inline + dropdown icons for the rest ─────────────────────

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
      width: double.infinity,
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
              color: Theme.of(context).colorScheme.outlineVariant),
        ),
        color: Theme.of(context).colorScheme.surfaceContainerLow,
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final groups = _buildGroups(constraints.maxWidth, controller,
                  onInsertLink, onInsertImage)
              .where((g) =>
                  g.tooltip != 'History' &&
                  g.tooltip != 'Text style' &&
                  g.tooltip != 'Text' &&
                  g.tooltip != 'Fonts')
              .toList();
          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                QuillSimpleToolbar(
                  controller: controller,
                  config: _cfg(undo: true, redo: true),
                ),
                VerticalDivider(
                  width: 1, indent: 8, endIndent: 8,
                  color: Theme.of(context).colorScheme.outlineVariant,
                ),
                FormatPainterButton(controller: controller),
                QuillSimpleToolbar(
                  controller: controller,
                  config: _cfg(
                    bold: true, italic: true, underline: true, strikeThrough: true,
                    inlineCode: true, subscript: true, superscript: true,
                  ),
                ),
                QuillSimpleToolbar(
                  controller: controller,
                  config: _cfg(header: true),
                ),
                QuillSimpleToolbar(
                  controller: controller,
                  config: _cfg(fontFamily: true, fontSize: true),
                ),
                VerticalDivider(
                  width: 1, indent: 8, endIndent: 8,
                  color: Theme.of(context).colorScheme.outlineVariant,
                ),
                ...groups.map((g) => _MacOSGroupButton(group: g)),
              ],
            ),
          );
        },
      ),
    );
  }
}

// ── macOS dropdown button ──────────────────────────────────────────────────────

class _MacOSGroupButton extends StatefulWidget {
  final _ToolbarGroup group;
  const _MacOSGroupButton({required this.group});

  @override
  State<_MacOSGroupButton> createState() => _MacOSGroupButtonState();
}

class _MacOSGroupButtonState extends State<_MacOSGroupButton> {
  OverlayEntry? _entry;
  final _key = GlobalKey();

  @override
  void dispose() {
    _entry?.remove();
    super.dispose();
  }

  void _close() {
    _entry?.remove();
    _entry = null;
  }

  void _toggle() {
    if (_entry != null) { _close(); return; }
    final box = _key.currentContext!.findRenderObject()! as RenderBox;
    final pos = box.localToGlobal(Offset.zero);
    final size = box.size;
    _entry = OverlayEntry(
      builder: (_) => Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _close,
            ),
          ),
          Positioned(
            left: pos.dx,
            top: pos.dy + size.height + 2,
            child: Material(
              elevation: 8,
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: widget.group.macContent(context, _close),
              ),
            ),
          ),
        ],
      ),
    );
    Overlay.of(context).insert(_entry!);
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      key: _key,
      icon: Icon(widget.group.icon, size: 22),
      tooltip: widget.group.tooltip,
      onPressed: _toggle,
    );
  }
}

// ── Android: group icons bar at bottom ────────────────────────────────────────

class _AndroidGroupBar extends StatefulWidget {
  final List<_ToolbarGroup> groups;
  final FocusNode? editorFocusNode;
  const _AndroidGroupBar({required this.groups, this.editorFocusNode});

  @override
  State<_AndroidGroupBar> createState() => _AndroidGroupBarState();
}

class _AndroidGroupBarState extends State<_AndroidGroupBar> {
  PersistentBottomSheetController? _sheetController;
  String? _openTooltip;

  @override
  void dispose() {
    _sheetController?.close();
    super.dispose();
  }

  void _onTap(BuildContext context, _ToolbarGroup group) {
    if (group.hidesKeyboard) {
      _sheetController?.close();
      showModalBottomSheet<void>(
        context: context,
        builder: (ctx) => group.content(ctx, () => Navigator.pop(ctx)),
      );
      return;
    }

    // Toggle: same icon closes the open sheet.
    if (_openTooltip == group.tooltip) {
      _sheetController?.close();
      return;
    }

    _sheetController?.close();

    final ctrl = Scaffold.of(context).showBottomSheet(
      (ctx) => _PersistentSheetContent(
        child: group.content(ctx, () => _sheetController?.close()),
      ),
    );

    setState(() { _sheetController = ctrl; _openTooltip = group.tooltip; });

    // Re-request editor focus so the keyboard stays visible after the tap
    // that opened the sheet caused a momentary focus loss.
    WidgetsBinding.instance.addPostFrameCallback(
        (_) => widget.editorFocusNode?.requestFocus());

    ctrl.closed.then((_) {
      if (mounted) setState(() { _sheetController = null; _openTooltip = null; });
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        border: Border(
            top: BorderSide(color: Theme.of(context).colorScheme.outlineVariant)),
        color: Theme.of(context).colorScheme.surfaceContainerLow,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: widget.groups.map((g) => IconButton(
          icon: Icon(g.icon, size: 22,
              color: _openTooltip == g.tooltip
                  ? Theme.of(context).colorScheme.primary
                  : null),
          tooltip: g.tooltip,
          onPressed: () => _onTap(context, g),
        )).toList(),
      ),
    );
  }
}

class _PersistentSheetContent extends StatelessWidget {
  final Widget child;
  const _PersistentSheetContent({required this.child});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 6),
        Container(
          width: 32,
          height: 4,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.outlineVariant,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(height: 4),
        child,
      ],
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
