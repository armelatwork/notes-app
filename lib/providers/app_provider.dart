import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import '../models/app_user.dart';
import '../models/folder.dart';
import '../models/note.dart';
import '../services/auth_service.dart';
import '../services/database_service.dart';
import '../services/device_service.dart';
import '../services/drive_sync_service.dart';
import '../services/encryption_service.dart';
import '../services/local_auth_service.dart';
import '../services/sync_log_service.dart';
import '../utils/image_utils.dart';
import '../utils/note_utils.dart';

// ── Sync status ───────────────────────────────────────────────────────────────

enum SyncStatus { idle, syncing, success, error }

final syncStatusProvider = StateProvider<SyncStatus>((ref) => SyncStatus.idle);

// ── Note reload trigger (incremented after a poll downloads new data) ─────────

final noteReloadTriggerProvider = StateProvider<int>((ref) => 0);

// ── Immediate poll trigger (sync button → poll right now) ────────────────────

final pollTriggerProvider = StateProvider<int>((ref) => 0);

// ── Current authenticated user ────────────────────────────────────────────────

class AppUserNotifier extends Notifier<AppUser?> {
  @override
  AppUser? build() => null;

  Future<void> tryRestore() async {
    final googleUser = await AuthService.instance.trySilentSignIn();
    if (googleUser == null) return;
    await _initGoogleSession(googleUser.id, googleUser);
  }

  Future<void> setGoogleUser(dynamic googleUser) async {
    await _initGoogleSession(googleUser.id as String, googleUser);
  }

  Future<void> _initGoogleSession(String userId, dynamic googleUser) async {
    final enc = EncryptionService.instance;
    final drv = DriveSyncService.instance;
    final api = await drv.getApi();
    if (api == null) return;
    final appFolderId = await drv.getOrCreateAppFolder(api);
    final remoteKey = await drv.fetchEncryptionKey(api, appFolderId);
    if (remoteKey != null) {
      enc.initWithKey(Uint8List.fromList(base64Decode(remoteKey)));
    } else {
      await enc.initForGoogleUser(userId);
      final localKey = await enc.exportCurrentKeyBase64();
      await drv.uploadEncryptionKey(api, appFolderId, localKey);
    }
    state = AppUser(
      id: userId,
      displayName: googleUser.displayName as String? ?? googleUser.email as String,
      email: googleUser.email as String,
      type: AuthType.google,
    );
  }

  void setLocalUser(AppUser user) => state = user;

  Future<void> signOut() async {
    final current = state;
    ref.read(notesProvider.notifier).cancelPendingPush();
    ref.read(foldersProvider.notifier).cancelPendingPush();
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

// ── Selected folder / note / search ───────────────────────────────────────────

final selectedFolderProvider = StateProvider<int?>((ref) => null);
final selectedNoteProvider = StateProvider<Note?>((ref) => null);
final searchQueryProvider = StateProvider<String>((ref) => '');

// ── Folders ───────────────────────────────────────────────────────────────────

class FoldersNotifier extends AsyncNotifier<List<Folder>> {
  Timer? _pushTimer;

  @override
  Future<List<Folder>> build() {
    ref.onDispose(() => _pushTimer?.cancel());
    return DatabaseService.instance.getFolders();
  }

  Future<void> reload() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => DatabaseService.instance.getFolders());
  }

  void cancelPendingPush() => _pushTimer?.cancel();

  Future<Folder> createFolder(String name, {int? parentId}) async {
    final folder = Folder.create(name: name, parentId: parentId);
    final id = await DatabaseService.instance.saveFolder(folder);
    folder.id = id;
    await reload();
    _scheduleIndexPush();
    return folder;
  }

  Future<void> renameFolder(Folder folder, String newName) async {
    folder.name = newName;
    await DatabaseService.instance.saveFolder(folder);
    await reload();
    _scheduleIndexPush();
  }

  Future<void> deleteFolder(int id) async {
    await DatabaseService.instance.deleteFolder(id);
    await reload();
    ref.invalidate(notesProvider);
    _scheduleCascadePush(id);
  }

  void _scheduleIndexPush() {
    if (ref.read(appUserProvider)?.type != AuthType.google) return;
    ref.read(syncStatusProvider.notifier).state = SyncStatus.idle;
    _pushTimer?.cancel();
    _pushTimer = Timer(
        const Duration(milliseconds: _kFastPushDebounceMs), _flushIndexPush);
  }

  void _scheduleCascadePush(int deletedFolderId) {
    if (ref.read(appUserProvider)?.type != AuthType.google) return;
    _pushTimer?.cancel();
    _pushTimer = Timer(const Duration(milliseconds: _kFastPushDebounceMs),
        () => _flushCascadePush(deletedFolderId));
  }

  void _flushIndexPush() {
    _run(() => _uploadIndexAndLog(op: 'upsert'));
  }

  Future<void> _flushCascadePush(int deletedId) async {
    // Push each note moved to root so other devices see the folderId change.
    final notes = await DatabaseService.instance.getNotes(allNotes: true);
    for (final n in notes.where((n) => n.folderId == null)) {
      await ref.read(notesProvider.notifier).pushNoteNow(n);
    }
    await _uploadIndexAndLog(op: 'delete', entityId: deletedId);
  }

  void _run(Future<void> Function() task) {
    ref.read(syncStatusProvider.notifier).state = SyncStatus.syncing;
    task().then((_) {
      ref.read(syncStatusProvider.notifier).state = SyncStatus.success;
    }).catchError((Object e) {
      debugPrint('[FoldersNotifier] push failed: $e');
      ref.read(syncStatusProvider.notifier).state = SyncStatus.error;
    });
  }

  Future<void> _uploadIndexAndLog(
      {required String op, int? entityId}) async {
    final drv = DriveSyncService.instance;
    final api = await drv.getApi();
    if (api == null) return;
    final appFolderId = await drv.getOrCreateAppFolder(api);
    final folders = await DatabaseService.instance.getFolders();
    final modTime = await drv.uploadFolderIndex(api, appFolderId, folders);
    await _appendLog(api, appFolderId, op: op, type: 'folder',
        entityId: entityId, modifiedTime: modTime);
  }

  Future<void> _appendLog(drive.DriveApi api, String appFolderId,
      {required String op,
      required String type,
      int? entityId,
      required String modifiedTime}) async {
    final deviceId = await DeviceService.instance.id;
    final userId = ref.read(appUserProvider)?.id;
    if (userId == null) return;
    final seq = await SyncLogService.instance.appendEntry(
      api, appFolderId,
      op: op, type: type, entityId: entityId,
      deviceId: deviceId, modifiedTime: modifiedTime,
    );
    await SyncLogService.instance.saveLastSeq(userId, seq);
  }
}

final foldersProvider =
    AsyncNotifierProvider<FoldersNotifier, List<Folder>>(FoldersNotifier.new);

// ── Notes ─────────────────────────────────────────────────────────────────────

const _kPushDebounceMs = 15000;     // note editing — batches rapid keystrokes
const _kFastPushDebounceMs = 5000; // discrete actions — move/folder ops

class NotesNotifier extends AsyncNotifier<List<Note>> {
  @visibleForTesting
  Timer? pushTimer;
  @visibleForTesting
  Note? pendingNote;
  @visibleForTesting
  List<String> pendingDeletedImages = [];
  // Batches rapid move operations; resets on each new move within the window.
  final List<Note> _pendingMoves = [];
  Timer? _moveTimer;
  // Serializes concurrent push operations so they never race on sync_log.json.
  Future<void> _pushQueue = Future.value();

  @override
  Future<List<Note>> build() => _load();

  Future<List<Note>> _load() {
    final folderId = ref.watch(selectedFolderProvider);
    final query = ref.watch(searchQueryProvider);
    if (query.isNotEmpty) return DatabaseService.instance.searchNotes(query);
    if (folderId == -1) {
      return DatabaseService.instance.getNotes(allNotes: true);
    }
    return DatabaseService.instance.getNotes(folderId: folderId);
  }

  Future<void> reload() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(_load);
  }

  /// Creates an empty note locally. Timer starts only on the first edit.
  Future<Note> createNote({int? folderId}) async {
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
  }

  /// Saves locally and schedules a 15 s push. Tracks images deleted this edit.
  Future<void> saveNote(Note note,
      {List<String> deletedImageFilenames = const []}) async {
    await DatabaseService.instance.saveNote(note);
    await reload();
    if (ref.read(appUserProvider)?.type != AuthType.google) return;
    ref.read(syncStatusProvider.notifier).state = SyncStatus.idle;
    pendingNote = note;
    pendingDeletedImages = [...pendingDeletedImages, ...deletedImageFilenames];
    pushTimer?.cancel();
    pushTimer = Timer(
        const Duration(milliseconds: _kPushDebounceMs), _flushPush);
  }

  Future<void> moveNote(Note note, int? folderId) async {
    note.folderId = folderId;
    await DatabaseService.instance.saveNote(note);
    await reload();
    if (ref.read(appUserProvider)?.type != AuthType.google) return;
    ref.read(syncStatusProvider.notifier).state = SyncStatus.idle;
    _pendingMoves.removeWhere((n) => n.id == note.id);
    _pendingMoves.add(note);
    _moveTimer?.cancel();
    _moveTimer = Timer(
        const Duration(milliseconds: _kFastPushDebounceMs), _flushMoves);
  }

  void _flushMoves() {
    final notes = List<Note>.from(_pendingMoves);
    _pendingMoves.clear();
    for (final note in notes) {
      _run(() => _pushNoteAndImages(note, []));
    }
  }

  Future<void> deleteNote(int id) async {
    final note = await DatabaseService.instance.getNote(id);
    if (pendingNote?.id == id) cancelPendingPush();
    await DatabaseService.instance.deleteNote(id);
    await reload();
    if (note?.driveFileId != null &&
        ref.read(appUserProvider)?.type == AuthType.google) {
      ref.read(syncStatusProvider.notifier).state = SyncStatus.idle;
      _run(() => _pushDelete(note!));
    }
  }

  Note? cancelPendingPush() {
    pushTimer?.cancel();
    pushTimer = null;
    _moveTimer?.cancel();
    _moveTimer = null;
    _pendingMoves.clear();
    final note = pendingNote;
    pendingNote = null;
    pendingDeletedImages = [];
    return note;
  }

  /// Bypasses the debounce — used by folder cascade and sync button.
  Future<void> pushNoteNow(Note note) => _pushNoteAndImages(note, []);

  /// Flushes any pending debounce immediately (sync button / poll trigger).
  void flushPendingPush() => _flushPush();

  void _flushPush() {
    final note = pendingNote;
    final deleted = List<String>.from(pendingDeletedImages);
    pendingNote = null;
    pendingDeletedImages = [];
    if (note == null) return;
    _run(() => performPush(note, deleted));
  }

  /// Overridable in tests to intercept the Drive push without real API calls.
  @visibleForTesting
  Future<void> performPush(Note note, List<String> deletedImages) =>
      _pushNoteAndImages(note, deletedImages);

  void _run(Future<void> Function() task) {
    ref.read(syncStatusProvider.notifier).state = SyncStatus.syncing;
    _pushQueue = _pushQueue.then((_) => task()).then((_) {
      ref.read(syncStatusProvider.notifier).state = SyncStatus.success;
    }).catchError((Object e) {
      debugPrint('[NotesNotifier] push failed: $e');
      ref.read(syncStatusProvider.notifier).state = SyncStatus.error;
    });
  }

  Future<void> _pushNoteAndImages(
      Note note, List<String> deletedImages) async {
    final drv = DriveSyncService.instance;
    final api = await drv.getApi();
    if (api == null) return;
    final appFolderId = await drv.getOrCreateAppFolder(api);
    final modTime = await drv.uploadNote(api, appFolderId, note);
    for (final fname in extractImageFilenames(note.content)) {
      final path = await imageLocalPath(fname);
      if (await File(path).exists()) {
        await drv.uploadImage(api, appFolderId, fname, path);
      }
    }
    for (final fname in deletedImages) {
      await drv.deleteImageFile(api, appFolderId, fname);
      await _appendLog(api, appFolderId, op: 'delete', type: 'image',
          filename: fname, modifiedTime: DateTime.now().toIso8601String());
    }
    await _appendLog(api, appFolderId, op: 'upsert', type: 'note',
        entityId: note.id, modifiedTime: modTime);
  }

  Future<void> _pushDelete(Note note) async {
    final drv = DriveSyncService.instance;
    final api = await drv.getApi();
    if (api == null) return;
    final appFolderId = await drv.getOrCreateAppFolder(api);
    await drv.deleteNoteFile(api, note.driveFileId!);
    await _appendLog(api, appFolderId, op: 'delete', type: 'note',
        entityId: note.id, modifiedTime: DateTime.now().toIso8601String());
  }

  Future<void> _appendLog(drive.DriveApi api, String appFolderId,
      {required String op,
      required String type,
      int? entityId,
      String? filename,
      required String modifiedTime}) async {
    final deviceId = await DeviceService.instance.id;
    final userId = ref.read(appUserProvider)?.id;
    if (userId == null) return;
    final seq = await SyncLogService.instance.appendEntry(
      api, appFolderId,
      op: op, type: type, entityId: entityId,
      filename: filename, deviceId: deviceId, modifiedTime: modifiedTime,
    );
    await SyncLogService.instance.saveLastSeq(userId, seq);
  }
}

final notesProvider =
    AsyncNotifierProvider<NotesNotifier, List<Note>>(NotesNotifier.new);
