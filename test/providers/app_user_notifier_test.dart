import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notes_app/models/app_user.dart';
import 'package:notes_app/models/folder.dart';
import 'package:notes_app/models/note.dart';
import 'package:notes_app/providers/app_provider.dart';
import 'package:notes_app/services/database_service.dart';
import 'package:notes_app/services/secure_storage_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Fakes that avoid hitting the real database / Google SDK.
class _FakeNotesNotifier extends NotesNotifier {
  @override
  Future<List<Note>> build() async => [];
}

class _FakeFoldersNotifier extends FoldersNotifier {
  @override
  Future<List<Folder>> build() async => [];
}

ProviderContainer _makeContainer() => ProviderContainer(
      overrides: [
        notesProvider.overrideWith(_FakeNotesNotifier.new),
        foldersProvider.overrideWith(_FakeFoldersNotifier.new),
      ],
    );

void main() {
  late Directory tempDir;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tempDir = await Directory.systemTemp.createTemp('app_user_notifier_test_');
    SecureStorageService.instance.setTestDirectory(tempDir.path);
    DatabaseService.clearAllOverride = () async {};
  });

  tearDown(() async {
    DatabaseService.clearAllOverride = null;
    SecureStorageService.instance.clearTestDirectory();
    await tempDir.delete(recursive: true);
  });

  group('AppUserNotifier', () {
    test('initial state is null', () {
      final container = _makeContainer();
      addTearDown(container.dispose);
      expect(container.read(appUserProvider), isNull);
    });

    test('setUser updates state to the provided user', () async {
      final container = _makeContainer();
      addTearDown(container.dispose);

      const user = AppUser(
        id: 'alice',
        displayName: 'alice',
        type: AuthType.local,
      );
      await container.read(appUserProvider.notifier).setUser(user);
      expect(container.read(appUserProvider), user);
    });

    test('setUser replaces a previous user', () async {
      final container = _makeContainer();
      addTearDown(container.dispose);

      const userA = AppUser(id: 'a', displayName: 'A', type: AuthType.local);
      const userB = AppUser(id: 'b', displayName: 'B', type: AuthType.local);
      await container.read(appUserProvider.notifier).setUser(userA);
      await container.read(appUserProvider.notifier).setUser(userB);
      expect(container.read(appUserProvider), userB);
    });

    test('signOut from local account sets state back to null', () async {
      final container = _makeContainer();
      addTearDown(container.dispose);

      const user = AppUser(id: 'alice', displayName: 'alice', type: AuthType.local);
      await container.read(appUserProvider.notifier).setUser(user);
      await container.read(appUserProvider.notifier).signOut();
      expect(container.read(appUserProvider), isNull);
    });

    test('signOut clears selectedNote', () async {
      final container = _makeContainer();
      addTearDown(container.dispose);

      final note = Note.create(
          title: 'Test', content: '{"ops":[{"insert":"\\n"}]}');
      container.read(selectedNoteProvider.notifier).state = note;
      await container.read(appUserProvider.notifier).setUser(
          const AppUser(id: 'a', displayName: 'a', type: AuthType.local));
      await container.read(appUserProvider.notifier).signOut();
      expect(container.read(selectedNoteProvider), isNull);
    });

    test('signOut clears selectedFolder', () async {
      final container = _makeContainer();
      addTearDown(container.dispose);

      container.read(selectedFolderProvider.notifier).state = 5;
      await container.read(appUserProvider.notifier).setUser(
          const AppUser(id: 'a', displayName: 'a', type: AuthType.local));
      await container.read(appUserProvider.notifier).signOut();
      expect(container.read(selectedFolderProvider), isNull);
    });
  });

  group('AppUserNotifier – _clearIfUserChanged', () {
    setUp(() => DatabaseService.openForUserOverride = (_) async {});
    tearDown(() => DatabaseService.openForUserOverride = null);

    test('setUser_opensDbForUser', () async {
      String? openedFor;
      DatabaseService.openForUserOverride = (id) async => openedFor = id;

      final container = _makeContainer();
      addTearDown(container.dispose);

      await container.read(appUserProvider.notifier).setUser(
          const AppUser(id: 'alice', displayName: 'Alice', type: AuthType.local));

      expect(openedFor, 'alice');
    });

    test('setUser_withDifferentUser_opensNewUserDb', () async {
      SharedPreferences.setMockInitialValues({'last_user_id': 'alice'});
      String? openedFor;
      DatabaseService.openForUserOverride = (id) async => openedFor = id;

      final container = _makeContainer();
      addTearDown(container.dispose);

      await container.read(appUserProvider.notifier).setUser(
          const AppUser(id: 'bob', displayName: 'Bob', type: AuthType.local));

      expect(openedFor, 'bob');
    });

    test('setUser_savesLastUserId', () async {
      final container = _makeContainer();
      addTearDown(container.dispose);

      await container.read(appUserProvider.notifier).setUser(
          const AppUser(id: 'alice', displayName: 'Alice', type: AuthType.local));

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('last_user_id'), 'alice');
    });

    test('setUser_withDifferentUser_savesNewUserId', () async {
      SharedPreferences.setMockInitialValues({'last_user_id': 'alice'});

      final container = _makeContainer();
      addTearDown(container.dispose);

      await container.read(appUserProvider.notifier).setUser(
          const AppUser(id: 'bob', displayName: 'Bob', type: AuthType.local));

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('last_user_id'), 'bob');
    });
  });
}
