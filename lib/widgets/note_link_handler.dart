import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:url_launcher/url_launcher.dart';

String? getLinkAtSelection(QuillController controller) {
  final style = controller.getSelectionStyle();
  return style.attributes[Attribute.link.key]?.value as String?;
}

void openLinkAtPosition(QuillController controller, int docOffset) {
  final node = controller.document.queryChild(docOffset);
  if (node.node == null) return;
  final url =
      node.node!.style.attributes[Attribute.link.key]?.value as String?;
  if (url == null) return;
  final uri = Uri.tryParse(url);
  if (uri != null) launchUrl(uri);
}

void showInsertLinkDialog(BuildContext context, QuillController controller) {
  final sel = controller.selection;
  final selStart = sel.start;
  final selLength = sel.end - sel.start;
  final selectedText = selLength > 0
      ? controller.document.getPlainText(selStart, selLength).trimRight()
      : '';
  final existingUrl = getLinkAtSelection(controller);

  final urlController = TextEditingController(text: existingUrl ?? '');
  final textController = TextEditingController(text: selectedText);

  showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(existingUrl != null ? 'Edit Link' : 'Insert Link'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: textController,
            decoration: const InputDecoration(labelText: 'Display text'),
            autofocus: selectedText.isEmpty && existingUrl == null,
          ),
          const SizedBox(height: 8),
          TextField(
            controller: urlController,
            decoration: const InputDecoration(labelText: 'URL'),
            keyboardType: TextInputType.url,
            autofocus: selectedText.isNotEmpty || existingUrl != null,
          ),
        ],
      ),
      actions: [
        if (existingUrl != null)
          TextButton(
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            onPressed: () {
              controller.formatText(
                selStart,
                selLength > 0 ? selLength : 1,
                const LinkAttribute(null),
              );
              Navigator.pop(ctx);
            },
            child: const Text('Remove link'),
          ),
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => _applyLink(
            ctx,
            controller,
            selStart,
            selLength,
            existingUrl,
            urlController.text,
            textController.text,
          ),
          child: const Text('Apply'),
        ),
      ],
    ),
  );
}

void _applyLink(
  BuildContext context,
  QuillController controller,
  int selStart,
  int selLength,
  String? existingUrl,
  String rawUrl,
  String rawDisplayText,
) {
  final url = rawUrl.trim();
  if (url.isEmpty) {
    Navigator.pop(context);
    return;
  }
  final displayText =
      rawDisplayText.trim().isEmpty ? url : rawDisplayText.trim();

  if (selLength > 0) {
    controller.replaceText(selStart, selLength, displayText, null);
  } else if (existingUrl == null) {
    controller.document.insert(selStart, displayText);
  }
  controller.formatText(selStart, displayText.length, LinkAttribute(url));
  Navigator.pop(context);
}
