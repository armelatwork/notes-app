/// Normalises HTML from external sources before converting to Quill delta.
///
/// Handles:
/// - Apple Notes: CSS-class-based styles → semantic tags
/// - Google Docs: `<p>` nested inside `<li>` for list items
/// - Tables: cell content extracted as paragraphs (Quill has no table support)
/// - Images: stripped — clipboard images come via pasteImageFromClipboard
String normalizeHtml(String html) {
  var result = _stripMsWordArtefacts(html);
  result = _unwrapGoogleDocsMarker(result);
  result = _cleanAppleClipboardMarkers(result);
  result = _normalizeListBlankLines(result);
  result = _splitBlocksAndClean(result);
  result = _resolveClassAndInlineStyles(result);
  result = _insertParagraphGaps(result);
  result = _applyMarginLeftIndent(result);
  return result;
}

// ── Source-specific cleanup ───────────────────────────────────────────────────

String _stripMsWordArtefacts(String html) {
  var result = html.replaceAll(
    RegExp(r'<o:\w+\b[^>]*>.*?</o:\w+>', dotAll: true, caseSensitive: false),
    '');
  result = result.replaceAll(
    RegExp(r'</?o:\w+\b[^>]*>', caseSensitive: false),
    '');
  // Strip MS Word paragraph class so HtmlToDelta treats <p class=MsoNormal>
  // as a standard block element and emits \n for each one.
  return result.replaceAll(
    RegExp(r'''\bclass=(?:"MsoNormal"|'MsoNormal'|MsoNormal)\b''',
        caseSensitive: false),
    '');
}

String _unwrapGoogleDocsMarker(String html) =>
    html.replaceAllMapped(
      RegExp(
        r'<b\b[^>]*\bid="docs-internal-guid-[^"]*"[^>]*>(.*?)</b>',
        dotAll: true,
        caseSensitive: false,
      ),
      (m) => m.group(1)!,
    );

String _cleanAppleClipboardMarkers(String html) {
  // Apple's clipboard insertion marker stops HtmlToDelta from parsing further.
  var result = html.replaceAll(
    RegExp(r'<br\b[^>]*class="Apple-interchange-newline"[^>]*/?>',
        caseSensitive: false),
    '');
  // Apple tab spans → 4 spaces so the surrounding paragraph text is kept.
  return result.replaceAll(
    RegExp(r'<span\b[^>]*class="Apple-tab-span"[^>]*>.*?</span>',
        dotAll: true, caseSensitive: false),
    '    ');
}

// ── List structure ────────────────────────────────────────────────────────────

String _normalizeListBlankLines(String html) {
  // Trailing all-<br> span after <li> → blank paragraph after </li>.
  // Google Docs encodes "press Enter after a bullet" as a <span> of <br> tags;
  // we preserve the intent as <p></p> so step 5 can split the list around it.
  var result = html.replaceAllMapped(
    RegExp(r'<span\b[^>]*>(?:\s*<br\s*/?>\s*)+</span>(</p></li>)',
        dotAll: true, caseSensitive: false),
    (m) => '${m.group(1)}<p></p>',
  );
  // Split <ul>/<ol> at <p></p> boundaries so blank paragraphs land outside
  // the list context. HtmlToDelta ignores <p></p> inside a <ul>.
  return result.replaceAllMapped(
    RegExp(r'(<(?:ul|ol)\b[^>]*>)(.*?)(</(?:ul|ol)>)',
        dotAll: true, caseSensitive: false),
    (m) {
      final open = m.group(1)!;
      final body = m.group(2)!;
      final close = m.group(3)!;
      if (!body.contains('<p></p>')) return m.group(0)!;
      final buf = StringBuffer();
      final segs = body.split('<p></p>');
      for (int i = 0; i < segs.length; i++) {
        final seg = segs[i].trim();
        if (seg.isNotEmpty) buf.write('$open$seg$close');
        if (i < segs.length - 1) buf.write('<p></p>');
      }
      return buf.toString();
    },
  );
}

// ── Block splitting and cleaning ──────────────────────────────────────────────

String _splitBlocksAndClean(String html) {
  // Split <span>/<p>/<li> at <br> so each becomes its own element.
  var result = _splitTagAtBr(html, 'span', joinWith: '<br>');
  result = _splitTagAtBr(result, 'p');
  result = _splitTagAtBr(result, 'li');
  // Remove <img>: clipboard images arrive via pasteImageFromClipboard.
  result = result.replaceAll(
    RegExp(r'<img\b[^>]*/?>', caseSensitive: false), '');
  // Unwrap <p> nested directly inside <li> (Google Docs list structure).
  return result.replaceAllMapped(
    RegExp(r'<li(\b[^>]*)>\s*<p[^>]*>(.*?)</p>\s*</li>',
        dotAll: true, caseSensitive: false),
    (m) => '<li${m.group(1)}>${m.group(2)!.trim()}</li>',
  );
}

// ── Style resolution ──────────────────────────────────────────────────────────

String _resolveClassAndInlineStyles(String html) {
  var result = html;
  final classStyles = _extractClassStyles(html);
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
  }
  return _inlineToSemantic(result);
}

// ── Paragraph gap insertion ───────────────────────────────────────────────────

String _insertParagraphGaps(String html) {
  // A bare <br/> between block elements represents an empty line in Google
  // Docs. HtmlToDelta ignores it, so materialise it as <p></p>.
  var result = html.replaceAllMapped(
    RegExp(r'</p>\s*<br\s*/?>\s*(<(?:p|h[1-6])\b)', caseSensitive: false),
    (m) => '</p><p></p>${m.group(1)}',
  );
  // Insert <br/> between adjacent </p><p> pairs so HtmlToDelta doesn't
  // merge same-colour paragraphs into a single op with no newlines.
  return result.replaceAll(
    RegExp(r'</p>\s*<p\b', caseSensitive: false),
    '</p><br/><p',
  );
}

// ── Margin-left → indent ──────────────────────────────────────────────────────

String _applyMarginLeftIndent(String html) =>
    html.replaceAllMapped(
      RegExp(r'<p\b([^>]*)>', caseSensitive: false),
      (m) {
        final attrs = m.group(1)!;
        final marginMatch =
            RegExp(r'margin-left:\s*([\d.]+)pt', caseSensitive: false)
                .firstMatch(attrs);
        if (marginMatch == null) return m.group(0)!;
        final marginPt = double.tryParse(marginMatch.group(1)!) ?? 0;
        final level = (marginPt / 36).round().clamp(0, 10);
        if (level == 0) return m.group(0)!;
        // Leading \t is detected by ClipboardDeltaProcessor and converted
        // to a Quill {indent: N} block attribute (not an inline tab embed).
        return '${m.group(0)!}${'\t' * level}';
      },
    );

// ── Style extraction helpers ──────────────────────────────────────────────────

Map<String, String> _extractClassStyles(String html) {
  final map = <String, String>{};
  final styleContent = RegExp(
    r'<style[^>]*>(.*?)</style>',
    dotAll: true,
    caseSensitive: false,
  ).firstMatch(html)?.group(1) ?? '';
  for (final m in RegExp(r'[^{]*\.(\w+)\s*\{([^}]+)\}').allMatches(styleContent)) {
    final relevant = <String>[];
    for (final prop in m.group(2)!.split(';')) {
      final kv = prop.trim();
      if (kv.startsWith('font-weight') || kv.startsWith('font-style') ||
          kv.startsWith('text-decoration') || kv.startsWith('color') ||
          kv.startsWith('background-color')) {
        relevant.add(kv);
      }
    }
    if (relevant.isNotEmpty) map[m.group(1)!] = relevant.join('; ');
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
      final style = m.group(1)!;
      final styleLower = style.toLowerCase();
      var content = m.group(2)!;
      if (_hasProp(styleLower, 'font-weight', r'bold|700')) {
        content = '<strong>$content</strong>';
      }
      if (_hasProp(styleLower, 'font-style', 'italic')) {
        content = '<em>$content</em>';
      }
      if (styleLower.contains('underline')) content = '<u>$content</u>';
      if (styleLower.contains('line-through')) content = '<s>$content</s>';
      final colorStyle = _extractColorStyle(style);
      return colorStyle.isEmpty
          ? content
          : '<span style="$colorStyle">$content</span>';
    },
  );
}

String _extractColorStyle(String style) {
  final parts = <String>[];
  for (final raw in style.split(';')) {
    final prop = raw.trim();
    final colon = prop.indexOf(':');
    if (colon < 0) continue;
    final key = prop.substring(0, colon).trim().toLowerCase();
    final val = prop.substring(colon + 1).trim();
    if (_isTransparentColor(val)) continue;
    if (key == 'color') {
      parts.add('color: $val');
    } else if (key == 'background-color') {
      parts.add('background-color: $val');
    }
  }
  return parts.join('; ');
}

bool _isTransparentColor(String val) {
  final v = val.toLowerCase();
  return v == 'transparent' || v == 'inherit' || v == 'initial' ||
      v == 'rgba(0,0,0,0)' || v == 'rgba(0, 0, 0, 0)';
}

bool _hasProp(String style, String property, String valuePattern) =>
    RegExp('$property\\s*:\\s*($valuePattern)').hasMatch(style);

/// Splits [tag] elements at `<br>` boundaries. Each resulting part is wrapped
/// in its own `<tag attrs>…</tag>`. For `<span>`, parts are joined with `<br>`
/// so downstream block splits can later separate them; block elements use no
/// separator.
String _splitTagAtBr(String html, String tag, {String joinWith = ''}) {
  return html.replaceAllMapped(
    RegExp('<$tag(\\b[^>]*)>(.*?)</$tag>', dotAll: true, caseSensitive: false),
    (m) {
      final attrs = m.group(1)!;
      final content = m.group(2)!;
      if (!RegExp(r'<br\s*/?>', caseSensitive: false).hasMatch(content)) {
        return m.group(0)!;
      }
      final parts = content
          .split(RegExp(r'<br\s*/?>', caseSensitive: false))
          .where((part) => part.trim().isNotEmpty)
          .toList();
      if (parts.isEmpty) {
        // Content was only <br>. For block elements, preserve as empty so a
        // separator can be injected and HtmlToDelta emits a blank paragraph.
        return joinWith.isEmpty ? '<$tag$attrs></$tag>' : '';
      }
      return parts.map((part) => '<$tag$attrs>$part</$tag>').join(joinWith);
    },
  );
}
