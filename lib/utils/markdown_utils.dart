import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_quill_delta_from_html/flutter_quill_delta_from_html.dart';
import 'package:markdown/markdown.dart' as md;
import '../services/app_logger.dart';
import '../services/clipboard_delta_processor.dart';

/// Converts a Markdown string to a Quill [Document].
///
/// Uses the pipeline: markdown → HTML → Quill delta → Document.
/// Falls back to plain-text insertion on any conversion error.
Document quillDocumentFromMarkdown(String markdownText) {
  if (markdownText.trim().isEmpty) return Document();
  try {
    final html = md.markdownToHtml(
      markdownText,
      extensionSet: md.ExtensionSet.gitHubFlavored,
    );
    final rawDelta = HtmlToDelta().convert(html);
    final cleanDelta = ClipboardDeltaProcessor().process(rawDelta);
    return Document.fromJson(cleanDelta.toJson());
  } catch (e) {
    AppLogger.instance.warn(
        'markdown_utils', 'markdown→delta conversion failed, falling back to plain text', e);
    return Document()..insert(0, markdownText);
  }
}
