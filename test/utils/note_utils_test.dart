import 'package:flutter_test/flutter_test.dart';
import 'package:notes_app/models/note.dart';
import 'package:notes_app/utils/note_utils.dart';

Note _note(String title, {int id = 0}) =>
    Note.create(title: title, content: '')..id = id;

void main() {
  group('computeDefaultNoteTitle', () {
    test('returns "New Note" when list is empty', () {
      expect(computeDefaultNoteTitle([]), 'New Note');
    });

    test('returns "New Note" when no note has that title', () {
      final notes = [_note('My thoughts'), _note('Shopping list')];
      expect(computeDefaultNoteTitle(notes), 'New Note');
    });

    test('returns "New Note 2" when one note has title "New Note"', () {
      final notes = [_note('New Note')];
      expect(computeDefaultNoteTitle(notes), 'New Note 2');
    });

    test('treats empty title as "New Note" for collision', () {
      final notes = [_note('')];
      expect(computeDefaultNoteTitle(notes), 'New Note 2');
    });

    test('treats whitespace-only title as "New Note" for collision', () {
      final notes = [_note('   ')];
      expect(computeDefaultNoteTitle(notes), 'New Note 2');
    });

    test('returns "New Note 3" when "New Note" and "New Note 2" are taken', () {
      final notes = [_note('New Note'), _note('New Note 2')];
      expect(computeDefaultNoteTitle(notes), 'New Note 3');
    });

    test('skips gaps — returns first available number', () {
      // "New Note" and "New Note 3" taken, but "New Note 2" is free
      final notes = [_note('New Note'), _note('New Note 3')];
      expect(computeDefaultNoteTitle(notes), 'New Note 2');
    });

    test('handles a long sequence of taken titles', () {
      final notes = [
        _note('New Note'),
        _note('New Note 2'),
        _note('New Note 3'),
        _note('New Note 4'),
        _note('New Note 5'),
      ];
      expect(computeDefaultNoteTitle(notes), 'New Note 6');
    });

    test('excludeId omits the current note from collision check', () {
      // The current note itself has title "New Note"; should still return "New Note"
      final current = _note('New Note', id: 42);
      final notes = [current, _note('Shopping list', id: 99)];
      expect(computeDefaultNoteTitle(notes, excludeId: 42), 'New Note');
    });

    test('excludeId omits current note with empty title from collision', () {
      final current = _note('', id: 1);
      final notes = [current];
      expect(computeDefaultNoteTitle(notes, excludeId: 1), 'New Note');
    });

    test('excludeId=null includes all notes', () {
      final notes = [_note('New Note', id: 42)];
      expect(computeDefaultNoteTitle(notes, excludeId: null), 'New Note 2');
    });

    test('unrelated titles do not affect the counter', () {
      final notes = [
        _note('New Note'),
        _note('New Note 2'),
        _note('Alpha'),
        _note('Beta'),
      ];
      expect(computeDefaultNoteTitle(notes), 'New Note 3');
    });

    test('note with matching title prefix but different format is not confused', () {
      // "New Note2" (no space) should not be treated as "New Note 2"
      final notes = [_note('New Note'), _note('New Note2')];
      expect(computeDefaultNoteTitle(notes), 'New Note 2');
    });
  });
}
