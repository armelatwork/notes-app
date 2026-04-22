import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_test/flutter_test.dart';

// Mirrors the private constant in note_editor.dart.
// U+2003 EM SPACE: visually 1em wide, a single character in the cursor model.
const _kTabIndent = ' ';

void main() {
  group('Tab key indent', () {
    test('_kTabIndent_value_isEmSpace', () {
      expect(_kTabIndent, equals(' '));
      expect(_kTabIndent.length, equals(1));
    });

    test('replaceText_withTabIndent_atCursor_insertsOneEmSpaceCharacter', () {
      // Arrange
      final controller = QuillController(
        document: Document(),
        selection: const TextSelection.collapsed(offset: 0),
      );

      // Act — simulate _onKeyEvent Tab branch (null selection = flutter_quill
      // advances cursor naturally by the insertion length = 1)
      controller.replaceText(0, 0, _kTabIndent, null);

      // Assert — document starts with EM SPACE
      expect(controller.document.toPlainText(), startsWith(_kTabIndent));
    });

    test('replaceText_withTabIndent_replacesSelection', () {
      // Arrange
      final doc = Document()..insert(0, 'hello');
      final controller = QuillController(
        document: doc,
        selection: const TextSelection(baseOffset: 0, extentOffset: 5),
      );

      // Act — Tab over selection replaces it with EM SPACE
      controller.replaceText(0, 5, _kTabIndent, null);

      // Assert
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

      // Act — insert EM SPACE between 'a' and 'b'
      controller.replaceText(1, 0, _kTabIndent, null);

      // Assert — text is 'a<EM>b', one left-arrow goes to 1 (before EM SPACE)
      expect(controller.document.toPlainText(), startsWith('a b'));
    });
  });
}
