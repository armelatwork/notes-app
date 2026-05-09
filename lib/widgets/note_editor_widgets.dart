import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';

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
    return LayoutBuilder(
      builder: (context, constraints) => _ToolbarContent(
        availableWidth: constraints.maxWidth,
        controller: quillController,
        onInsertImage: onInsertImage,
        onInsertLink: onInsertLink,
      ),
    );
  }
}

class _ToolbarContent extends StatelessWidget {
  final double availableWidth;
  final QuillController controller;
  final VoidCallback onInsertImage;
  final VoidCallback onInsertLink;

  const _ToolbarContent({
    required this.availableWidth,
    required this.controller,
    required this.onInsertImage,
    required this.onInsertLink,
  });

  static const _kTextStyleWidth = 500.0;
  static const _kFormatWidth = 650.0;
  static const _kAdvancedWidth = 800.0;
  static const _kTypographyWidth = 950.0;

  bool get _showTextStyle => availableWidth >= _kTextStyleWidth;
  bool get _showFormat => availableWidth >= _kFormatWidth;
  bool get _showAdvanced => availableWidth >= _kAdvancedWidth;
  bool get _showTypography => availableWidth >= _kTypographyWidth;
  bool get _hasOverflow => !_showTypography;

  QuillSimpleToolbarConfig _primaryConfig(VoidCallback onOverflow) =>
      QuillSimpleToolbarConfig(
        showFontFamily: _showTypography,
        showFontSize: _showTypography,
        showBoldButton: true,
        showItalicButton: true,
        showUnderLineButton: true,
        showStrikeThrough: false,
        showColorButton: _showFormat,
        showBackgroundColorButton: _showAdvanced,
        showClearFormat: _showFormat,
        showAlignmentButtons: _showFormat,
        showLeftAlignment: true,
        showCenterAlignment: true,
        showRightAlignment: true,
        showHeaderStyle: _showTextStyle,
        showListNumbers: _showTextStyle,
        showListBullets: _showTextStyle,
        showListCheck: _showFormat,
        showCodeBlock: false,
        showQuote: false,
        showIndent: _showAdvanced,
        showLink: false,
        showUndo: true,
        showRedo: true,
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
          if (_hasOverflow)
            QuillToolbarCustomButtonOptions(
              icon: const Icon(Icons.more_horiz, size: 18),
              tooltip: 'More formatting',
              onPressed: onOverflow,
            ),
        ],
      );

  QuillSimpleToolbarConfig get _overflowConfig => QuillSimpleToolbarConfig(
        showFontFamily: !_showTypography,
        showFontSize: !_showTypography,
        showBoldButton: false,
        showItalicButton: false,
        showUnderLineButton: false,
        showStrikeThrough: false,
        showColorButton: !_showFormat,
        showBackgroundColorButton: !_showAdvanced,
        showClearFormat: !_showFormat,
        showAlignmentButtons: !_showFormat,
        showLeftAlignment: true,
        showCenterAlignment: true,
        showRightAlignment: true,
        showHeaderStyle: !_showTextStyle,
        showListNumbers: !_showTextStyle,
        showListBullets: !_showTextStyle,
        showListCheck: !_showFormat,
        showCodeBlock: false,
        showQuote: false,
        showIndent: !_showAdvanced,
        showLink: false,
        showUndo: false,
        showRedo: false,
        customButtons: [],
      );

  void _showOverflowSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: Text(
                  'More formatting',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: Colors.grey[600],
                      ),
                ),
              ),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: QuillSimpleToolbar(
                  controller: controller,
                  config: _overflowConfig,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

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
      child: QuillSimpleToolbar(
        controller: controller,
        config: _primaryConfig(() => _showOverflowSheet(context)),
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
