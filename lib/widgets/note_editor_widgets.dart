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
          controller: quillController,
          config: QuillSimpleToolbarConfig(
            showFontFamily: true,
            showFontSize: true,
            showBoldButton: true,
            showItalicButton: true,
            showUnderLineButton: true,
            showStrikeThrough: false,
            showColorButton: true,
            showBackgroundColorButton: true,
            showClearFormat: true,
            showAlignmentButtons: true,
            showLeftAlignment: true,
            showCenterAlignment: true,
            showRightAlignment: true,
            showHeaderStyle: true,
            showListNumbers: true,
            showListBullets: true,
            showListCheck: true,
            showCodeBlock: false,
            showQuote: false,
            showIndent: true,
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
            ],
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
