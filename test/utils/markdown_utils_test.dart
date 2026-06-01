import 'package:flutter_test/flutter_test.dart';
import 'package:notes_app/utils/markdown_utils.dart';

void main() {
  group('quillDocumentFromMarkdown', () {
    test('quillDocumentFromMarkdown_emptyString_returnsEmptyDocument', () {
      final doc = quillDocumentFromMarkdown('');
      expect(doc.toPlainText().trim(), isEmpty);
    });

    test('quillDocumentFromMarkdown_whitespaceOnly_returnsEmptyDocument', () {
      final doc = quillDocumentFromMarkdown('   \n  ');
      expect(doc.toPlainText().trim(), isEmpty);
    });

    test('quillDocumentFromMarkdown_plainText_preservesContent', () {
      final doc = quillDocumentFromMarkdown('Hello world');
      expect(doc.toPlainText(), contains('Hello world'));
    });

    test('quillDocumentFromMarkdown_boldText_producesBoldAttribute', () {
      final doc = quillDocumentFromMarkdown('**bold**');
      final ops = doc.toDelta().toList();
      final hasBold = ops.any(
        (op) => op.isInsert && op.attributes?['bold'] == true,
      );
      expect(hasBold, isTrue);
    });

    test('quillDocumentFromMarkdown_italicText_producesItalicAttribute', () {
      final doc = quillDocumentFromMarkdown('*italic*');
      final ops = doc.toDelta().toList();
      final hasItalic = ops.any(
        (op) => op.isInsert && op.attributes?['italic'] == true,
      );
      expect(hasItalic, isTrue);
    });

    test('quillDocumentFromMarkdown_h1_producesHeaderAttribute', () {
      final doc = quillDocumentFromMarkdown('# Heading 1');
      final ops = doc.toDelta().toList();
      final hasH1 = ops.any(
        (op) => op.isInsert && op.data == '\n' && op.attributes?['header'] == 1,
      );
      expect(hasH1, isTrue);
    });

    test('quillDocumentFromMarkdown_h2_producesH2Attribute', () {
      final doc = quillDocumentFromMarkdown('## Heading 2');
      final ops = doc.toDelta().toList();
      final hasH2 = ops.any(
        (op) => op.isInsert && op.data == '\n' && op.attributes?['header'] == 2,
      );
      expect(hasH2, isTrue);
    });

    test('quillDocumentFromMarkdown_bulletList_producesBulletAttribute', () {
      final doc = quillDocumentFromMarkdown('- item one');
      final ops = doc.toDelta().toList();
      final hasBullet = ops.any(
        (op) =>
            op.isInsert &&
            op.data == '\n' &&
            op.attributes?['list'] == 'bullet',
      );
      expect(hasBullet, isTrue);
    });

    test('quillDocumentFromMarkdown_orderedList_producesOrderedAttribute', () {
      final doc = quillDocumentFromMarkdown('1. first item');
      final ops = doc.toDelta().toList();
      final hasOrdered = ops.any(
        (op) =>
            op.isInsert &&
            op.data == '\n' &&
            op.attributes?['list'] == 'ordered',
      );
      expect(hasOrdered, isTrue);
    });

    test('quillDocumentFromMarkdown_mixedContent_preservesAllText', () {
      const markdown = '# Title\n\nSome **bold** and *italic* text.\n\n- item';
      final doc = quillDocumentFromMarkdown(markdown);
      final plain = doc.toPlainText();
      expect(plain, contains('Title'));
      expect(plain, contains('bold'));
      expect(plain, contains('italic'));
      expect(plain, contains('item'));
    });

    test('quillDocumentFromMarkdown_documentEndsWithNewline', () {
      final doc = quillDocumentFromMarkdown('hello');
      expect(doc.toPlainText().endsWith('\n'), isTrue);
    });
  });
}
