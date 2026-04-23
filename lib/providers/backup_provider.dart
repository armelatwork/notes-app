import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/backup_settings_service.dart';
import '../services/drive_sync_service.dart';

enum BackupStatus { idle, syncing, success, error }

class BackupState {
  const BackupState({
    required this.enabled,
    this.lastBackupAt,
    this.status = BackupStatus.idle,
  });

  final bool enabled;
  final DateTime? lastBackupAt;
  final BackupStatus status;

  BackupState copyWith({
    bool? enabled,
    DateTime? lastBackupAt,
    BackupStatus? status,
  }) =>
      BackupState(
        enabled: enabled ?? this.enabled,
        lastBackupAt: lastBackupAt ?? this.lastBackupAt,
        status: status ?? this.status,
      );
}

class BackupNotifier extends AsyncNotifier<BackupState> {
  @override
  Future<BackupState> build() async {
    final svc = BackupSettingsService.instance;
    return BackupState(
      enabled: await svc.isEnabled,
      lastBackupAt: await svc.lastBackupAt,
    );
  }

  Future<void> toggle() async {
    final current = state.valueOrNull;
    if (current == null) return;
    final newEnabled = !current.enabled;
    await BackupSettingsService.instance.setEnabled(newEnabled);
    state = AsyncData(current.copyWith(enabled: newEnabled));
    if (newEnabled) await backupNow();
  }

  Future<void> backupNow() async {
    final current = state.valueOrNull;
    if (current == null) return;
    state = AsyncData(current.copyWith(status: BackupStatus.syncing));
    try {
      await DriveSyncService.instance.syncAll();
      await BackupSettingsService.instance.recordBackup();
      final lastBackupAt = await BackupSettingsService.instance.lastBackupAt;
      state = AsyncData(current.copyWith(
        status: BackupStatus.success,
        lastBackupAt: lastBackupAt,
      ));
    } catch (e) {
      state = AsyncData(current.copyWith(status: BackupStatus.error));
    }
  }

  Future<void> refreshLastBackupAt() async {
    final current = state.valueOrNull;
    if (current == null) return;
    final lastBackupAt = await BackupSettingsService.instance.lastBackupAt;
    state = AsyncData(current.copyWith(lastBackupAt: lastBackupAt));
  }
}

final backupProvider =
    AsyncNotifierProvider<BackupNotifier, BackupState>(BackupNotifier.new);
