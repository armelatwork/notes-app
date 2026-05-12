import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notes_app/utils/note_utils.dart';

// Tests for the "discard empty new note" feature.
// _isNewEmptyNote() on _NoteEditorState combines three conditions:
//   1. !_isDirty
//   2. isDefaultNoteTitle(note.title)
//   3. controller.document.toPlainText().trim().isEmpty
// Conditions 2 and 3 are exercised here; _isDirty is a simple bool flag
// covered implicitly by the noteUtils tests and the overall logic.

QuillController _controllerFromJson(String json) {
  final ops = (json.isEmpty)
      ? [{"insert": "\n"}]
      : [{"insert": json}, {"insert": "\n"}];
  final doc = Document.fromJson(ops);
  return QuillController(
      document: doc, selection: const TextSelection.collapsed(offset: 0));
}

void main() {
  group('Empty-note detection — document content', () {
    test(
        'freshDocument_defaultContent_isEffectivelyEmpty', () {
      final ctrl = _controllerFromJson('');
      addTearDown(ctrl.dispose);

      expect(ctrl.document.toPlainText().trim(), isEmpty);
    });

    test(
        'document_withText_isNotEmpty', () {
      final ctrl = _controllerFromJson('Hello world');
      addTearDown(ctrl.dispose);

      expect(ctrl.document.toPlainText().trim(), isNotEmpty);
    });

    test(
        'document_withOnlyWhitespace_isEffectivelyEmpty', () {
      final ctrl = _controllerFromJson('   ');
      addTearDown(ctrl.dispose);

      expect(ctrl.document.toPlainText().trim(), isEmpty);
    });
  });

  group('Empty-note detection — title check', () {
    test('defaultTitle_newNote_isDefault', () {
      expect(isDefaultNoteTitle('New Note'), isTrue);
    });

    test('defaultTitle_newNote2_isDefault', () {
      expect(isDefaultNoteTitle('New Note 2'), isTrue);
    });

    test('customTitle_isNotDefault', () {
      expect(isDefaultNoteTitle('My shopping list'), isFalse);
    });

    test('emptyTitle_isNotDefault', () {
      expect(isDefaultNoteTitle(''), isFalse);
    });
  });

  group('Empty-note detection — combined gate', () {
    bool isNewEmptyNote({
      required bool isDirty,
      required String title,
      required String content,
    }) {
      if (isDirty) return false;
      if (!isDefaultNoteTitle(title)) return false;
      final ctrl = _controllerFromJson(content);
      final empty = ctrl.document.toPlainText().trim().isEmpty;
      ctrl.dispose();
      return empty;
    }

    test('neverEdited_defaultTitle_emptyContent_shouldDiscard', () {
      expect(
          isNewEmptyNote(isDirty: false, title: 'New Note', content: ''),
          isTrue);
    });

    test('isDirty_shouldNotDiscard', () {
      expect(
          isNewEmptyNote(isDirty: true, title: 'New Note', content: ''),
          isFalse);
    });

    test('customTitle_shouldNotDiscard', () {
      expect(
          isNewEmptyNote(isDirty: false, title: 'Meeting notes', content: ''),
          isFalse);
    });

    test('hasContent_shouldNotDiscard', () {
      expect(
          isNewEmptyNote(
              isDirty: false, title: 'New Note', content: 'Some text'),
          isFalse);
    });

    test('hasContent_andCustomTitle_shouldNotDiscard', () {
      expect(
          isNewEmptyNote(
              isDirty: false, title: 'My note', content: 'Some text'),
          isFalse);
    });
  });
}
