import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_quill/quill_delta.dart';
import 'package:flutter_quill_delta_from_html/flutter_quill_delta_from_html.dart';
import 'package:notes_app/services/clipboard_delta_processor.dart';
import 'package:notes_app/utils/html_normalizer.dart';

// Runs the full paste pipeline: normalise → HtmlToDelta → process.
// Uses styled spans so adjacent ops are not merged by the Delta builder,
// matching what real Google Docs / Apple Notes HTML produces.
Delta _processHtml(String html) {
  final processor = ClipboardDeltaProcessor();
  final normalized = normalizeHtml(html);
  final rawDelta = HtmlToDelta().convert(normalized);
  return processor.process(rawDelta);
}

void main() {
  late ClipboardDeltaProcessor processor;

  setUp(() => processor = ClipboardDeltaProcessor());

  // ── Attribute stripping ────────────────────────────────────────────────────

  group('process_stripsNonQuillAttributes', () {
    test('removesLineHeight', () {
      final delta = Delta()
        ..insert('Hello', {'line-height': '1.5', 'bold': true});
      final result = processor.process(delta);
      final op = result.toList().first;
      expect(op.attributes?['line-height'], isNull);
      expect(op.attributes?['bold'], isTrue);
    });

    test('removesWhiteSpace', () {
      final delta = Delta()..insert('Text', {'white-space': 'pre'});
      final result = processor.process(delta);
      expect(result.toList().first.attributes, isNull);
    });

    test('removesVerticalAlign', () {
      final delta = Delta()
        ..insert('Text', {'vertical-align': 'super', 'bold': true});
      final result = processor.process(delta);
      expect(result.toList().first.attributes?['vertical-align'], isNull);
      expect(result.toList().first.attributes?['bold'], isTrue);
    });

    test('passesOpThroughWhenNoNonQuillAttributes', () {
      final delta = Delta()..insert('Plain', {'bold': true});
      final result = processor.process(delta);
      expect(result.toList().first.attributes?['bold'], isTrue);
    });
  });

  // ── Indent via margin-left (realistic Google Docs HTML) ────────────────────
  //
  // normalizeHtml injects a leading \t for each margin-left level. Real Google
  // Docs HTML always has styled <span> or <strong> tags inside <p>, which keeps
  // the \t op separate from the content op so indent detection works.

  group('process_convertsMarginLeftToBlockIndent', () {
    test('boldParagraphWithMarginLeft36pt_appliesIndent1', () {
      final result = _processHtml(
          '<p style="margin-left: 36pt;"><strong>Text</strong></p>');
      final ops = result.toList();
      final newlineOp = ops.lastWhere((op) => op.data == '\n');
      expect(newlineOp.attributes?['indent'], 1);
    });

    test('boldParagraphWithMarginLeft72pt_appliesIndent2', () {
      final result = _processHtml(
          '<p style="margin-left: 72pt;"><strong>Text</strong></p>');
      final ops = result.toList();
      final newlineOp = ops.lastWhere((op) => op.data == '\n');
      expect(newlineOp.attributes?['indent'], 2);
    });

    test('boldParagraphNoMarginLeft_producesNoIndent', () {
      final result = _processHtml('<p><strong>Normal</strong></p>');
      final ops = result.toList();
      expect(ops.every((op) => op.attributes?['indent'] == null), isTrue);
    });

    test('boldIsPreservedAlongsideIndent', () {
      final result = _processHtml(
          '<p style="margin-left: 36pt;"><strong>Bold</strong></p>');
      final ops = result.toList();
      expect(ops.any((op) => op.attributes?['bold'] == true), isTrue);
      final newlineOp = ops.lastWhere((op) => op.data == '\n');
      expect(newlineOp.attributes?['indent'], 1);
    });

    test('colorSpanWithMarginLeft_appliesIndentAndPreservesColor', () {
      final result = _processHtml(
          '<p style="margin-left: 36pt;">'
          '<span style="color: #333333;">Text</span></p>');
      final ops = result.toList();
      expect(ops.any((op) => op.attributes?['color'] != null), isTrue);
      final newlineOp = ops.lastWhere((op) => op.data == '\n');
      expect(newlineOp.attributes?['indent'], 1);
    });
  });

  // ── Two consecutive indented paragraphs ───────────────────────────────────

  group('process_handlesTwoConsecutiveIndentedParagraphs', () {
    test('bothParagraphsGetIndent', () {
      final result = _processHtml(
          '<p style="margin-left: 36pt;"><strong>A</strong></p>'
          '<p style="margin-left: 36pt;"><strong>B</strong></p>');
      final ops = result.toList();
      final newlineOps = ops.where((op) => op.data == '\n').toList();
      expect(newlineOps.length, greaterThanOrEqualTo(1));
      expect(newlineOps.every((op) => op.attributes?['indent'] == 1), isTrue);
    });
  });
}
