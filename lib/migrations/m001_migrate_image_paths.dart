import '../services/database_service.dart';
import '../utils/image_utils.dart' show migrateImageContent;

/// Converts old absolute-path image references in note content to portable
/// UUID filenames, copying the image file to the new location.
/// Safe to re-run — notes with no old-format images are skipped.
class M001MigrateImagePaths {
  String get id => 'm001_migrate_image_paths';

  Future<void> run() async {
    final notes = await DatabaseService.instance.getNotes(allNotes: true);
    for (final note in notes) {
      final migrated = await migrateImageContent(note.content);
      if (migrated != null) {
        note.content = migrated;
        await DatabaseService.instance.saveNote(note);
      }
    }
  }
}
