/// Normalises HTML from external sources before converting to Quill delta.
///
/// Handles:
/// - Apple Notes: CSS-class-based styles → semantic tags
/// - Google Docs: <p> nested inside <li> for list items
/// - Tables: cell content extracted as paragraphs (Quill has no table support)
/// - Images: stripped — clipboard images come via pasteImageFromClipboard
String normalizeHtml(String html) {
  var result = html;

  // 1. Strip MS Word Office-namespace elements (e.g. <o:p>&nbsp;</o:p>).
  //    These add spurious non-breaking spaces and noise that confuse HtmlToDelta.
  result = result.replaceAll(
    RegExp(r'<o:\w+\b[^>]*>.*?</o:\w+>', dotAll: true, caseSensitive: false),
    '');
  result = result.replaceAll(
    RegExp(r'</?o:\w+\b[^>]*>', caseSensitive: false),
    '');
  // Strip MS Word paragraph class (quoted or unquoted) so HtmlToDelta treats
  // <p class=MsoNormal> as a standard block element and emits \n for each one.
  result = result.replaceAll(
    RegExp(r'''\bclass=(?:"MsoNormal"|'MsoNormal'|MsoNormal)\b''',
        caseSensitive: false),
    '');

  // 2. Unwrap Google Docs content marker: <b id="docs-internal-guid-..." style="font-weight:normal;">
  //    HtmlToDelta treats <b> as bold and flattens all block children (h2, p, ol…)
  //    into a single inline run with no newlines. Stripping the wrapper restores
  //    block structure and prevents spurious bold on every op.
  result = result.replaceAllMapped(
    RegExp(
      r'<b\b[^>]*\bid="docs-internal-guid-[^"]*"[^>]*>(.*?)</b>',
      dotAll: true,
      caseSensitive: false,
    ),
    (m) => m.group(1)!,
  );

  // 3. Strip Apple's clipboard insertion marker — it's not content and
  //    causes HtmlToDelta to stop parsing any remaining elements.
  result = result.replaceAll(
    RegExp(r'<br\b[^>]*class="Apple-interchange-newline"[^>]*/?>',
        caseSensitive: false),
    '');

  // 3. Replace Apple tab spans with non-breaking spaces so the surrounding
  //    paragraph text is not lost when HtmlToDelta encounters the tab char.
  result = result.replaceAll(
    RegExp(r'<span\b[^>]*class="Apple-tab-span"[^>]*>.*?</span>',
        dotAll: true, caseSensitive: false),
    '    ');

  // 4. Trailing all-<br> span at end of <li> → blank paragraph after </li>.
  //    Google Docs encodes "press Enter after a bullet" as a <span> containing
  //    only <br> tags at the very end of the <p> inside the <li>. Step 5 would
  //    strip that span (empty parts after split), losing the blank-line intent.
  //    We remove the span here and append <p></p> after </li> so the blank
  //    line survives the <p>-unwrap step that follows.
  result = result.replaceAllMapped(
    RegExp(r'<span\b[^>]*>(?:\s*<br\s*/?>\s*)+</span>(</p></li>)',
        dotAll: true, caseSensitive: false),
    (m) => '${m.group(1)}<p></p>',
  );

  // 5. Split <ul>/<ol> at <p></p> boundaries so blank paragraphs land outside
  //    the list context. HtmlToDelta ignores <p></p> inside a <ul>; by
  //    closing and reopening the list around each <p></p> marker the blank
  //    line becomes a proper inter-list paragraph that HtmlToDelta emits.
  result = result.replaceAllMapped(
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

  // 6. Split <span> elements that contain <br> into separate spans, one per
  //    line. This must run before the <p>/<li> split (steps 7-8) because
  //    _inlineToSemantic (step 11) uses dotAll regex and would otherwise
  //    re-merge content across paragraph boundaries through unclosed spans.
  result = _splitTagAtBr(result, 'span', joinWith: '<br>');
  // 5. Split <p> and <li> elements at <br> boundaries (spans are now properly
  //    closed so each split part is valid HTML with no orphaned tags).
  result = _splitTagAtBr(result, 'p');
  // 6. (see _splitTagAtBr for <li> — same rationale as step 5)
  result = _splitTagAtBr(result, 'li');

  // 7. Remove all <img> tags. Images copied as PNG/JPEG data are handled by
  //    pasteImageFromClipboard via the native platform channel. Keeping <img>
  //    src="https://..." in the HTML would create broken URL-based embeds.
  result = result.replaceAll(
    RegExp(r'<img\b[^>]*/?>', caseSensitive: false), '');

  // 8. Unwrap <p> nested directly inside <li> (Google Docs list structure).
  //    <li><p>text</p></li>  →  <li>text</li>
  result = result.replaceAllMapped(
    RegExp(r'<li(\b[^>]*)>\s*<p[^>]*>(.*?)</p>\s*</li>',
        dotAll: true, caseSensitive: false),
    (m) => '<li${m.group(1)}>${m.group(2)!.trim()}</li>',
  );

  // 9. Resolve CSS class styles → inline styles (Apple Notes / Cocoa).
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
  }

  // 10. Always convert inline styles → semantic tags so that sources that
  //    use style="" directly (Google Docs, web pages) also get formatting.
  result = _inlineToSemantic(result);

  // 11. Convert <br/> between block elements to an empty <p> element.
  //     A bare <br/> between </p> and <p> or <h1>–<h6> in Google Docs HTML
  //     represents an empty line. HtmlToDelta ignores <br/> between block
  //     elements, so we materialise it as <p></p> before step 12.
  result = result.replaceAllMapped(
    RegExp(r'</p>\s*<br\s*/?>\s*(<(?:p|h[1-6])\b)', caseSensitive: false),
    (m) => '</p><p></p>${m.group(1)}',
  );

  // 12. Insert <br/> between any </p> … <p> pair (with optional whitespace).
  //     Google Docs puts </p><p> directly adjacent; MS Word separates them
  //     with newlines. Without this separator HtmlToDelta merges all same-
  //     colour paragraphs into a single text op with no newlines.
  result = result.replaceAll(
    RegExp(r'</p>\s*<p\b', caseSensitive: false),
    '</p><br/><p',
  );

  // 12. Google Docs / Web: margin-left on <p> → leading \t text node.
  //     Run last so no intermediate step can drop the injected character.
  //     36pt per indent level (Google Docs standard). The \t is detected by
  //     _convertLeadingSpacesToIndent and converted to a Quill {indent: N}
  //     line attribute (block indentation, not an inline tab-stop embed).
  result = result.replaceAllMapped(
    RegExp(r'<p\b([^>]*)>', caseSensitive: false),
    (m) {
      final attrs = m.group(1)!;
      final marginMatch = RegExp(r'margin-left:\s*([\d.]+)pt', caseSensitive: false)
          .firstMatch(attrs);
      if (marginMatch == null) return m.group(0)!;
      final marginPt = double.tryParse(marginMatch.group(1)!) ?? 0;
      final level = (marginPt / 36).round().clamp(0, 10);
      if (level == 0) return m.group(0)!;
      return '${m.group(0)!}${'\t' * level}';
    },
  );

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
          kv.startsWith('text-decoration') ||
          kv.startsWith('color') ||
          kv.startsWith('background-color')) {
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
      final style = m.group(1)!;
      final styleLower = style.toLowerCase();
      var content = m.group(2)!;

      // Convert weight/style/decoration to semantic tags that HtmlToDelta
      // recognises. These replace the span — colour is handled separately.
      if (_hasProp(styleLower, 'font-weight', r'bold|700')) {
        content = '<strong>$content</strong>';
      }
      if (_hasProp(styleLower, 'font-style', 'italic')) {
        content = '<em>$content</em>';
      }
      if (styleLower.contains('underline')) content = '<u>$content</u>';
      if (styleLower.contains('line-through')) content = '<s>$content</s>';

      // Preserve colour and background-colour as a <span> so HtmlToDelta
      // can emit {color:…} / {background:…} Quill attributes.
      final colorStyle = _extractColorStyle(style);
      return colorStyle.isEmpty
          ? content
          : '<span style="$colorStyle">$content</span>';
    },
  );
}

/// Extracts `color` and `background-color` properties from a CSS style string,
/// skipping transparent/inherit values that carry no visual meaning.
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
/// so downstream `<p>`/`<li>` splits can later separate them; for block
/// elements the parts are joined without a separator.
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
        // Content was only <br>. For block elements, preserve as an empty
        // element so step 12 can inject a separator and HtmlToDelta emits a
        // blank paragraph. For inline elements (span), drop it — no content.
        return joinWith.isEmpty ? '<$tag$attrs></$tag>' : '';
      }
      return parts.map((part) => '<$tag$attrs>$part</$tag>').join(joinWith);
    },
  );
}
