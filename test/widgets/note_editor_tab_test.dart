import 'package:flutter/services.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notes_app/widgets/note_tab_embed.dart';

void main() {
  group('Tab embed insert', () {
    test('insert_tabEmbed_atCursor_addsEmbedToDocument', () {
      // Arrange
      final controller = QuillController(
        document: Document(),
        selection: const TextSelection.collapsed(offset: 0),
      );

      // Act
      controller.document.insert(0, const Embeddable(kTabEmbedType, ''));

      // Assert — delta contains a tab embed op
      final ops = controller.document.toDelta().toList();
      expect(
        ops.any((op) =>
            op.isInsert &&
            op.data is Map &&
            (op.data as Map).containsKey(kTabEmbedType)),
        isTrue,
      );
    });

    test('insert_tabEmbed_atMidDocumentPosition_insertsCorrectly', () {
      // Arrange
      final doc = Document()..insert(0, 'ab');
      final controller = QuillController(
        document: doc,
        selection: const TextSelection.collapsed(offset: 1),
      );

      // Act — insert tab between 'a' and 'b'
      controller.document.insert(1, const Embeddable(kTabEmbedType, ''));

      // Assert — plain text is 'a<obj>b\n' where obj is embed character
      final plain = controller.document.toPlainText();
      expect(plain, startsWith('a'));
      expect(plain, contains('b'));
    });

    test('insert_tabEmbed_withSelection_replacesSelectionThenInsertsEmbed', () {
      // Arrange
      final doc = Document()..insert(0, 'hello');
      final controller = QuillController(
        document: doc,
        selection: const TextSelection(baseOffset: 0, extentOffset: 5),
      );

      // Act — replicate _insertTab behaviour: delete selection, then embed
      controller.replaceText(0, 5, '', null);
      controller.document.insert(0, const Embeddable(kTabEmbedType, ''));

      // Assert — 'hello' is gone, embed is present
      final plain = controller.document.toPlainText();
      expect(plain, isNot(contains('hello')));
      final ops = controller.document.toDelta().toList();
      expect(
        ops.any((op) =>
            op.isInsert &&
            op.data is Map &&
            (op.data as Map).containsKey(kTabEmbedType)),
        isTrue,
      );
    });

    test('kTabEmbedType_value_isTab', () {
      expect(kTabEmbedType, equals('tab'));
    });
  });
}
