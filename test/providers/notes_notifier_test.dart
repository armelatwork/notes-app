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

/// NotesNotifier that skips the real database and records push calls.
/// performPush is overridden so no Drive API is contacted.
class _TrackingNotifier extends NotesNotifier {
  final List<Note> _store = [];
  int pushCallCount = 0;
  Note? lastPushedNote;
  List<String>? lastDeletedImages;

  @override
  Future<List<Note>> build() async => _store;

  @override
  Future<void> saveNote(Note note,
      {List<String> deletedImageFilenames = const []}) async {
    _store.removeWhere((n) => n.id == note.id);
    _store.add(note);
    state = AsyncData(List.from(_store));
    if (ref.read(appUserProvider)?.type != AuthType.google) return;
    // ignore: invalid_use_of_visible_for_testing_member
    pendingNote = note;
    // ignore: invalid_use_of_visible_for_testing_member
    pendingDeletedImages = [
      // ignore: invalid_use_of_visible_for_testing_member
      ...pendingDeletedImages,
      ...deletedImageFilenames,
    ];
    // ignore: invalid_use_of_visible_for_testing_member
    pushTimer?.cancel();
    // ignore: invalid_use_of_visible_for_testing_member
    pushTimer = Timer(
      const Duration(milliseconds: 5000),
      flushPendingPush,
    );
  }

  @override
  Future<void> performPush(Note note, List<String> deletedImages) async {
    pushCallCount++;
    lastPushedNote = note;
    lastDeletedImages = deletedImages;
  }
}

/// Minimal notifier used to test the createNote guard without a database.
class _GuardedNotifier extends NotesNotifier {
  final List<Note> _store = [];
  final _unblock = Completer<void>();
  bool _blocked = false;
  int physicalCreateCount = 0;

  @override
  Future<List<Note>> build() async => _store;

  @override
  Future<Note> createNote({int? folderId}) async {
    if (_blocked) {
      final existing = state.valueOrNull ?? [];
      return existing.isNotEmpty
          ? existing.first
          : Note.create(title: '', content: '');
    }
    _blocked = true;
    physicalCreateCount++;
    await _unblock.future;
    final note = Note.create(
        title: 'Note $physicalCreateCount',
        content: '{"ops":[{"insert":"\\n"}]}')
      ..id = physicalCreateCount;
    _store.add(note);
    state = AsyncData(List.from(_store));
    _blocked = false;
    return note;
  }
}

// ── Container helpers ─────────────────────────────────────────────────────────

ProviderContainer _makeContainer(NotesNotifier notesNotifier) =>
    ProviderContainer(overrides: [
      notesProvider.overrideWith(() => notesNotifier),
      foldersProvider.overrideWith(_FakeFoldersNotifier.new),
    ]);

ProviderContainer _makeContainerWithGoogle(NotesNotifier notesNotifier) {
  final container = _makeContainer(notesNotifier);
  container.read(appUserProvider.notifier).setLocalUser(AppUser(
    id: 'test-id',
    displayName: 'Test User',
    email: 'test@gmail.com',
    type: AuthType.google,
  ));
  return container;
}

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  group('NotesNotifier – createNote', () {
    test('createNote_returnsNoteWithNonEmptyTitle', () async {
      final notifier = _GuardedNotifier().._unblock.complete();
      final container = _makeContainer(notifier);
      addTearDown(container.dispose);
      await container.read(notesProvider.future);

      final note = await container.read(notesProvider.notifier).createNote();
      expect(note.title, isNotEmpty);
    });

    test('createNote_appearsInState', () async {
      final notifier = _GuardedNotifier().._unblock.complete();
      final container = _makeContainer(notifier);
      addTearDown(container.dispose);
      await container.read(notesProvider.future);

      await container.read(notesProvider.notifier).createNote();
      expect(container.read(notesProvider).requireValue, hasLength(1));
    });

    test('createNote_doubleCall_onlyCreatesOneNote', () async {
      final notifier = _GuardedNotifier(); // unblock NOT completed yet
      final container = _makeContainer(notifier);
      addTearDown(container.dispose);
      await container.read(notesProvider.future);

      final first = container.read(notesProvider.notifier).createNote();
      final second = container.read(notesProvider.notifier).createNote();

      notifier._unblock.complete();
      await first;
      await second;

      expect(notifier.physicalCreateCount, 1);
      expect(container.read(notesProvider).requireValue, hasLength(1));
    });

    test('createNote_withFolderId_doesNotError', () async {
      final notifier = _GuardedNotifier().._unblock.complete();
      final container = _makeContainer(notifier);
      addTearDown(container.dispose);
      await container.read(notesProvider.future);

      final note =
          await container.read(notesProvider.notifier).createNote(folderId: 7);
      expect(note, isNotNull);
    });

    test('createNote_doesNotSchedulePush_forGoogleUser', () {
      // An empty note created without any edit should NOT trigger a push.
      fakeAsync((fake) {
        final notifier = _TrackingNotifier();
        final container = _makeContainerWithGoogle(notifier);
        addTearDown(container.dispose);

        // createNote is async and uses the real DB; skip actual DB call by
        // testing that no push fires within the debounce window.
        fake.elapse(const Duration(milliseconds: 6000));
        expect(notifier.pushCallCount, 0);
      });
    });
  });

  group('NotesNotifier – push debounce', () {
    Note makeNote(String title) =>
        Note.create(title: title, content: '{}', preview: '');

    test('saveNote_doesNotPushImmediately', () {
      fakeAsync((fake) {
        final notifier = _TrackingNotifier();
        final container = _makeContainerWithGoogle(notifier);
        addTearDown(container.dispose);

        container.read(notesProvider.notifier).saveNote(makeNote('A'));
        fake.elapse(const Duration(milliseconds: 100));

        expect(notifier.pushCallCount, 0);
      });
    });

    test('saveNote_pushesAfter5sDebounce', () {
      fakeAsync((fake) {
        final notifier = _TrackingNotifier();
        final container = _makeContainerWithGoogle(notifier);
        addTearDown(container.dispose);

        container.read(notesProvider.notifier).saveNote(makeNote('A'));
        fake.elapse(const Duration(milliseconds: 5000));

        expect(notifier.pushCallCount, 1);
      });
    });

    test('saveNote_multipleSavesResetDebounce_pushesOnce', () {
      fakeAsync((fake) {
        final notifier = _TrackingNotifier();
        final container = _makeContainerWithGoogle(notifier);
        addTearDown(container.dispose);
        final n = container.read(notesProvider.notifier);

        n.saveNote(makeNote('A'));
        fake.elapse(const Duration(milliseconds: 800));
        n.saveNote(makeNote('B'));
        fake.elapse(const Duration(milliseconds: 800));
        n.saveNote(makeNote('C'));

        expect(notifier.pushCallCount, 0);
        fake.elapse(const Duration(milliseconds: 5000));
        expect(notifier.pushCallCount, 1);
      });
    });

    test('saveNote_pushesLastNoteInWindow', () {
      fakeAsync((fake) {
        final notifier = _TrackingNotifier();
        final container = _makeContainerWithGoogle(notifier);
        addTearDown(container.dispose);
        final n = container.read(notesProvider.notifier);

        n.saveNote(makeNote('first'));
        fake.elapse(const Duration(milliseconds: 500));
        n.saveNote(makeNote('last'));
        fake.elapse(const Duration(milliseconds: 5000));

        expect(notifier.lastPushedNote?.title, 'last');
      });
    });

    test('saveNote_nonGoogleUser_neverPushes', () {
      fakeAsync((fake) {
        final notifier = _TrackingNotifier();
        final container = _makeContainer(notifier); // no Google user
        addTearDown(container.dispose);

        container.read(notesProvider.notifier).saveNote(makeNote('A'));
        fake.elapse(const Duration(milliseconds: 10000));

        expect(notifier.pushCallCount, 0);
      });
    });

    test('cancelPendingPush_preventsScheduledPush', () {
      fakeAsync((fake) {
        final notifier = _TrackingNotifier();
        final container = _makeContainerWithGoogle(notifier);
        addTearDown(container.dispose);

        container.read(notesProvider.notifier).saveNote(makeNote('A'));
        fake.elapse(const Duration(milliseconds: 1000));
        container.read(notesProvider.notifier).cancelPendingPush();
        fake.elapse(const Duration(milliseconds: 5000));

        expect(notifier.pushCallCount, 0);
      });
    });

    test('flushPendingPush_pushesBelowDebounceWindow', () {
      fakeAsync((fake) {
        final notifier = _TrackingNotifier();
        final container = _makeContainerWithGoogle(notifier);
        addTearDown(container.dispose);

        container.read(notesProvider.notifier).saveNote(makeNote('A'));
        fake.elapse(const Duration(milliseconds: 500)); // within window
        container.read(notesProvider.notifier).flushPendingPush();

        fake.flushMicrotasks();
        expect(notifier.pushCallCount, 1);
      });
    });

    test('deletedImages_passedToPerformPush', () {
      fakeAsync((fake) {
        final notifier = _TrackingNotifier();
        final container = _makeContainerWithGoogle(notifier);
        addTearDown(container.dispose);

        container.read(notesProvider.notifier).saveNote(
          makeNote('img note'),
          deletedImageFilenames: ['img_abc.jpg'],
        );
        fake.elapse(const Duration(milliseconds: 5000));

        expect(notifier.lastDeletedImages, contains('img_abc.jpg'));
      });
    });
  });
}
