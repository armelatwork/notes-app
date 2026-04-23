import 'package:shared_preferences/shared_preferences.dart';

class BackupSettingsService {
  static final BackupSettingsService instance = BackupSettingsService._();
  BackupSettingsService._();

  static const _kEnabledKey = 'backup_enabled';
  static const _kLastBackupKey = 'last_backup_at';

  Future<bool> get isEnabled async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kEnabledKey) ?? true;
  }

  Future<void> setEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kEnabledKey, value);
  }

  Future<DateTime?> get lastBackupAt async {
    final prefs = await SharedPreferences.getInstance();
    final iso = prefs.getString(_kLastBackupKey);
    return iso != null ? DateTime.tryParse(iso) : null;
  }

  Future<void> recordBackup() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kLastBackupKey, DateTime.now().toIso8601String());
  }
}
