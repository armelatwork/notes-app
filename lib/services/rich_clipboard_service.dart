import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/services.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_quill/quill_delta.dart';
import 'package:super_clipboard/super_clipboard.dart';
import 'package:vsc_quill_delta_to_html/vsc_quill_delta_to_html.dart';
import 'package:flutter_quill_delta_from_html/flutter_quill_delta_from_html.dart';
import '../utils/html_normalizer.dart';
import '../widgets/note_tab_embed.dart';
import '../widgets/note_table_embed.dart';
import 'app_logger.dart';

// Internal clipboard format — lossless round-trip within My Notes.
// External apps ignore unknown types and see HTML or plain text instead.
final _kQuillDeltaFormat = CustomValueFormat<String>(
  applicationId: 'app.mynotes.quill-delta',
  // value is Uint8List on macOS/iOS; decode bytes → JSON string.
  onDecode: (value, _) async {
    if (value is Uint8List) return utf8.decode(value);
    return value as String?;
  },
  // Encode the JSON string as UTF-8 bytes for the platform clipboard.
  onEncode: (value, _) => utf8.encode(value),
);

class RichClipboardService {
  static final RichClipboardService instance = RichClipboardService._();
  RichClipboardService._();

  // Set synchronously at the start of _handlePaste() so the macOS native
  // Paste menu action (which fires simultaneously via the responder chain)
  // is suppressed before it can insert a duplicate.
  bool _keyboardPasteInProgress = false;

  // ── Copy ───────────────────────────────────────────────────────────────────

  /// Writes Quill delta JSON + HTML + plain text to the system clipboard.
  /// Paste within My Notes uses the lossless delta; external apps get HTML.
  Future<void> copy(QuillController ctrl) async {
    final sel = ctrl.selection;
    if (!sel.isValid || sel.isCollapsed) return;

    final fullText = ctrl.document.toPlainText();
    final start = sel.start.clamp(0, fullText.length);
    final end = sel.end.clamp(0, fullText.length);
    final plainText = fullText.substring(start, end);

    final selected = _sliceDelta(ctrl.document.toDelta(), sel.start, sel.end);
    final deltaJson = jsonEncode(selected.toJson());
    final html = _toHtml(selected);

    try {
      await SystemClipboard.instance?.write([
        DataWriterItem()
          ..add(_kQuillDeltaFormat(deltaJson))
          ..add(Formats.htmlText(html))
          ..add(Formats.plainText(plainText)),
      ]);
    } catch (e) {
      AppLogger.instance.warn('RichClipboard', 'rich copy failed, falling back', e);
      await Clipboard.setData(ClipboardData(text: plainText));
    }
  }

  // ── Paste ──────────────────────────────────────────────────────────────────

  /// Reads clipboard in priority order:
  /// 1. Quill delta JSON  → lossless (internal copy-paste within My Notes)
  /// 2. HTML              → preserves bold, italic, headings, lists, links
  /// 3. Plain text        → fallback, no formatting
  // Called by _handlePaste() before any await so the flag is set before
  // the macOS native Paste menu fires its own paste() call.
  void beginKeyboardPaste() => _keyboardPasteInProgress = true;
  void endKeyboardPaste()   => _keyboardPasteInProgress = false;

  Future<void> paste(QuillController ctrl, {bool fromKeyboard = false}) async {
    // On macOS, Cmd+V triggers both _onKeyEvent (keyboard handler) and the
    // native Paste menu action via the responder chain simultaneously.
    // The keyboard path calls paste(fromKeyboard: true) directly, so it is
    // never suppressed. The duplicate menu call (fromKeyboard: false) is
    // suppressed while the keyboard paste is in progress.
    if (!fromKeyboard && _keyboardPasteInProgress) return;

    AppLogger.instance.debug('RichClipboard', 'paste() called fromKeyboard=$fromKeyboard');
    try {
      final reader = await SystemClipboard.instance?.read();
      AppLogger.instance.debug('RichClipboard', 'clipboard reader: ${reader == null ? 'null' : 'ok'}'
          ' canDelta=${reader?.canProvide(_kQuillDeltaFormat)}'
          ' canHtml=${reader?.canProvide(Formats.htmlText)}'
          ' canText=${reader?.canProvide(Formats.plainText)}');
      if (reader == null) return;

      if (reader.canProvide(_kQuillDeltaFormat)) {
        final json = await reader.readValue(_kQuillDeltaFormat);
        if (json != null) {
          AppLogger.instance.debug('RichClipboard', 'pasting internal delta');
          _insertDelta(ctrl, Delta.fromJson(jsonDecode(json) as List));
          return;
        }
      }

      if (reader.canProvide(Formats.htmlText)) {
        final rawHtml = await reader.readValue(Formats.htmlText);
        if (rawHtml != null && rawHtml.isNotEmpty) {
          final tables = <String, List<List<String>>>{};
          final processedHtml = _extractTables(rawHtml, tables);
          AppLogger.instance.debug('RichClipboard', 'raw HTML:\n$processedHtml');
          final normalized = normalizeHtml(processedHtml);
          AppLogger.instance.debug('RichClipboard', 'normalized HTML:\n$normalized');
          final rawDelta = HtmlToDelta().convert(normalized);
          final indentOps = rawDelta.toList()
              .where((op) => op.isInsert && (
                  (op.data is String && (op.data as String).contains('\t')) ||
                  (op.attributes?.containsKey('indent') ?? false)))
              .map((op) => 'data=${op.data} attrs=${op.attributes}')
              .join(' | ');
          AppLogger.instance.debug('RichClipboard', 'indent-related ops: $indentOps');
          var delta = _convertLeadingSpacesToIndent(
              _stripNonQuillAttributes(rawDelta));
          final tabEmbedOps = delta.toList()
              .where((op) => op.isInsert && op.data is Map)
              .map((op) => '${op.data}')
              .join(' | ');
          AppLogger.instance.debug('RichClipboard', 'embed ops after processing: $tabEmbedOps');
          if (tables.isNotEmpty) delta = _injectTableEmbeds(delta, tables);
          _insertDelta(ctrl, delta);
          return;
        }
      }

      final text = await reader.readValue(Formats.plainText);
      if (text != null && text.isNotEmpty) _insertPlainText(ctrl, text);
    } catch (e) {
      AppLogger.instance.warn('RichClipboard', 'rich paste failed, falling back', e);
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      if (data?.text != null) _insertPlainText(ctrl, data!.text!);
    }
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  Delta _sliceDelta(Delta full, int start, int end) {
    var pos = 0;
    final result = Delta();
    for (final op in full.toList()) {
      if (!op.isInsert) continue;
      final opLen = op.length ?? 0;
      final opEnd = pos + opLen;
      if (opEnd <= start) { pos = opEnd; continue; }
      if (pos >= end) break;
      final sliceStart = math.max(start - pos, 0);
      final sliceEnd = math.min(end - pos, opLen);
      if (op.data is String) {
        result.insert(
          (op.data as String).substring(sliceStart, sliceEnd),
          op.attributes,
        );
      } else if (sliceStart == 0) {
        result.insert(op.data, op.attributes);
      }
      pos = opEnd;
    }
    return result;
  }

  String _toHtml(Delta delta) {
    try {
      final ops = delta.toJson().cast<Map<String, dynamic>>();
      return QuillDeltaToHtmlConverter(ops).convert();
    } catch (_) {
      return '';
    }
  }

  void _insertDelta(QuillController ctrl, Delta pasted) {
    final sel = ctrl.selection;
    final insertAt = sel.isCollapsed ? sel.baseOffset : sel.start;
    final deleteLen = sel.isCollapsed ? 0 : sel.end - sel.start;

    final compose = Delta()..retain(insertAt);
    if (deleteLen > 0) compose.delete(deleteLen);
    for (final op in pasted.toList()) {
      if (op.isInsert) compose.push(op);
    }
    ctrl.document.compose(compose, ChangeSource.local);

    final insertedLen = pasted.toList()
        .where((op) => op.isInsert)
        .fold<int>(0, (sum, op) {
          final d = op.data;
          return sum + (d is String ? d.length : 1);
        });
    // Place cursor after the inserted content, clamped to document.length - 2.
    //
    // Using document.length - 1 (the terminal \n) is problematic on macOS:
    // when the user types the first character after paste, macOS computes the
    // new cursor as (current + 1) = document.length, which Quill rejects with
    // an index-out-of-range assertion. Staying one position earlier means the
    // first keystroke lands on document.length - 1, which is always valid.
    final docLen = ctrl.document.length;
    final maxOffset = docLen > 1 ? docLen - 2 : 0;
    final newOffset = (insertAt + insertedLen).clamp(0, maxOffset);
    ctrl.updateSelection(
      TextSelection.collapsed(offset: newOffset),
      ChangeSource.local,
    );
  }

  void _insertPlainText(QuillController ctrl, String text) {
    final sel = ctrl.selection;
    ctrl.replaceText(
      sel.isCollapsed ? sel.baseOffset : sel.start,
      sel.isCollapsed ? 0 : sel.end - sel.start,
      text,
      null,
    );
  }

  // ── Delta sanitisation ─────────────────────────────────────────────────────

  // CSS-derived attributes that HtmlToDelta emits but Quill cannot render.
  // Leaving them on text ops causes RenderEditable to miscalculate cursor
  // positions, which breaks keyboard input after paste.
  static const _kNonQuillAttributes = {'line-height', 'white-space', 'vertical-align'};

  Delta _stripNonQuillAttributes(Delta delta) {
    final result = Delta();
    for (final op in delta.toList()) {
      if (!op.isInsert) {
        result.push(op);
        continue;
      }
      final attrs = op.attributes;
      if (attrs == null || attrs.isEmpty || !attrs.keys.any(_kNonQuillAttributes.contains)) {
        result.push(op);
        continue;
      }
      final filtered = Map<String, dynamic>.fromEntries(
        attrs.entries.where((e) => !_kNonQuillAttributes.contains(e.key)),
      );
      result.insert(op.data, filtered.isEmpty ? null : filtered);
    }
    return result;
  }

  // ── Indent conversion ──────────────────────────────────────────────────────

  /// Converts paragraphs that start with groups of four spaces (from
  /// Apple-tab-span replacement) into proper Quill indent levels.
  /// The leading spaces are stripped and `{indent: N}` is applied to the
  /// paragraph-terminating `\n` op instead.
  Delta _convertLeadingSpacesToIndent(Delta delta) {
    // Pre-pass: split ops like "\n\t" that Delta merged after attribute
    // stripping. When a \n op and a \t op both end up with null attrs,
    // Delta.insert() merges them into "\n\t". Split them back into two
    // separate ops so the paragraph-start detection below works correctly.
    final ops = _splitMergedNewlineIndentOps(delta.toList());

    // Matches a tab or a group of 4 space/non-breaking-space chars.
    // Google Docs uses   (non-breaking space) inside white-space:pre
    // spans, which HtmlToDelta preserves. Regular ASCII spaces and raw \t
    // chars (from Apple-tab-span replacement) are also handled.
    final kIndent = RegExp(r'^(\t|[  ]{4})+');

    // Pass 1: find which \n ops need an indent level.
    final indentByIdx = <int, int>{};
    bool paraStart = true;
    int pendingIndent = 0;

    for (int i = 0; i < ops.length; i++) {
      final op = ops[i];
      if (!op.isInsert) continue;
      final data = op.data;
      if (data is String && data.isNotEmpty && data.replaceAll('\n', '').isEmpty) {
        if (pendingIndent > 0) indentByIdx[i] = pendingIndent;
        paraStart = true;
        pendingIndent = 0;
      } else if (data is String && paraStart) {
        final m = kIndent.firstMatch(data);
        if (m != null) {
          // Normalise to tabs to count levels (4 spaces/nbsp = 1 level)
          final s = m.group(0)!.replaceAll(RegExp(r'[  ]{4}'), '\t');
          pendingIndent = s.length;
        }
        paraStart = false;
      } else {
        paraStart = false;
      }
    }

    if (indentByIdx.isEmpty) return delta;

    // Pass 2: rebuild delta, converting leading indent to either:
    //   • kTabEmbedType embed  — space-based indent (Apple-tab-span, Tab key)
    //   • Quill {indent: N}   — \t-based indent (CSS margin-left, block style)
    final result = Delta();
    paraStart = true;
    int pendingBlockIndent = 0; // level to apply as {indent:N} to next \n op

    for (int i = 0; i < ops.length; i++) {
      final op = ops[i];
      if (!op.isInsert) { result.push(op); continue; }
      final data = op.data;

      if (data is String && data.isNotEmpty && data.replaceAll('\n', '').isEmpty) {
        if (pendingBlockIndent > 0) {
          final attrs = Map<String, dynamic>.from(op.attributes ?? {});
          attrs['indent'] = pendingBlockIndent;
          result.insert(data, attrs);
          pendingBlockIndent = 0;
        } else {
          result.push(op);
        }
        paraStart = true;
      } else if (data is String && paraStart) {
        final level = _leadingIndentLevel(data);
        final stripped = _stripLeadingIndent(data);
        if (level > 0 && data.startsWith('\t')) {
          // \t = margin-left (Google Docs): use Quill block indentation.
          // The \t op itself is consumed; {indent: N} goes on the \n op.
          pendingBlockIndent = level;
          if (stripped.isNotEmpty) result.insert(stripped, op.attributes);
        } else {
          // Spaces/nbsp = Tab-key press: use inline tab-stop embed.
          for (int t = 0; t < level; t++) {
            result.insert({kTabEmbedType: ''});
          }
          if (stripped.isNotEmpty) {
            result.insert(stripped, op.attributes);
          } else if (level == 0) {
            result.push(op);
          }
        }
        paraStart = false;
      } else {
        // If a block indent is pending and this op starts with \n, the
        // paragraph-ending \n was merged into it (null-attr Delta merging).
        // Pull out the first \n, tag it with {indent}, push the rest as-is.
        if (pendingBlockIndent > 0 &&
            data is String &&
            data.startsWith('\n')) {
          final s = data;
          final attrs = Map<String, dynamic>.from(op.attributes ?? {});
          attrs['indent'] = pendingBlockIndent;
          pendingBlockIndent = 0;
          result.insert('\n', attrs);
          paraStart = true;
          if (s.length > 1) result.insert(s.substring(1), op.attributes);
        } else {
          result.push(op);
          if (data is! String) paraStart = false;
        }
      }
    }

    return result;
  }

  int _leadingIndentLevel(String text) {
    int level = 0;
    int i = 0;
    while (i < text.length) {
      if (text[i] == '\t') {
        level++;
        i++;
      } else if (i + 4 <= text.length && _areIndentSpaces(text, i, 4)) {
        level++;
        i += 4;
      } else {
        break;
      }
    }
    return level;
  }

  String _stripLeadingIndent(String text) {
    int i = 0;
    while (i < text.length) {
      if (text[i] == '\t') {
        i++;
      } else if (i + 4 <= text.length && _areIndentSpaces(text, i, 4)) {
        i += 4;
      } else {
        break;
      }
    }
    return text.substring(i);
  }

  bool _areIndentSpaces(String text, int offset, int count) {
    for (int j = offset; j < offset + count; j++) {
      final c = text.codeUnitAt(j);
      if (c != 0x20 && c != 0xA0) return false;
    }
    return true;
  }

  /// Splits ops like `"\n\t"` that Delta merges when adjacent ops end up with
  /// the same (null) attributes after `_stripNonQuillAttributes`. Without this,
  /// `"\n"` + `"\t"` become `"\n\t"` — a single op that starts with `\n`, so
  /// the paragraph-start indent detector never sees the leading `\t`.
  List<Operation> _splitMergedNewlineIndentOps(List<Operation> ops) {
    final result = <Operation>[];
    for (final op in ops) {
      if (!op.isInsert || op.data is! String || op.attributes != null) {
        result.add(op);
        continue;
      }
      final s = op.data as String;
      final firstNonNl = s.indexOf(RegExp(r'[^\n]'));
      if (firstNonNl <= 0) { result.add(op); continue; }
      final rest = s.substring(firstNonNl);
      if (rest[0] != '\t' && !_areIndentSpaces(rest, 0, 1)) {
        result.add(op);
        continue;
      }
      result.add(Operation.insert(s.substring(0, firstNonNl)));
      result.add(Operation.insert(rest));
    }
    return result;
  }

  // ── Table extraction ───────────────────────────────────────────────────────

  /// Replaces each `<table>` in [html] with either a `<p>___TABLE_N___</p>`
  /// placeholder (data tables → embedded grid) or flattened `<p>` paragraphs
  /// (layout tables → formatted text, e.g. Google Docs single-column wrapper).
  String _extractTables(String html, Map<String, List<List<String>>> tables) {
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
        // Layout table (e.g. Google Docs single-column wrapper): flatten each
        // cell to paragraphs, keeping inner HTML so formatting is preserved.
        return _richTableToParagraphs(tableHtml);
      },
    );
  }

  /// Data tables have multiple cells per row or `<th>` header cells.
  /// Single-column tables are treated as layout containers (e.g. Google Docs).
  bool _isDataTable(String tableHtml) {
    if (RegExp(r'<th\b', caseSensitive: false).hasMatch(tableHtml)) { return true; }
    for (final row in RegExp(r'<tr\b[^>]*>(.*?)</tr>',
            dotAll: true, caseSensitive: false)
        .allMatches(tableHtml)) {
      if (RegExp(r'<t[dh]\b', caseSensitive: false)
              .allMatches(row.group(1)!)
              .length >
          1) { return true; }
    }
    return false;
  }

  /// Flattens a layout table into `<p>` blocks, preserving each cell's inner
  /// HTML so HtmlToDelta can process inline formatting (bold, italic, etc.).
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
        // If the cell already starts with a block element, use it as-is.
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

  /// Scans [delta] for placeholder text ops and replaces each one with
  /// a [kTableEmbedType] block embed carrying the parsed row data.
  Delta _injectTableEmbeds(
      Delta delta, Map<String, List<List<String>>> tables) {
    final result = Delta();
    for (final op in delta.toList()) {
      if (!op.isInsert || op.data is! String) {
        result.push(op);
        continue;
      }
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
