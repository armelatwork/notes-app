part of 'app_provider.dart';

// ── Push debounce constants ────────────────────────────────────────────────────

const _kPushDebounceMs = 15000;     // note editing — batches rapid keystrokes
const _kFastPushDebounceMs = 5000;  // discrete actions — move/folder ops

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
      AppLogger.instance.error('FoldersNotifier', 'push failed', e);
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
    await _appendLog(api, appFolderId,
        op: op, type: 'folder', entityId: entityId, modifiedTime: modTime);
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
