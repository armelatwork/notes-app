import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/services.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_quill/quill_delta.dart';
import 'package:super_clipboard/super_clipboard.dart';
import 'package:vsc_quill_delta_to_html/vsc_quill_delta_to_html.dart';
import 'package:flutter_quill_delta_from_html/flutter_quill_delta_from_html.dart';
import '../utils/html_normalizer.dart';
import 'app_logger.dart';

// Internal clipboard format — lossless round-trip within My Notes.
// External apps ignore unknown types and see HTML or plain text instead.
final _kQuillDeltaFormat = CustomValueFormat<String>(
  applicationId: 'app.mynotes.quill-delta',
  onDecode: (value, _) async => value.toString(),
  onEncode: (value, _) => value,
);

class RichClipboardService {
  static final RichClipboardService instance = RichClipboardService._();
  RichClipboardService._();

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
  Future<void> paste(QuillController ctrl) async {
    try {
      final reader = await SystemClipboard.instance?.read();
      if (reader == null) return;

      if (reader.canProvide(_kQuillDeltaFormat)) {
        final json = await reader.readValue(_kQuillDeltaFormat);
        if (json != null) {
          _insertDelta(ctrl, Delta.fromJson(jsonDecode(json) as List));
          return;
        }
      }

      if (reader.canProvide(Formats.htmlText)) {
        final html = await reader.readValue(Formats.htmlText);
        if (html != null && html.isNotEmpty) {
          final delta = HtmlToDelta().convert(normalizeHtml(html));
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
    ctrl.updateSelection(
      TextSelection.collapsed(offset: insertAt + insertedLen),
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
}
