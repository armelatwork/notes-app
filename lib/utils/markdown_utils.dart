import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_quill_delta_from_html/flutter_quill_delta_from_html.dart';
import 'package:markdown/markdown.dart' as md;
import '../services/app_logger.dart';

/// Converts a Markdown string to a Quill [Document].
///
/// Uses the pipeline: markdown → HTML → Quill delta → Document.
/// Falls back to plain-text insertion on any conversion error.
Document quillDocumentFromMarkdown(String markdownText) {
  if (markdownText.trim().isEmpty) return Document();
  try {
    final rawHtml = md.markdownToHtml(
      markdownText,
      extensionSet: md.ExtensionSet.gitHubFlavored,
    );
    // flutter_quill_delta_from_html classifies <p> as inline (not block),
    // so it never inserts a block-terminating \n between plain paragraphs.
    // <div> IS classified as block, so replacing <p> fixes paragraph breaks.
    final html = rawHtml
        .replaceAll('<p>', '<div>')
        .replaceAll('</p>', '</div>');
    final delta = HtmlToDelta().convert(html);
    return Document.fromJson(delta.toJson());
  } catch (e) {
    AppLogger.instance.warn(
        'markdown_utils', 'markdown→delta conversion failed, falling back to plain text', e);
    return Document()..insert(0, markdownText);
  }
}
