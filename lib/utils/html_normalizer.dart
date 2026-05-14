/// Normalises HTML from external sources before converting to Quill delta.
///
/// Handles:
/// - Apple Notes: CSS-class-based styles → semantic tags
/// - Google Docs: <p> nested inside <li> for list items
/// - Tables: cell content extracted as paragraphs (Quill has no table support)
/// - Images: stripped — clipboard images come via pasteImageFromClipboard
String normalizeHtml(String html) {
  var result = html;

  // 1. Remove all <img> tags. Images copied as PNG/JPEG data are handled by
  //    pasteImageFromClipboard via the native platform channel. Keeping <img>
  //    src="https://..." in the HTML would create broken URL-based embeds.
  result = result.replaceAll(
    RegExp(r'<img\b[^>]*/?>', caseSensitive: false), '');

  // 2. Convert table cells to paragraphs so cell text is preserved, then
  //    strip the surrounding table structure tags.
  result = result.replaceAllMapped(
    RegExp(r'<t[dh]\b[^>]*>(.*?)</t[dh]>',
        dotAll: true, caseSensitive: false),
    (m) => '<p>${m.group(1)!.trim()}</p>',
  );
  result = result.replaceAll(
    RegExp(
        r'</?(?:table|tbody|thead|tfoot|tr|colgroup|col)\b[^>]*>',
        caseSensitive: false),
    '',
  );

  // 3. Unwrap <p> nested directly inside <li> (Google Docs list structure).
  //    <li><p>text</p></li>  →  <li>text</li>
  result = result.replaceAllMapped(
    RegExp(r'<li(\b[^>]*)>\s*<p[^>]*>(.*?)</p>\s*</li>',
        dotAll: true, caseSensitive: false),
    (m) => '<li${m.group(1)}>${m.group(2)!.trim()}</li>',
  );

  // 4. Resolve Apple Notes / Cocoa CSS class styles → semantic HTML.
  final classStyles = _extractClassStyles(result);
  if (classStyles.isNotEmpty) {
    result = result.replaceAllMapped(
      RegExp(r'\bclass="([^"]*)"'),
      (m) {
        final props = <String>[];
        for (final cls in m.group(1)!.trim().split(RegExp(r'\s+'))) {
          final s = classStyles[cls];
          if (s != null) props.add(s);
        }
        return props.isEmpty ? '' : 'style="${props.join('; ')}"';
      },
    );
    result = _inlineToSemantic(result);
  }

  return result;
}

Map<String, String> _extractClassStyles(String html) {
  final map = <String, String>{};
  final styleContent = RegExp(
    r'<style[^>]*>(.*?)</style>',
    dotAll: true,
    caseSensitive: false,
  ).firstMatch(html)?.group(1) ?? '';

  for (final m in RegExp(r'[^{]*\.(\w+)\s*\{([^}]+)\}').allMatches(styleContent)) {
    final className = m.group(1)!;
    final relevant = <String>[];
    for (final prop in m.group(2)!.split(';')) {
      final kv = prop.trim();
      if (kv.startsWith('font-weight') ||
          kv.startsWith('font-style') ||
          kv.startsWith('text-decoration')) {
        relevant.add(kv);
      }
    }
    if (relevant.isNotEmpty) map[className] = relevant.join('; ');
  }
  return map;
}

String _inlineToSemantic(String html) {
  return html.replaceAllMapped(
    RegExp(
      r'<span\b[^>]*style="([^"]*)"[^>]*>(.*?)</span>',
      dotAll: true,
      caseSensitive: false,
    ),
    (m) {
      final style = m.group(1)!.toLowerCase();
      var content = m.group(2)!;
      if (_hasProp(style, 'font-weight', r'bold|700')) {
        content = '<strong>$content</strong>';
      }
      if (_hasProp(style, 'font-style', 'italic')) {
        content = '<em>$content</em>';
      }
      if (style.contains('underline')) content = '<u>$content</u>';
      if (style.contains('line-through')) content = '<s>$content</s>';
      return content;
    },
  );
}

bool _hasProp(String style, String property, String valuePattern) =>
    RegExp('$property\\s*:\\s*($valuePattern)').hasMatch(style);
