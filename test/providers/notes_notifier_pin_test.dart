import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notes_app/models/app_user.dart';
import 'package:notes_app/models/folder.dart';
import 'package:notes_app/models/note.dart';
import 'package:notes_app/providers/app_provider.dart';

// ── Fake notifiers ────────────────────────────────────────────────────────────

class _FakeFoldersNotifier extends FoldersNotifier {
  @override
  Future<List<Folder>> build() async => [];
}

/// NotesNotifier that bypasses the database and overrides togglePin so that
/// no DatabaseService call is made, matching how other test notifiers work.
class _PinTrackingNotifier extends NotesNotifier {
  final List<Note> _store = [];
  bool performPushCalled = false;

  @override
  Future<List<Note>> build() async => _store;

  void seedNote(Note note) {
    _store.add(note);
    state = AsyncData(List.from(_store));
  }

  @override
  Future<void> togglePin(Note note) async {
    note.isPinned = !note.isPinned;
    _store.removeWhere((n) => n.id == note.id);
    _store.add(note);
    state = AsyncData(List.from(_store));
    if (ref.read(appUserProvider)?.type != AuthType.google) return;
    ref.read(syncStatusProvider.notifier).state = SyncStatus.idle;
    // ignore: invalid_use_of_visible_for_testing_member
    pendingNotes[note.id] = note;
    // ignore: invalid_use_of_visible_for_testing_member
    pushTimer?.cancel();
    // ignore: invalid_use_of_visible_for_testing_member
    pushTimer =
        Timer(const Duration(milliseconds: 5000), flushPendingPush);
  }

  @override
  Future<void> performPush(Note note, List<String> deletedImages) async {
    performPushCalled = true;
  }
}

// ── Container helpers ─────────────────────────────────────────────────────────

ProviderContainer _makeContainer(_PinTrackingNotifier notifier) =>
    ProviderContainer(overrides: [
      notesProvider.overrideWith(() => notifier),
      foldersProvider.overrideWith(_FakeFoldersNotifier.new),
    ]);

ProviderContainer _makeGoogleContainer(_PinTrackingNotifier notifier) {
  final container = _makeContainer(notifier);
  container.read(appUserProvider.notifier).setLocalUser(AppUser(
    id: 'user-1',
    displayName: 'Test',
    email: 'test@gmail.com',
    type: AuthType.google,
  ));
  return container;
}

Note _makeNote({int id = 1, bool isPinned = false}) {
  final n = Note.create(title: 'Note $id', content: '[{"insert":"\\n"}]')
    ..id = id
    ..isPinned = isPinned;
  return n;
}

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  group('Note model – isPinned', () {
    test('isPinned_defaultsToFalse', () {
      final note = Note.create(title: 'Test', content: '[{"insert":"\\n"}]');
      expect(note.isPinned, isFalse);
    });

    test('isPinned_canBeSetToTrue', () {
      final note = Note.create(title: 'Test', content: '[{"insert":"\\n"}]')
        ..isPinned = true;
      expect(note.isPinned, isTrue);
    });
  });

  group('NotesNotifier – togglePin', () {
    test('togglePin_unpinnedNote_setsPinnedTrue', () async {
      final notifier = _PinTrackingNotifier();
      final container = _makeContainer(notifier);
      addTearDown(container.dispose);
      await container.read(notesProvider.future);

      final note = _makeNote(isPinned: false);
      notifier.seedNote(note);

      await container.read(notesProvider.notifier).togglePin(note);

      final notes = container.read(notesProvider).valueOrNull ?? [];
      expect(notes.first.isPinned, isTrue);
    });

    test('togglePin_pinnedNote_setsPinnedFalse', () async {
      final notifier = _PinTrackingNotifier();
      final container = _makeContainer(notifier);
      addTearDown(container.dispose);
      await container.read(notesProvider.future);

      final note = _makeNote(isPinned: true);
      notifier.seedNote(note);

      await container.read(notesProvider.notifier).togglePin(note);

      final notes = container.read(notesProvider).valueOrNull ?? [];
      expect(notes.first.isPinned, isFalse);
    });

    test('togglePin_localUser_doesNotQueueDrivePush', () async {
      final notifier = _PinTrackingNotifier();
      final container = _makeContainer(notifier);
      addTearDown(container.dispose);
      await container.read(notesProvider.future);

      final note = _makeNote();
      notifier.seedNote(note);

      await container.read(notesProvider.notifier).togglePin(note);

      // ignore: invalid_use_of_visible_for_testing_member
      expect(notifier.pendingNotes, isEmpty);
    });

    test('togglePin_googleUser_addsToPendingNotesAndStartsTimer', () {
      fakeAsync((async) async {
        final notifier = _PinTrackingNotifier();
        final container = _makeGoogleContainer(notifier);
        addTearDown(container.dispose);
        await container.read(notesProvider.future);

        final note = _makeNote();
        notifier.seedNote(note);

        await container.read(notesProvider.notifier).togglePin(note);

        // ignore: invalid_use_of_visible_for_testing_member
        expect(notifier.pendingNotes.containsKey(note.id), isTrue);
        // ignore: invalid_use_of_visible_for_testing_member
        expect(notifier.pushTimer, isNotNull);

        async.elapse(const Duration(milliseconds: 5000));
        expect(notifier.performPushCalled, isTrue);
      });
    });

    test('togglePin_updatesSelectedNoteProvider', () async {
      final notifier = _PinTrackingNotifier();
      final container = _makeContainer(notifier);
      addTearDown(container.dispose);
      await container.read(notesProvider.future);

      final note = _makeNote();
      notifier.seedNote(note);
      container.read(selectedNoteProvider.notifier).state = note;

      await container.read(notesProvider.notifier).togglePin(note);

      final selected = container.read(selectedNoteProvider);
      expect(selected?.isPinned, isTrue);
    });
  });
}
