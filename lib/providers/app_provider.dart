import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/app_user.dart';
import '../models/note.dart';
import '../models/folder.dart';
import '../services/database_service.dart';
import '../services/auth_service.dart';
import '../services/local_auth_service.dart';
import '../services/encryption_service.dart';
import '../services/drive_sync_service.dart';

// ── Drive sync status ─────────────────────────────────────────────────────────

enum SyncStatus { idle, syncing, success, error }

final syncStatusProvider =
    StateProvider<SyncStatus>((ref) => SyncStatus.idle);

// ── Current authenticated user ────────────────────────────────────────────────

class AppUserNotifier extends Notifier<AppUser?> {
  @override
  AppUser? build() => null;

  Future<void> tryRestore() async {
    final googleUser = await AuthService.instance.trySilentSignIn();
    if (googleUser != null) {
      await EncryptionService.instance.initForGoogleUser(googleUser.id);
      state = AppUser(
        id: googleUser.id,
        displayName: googleUser.displayName ?? googleUser.email,
        email: googleUser.email,
        type: AuthType.google,
      );
    }
    // Local accounts always require password on restart (key can't be re-derived
    // without the password, so there is no persistent local session).
  }

  void setUser(AppUser user) => state = user;

  Future<void> signOut() async {
    final current = state;
    if (current?.type == AuthType.google) {
      await AuthService.instance.signOut();
    } else if (current?.type == AuthType.local) {
      await LocalAuthService.instance.signOut();
    }
    EncryptionService.instance.clear();
    ref.invalidate(notesProvider);
    ref.invalidate(foldersProvider);
    ref.read(selectedNoteProvider.notifier).state = null;
    ref.read(selectedFolderProvider.notifier).state = null;
    state = null;
  }
}

final appUserProvider =
    NotifierProvider<AppUserNotifier, AppUser?>(AppUserNotifier.new);

// ── Selected folder (null = root/unfiled, -1 = All Notes) ────────────────────

final selectedFolderProvider = StateProvider<int?>((ref) => null);

// ── Selected note ─────────────────────────────────────────────────────────────

final selectedNoteProvider = StateProvider<Note?>((ref) => null);

// ── Search query ──────────────────────────────────────────────────────────────

final searchQueryProvider = StateProvider<String>((ref) => '');

// ── Folders ───────────────────────────────────────────────────────────────────

class FoldersNotifier extends AsyncNotifier<List<Folder>> {
  @override
  Future<List<Folder>> build() => DatabaseService.instance.getFolders();

  Future<void> reload() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(
        () => DatabaseService.instance.getFolders());
  }

  Future<Folder> createFolder(String name, {int? parentId}) async {
    final folder = Folder.create(name: name, parentId: parentId);
    final id = await DatabaseService.instance.saveFolder(folder);
    folder.id = id;
    await reload();
    return folder;
  }

  Future<void> renameFolder(Folder folder, String newName) async {
    folder.name = newName;
    await DatabaseService.instance.saveFolder(folder);
    await reload();
  }

  Future<void> deleteFolder(int id) async {
    await DatabaseService.instance.deleteFolder(id);
    await reload();
  }
}

final foldersProvider =
    AsyncNotifierProvider<FoldersNotifier, List<Folder>>(FoldersNotifier.new);

// ── Notes ─────────────────────────────────────────────────────────────────────

class NotesNotifier extends AsyncNotifier<List<Note>> {
  @override
  Future<List<Note>> build() => _load();

  Future<List<Note>> _load() {
    final folderId = ref.watch(selectedFolderProvider);
    final query = ref.watch(searchQueryProvider);
    if (query.isNotEmpty) {
      return DatabaseService.instance.searchNotes(query);
    }
    if (folderId == -1) {
      return DatabaseService.instance.getNotes(allNotes: true);
    }
    return DatabaseService.instance.getNotes(folderId: folderId);
  }

  Future<void> reload() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(_load);
  }

  Future<Note> createNote({int? folderId}) async {
    final note = Note.create(
      title: 'New Note',
      content: '{"ops":[{"insert":"\\n"}]}',
      preview: '',
      folderId: folderId,
    );
    final id = await DatabaseService.instance.saveNote(note);
    note.id = id;
    await reload();
    return note;
  }

  Future<void> saveNote(Note note) async {
    await DatabaseService.instance.saveNote(note);
    await reload();
    final appUser = ref.read(appUserProvider);
    if (appUser?.type == AuthType.google) {
      ref.read(syncStatusProvider.notifier).state = SyncStatus.syncing;
      DriveSyncService.instance.syncNote(note).then((_) {
        ref.read(syncStatusProvider.notifier).state = SyncStatus.success;
      }).catchError((e) {
        debugPrint('[Drive sync] syncNote failed: $e');
        ref.read(syncStatusProvider.notifier).state = SyncStatus.error;
      });
    }
  }

  Future<void> deleteNote(int id) async {
    await DatabaseService.instance.deleteNote(id);
    await reload();
  }
}

final notesProvider =
    AsyncNotifierProvider<NotesNotifier, List<Note>>(NotesNotifier.new);
