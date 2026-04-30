import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/app_user.dart';
import '../models/note.dart';
import '../models/folder.dart';
import '../services/backup_settings_service.dart';
import '../services/database_service.dart';
import '../services/auth_service.dart';
import '../services/local_auth_service.dart';
import '../services/encryption_service.dart';
import '../services/drive_sync_service.dart';
import '../services/persistence_service.dart';
import '../utils/note_utils.dart';
import 'backup_provider.dart';

// ── Drive sync status ─────────────────────────────────────────────────────────

enum SyncStatus { idle, syncing, success, error }

final syncStatusProvider =
    StateProvider<SyncStatus>((ref) => SyncStatus.idle);

// Runs a Drive operation and reflects the result in syncStatusProvider.
// onSuccess fires after the status is set to success (for side-effects like
// recording the backup timestamp).
void _driveSync(
  Ref ref,
  Future<void> Function() operation, {
  String tag = 'DriveSync',
  Future<void> Function()? onSuccess,
}) {
  ref.read(syncStatusProvider.notifier).state = SyncStatus.syncing;
  operation().then((_) async {
    ref.read(syncStatusProvider.notifier).state = SyncStatus.success;
    await onSuccess?.call();
  }).catchError((Object e) {
    debugPrint('[$tag] failed: $e');
    ref.read(syncStatusProvider.notifier).state = SyncStatus.error;
  });
}

// Cancels any existing timer, marks status as idle (pending changes), and
// starts a new debounce timer.
Timer _scheduleSync(
  Ref ref,
  Timer? existingTimer,
  void Function() onFire,
) {
  existingTimer?.cancel();
  ref.read(syncStatusProvider.notifier).state = SyncStatus.idle;
  return Timer(const Duration(milliseconds: _kSyncDebounceMs), onFire);
}

// ── Drive restore check in progress ──────────────────────────────────────────

final restoreCheckInProgressProvider = StateProvider<bool>((ref) => false);

// ── Current authenticated user ────────────────────────────────────────────────

class AppUserNotifier extends Notifier<AppUser?> {
  @override
  AppUser? build() => null;

  Future<void> tryRestore() async {
    final googleUser = await AuthService.instance.trySilentSignIn();
    if (googleUser != null) {
      await initGoogleEncryptionKey(googleUser.id);
      await _clearIfUserChanged(googleUser.id);
      state = AppUser(
        id: googleUser.id,
        displayName: googleUser.displayName ?? googleUser.email,
        email: googleUser.email,
        type: AuthType.google,
      );
      // Session was silently restored, so Drive was in sync when the app last
      // closed. Show green until the user makes a change.
      ref.read(syncStatusProvider.notifier).state = SyncStatus.success;
    }
    // Local accounts always require password on restart (key can't be re-derived
    // without the password, so there is no persistent local session).
  }

  Future<void> initGoogleEncryptionKey(String userId) async {
    final enc = EncryptionService.instance;
    // Drive is the source of truth — always prefer it so all devices share one key.
    try {
      final driveKey =
          await DriveSyncService.instance.fetchEncryptionKeyBase64();
      if (driveKey != null) {
        await enc.initWithBase64Key(userId, driveKey);
        return;
      }
    } catch (e) {
      debugPrint('[AppUserNotifier] fetchEncryptionKey failed: $e');
    }
    // No Drive key yet — use local key if available, otherwise generate and upload.
    if (await enc.tryInitFromLocalStorage(userId)) {
      final localKey = await enc.exportCurrentKeyBase64();
      await DriveSyncService.instance.uploadEncryptionKeyBase64(localKey);
      return;
    }
    final newKey = await enc.generateAndStoreKey(userId);
    await DriveSyncService.instance.uploadEncryptionKeyBase64(newKey);
  }

  Future<void> setUser(AppUser user) async {
    await _clearIfUserChanged(user.id);
    state = user;
  }

  Future<void> _clearIfUserChanged(String userId) async {
    final lastId = await PersistenceService.instance.loadLastUserId();
    await DatabaseService.instance.openForUser(userId);
    await PersistenceService.instance.saveLastUserId(userId);
    if (lastId != userId) {
      ref.invalidate(notesProvider);
      ref.invalidate(foldersProvider);
    }
  }

  Future<void> signOut() async {
    final current = state;
    if (current?.type == AuthType.google) {
      // Only sync the note that was waiting in the debounce timer, not all
      // notes. syncAll() on every logout is far too slow.
      final pending = ref.read(notesProvider.notifier).cancelPendingSync();
      ref.read(syncStatusProvider.notifier).state = SyncStatus.syncing;
      var synced = false;
      try {
        if (pending != null) {
          await DriveSyncService.instance.syncNote(pending);
        }
        // Always upload the folder index — folder-only changes are not
        // captured by the note debounce and would otherwise be lost.
        await DriveSyncService.instance.syncFolderIndex();
        synced = true;
      } catch (e) {
        debugPrint('[AppUserNotifier] pre-signout sync failed: $e');
      }
      // Keep success state so the next login opens with the green icon.
      // On failure reset to idle — don't show red while logging out.
      ref.read(syncStatusProvider.notifier).state =
          synced ? SyncStatus.success : SyncStatus.idle;
      await AuthService.instance.signOut();
    } else if (current?.type == AuthType.local) {
      await LocalAuthService.instance.signOut();
      ref.read(syncStatusProvider.notifier).state = SyncStatus.idle;
    }
    EncryptionService.instance.clear();
    ref.invalidate(notesProvider);
    ref.invalidate(foldersProvider);
    ref.read(selectedNoteProvider.notifier).state = null;
    ref.read(selectedFolderProvider.notifier).state = -1;
    state = null;
  }
}

final appUserProvider =
    NotifierProvider<AppUserNotifier, AppUser?>(AppUserNotifier.new);

// ── Selected folder (null = root/unfiled, -1 = All Notes) ────────────────────

final selectedFolderProvider = StateProvider<int?>((ref) => -1);

// ── Selected note ─────────────────────────────────────────────────────────────

final selectedNoteProvider = StateProvider<Note?>((ref) => null);

// ── Search query ──────────────────────────────────────────────────────────────

final searchQueryProvider = StateProvider<String>((ref) => '');

// ── Folders ───────────────────────────────────────────────────────────────────

class FoldersNotifier extends AsyncNotifier<List<Folder>> {
  Timer? _syncTimer;

  @override
  Future<List<Folder>> build() {
    ref.onDispose(() => _syncTimer?.cancel());
    return DatabaseService.instance.getFolders();
  }

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
    _scheduleFolderSync();
    return folder;
  }

  Future<void> renameFolder(Folder folder, String newName) async {
    folder.name = newName;
    await DatabaseService.instance.saveFolder(folder);
    await reload();
    _scheduleFolderSync();
  }

  Future<void> deleteFolder(int id) async {
    await DatabaseService.instance.deleteFolder(id);
    await reload();
    _scheduleFolderSync();
  }

  void _scheduleFolderSync() {
    if (ref.read(appUserProvider)?.type != AuthType.google) return;
    _syncTimer = _scheduleSync(ref, _syncTimer, _flushFolderSync);
  }

  void _flushFolderSync() {
    _driveSync(ref, DriveSyncService.instance.syncFolderIndex,
        tag: 'FoldersNotifier');
  }
}

final foldersProvider =
    AsyncNotifierProvider<FoldersNotifier, List<Folder>>(FoldersNotifier.new);

// ── Notes ─────────────────────────────────────────────────────────────────────

const _kSyncDebounceMs = 5000;

class NotesNotifier extends AsyncNotifier<List<Note>> {
  bool _creating = false;

  @visibleForTesting Timer? syncTimer;
  @visibleForTesting Note? pendingSyncNote;

  @override
  Future<List<Note>> build() {
    // Do NOT cancel syncTimer here. ref.onDispose fires on every rebuild
    // (e.g. when selectedFolderProvider changes), which would silently drop
    // a pending sync after a note move. Cancellation is handled explicitly
    // by cancelPendingSync() on sign-out.
    return _load();
  }

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
    if (_creating) {
      // Return existing first note if double-tap guard fires
      return state.valueOrNull?.firstOrNull ??
          Note.create(title: 'New Note', content: '{"ops":[{"insert":"\\n"}]}', preview: '', folderId: folderId);
    }
    _creating = true;
    try {
      final title = computeDefaultNoteTitle(state.valueOrNull ?? []);
      final note = Note.create(
        title: title,
        content: '{"ops":[{"insert":"\\n"}]}',
        preview: '',
        folderId: folderId,
      );
      final id = await DatabaseService.instance.saveNote(note);
      note.id = id;
      await reload();
      return note;
    } finally {
      _creating = false;
    }
  }

  Future<void> saveNote(Note note) async {
    await DatabaseService.instance.saveNote(note);
    await reload();
    final appUser = ref.read(appUserProvider);
    if (appUser?.type == AuthType.google) {
      final backupEnabled = ref.read(backupProvider).valueOrNull?.enabled ?? true;
      if (!backupEnabled) return;
      pendingSyncNote = note;
      syncTimer = _scheduleSync(ref, syncTimer, flushSync);
    }
  }

  // Cancels the debounce timer and returns the note that was waiting, if any.
  Note? cancelPendingSync() {
    syncTimer?.cancel();
    syncTimer = null;
    final note = pendingSyncNote;
    pendingSyncNote = null;
    return note;
  }

  @visibleForTesting
  void flushSync() {
    final note = pendingSyncNote;
    if (note == null) return;
    pendingSyncNote = null;
    try {
      performSync(note);
    } catch (_) {
      // Notifier was disposed before the timer fired — safe to ignore.
    }
  }

  void performSync(Note note) {
    _driveSync(
      ref,
      () => DriveSyncService.instance.syncNote(note),
      tag: 'NotesNotifier',
      onSuccess: () async {
        await BackupSettingsService.instance.recordBackup();
        ref.read(backupProvider.notifier).refreshLastBackupAt();
      },
    );
  }

  Future<void> moveNote(Note note, int? folderId) async {
    note.folderId = folderId;
    await saveNote(note);
  }

  Future<void> deleteNote(int id) async {
    final note = await DatabaseService.instance.getNote(id);
    await DatabaseService.instance.deleteNote(id);
    await reload();
    final driveFileId = note?.driveFileId;
    if (driveFileId != null && ref.read(appUserProvider)?.type == AuthType.google) {
      ref.read(syncStatusProvider.notifier).state = SyncStatus.syncing;
      DriveSyncService.instance.deleteNote(driveFileId).whenComplete(() {
        ref.read(syncStatusProvider.notifier).state = SyncStatus.success;
      });
    }
  }
}

final notesProvider =
    AsyncNotifierProvider<NotesNotifier, List<Note>>(NotesNotifier.new);
