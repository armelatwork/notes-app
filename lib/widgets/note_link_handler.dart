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
  if (uri != null) launchUrl(uri, mode: LaunchMode.externalApplication);
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
              final (start, end) =
                  _fullLinkRange(controller, selStart, existingUrl);
              controller.formatText(
                  start, end - start, const LinkAttribute(null));
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

/// Returns the [start, end) document range of the contiguous run of ops
/// that share [url] as their link attribute and contains [offset].
(int, int) _fullLinkRange(QuillController ctrl, int offset, String url) {
  int pos = 0;
  int? start;
  int end = 0;
  bool passedOffset = false;

  for (final op in ctrl.document.toDelta().toList()) {
    final len = op.length ?? 0;
    final opUrl = op.attributes?['link'] as String?;

    if (opUrl == url) {
      start ??= pos;
      end = pos + len;
      if (pos <= offset && offset < pos + len) passedOffset = true;
    } else {
      if (passedOffset) break;
      start = null;
      end = 0;
    }
    pos += len;
  }

  return (start ?? offset, end > 0 ? end : offset + 1);
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
