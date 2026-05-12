import 'package:flutter/services.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_test/flutter_test.dart';

// Exercises the paragraph-selection logic extracted from _NoteEditorState.
// The public surface under test is QuillController.updateSelection, driven
// by the same boundary-walking algorithm used in _selectParagraphAtCursor.

TextSelection _selectParagraphAtOffset(QuillController ctrl, int offset) {
  final text = ctrl.document.toPlainText();
  final clamped = offset.clamp(0, text.length);
  var start = clamped;
  while (start > 0 && text[start - 1] != '\n') {
    start--;
  }
  var end = clamped;
  while (end < text.length && text[end] != '\n') {
    end++;
  }
  final sel = TextSelection(baseOffset: start, extentOffset: end);
  ctrl.updateSelection(sel, ChangeSource.local);
  return sel;
}

QuillController _controllerWithText(String plain) {
  final doc = Document()..insert(0, plain);
  return QuillController(
    document: doc,
    selection: const TextSelection.collapsed(offset: 0),
  );
}

void main() {
  group('Triple-tap paragraph selection', () {
    test(
        'selectParagraph_cursorInOnlyParagraph_selectsAll', () {
      final ctrl = _controllerWithText('Hello world');
      addTearDown(ctrl.dispose);

      final sel = _selectParagraphAtOffset(ctrl, 5);

      expect(sel.start, 0);
      expect(sel.end, 11);
    });

    test(
        'selectParagraph_cursorAtStart_selectsFirstParagraph', () {
      final ctrl = _controllerWithText('First\nSecond');
      addTearDown(ctrl.dispose);

      final sel = _selectParagraphAtOffset(ctrl, 0);

      expect(sel.start, 0);
      expect(sel.end, 5);
    });

    test(
        'selectParagraph_cursorInSecondParagraph_selectsSecond', () {
      final ctrl = _controllerWithText('First\nSecond paragraph');
      addTearDown(ctrl.dispose);

      final sel = _selectParagraphAtOffset(ctrl, 8);

      expect(sel.start, 6);
      expect(sel.end, 22);
    });

    test(
        'selectParagraph_cursorOnNewline_selectsPrecedingParagraph', () {
      final ctrl = _controllerWithText('Hello\nWorld');
      addTearDown(ctrl.dispose);

      // offset 5 is the '\n' character — end walks stops immediately,
      // start walks back through 'Hello' to 0, selecting the first paragraph.
      final sel = _selectParagraphAtOffset(ctrl, 5);

      expect(sel.start, 0);
      expect(sel.end, 5);
    });

    test(
        'selectParagraph_multipleSentencesNoCR_selectsEntireParagraph', () {
      const text = 'Sentence one. Sentence two. Sentence three.';
      final ctrl = _controllerWithText(text);
      addTearDown(ctrl.dispose);

      final sel = _selectParagraphAtOffset(ctrl, 20);

      expect(sel.start, 0);
      expect(sel.end, text.length);
    });

    test(
        'selectParagraph_cursorInMiddleParagraph_doesNotSelectNeighbours', () {
      final ctrl = _controllerWithText('A\nB line here\nC');
      addTearDown(ctrl.dispose);

      final sel = _selectParagraphAtOffset(ctrl, 5);

      expect(sel.start, 2);
      expect(sel.end, 13);
    });

    test(
        'selectParagraph_emptyDocument_returnsEmptySelection', () {
      final ctrl = QuillController(
        document: Document(),
        selection: const TextSelection.collapsed(offset: 0),
      );
      addTearDown(ctrl.dispose);

      final sel = _selectParagraphAtOffset(ctrl, 0);

      expect(sel.start, equals(sel.end));
    });
  });
}
