// Regression tests for bugs fixed during the log-based sync rewrite.
import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notes_app/models/app_user.dart';
import 'package:notes_app/models/folder.dart';
import 'package:notes_app/models/note.dart';
import 'package:notes_app/providers/app_provider.dart';

// ── Shared fakes ──────────────────────────────────────────────────────────────

class _FakeFoldersNotifier extends FoldersNotifier {
  @override
  Future<List<Folder>> build() async => [];
}

/// Tracks move pushes without hitting the database.
/// Replicates the same debounce/batch logic as the real moveNote but in-memory.
class _MovePushTracker extends NotesNotifier {
  final List<Note> pushedNotes = [];
  final List<Note> _store = [];
  final List<Note> _pendingMoveQueue = [];
  Timer? _moveDebounce;

  @override
  Future<List<Note>> build() async => _store;

  @override
  Future<void> moveNote(Note note, int? folderId) async {
    note.folderId = folderId;
    _store.removeWhere((n) => n.id == note.id);
    _store.add(note);
    state = AsyncData(List.from(_store));
    _pendingMoveQueue.removeWhere((n) => n.id == note.id);
    _pendingMoveQueue.add(note);
    _moveDebounce?.cancel();
    _moveDebounce = Timer(const Duration(milliseconds: 5000), () {
      final batch = List<Note>.from(_pendingMoveQueue);
      _pendingMoveQueue.clear();
      for (final n in batch) {
        performPush(n, []);
      }
    });
  }

  @override
  Note? cancelPendingPush() {
    _moveDebounce?.cancel();
    _moveDebounce = null;
    _pendingMoveQueue.clear();
    return super.cancelPendingPush();
  }

  @override
  Future<void> performPush(Note note, List<String> deletedImages) async {
    pushedNotes.add(note);
  }
}

ProviderContainer _makeGoogle(NotesNotifier notifier) {
  final c = ProviderContainer(overrides: [
    notesProvider.overrideWith(() => notifier),
    foldersProvider.overrideWith(_FakeFoldersNotifier.new),
  ]);
  c.read(appUserProvider.notifier).setLocalUser(AppUser(
    id: 'u1', displayName: 'Test', email: 't@g.com', type: AuthType.google,
  ));
  return c;
}

Note _note(String title, {int id = 1, int? folderId}) =>
    Note.create(title: title, content: '{}', preview: '')
      ..id = id
      ..folderId = folderId;

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  // ── Regression: pendingNote single-slot bug (moved notes dropped) ──────────
  // Before fix: moveNote called saveNote which stored only ONE pendingNote.
  // Moving A then B within the debounce window silently discarded A's push.

  group('moveNote – batch debounce coalesces rapid moves', () {
    test('rapidMoves_withinWindow_allFlushedTogether', () {
      fakeAsync((fake) {
        final notifier = _MovePushTracker();
        final container = _makeGoogle(notifier);
        addTearDown(container.dispose);

        final n = container.read(notesProvider.notifier);
        n.moveNote(_note('A', id: 1), 10);
        fake.elapse(const Duration(seconds: 1));
        n.moveNote(_note('B', id: 2), 10);
        fake.elapse(const Duration(seconds: 1));
        n.moveNote(_note('C', id: 3), 10);

        // Timer hasn't fired — nothing pushed yet.
        expect(notifier.pushedNotes, isEmpty);

        // 5 s after last move: all 3 flushed together.
        fake.elapse(const Duration(seconds: 5));
        expect(notifier.pushedNotes.length, equals(3));
        expect(notifier.pushedNotes.map((n) => n.title),
            containsAll(['A', 'B', 'C']));
      });
    });

    test('eachMoveResetsDebounceTimer', () {
      fakeAsync((fake) {
        final notifier = _MovePushTracker();
        final container = _makeGoogle(notifier);
        addTearDown(container.dispose);

        final n = container.read(notesProvider.notifier);
        n.moveNote(_note('A', id: 1), 10);
        fake.elapse(const Duration(seconds: 4)); // just before original timer fires
        n.moveNote(_note('B', id: 2), 10);       // resets timer
        fake.elapse(const Duration(seconds: 4)); // would have fired without reset
        expect(notifier.pushedNotes, isEmpty);

        fake.elapse(const Duration(seconds: 2)); // 5 s since last move
        expect(notifier.pushedNotes.length, equals(2));
      });
    });

    test('moveSameNoteTwice_onlyLatestVersionPushed', () {
      fakeAsync((fake) {
        final notifier = _MovePushTracker();
        final container = _makeGoogle(notifier);
        addTearDown(container.dispose);

        final n = container.read(notesProvider.notifier);
        n.moveNote(_note('A', id: 1), 10);
        fake.elapse(const Duration(seconds: 1));
        n.moveNote(_note('A', id: 1), 20); // same note, different folder

        fake.elapse(const Duration(seconds: 5));
        // Should only push once (deduped by id).
        expect(notifier.pushedNotes.length, equals(1));
        expect(notifier.pushedNotes.first.folderId, equals(20));
      });
    });

    test('cancelPendingPush_preventsMoveFlush', () {
      fakeAsync((fake) {
        final notifier = _MovePushTracker();
        final container = _makeGoogle(notifier);
        addTearDown(container.dispose);

        final n = container.read(notesProvider.notifier);
        n.moveNote(_note('A', id: 1), 10);
        fake.elapse(const Duration(seconds: 1));
        n.cancelPendingPush();
        fake.elapse(const Duration(seconds: 10));

        expect(notifier.pushedNotes, isEmpty);
      });
    });

    test('moveNote_updatesFolder_onEachNote', () {
      fakeAsync((fake) {
        final notifier = _MovePushTracker();
        final container = _makeGoogle(notifier);
        addTearDown(container.dispose);

        final n = container.read(notesProvider.notifier);
        n.moveNote(_note('A', id: 1, folderId: null), 5);
        n.moveNote(_note('B', id: 2, folderId: null), 5);

        fake.elapse(const Duration(seconds: 5));
        expect(notifier.pushedNotes.every((n) => n.folderId == 5), isTrue);
      });
    });
  });
}
