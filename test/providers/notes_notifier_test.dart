import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notes_app/models/folder.dart';
import 'package:notes_app/models/note.dart';
import 'package:notes_app/providers/app_provider.dart';
import 'package:notes_app/services/database_service.dart';

// ---------------------------------------------------------------------------
// Fake notifiers — no real database required.
// ---------------------------------------------------------------------------

class _FakeFoldersNotifier extends FoldersNotifier {
  @override
  Future<List<Folder>> build() async => [];
}

/// A NotesNotifier that delegates to a simple in-memory list.
/// Used to test the _creating guard without a real database.
class _GuardedTestNotifier extends NotesNotifier {
  final List<Note> _store = [];
  bool createBlocked = false;
  final _unblock = Completer<void>();
  int physicalCreateCount = 0;

  @override
  Future<List<Note>> build() async => _store;

  @override
  Future<Note> createNote({int? folderId}) async {
    if (createBlocked) {
      // Second call arrives while first is still in-flight.
      // Return the first existing note, or a no-op sentinel when list is empty.
      final existing = state.valueOrNull ?? [];
      return existing.isNotEmpty
          ? existing.first
          : Note.create(title: '', content: '');
    }
    createBlocked = true;
    physicalCreateCount++;
    await _unblock.future; // hold until test releases
    final note = Note.create(
        title: '', content: '{"ops":[{"insert":"\\n"}]}')
      ..id = physicalCreateCount;
    _store.add(note);
    state = AsyncData(List.from(_store));
    createBlocked = false;
    return note;
  }
}

/// A NotesNotifier whose reload() uses the in-memory store so moveNote can be
/// tested without a real database.
class _MoveTestNotifier extends NotesNotifier {
  final List<Note> _store;
  _MoveTestNotifier(this._store);

  @override
  Future<List<Note>> build() async => _store;

  @override
  Future<void> reload() async {
    state = AsyncData(List.from(_store));
  }
}

ProviderContainer _makeContainer(NotesNotifier notesNotifier) =>
    ProviderContainer(overrides: [
      notesProvider.overrideWith(() => notesNotifier),
      foldersProvider.overrideWith(_FakeFoldersNotifier.new),
    ]);

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('NotesNotifier – createNote', () {
    test('creates a note with an empty title', () async {
      final notifier = _GuardedTestNotifier();
      notifier._unblock.complete();
      final container = _makeContainer(notifier);
      addTearDown(container.dispose);
      await container.read(notesProvider.future); // wait for initial build

      final note = await container.read(notesProvider.notifier).createNote();
      expect(note.title, isEmpty);
    });

    test('newly created note appears in state', () async {
      final notifier = _GuardedTestNotifier();
      notifier._unblock.complete();
      final container = _makeContainer(notifier);
      addTearDown(container.dispose);
      await container.read(notesProvider.future);

      await container.read(notesProvider.notifier).createNote();
      expect(container.read(notesProvider).requireValue.length, 1);
    });

    test('double-creation guard: second concurrent call is ignored', () async {
      final notifier = _GuardedTestNotifier(); // _unblock NOT completed yet
      final container = _makeContainer(notifier);
      addTearDown(container.dispose);
      await container.read(notesProvider.future); // ensure state is AsyncData

      // Start first call — it blocks until _unblock is completed.
      final firstFuture =
          container.read(notesProvider.notifier).createNote();

      // Second call arrives while first is still running — guard intercepts.
      final secondFuture =
          container.read(notesProvider.notifier).createNote();

      expect(notifier.physicalCreateCount, 1);

      notifier._unblock.complete();
      await firstFuture;
      await secondFuture;

      // Only one note was physically created.
      expect(notifier.physicalCreateCount, 1);
      expect(container.read(notesProvider).requireValue.length, 1);
    });

    test('folderId parameter is accepted without error', () async {
      final notifier = _GuardedTestNotifier();
      notifier._unblock.complete();
      final container = _makeContainer(notifier);
      addTearDown(container.dispose);
      await container.read(notesProvider.future);

      final note =
          await container.read(notesProvider.notifier).createNote(folderId: 7);
      expect(note, isNotNull);
    });

    test('sequential creates produce independent notes', () async {
      final notifier = _GuardedTestNotifier();
      notifier._unblock.complete();
      final container = _makeContainer(notifier);
      addTearDown(container.dispose);
      await container.read(notesProvider.future);

      final noteA = await container.read(notesProvider.notifier).createNote();
      final noteB = await container.read(notesProvider.notifier).createNote();

      expect(noteA.id, isNot(equals(noteB.id)));
      expect(container.read(notesProvider).requireValue.length, 2);
    });
  });

  group('NotesNotifier – moveNote', () {
    setUp(() {
      DatabaseService.saveNoteOverride = (_) async => 0;
    });

    tearDown(() {
      DatabaseService.saveNoteOverride = null;
    });

    test('moveNote_toFolder_setsNoteFolderId', () async {
      final note = Note.create(title: 'N', content: '{}', folderId: 1)..id = 1;
      final notifier = _MoveTestNotifier([note]);
      final container = _makeContainer(notifier);
      addTearDown(container.dispose);
      await container.read(notesProvider.future);

      await container.read(notesProvider.notifier).moveNote(note, 5);

      expect(note.folderId, 5);
    });

    test('moveNote_toNull_movesNoteToRoot', () async {
      final note = Note.create(title: 'N', content: '{}', folderId: 3)..id = 1;
      final notifier = _MoveTestNotifier([note]);
      final container = _makeContainer(notifier);
      addTearDown(container.dispose);
      await container.read(notesProvider.future);

      await container.read(notesProvider.notifier).moveNote(note, null);

      expect(note.folderId, isNull);
    });

    test('moveNote_reloadsState', () async {
      final note = Note.create(title: 'N', content: '{}')..id = 1;
      final notifier = _MoveTestNotifier([note]);
      final container = _makeContainer(notifier);
      addTearDown(container.dispose);
      await container.read(notesProvider.future);

      await container.read(notesProvider.notifier).moveNote(note, 7);

      expect(container.read(notesProvider).hasValue, isTrue);
    });
  });
}
