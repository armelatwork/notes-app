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

part 'folders_provider.dart';
part 'notes_provider.dart';

// ── Sync status ───────────────────────────────────────────────────────────────

enum SyncStatus { idle, syncing, success, error }

final syncStatusProvider = StateProvider<SyncStatus>((ref) => SyncStatus.idle);
final noteReloadTriggerProvider = StateProvider<int>((ref) => 0);
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
