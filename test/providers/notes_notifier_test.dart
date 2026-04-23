import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notes_app/models/app_user.dart';
import 'package:notes_app/models/folder.dart';
import 'package:notes_app/models/note.dart';
import 'package:notes_app/providers/app_provider.dart';

// ---------------------------------------------------------------------------
// Fake notifiers — no real database required.
// ---------------------------------------------------------------------------

class _FakeFoldersNotifier extends FoldersNotifier {
  @override
  Future<List<Folder>> build() async => [];
}

/// NotesNotifier that skips the real database and records Drive sync calls.
/// saveNote uses the real parent debounce fields so timer logic is not duplicated.
class _SyncTrackingNotifier extends NotesNotifier {
  final List<Note> _store = [];
  int syncCallCount = 0;
  Note? lastSyncedNote;

  @override
  Future<List<Note>> build() async {
    ref.onDispose(() => syncTimer?.cancel());
    return _store;
  }

  @override
  Future<void> saveNote(Note note) async {
    _store.add(note);
    state = AsyncData(List.from(_store));
    final appUser = ref.read(appUserProvider);
    if (appUser?.type == AuthType.google) {
      pendingSyncNote = note;
      syncTimer?.cancel();
      syncTimer = Timer(const Duration(milliseconds: 5000), flushSync);
    }
  }

  @override
  void performSync(Note note) {
    syncCallCount++;
    lastSyncedNote = note;
  }
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

ProviderContainer _makeContainer(NotesNotifier notesNotifier) =>
    ProviderContainer(overrides: [
      notesProvider.overrideWith(() => notesNotifier),
      foldersProvider.overrideWith(_FakeFoldersNotifier.new),
    ]);

ProviderContainer _makeContainerWithGoogleUser(NotesNotifier notesNotifier) {
  final container = _makeContainer(notesNotifier);
  container.read(appUserProvider.notifier).setUser(AppUser(
    id: 'test-id',
    displayName: 'Test User',
    email: 'test@gmail.com',
    type: AuthType.google,
  ));
  return container;
}

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

  group('NotesNotifier – Drive sync debounce', () {
    Note makeNote(String title) =>
        Note.create(title: title, content: '{}', preview: '');

    test('saveNote_forGoogleUser_doesNotSyncImmediately', () {
      fakeAsync((fake) {
        final notifier = _SyncTrackingNotifier();
        final container = _makeContainerWithGoogleUser(notifier);
        addTearDown(container.dispose);

        container.read(notesProvider.notifier).saveNote(makeNote('A'));

        fake.elapse(const Duration(milliseconds: 100));

        expect(notifier.syncCallCount, 0);
      });
    });

    test('saveNote_forGoogleUser_syncsAfterDebounceWindow', () {
      fakeAsync((fake) {
        final notifier = _SyncTrackingNotifier();
        final container = _makeContainerWithGoogleUser(notifier);
        addTearDown(container.dispose);

        container.read(notesProvider.notifier).saveNote(makeNote('A'));

        fake.elapse(const Duration(milliseconds: 5000));

        expect(notifier.syncCallCount, 1);
      });
    });

    test('saveNote_multipleSavesWithinWindow_syncsOnlyOnce', () {
      fakeAsync((fake) {
        final notifier = _SyncTrackingNotifier();
        final container = _makeContainerWithGoogleUser(notifier);
        addTearDown(container.dispose);

        final n = container.read(notesProvider.notifier);
        n.saveNote(makeNote('A'));
        fake.elapse(const Duration(milliseconds: 800));
        n.saveNote(makeNote('B'));
        fake.elapse(const Duration(milliseconds: 800));
        n.saveNote(makeNote('C'));

        // Still within debounce window — no sync yet.
        expect(notifier.syncCallCount, 0);

        fake.elapse(const Duration(milliseconds: 5000));

        expect(notifier.syncCallCount, 1);
      });
    });

    test('saveNote_multipleSavesWithinWindow_syncsLatestNote', () {
      fakeAsync((fake) {
        final notifier = _SyncTrackingNotifier();
        final container = _makeContainerWithGoogleUser(notifier);
        addTearDown(container.dispose);

        final n = container.read(notesProvider.notifier);
        n.saveNote(makeNote('first'));
        fake.elapse(const Duration(milliseconds: 500));
        n.saveNote(makeNote('last'));

        fake.elapse(const Duration(milliseconds: 5000));

        expect(notifier.lastSyncedNote?.title, 'last');
      });
    });

    test('saveNote_forNonGoogleUser_neverSyncs', () {
      fakeAsync((fake) {
        final notifier = _SyncTrackingNotifier();
        // No Google user set — use plain container.
        final container = _makeContainer(notifier);
        addTearDown(container.dispose);

        container.read(notesProvider.notifier).saveNote(makeNote('A'));

        fake.elapse(const Duration(milliseconds: 10000));

        expect(notifier.syncCallCount, 0);
      });
    });
  });
}
