part of 'app_provider.dart';

// ── AppUserNotifier helpers ───────────────────────────────────────────────────
// Pure functions that operate on service singletons without needing ref or state.

// Prefer the locally stored key (SecureStorage) — it was used to encrypt
// notes on this device and persists across sign-outs. Falls back to Drive
// on a fresh install. Self-repairs Drive if the two keys have drifted apart.
Future<void> _initEncryptionKey(
    dynamic api, String appFolderId, String userId) async {
  final enc = EncryptionService.instance;
  final drv = DriveSyncService.instance;
  final localKey = await enc.readLocalKeyBase64(userId);
  if (localKey != null) {
    enc.initWithKey(Uint8List.fromList(base64Decode(localKey)));
    final remoteKey = await drv.fetchEncryptionKey(api, appFolderId);
    if (remoteKey == null || remoteKey != localKey) {
      AppLogger.instance.warn('AppUserNotifier',
          'Drive key differs from local storage — restoring local key to Drive');
      try {
        await drv.uploadEncryptionKey(api, appFolderId, localKey);
      } catch (e) {
        AppLogger.instance.warn('AppUserNotifier', 'Drive key repair failed', e);
      }
    }
    return;
  }
  // No local key (fresh install). Fall back to Drive; persist locally to
  // prevent future divergence.
  final remoteKey = await drv.fetchEncryptionKey(api, appFolderId);
  if (remoteKey != null) {
    enc.initWithKey(Uint8List.fromList(base64Decode(remoteKey)));
    await enc.saveCurrentKeyLocally(userId);
    return;
  }
  await enc.initForGoogleUser(userId);
  await _uploadNewKey(api, appFolderId, await enc.exportCurrentKeyBase64());
}

Future<void> _uploadNewKey(
    dynamic api, String appFolderId, String newKey) async {
  final drv = DriveSyncService.instance;
  try {
    await drv.uploadEncryptionKey(api, appFolderId, newKey);
  } catch (e) {
    // The parent folder may have been deleted from Drive between the list
    // and the create calls. Clear the cache and retry with a fresh folder.
    AppLogger.instance.warn(
        'AppUserNotifier', 'uploadEncryptionKey failed, retrying with fresh folder', e);
    drv.clearCache();
    final freshFolderId = await drv.getOrCreateAppFolder(api);
    await drv.uploadEncryptionKey(api, freshFolderId, newKey);
  }
}

Future<void> _deleteLocalData() async {
  await DatabaseService.instance.clearAll();
  try {
    await deleteLocalImages();
  } catch (e) {
    AppLogger.instance.warn('AppUserNotifier', 'failed to delete local images', e);
  }
  try {
    await PersistenceService.instance.saveLastFolder(null);
    await PersistenceService.instance.saveLastNote(null);
  } catch (e) {
    AppLogger.instance.warn('AppUserNotifier', 'failed to clear persistence', e);
  }
}
