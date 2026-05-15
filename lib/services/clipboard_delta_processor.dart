import 'package:flutter_quill/quill_delta.dart';
import '../widgets/note_tab_embed.dart';

/// Strips CSS-only attributes from an HTML-derived delta and converts
/// leading indent markers (tabs / 4-space groups) to proper Quill attributes.
class ClipboardDeltaProcessor {
  static const _kNonQuillAttributes = {'line-height', 'white-space', 'vertical-align'};

  Delta process(Delta rawDelta) =>
      _convertLeadingSpacesToIndent(_stripNonQuillAttributes(rawDelta));

  // ── Attribute stripping ──────────────────────────────────────────────────────

  Delta _stripNonQuillAttributes(Delta delta) {
    final result = Delta();
    for (final op in delta.toList()) {
      if (!op.isInsert) { result.push(op); continue; }
      final attrs = op.attributes;
      if (attrs == null || attrs.isEmpty ||
          !attrs.keys.any(_kNonQuillAttributes.contains)) {
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

  // ── Indent conversion ────────────────────────────────────────────────────────

  Delta _convertLeadingSpacesToIndent(Delta delta) {
    final ops = _splitMergedNewlineIndentOps(delta.toList());
    final indentByIdx = _computeIndentMap(ops);
    if (indentByIdx.isEmpty) return delta;
    return _buildIndentedDelta(ops, indentByIdx);
  }

  Map<int, int> _computeIndentMap(List<Operation> ops) {
    final kIndent = RegExp(r'^(\t|[  ]{4})+');
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
          final s = m.group(0)!.replaceAll(RegExp(r'[  ]{4}'), '\t');
          pendingIndent = s.length;
        }
        paraStart = false;
      } else {
        paraStart = false;
      }
    }
    return indentByIdx;
  }

  Delta _buildIndentedDelta(List<Operation> ops, Map<int, int> indentByIdx) {
    final result = Delta();
    bool paraStart = true;
    int pendingBlockIndent = 0;
    for (int i = 0; i < ops.length; i++) {
      final op = ops[i];
      if (!op.isInsert) { result.push(op); continue; }
      final data = op.data;
      if (data is String && data.isNotEmpty && data.replaceAll('\n', '').isEmpty) {
        pendingBlockIndent = _flushNewlineOp(result, op, pendingBlockIndent);
        paraStart = true;
      } else if (data is String && paraStart) {
        pendingBlockIndent = _flushParaStartOp(result, op);
        paraStart = false;
      } else {
        (pendingBlockIndent, paraStart) =
            _flushElseOp(result, op, pendingBlockIndent, paraStart);
      }
    }
    return result;
  }

  int _flushNewlineOp(Delta result, Operation op, int pendingBlockIndent) {
    if (pendingBlockIndent > 0) {
      final attrs = Map<String, dynamic>.from(op.attributes ?? {})
        ..['indent'] = pendingBlockIndent;
      result.insert(op.data, attrs);
      return 0;
    }
    result.push(op);
    return 0;
  }

  int _flushParaStartOp(Delta result, Operation op) {
    final data = op.data as String;
    final level = _leadingIndentLevel(data);
    final stripped = _stripLeadingIndent(data);
    if (level > 0 && data.startsWith('\t')) {
      if (stripped.isNotEmpty) result.insert(stripped, op.attributes);
      return level;
    }
    for (int t = 0; t < level; t++) {
      result.insert({kTabEmbedType: ''});
    }
    if (stripped.isNotEmpty) {
      result.insert(stripped, op.attributes);
    } else if (level == 0) {
      result.push(op);
    }
    return 0;
  }

  (int, bool) _flushElseOp(
      Delta result, Operation op, int pendingBlockIndent, bool paraStart) {
    final data = op.data;
    if (pendingBlockIndent > 0 && data is String && data.startsWith('\n')) {
      final attrs = Map<String, dynamic>.from(op.attributes ?? {})
        ..['indent'] = pendingBlockIndent;
      result.insert('\n', attrs);
      if (data.length > 1) result.insert(data.substring(1), op.attributes);
      return (0, true);
    }
    result.push(op);
    return (pendingBlockIndent, data is! String ? false : paraStart);
  }

  // ── Indent helpers ───────────────────────────────────────────────────────────

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

  /// Splits ops like `"\n\t"` that Delta merges when adjacent ops share null
  /// attributes after stripping. Without this, the paragraph-start indent
  /// detector never sees the leading `\t` because it starts after `\n`.
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
}
