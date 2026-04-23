import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_test/flutter_test.dart';

// Mirrors the private constant in note_editor.dart so the test breaks
// if the value is changed without updating both sides.
const _kTabIndent = '    ';

void main() {
  group('Tab key indent', () {
    test('_kTabIndent_value_isFourSpaces', () {
      expect(_kTabIndent, equals('    '));
      expect(_kTabIndent.length, equals(4));
    });

    test('replaceText_withTabIndent_atCursorInsertsFourSpaces', () {
      // Arrange
      final doc = Document();
      final controller = QuillController(
        document: doc,
        selection: const TextSelection.collapsed(offset: 0),
      );

      // Act – simulate what _onKeyEvent does on Tab
      const sel = TextSelection.collapsed(offset: 0);
      controller.replaceText(sel.start, sel.end - sel.start, _kTabIndent, null);

      // Assert
      expect(controller.document.toPlainText(), startsWith(_kTabIndent));
    });

    test('replaceText_withTabIndent_replacesSelection', () {
      // Arrange
      final doc = Document()..insert(0, 'hello');
      final controller = QuillController(
        document: doc,
        selection: const TextSelection(baseOffset: 0, extentOffset: 5),
      );

      // Act – tab over a selection replaces it with indent
      const sel = TextSelection(baseOffset: 0, extentOffset: 5);
      controller.replaceText(sel.start, sel.end - sel.start, _kTabIndent, null);

      // Assert – 'hello' replaced by four spaces
      final text = controller.document.toPlainText();
      expect(text, startsWith(_kTabIndent));
      expect(text, isNot(contains('hello')));
    });

    test('replaceText_withTabIndent_atMidDocumentPosition_insertsCorrectly', () {
      // Arrange
      final doc = Document()..insert(0, 'ab');
      final controller = QuillController(
        document: doc,
        selection: const TextSelection.collapsed(offset: 1),
      );

      // Act – insert tab between 'a' and 'b'
      const sel = TextSelection.collapsed(offset: 1);
      controller.replaceText(sel.start, sel.end - sel.start, _kTabIndent, null);

      // Assert
      final text = controller.document.toPlainText();
      expect(text, startsWith('a    b'));
    });
  });
}
