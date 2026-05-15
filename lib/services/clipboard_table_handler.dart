import 'dart:convert';
import 'package:flutter_quill/quill_delta.dart';
import '../widgets/note_table_embed.dart';

/// Extracts HTML `<table>` blocks before normalisation (replacing each with a
/// placeholder) and re-injects them as Quill table embeds afterward.
///
/// Data tables (multi-column / `<th>` headers) → embedded grid widget.
/// Layout tables (single-column, e.g. Google Docs wrapper) → flattened `<p>`.
class ClipboardTableHandler {
  // ── Extract ──────────────────────────────────────────────────────────────────

  String extract(String html, Map<String, List<List<String>>> tables) {
    var i = 0;
    return html.replaceAllMapped(
      RegExp(r'<table\b[^>]*>.*?</table>', dotAll: true, caseSensitive: false),
      (m) {
        final tableHtml = m.group(0)!;
        if (_isDataTable(tableHtml)) {
          final key = '___TABLE_${i++}___';
          tables[key] = _parseTableRows(tableHtml);
          return '<p>$key</p>';
        }
        return _richTableToParagraphs(tableHtml);
      },
    );
  }

  bool _isDataTable(String tableHtml) {
    if (RegExp(r'<th\b', caseSensitive: false).hasMatch(tableHtml)) return true;
    for (final row in RegExp(r'<tr\b[^>]*>(.*?)</tr>',
            dotAll: true, caseSensitive: false)
        .allMatches(tableHtml)) {
      if (RegExp(r'<t[dh]\b', caseSensitive: false)
              .allMatches(row.group(1)!)
              .length > 1) {
        return true;
      }
    }
    return false;
  }

  String _richTableToParagraphs(String tableHtml) {
    final buf = StringBuffer();
    for (final row in RegExp(r'<tr\b[^>]*>(.*?)</tr>',
            dotAll: true, caseSensitive: false)
        .allMatches(tableHtml)) {
      for (final cell in RegExp(r'<t[dh]\b[^>]*>(.*?)</t[dh]>',
              dotAll: true, caseSensitive: false)
          .allMatches(row.group(1)!)) {
        final content = cell.group(1)!.trim();
        if (content.isEmpty) continue;
        if (RegExp(r'^\s*<(p|h[1-6]|ul|ol|div)\b', caseSensitive: false)
            .hasMatch(content)) {
          buf.write(content);
        } else {
          buf.write('<p>$content</p>');
        }
      }
    }
    return buf.toString();
  }

  List<List<String>> _parseTableRows(String tableHtml) {
    final rows = <List<String>>[];
    for (final row in RegExp(r'<tr\b[^>]*>(.*?)</tr>',
            dotAll: true, caseSensitive: false)
        .allMatches(tableHtml)) {
      final cells = <String>[];
      for (final cell in RegExp(r'<t[dh]\b[^>]*>(.*?)</t[dh]>',
              dotAll: true, caseSensitive: false)
          .allMatches(row.group(1)!)) {
        cells.add(cell.group(1)!
            .replaceAll(RegExp(r'<[^>]+>'), '')
            .replaceAll('&amp;', '&')
            .replaceAll('&lt;', '<')
            .replaceAll('&gt;', '>')
            .replaceAll('&nbsp;', ' ')
            .replaceAll('&quot;', '"')
            .trim());
      }
      if (cells.isNotEmpty) rows.add(cells);
    }
    return rows;
  }

  // ── Inject ───────────────────────────────────────────────────────────────────

  Delta inject(Delta delta, Map<String, List<List<String>>> tables) {
    final result = Delta();
    for (final op in delta.toList()) {
      if (!op.isInsert || op.data is! String) { result.push(op); continue; }
      var text = op.data as String;
      var matched = false;
      for (final entry in tables.entries) {
        final idx = text.indexOf(entry.key);
        if (idx < 0) continue;
        if (idx > 0) result.insert(text.substring(0, idx), op.attributes);
        result.insert({kTableEmbedType: jsonEncode(entry.value)});
        text = text.substring(idx + entry.key.length);
        matched = true;
        break;
      }
      if (matched) {
        if (text.isNotEmpty) result.insert(text, op.attributes);
      } else {
        result.push(op);
      }
    }
    return result;
  }
}
