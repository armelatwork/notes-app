import 'package:shared_preferences/shared_preferences.dart';
import '../services/database_service.dart';
import 'm001_migrate_image_paths.dart';

/// Runs pending data migrations once per user, tracking completion in
/// SharedPreferences so each migration never executes more than once.
class MigrationService {
  static final MigrationService instance = MigrationService._();
  MigrationService._();

  static const _kKey = 'completed_migrations';

  final _migrations = [M001MigrateImagePaths()];

  Future<void> runPendingFor(String userId) async {
    // clearAllOverride is set in every unit test setUp — skip migrations in
    // that environment to avoid triggering path_provider (no Flutter binding).
    if (DatabaseService.clearAllOverride != null) return;
    final prefs = await SharedPreferences.getInstance();
    final key = '${_kKey}_$userId';
    final done = Set<String>.from(prefs.getStringList(key) ?? []);
    for (final migration in _migrations) {
      if (!done.contains(migration.id)) {
        await migration.run();
        done.add(migration.id);
        await prefs.setStringList(key, done.toList());
      }
    }
  }
}
