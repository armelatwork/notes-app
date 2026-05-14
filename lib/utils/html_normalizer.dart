/// Normalizes CSS-class-based HTML (Apple Notes, Cocoa editors) to semantic
/// HTML that flutter_quill_delta_from_html can parse.
///
/// Apple Notes copies with class-based styles:
///   <style> span.s2 { font-weight: bold } </style>
///   <span class="s2">Bold text</span>
///
/// This resolves those classes to standard <strong>, <em>, <u>, <s> tags.
String normalizeHtml(String html) {
  final classStyles = _extractClassStyles(html);
  if (classStyles.isEmpty) return html;

  var result = html.replaceAllMapped(
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

  return _inlineToSemantic(result);
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
