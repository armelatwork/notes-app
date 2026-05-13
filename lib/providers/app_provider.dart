import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import '../models/app_user.dart';
import '../models/folder.dart';
import '../models/note.dart';
import '../services/app_logger.dart';
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

enum DriveStorageSeverity { none, warning, exceeded }

class DriveStorageAlert {
  final DriveStorageSeverity severity;
  // null = current user ("Your Drive"). Set to the folder owner's display
  // name when note-sharing is added so the message adapts automatically.
  final String? ownerName;
  final int? usagePercent;

  const DriveStorageAlert({
    required this.severity,
    this.ownerName,
    this.usagePercent,
  });

  static const none = DriveStorageAlert(severity: DriveStorageSeverity.none);

  String get message {
    final prefix = ownerName != null ? "$ownerName's" : 'Your';
    final action =
        ownerName != null ? 'Ask them to free up space' : 'Free up space';
    return switch (severity) {
      DriveStorageSeverity.none => '',
      DriveStorageSeverity.warning =>
        '$prefix Google Drive storage is $usagePercent% full. '
            '$action to avoid sync interruptions.',
      DriveStorageSeverity.exceeded =>
        '$prefix Google Drive storage is full. $action to continue syncing.',
    };
  }
}

final driveStorageAlertProvider =
    StateProvider<DriveStorageAlert>((ref) => DriveStorageAlert.none);

bool isStorageQuotaExceeded(Object e) {
  final s = e.toString().toLowerCase();
  return s.contains('storagequotaexceeded') || s.contains('quota_exceeded');
}

// ── Current authenticated user ────────────────────────────────────────────────

class AppUserNotifier extends Notifier<AppUser?> {
  @override
  AppUser? build() => null;

  Future<void> tryRestore() async {
    final googleUser = await AuthService.instance.trySilentSignIn();
    if (googleUser == null) return;
    try {
      await _initGoogleSession(googleUser.id, googleUser);
    } catch (e) {
      // The restored token lacks the Drive scope (403 insufficient scopes).
      // Clear the cached session so the user is prompted to sign in
      // interactively, which goes through _ensureDriveScope and re-grants it.
      if (_isAuthScopeError(e)) {
        AppLogger.instance.warn(
            'AppUserNotifier', 'restored token lacks Drive scope — clearing session', e);
        await AuthService.instance.signOut();
        return;
      }
      AppLogger.instance.error('AppUserNotifier', 'session restore failed', e);
    }
  }

  // Catches 401 (invalid credentials) and 403 (insufficient scope) from the
  // Drive API — both indicate the token lacks the required drive.file access.
  static bool _isAuthScopeError(Object e) {
    final s = e.toString();
    return s.contains('401') ||
        (s.contains('403') && s.contains('scope')) ||
        s.contains('insufficient');
  }

  Future<void> setGoogleUser(dynamic googleUser) async {
    try {
      await _initGoogleSession(googleUser.id as String, googleUser);
    } catch (e) {
      if (_isAuthScopeError(e)) {
        AppLogger.instance.warn(
            'AppUserNotifier', 'Drive scope missing after sign-in; signing out', e);
        await AuthService.instance.signOut();
        return;
      }
      rethrow;
    }
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
    DriveSyncService.instance.clearCache();
    ref.read(notesProvider.notifier).cancelPendingPush();
    ref.read(foldersProvider.notifier).cancelPendingPush();
    ref.read(driveStorageAlertProvider.notifier).state = DriveStorageAlert.none;
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

  Future<void> deleteAccount() async {
    final current = state;
    ref.read(notesProvider.notifier).cancelPendingPush();
    ref.read(foldersProvider.notifier).cancelPendingPush();
    ref.read(driveStorageAlertProvider.notifier).state = DriveStorageAlert.none;
    await DatabaseService.instance.clearAll();
    if (current?.type == AuthType.google) {
      final api = await DriveSyncService.instance.getApi();
      if (api != null) {
        await DriveSyncService.instance.deleteAppData(api);
      }
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
