import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_quill/quill_delta.dart';
import 'package:notes_app/services/clipboard_table_handler.dart';
import 'package:notes_app/widgets/note_table_embed.dart';

void main() {
  late ClipboardTableHandler handler;

  setUp(() => handler = ClipboardTableHandler());

  // ── extract ────────────────────────────────────────────────────────────────

  group('extract', () {
    test('singleColumnTable_isFlattenedToParagraphs', () {
      const html = '<table><tr><td><p>Row one</p></td></tr>'
          '<tr><td><p>Row two</p></td></tr></table>';
      final tables = <String, List<List<String>>>{};
      final result = handler.extract(html, tables);
      expect(tables, isEmpty);
      expect(result, contains('Row one'));
      expect(result, contains('Row two'));
    });

    test('multiColumnTable_isReplacedWithPlaceholder', () {
      const html = '<table><tr><td>A</td><td>B</td></tr></table>';
      final tables = <String, List<List<String>>>{};
      final result = handler.extract(html, tables);
      expect(tables.length, 1);
      final key = tables.keys.first;
      expect(result, contains(key));
    });

    test('tableWithThHeaders_isReplacedWithPlaceholder', () {
      const html =
          '<table><tr><th>Name</th><th>Age</th></tr>'
          '<tr><td>Alice</td><td>30</td></tr></table>';
      final tables = <String, List<List<String>>>{};
      handler.extract(html, tables);
      expect(tables.length, 1);
    });

    test('multiColumnTable_parsesRowsCorrectly', () {
      const html =
          '<table><tr><td>A</td><td>B</td></tr>'
          '<tr><td>C</td><td>D</td></tr></table>';
      final tables = <String, List<List<String>>>{};
      handler.extract(html, tables);
      final rows = tables.values.first;
      expect(rows.length, 2);
      expect(rows[0], ['A', 'B']);
      expect(rows[1], ['C', 'D']);
    });

    test('htmlEntitiesInCells_areDecoded', () {
      const html =
          '<table><tr><td>A &amp; B</td><td>C &lt; D</td></tr></table>';
      final tables = <String, List<List<String>>>{};
      handler.extract(html, tables);
      final rows = tables.values.first;
      expect(rows[0][0], 'A & B');
      expect(rows[0][1], 'C < D');
    });

    test('multipleTables_eachGetOwnPlaceholder', () {
      const html = '<table><tr><td>A</td><td>B</td></tr></table>'
          'Text'
          '<table><tr><td>C</td><td>D</td></tr></table>';
      final tables = <String, List<List<String>>>{};
      handler.extract(html, tables);
      expect(tables.length, 2);
    });
  });

  // ── inject ─────────────────────────────────────────────────────────────────

  group('inject', () {
    test('replacesPlaceholderWithTableEmbed', () {
      const key = '___TABLE_0___';
      final tables = {
        key: [
          ['A', 'B'],
          ['C', 'D'],
        ],
      };
      final delta = Delta()..insert('\n$key\n');
      final result = handler.inject(delta, tables);
      final ops = result.toList();
      expect(ops.any((op) => op.data is Map && (op.data as Map).containsKey(kTableEmbedType)), isTrue);
      expect(ops.any((op) => op.data == key), isFalse);
    });

    test('noPlaceholder_returnsDeltaUnchanged', () {
      final delta = Delta()..insert('Just text\n');
      final result = handler.inject(delta, {'___TABLE_0___': []});
      expect(result.toList().first.data, 'Just text\n');
    });

    test('textBeforePlaceholder_isPreserved', () {
      const key = '___TABLE_0___';
      final tables = {key: [['X']]};
      final delta = Delta()..insert('Before$key');
      final result = handler.inject(delta, tables);
      final ops = result.toList();
      expect(ops.any((op) => op.data == 'Before'), isTrue);
    });
  });
}
