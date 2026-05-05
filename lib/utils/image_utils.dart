import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

const _uuid = Uuid();

/// Returns the absolute local path for a UUID image filename,
/// creating the note_images directory if it does not exist yet.
Future<String> imageLocalPath(String filename) async {
  final appDir = await getApplicationDocumentsDirectory();
  final dir = Directory(p.join(appDir.path, 'note_images'));
  await dir.create(recursive: true);
  return p.join(dir.path, filename);
}

/// Generates a stable UUID-based filename like `img_<uuid>.jpg` from [sourcePath].
String generateImageFilename(String sourcePath) {
  final ext = p.extension(sourcePath).toLowerCase();
  return 'img_${_uuid.v4()}$ext';
}

/// Returns true for UUID-based image refs (e.g. `img_abc123.jpg`).
/// Legacy refs contain path separators or don't start with `img_`.
bool isNewImageRef(String value) =>
    value.startsWith('img_') &&
    !value.contains('/') &&
    !value.contains('\\');

/// Scans [content] (Quill delta JSON) for legacy absolute-path image refs,
/// copies each file to the note_images directory under a new UUID name, and
/// returns the updated JSON. Returns null if no migration was needed.
Future<String?> migrateImageContent(String content) async {
  try {
    final dynamic raw = jsonDecode(content);
    final List<dynamic> ops;
    if (raw is List) {
      ops = raw;
    } else if (raw is Map) {
      ops = (raw['ops'] as List<dynamic>?) ?? [];
    } else {
      return null;
    }
    var changed = false;
    final migrated = <dynamic>[];
    for (final op in ops) {
      if (op is! Map<String, dynamic>) { migrated.add(op); continue; }
      final insert = op['insert'];
      if (insert is! Map<String, dynamic>) { migrated.add(op); continue; }
      final ref = insert['image'] as String?;
      if (ref == null || isNewImageRef(ref)) { migrated.add(op); continue; }
      final src = File(ref);
      if (!await src.exists()) { migrated.add(op); continue; }
      final newFilename = generateImageFilename(ref);
      final dest = await imageLocalPath(newFilename);
      await src.copy(dest);
      migrated.add({...op, 'insert': {...insert, 'image': newFilename}});
      changed = true;
    }
    return changed ? jsonEncode(migrated) : null;
  } catch (_) {
    return null;
  }
}

/// Parses a Quill delta JSON string and returns all UUID image filenames.
List<String> extractImageFilenames(String content) {
  try {
    final dynamic raw = jsonDecode(content);
    final List<dynamic> ops;
    if (raw is List) {
      ops = raw;
    } else if (raw is Map) {
      ops = (raw['ops'] as List<dynamic>?) ?? [];
    } else {
      return [];
    }
    return ops
        .whereType<Map<String, dynamic>>()
        .map((op) => op['insert'])
        .whereType<Map<String, dynamic>>()
        .map((ins) => ins['image'] as String?)
        .whereType<String>()
        .where(isNewImageRef)
        .toList();
  } catch (_) {
    return [];
  }
}
