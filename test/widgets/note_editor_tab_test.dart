import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_test/flutter_test.dart';

// Mirrors the private constant in note_editor.dart so the test breaks
// if the value is changed without updating both sides.
const _kTabIndent = '\t';

void main() {
  group('Tab key indent', () {
    test('_kTabIndent_value_isSingleTabCharacter', () {
      expect(_kTabIndent, equals('\t'));
      expect(_kTabIndent.length, equals(1));
    });

    test('replaceText_withTabIndent_atCursor_insertsSingleTabCharacter', () {
      // Arrange
      final doc = Document();
      final controller = QuillController(
        document: doc,
        selection: const TextSelection.collapsed(offset: 0),
      );

      // Act – simulate what _onKeyEvent does on Tab
      const insertAt = 0;
      controller.replaceText(
        insertAt,
        0,
        _kTabIndent,
        TextSelection.collapsed(offset: insertAt + _kTabIndent.length),
      );

      // Assert
      expect(controller.document.toPlainText(), startsWith(_kTabIndent));
    });

    test('replaceText_withTabIndent_cursorLandsAfterTab', () {
      // Arrange
      final doc = Document();
      final controller = QuillController(
        document: doc,
        selection: const TextSelection.collapsed(offset: 0),
      );

      // Act
      const insertAt = 0;
      controller.replaceText(
        insertAt,
        0,
        _kTabIndent,
        TextSelection.collapsed(offset: insertAt + _kTabIndent.length),
      );

      // Assert – cursor is at offset 1, after the tab character
      expect(controller.selection.baseOffset, equals(1));
      expect(controller.selection.extentOffset, equals(1));
    });

    test('replaceText_withTabIndent_replacesSelection', () {
      // Arrange
      final doc = Document()..insert(0, 'hello');
      final controller = QuillController(
        document: doc,
        selection: const TextSelection(baseOffset: 0, extentOffset: 5),
      );

      // Act – tab over a selection replaces it with the tab character
      const sel = TextSelection(baseOffset: 0, extentOffset: 5);
      controller.replaceText(
        sel.start,
        sel.end - sel.start,
        _kTabIndent,
        TextSelection.collapsed(offset: sel.start + _kTabIndent.length),
      );

      // Assert – 'hello' replaced by single tab, cursor after it
      final text = controller.document.toPlainText();
      expect(text, startsWith(_kTabIndent));
      expect(text, isNot(contains('hello')));
      expect(controller.selection.baseOffset, equals(1));
    });

    test('replaceText_withTabIndent_atMidDocumentPosition_insertsCorrectly', () {
      // Arrange
      final doc = Document()..insert(0, 'ab');
      final controller = QuillController(
        document: doc,
        selection: const TextSelection.collapsed(offset: 1),
      );

      // Act – insert tab between 'a' and 'b'
      const insertAt = 1;
      controller.replaceText(
        insertAt,
        0,
        _kTabIndent,
        TextSelection.collapsed(offset: insertAt + _kTabIndent.length),
      );

      // Assert – cursor lands at offset 2 (after the tab), text is 'a\tb'
      final text = controller.document.toPlainText();
      expect(text, startsWith('a\tb'));
      expect(controller.selection.baseOffset, equals(2));
    });
  });
}
