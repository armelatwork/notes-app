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
import 'clipboard_delta_processor.dart';
import 'clipboard_table_handler.dart';

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
        final rawHtml = await reader.readValue(Formats.htmlText);
        if (rawHtml != null && rawHtml.isNotEmpty) {
          await _pasteFromHtml(ctrl, rawHtml);
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

  Future<void> _pasteFromHtml(QuillController ctrl, String rawHtml) async {
    final tableHandler = ClipboardTableHandler();
    final tables = <String, List<List<String>>>{};
    final processedHtml = tableHandler.extract(rawHtml, tables);
    final normalized = normalizeHtml(processedHtml);
    final rawDelta = HtmlToDelta().convert(normalized);
    var delta = ClipboardDeltaProcessor().process(rawDelta);
    if (tables.isNotEmpty) delta = tableHandler.inject(delta, tables);
    _insertDelta(ctrl, delta);
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
    // Clamp to length-2: macOS advances the cursor by 1 on the next keypress;
    // landing on length-1 (the terminal \n) triggers a Quill assertion.
    final docLen = ctrl.document.length;
    final maxOffset = docLen > 1 ? docLen - 2 : 0;
    final newOffset = (insertAt + _computeInsertedLength(pasted)).clamp(0, maxOffset);
    ctrl.updateSelection(
      TextSelection.collapsed(offset: newOffset),
      ChangeSource.local,
    );
  }

  int _computeInsertedLength(Delta pasted) =>
      pasted.toList().where((op) => op.isInsert).fold<int>(0, (sum, op) {
        final d = op.data;
        return sum + (d is String ? d.length : 1);
      });

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
