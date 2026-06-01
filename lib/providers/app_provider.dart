import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
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
import '../services/feedback_service.dart';
import '../services/persistence_service.dart';
import '../services/sharing_service.dart';
import '../services/sync_log_service.dart';
import '../services/ai_service.dart';
import '../services/claude_api_service.dart';
import '../services/gemini_api_service.dart';
import '../services/openai_api_service.dart';
import '../services/perplexity_api_service.dart';
import '../utils/image_utils.dart';
import '../utils/note_utils.dart';

part 'folders_provider.dart';
part 'notes_provider.dart';
part 'notes_drive_sync.dart';
part 'app_provider_helpers.dart';

// ── Sync status ───────────────────────────────────────────────────────────────

enum SyncStatus { idle, syncing, success, error }

final syncStatusProvider = StateProvider<SyncStatus>((ref) => SyncStatus.idle);
final noteReloadTriggerProvider = StateProvider<int>((ref) => 0);
final pollTriggerProvider = StateProvider<int>((ref) => 0);
// Keep for any existing call-sites; new code should use aiKeyVerifiedProvider.
final claudeKeyVerifiedProvider = FutureProvider<bool>(
  (_) => ClaudeApiService.instance.isVerified(),
);
final aiHelperRequestProvider = StateProvider<int>((ref) => 0);

// ── Multi-provider AI ─────────────────────────────────────────────────────────

enum AiProvider { claude, perplexity, gemini, chatgpt }

class AiProviderNotifier extends Notifier<AiProvider> {
  @override
  AiProvider build() => AiProvider.claude;

  Future<void> select(AiProvider provider) async {
    state = provider;
    await PersistenceService.instance.saveAiProvider(provider.name);
  }

  Future<void> restore() async {
    final saved = await PersistenceService.instance.loadAiProvider();
    if (saved != null) {
      state = AiProvider.values.firstWhere(
        (p) => p.name == saved,
        orElse: () => AiProvider.claude,
      );
    }
  }
}

final aiProviderProvider =
    NotifierProvider<AiProviderNotifier, AiProvider>(AiProviderNotifier.new);

final activeAiServiceProvider = Provider<AiService>((ref) {
  return switch (ref.watch(aiProviderProvider)) {
    AiProvider.claude => ClaudeApiService.instance,
    AiProvider.perplexity => PerplexityApiService.instance,
    AiProvider.gemini => GeminiApiService.instance,
    AiProvider.chatgpt => OpenAiApiService.instance,
  };
});

final aiKeyVerifiedProvider = FutureProvider<bool>((ref) {
  return ref.watch(activeAiServiceProvider).isVerified();
});

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
    final incomingId = googleUser.id as String;
    // Switching accounts without an explicit sign-out: clear the previous
    // user's local data so the incoming user starts with a clean slate.
    if (state != null && state!.id != incomingId) {
      await DatabaseService.instance.clearAll();
      await PersistenceService.instance.saveLastFolder(null);
      await PersistenceService.instance.saveLastNote(null);
    }
    try {
      await _initGoogleSession(incomingId, googleUser);
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
    final drv = DriveSyncService.instance;
    // Always start with a clean folder cache so a stale ID from a previous
    // session never leaks into the new user's Drive requests.
    drv.clearCache();
    SyncLogService.instance.clearCache();
    final api = await drv.getApi();
    if (api == null) return;
    final appFolderId = await drv.getOrCreateAppFolder(api);
    await _initEncryptionKey(api, appFolderId, userId);
    state = AppUser(
      id: userId,
      displayName: googleUser.displayName as String? ?? googleUser.email as String,
      email: googleUser.email as String,
      type: AuthType.google,
    );
  }

  void setLocalUser(AppUser user) => state = user;

  // Flush pending Drive uploads before revoking auth so notes edited just
  // before logout are not lost when clearAll() wipes the local copy.
  Future<void> _flushPendingSync() async {
    try {
      await Future.wait([
        ref.read(notesProvider.notifier).flushAndDrain(),
        ref.read(foldersProvider.notifier).flushNow(),
      ]).timeout(const Duration(seconds: 15));
    } catch (e) {
      AppLogger.instance.warn(
          'AppUserNotifier', 'pre-logout sync flush failed or timed out', e);
    }
  }

  Future<void> signOut() async {
    final current = state;
    if (current?.type == AuthType.google) await _flushPendingSync();
    DriveSyncService.instance.clearCache();
    SyncLogService.instance.clearCache();
    ref.read(notesProvider.notifier).cancelPendingPush();
    ref.read(foldersProvider.notifier).cancelPendingPush();
    ref.read(driveStorageAlertProvider.notifier).state = DriveStorageAlert.none;
    if (current?.type == AuthType.google) {
      await AuthService.instance.signOut();
      // Clear local Isar data so the next Google user starts with a clean
      // slate. Their notes are safe on Drive and will re-sync on next login.
      await DatabaseService.instance.clearAll();
      await PersistenceService.instance.saveLastFolder(null);
      await PersistenceService.instance.saveLastNote(null);
    } else if (current?.type == AuthType.local) {
      await LocalAuthService.instance.signOut();
    }
    EncryptionService.instance.clear();
    FeedbackService.instance.reset();
    ref.invalidate(notesProvider);
    ref.invalidate(foldersProvider);
    ref.read(selectedNoteProvider.notifier).state = null;
    ref.read(selectedFolderProvider.notifier).state = null;
    state = null;
  }

  void _resetState() {
    DriveSyncService.instance.clearCache();
    SyncLogService.instance.clearCache();
    EncryptionService.instance.clear();
    FeedbackService.instance.reset();
    ref.invalidate(notesProvider);
    ref.invalidate(foldersProvider);
    ref.read(selectedNoteProvider.notifier).state = null;
    ref.read(selectedFolderProvider.notifier).state = null;
    state = null;
  }

  // Remote data (Firestore + Drive) is deleted first. If any remote step fails
  // after all retries, the method throws and local data is left intact so the
  // user can retry. Local data is only wiped once every remote deletion succeeds.
  // State reset always runs even if the final signOut throws (e.g. keychain error).
  Future<void> deleteAccount() async {
    final current = state;
    ref.read(notesProvider.notifier).cancelPendingPush();
    ref.read(foldersProvider.notifier).cancelPendingPush();
    ref.read(driveStorageAlertProvider.notifier).state = DriveStorageAlert.none;
    if (current?.type == AuthType.google) {
      await _cleanupFirestoreSharing(current!);
      await _withRetry(() async {
        final api = await DriveSyncService.instance.getApi();
        if (api == null) throw Exception('Could not connect to Google Drive');
        await DriveSyncService.instance.deleteAppData(api);
      }, 'Drive deletion');
    }
    await _deleteLocalData();
    // A 10 s timeout ensures a hanging Firebase keychain call (common on
    // macOS without a developer certificate) never blocks the state reset.
    try {
      if (current?.type == AuthType.google) {
        await AuthService.instance.signOut().timeout(const Duration(seconds: 10));
      } else if (current?.type == AuthType.local) {
        await LocalAuthService.instance.deleteAccount();
      }
    } catch (e) {
      AppLogger.instance.warn('AppUserNotifier', 'signOut during deleteAccount failed', e);
    }
    _resetState();
  }

  Future<void> _cleanupFirestoreSharing(AppUser user) async {
    await _withRetry(
        () => SharingService.instance.deleteAllOwnedSharedNotes(user.id),
        'Firestore owned notes');
    if (user.email == null) return;
    await _withRetry(
        () => SharingService.instance.removeFromAllSharedNotes(user.email!),
        'Firestore collaborator removal');
  }
}

final appUserProvider =
    NotifierProvider<AppUserNotifier, AppUser?>(AppUserNotifier.new);

// ── Retry helper ──────────────────────────────────────────────────────────────

const _kDeleteMaxAttempts = 3;
const _kDeleteAttemptTimeout = Duration(seconds: 10);
const _kDeleteRetryDelay = Duration(seconds: 2);

/// Retries [fn] up to [_kDeleteMaxAttempts] times, each with a
/// [_kDeleteAttemptTimeout] deadline. Throws the last error if all fail.
Future<T> _withRetry<T>(Future<T> Function() fn, String tag) async {
  Object? lastError;
  for (var i = 0; i < _kDeleteMaxAttempts; i++) {
    try {
      return await fn().timeout(_kDeleteAttemptTimeout);
    } catch (e) {
      lastError = e;
      AppLogger.instance.warn('deleteAccount', '$tag attempt ${i + 1} failed', e);
      if (i < _kDeleteMaxAttempts - 1) {
        await Future.delayed(_kDeleteRetryDelay);
      }
    }
  }
  throw lastError!;
}

// ── Selected folder / note / search ───────────────────────────────────────────

const kFolderAllNotes = -1;
const kFolderPinnedNotes = -2;

final selectedFolderProvider = StateProvider<int?>((ref) => null);
final selectedNoteProvider = StateProvider<Note?>((ref) => null);
final searchQueryProvider = StateProvider<String>((ref) => '');
final themeModeProvider = StateProvider<ThemeMode>((ref) => ThemeMode.system);
