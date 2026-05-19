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

/// Returns true for base64 data URI image refs (e.g. `data:image/png;base64,...`).
bool isBase64ImageRef(String value) => value.startsWith('data:');

const _kMaxInlineImageBytes = 600 * 1024; // 600 KB per image on disk (macOS clipboard PNGs can be large)
const _kMaxTotalInlinedBytes = 800 * 1024; // 800 KB total base64 budget
const _kImageOmittedText =
    '[Image not shared — note exceeded sharing size limit]\n';

/// Replaces UUID image filename refs in a Quill delta JSON with base64 data
/// URIs so recipients can view images without Drive access.
/// Images that exceed the per-file or total budget are replaced with an inline
/// text placeholder so the recipient knows an image was omitted.
Future<String> inlineImagesForSharing(String content) async {
  try {
    final dynamic raw = jsonDecode(content);
    final List<dynamic> ops =
        raw is List ? raw : ((raw as Map)['ops'] as List? ?? []);
    var changed = false;
    var totalInlined = 0;
    final result = <dynamic>[];
    for (final op in ops) {
      if (op is! Map<String, dynamic>) { result.add(op); continue; }
      final insert = op['insert'];
      if (insert is! Map<String, dynamic>) { result.add(op); continue; }
      final ref = insert['image'] as String?;
      if (ref == null || !isNewImageRef(ref)) { result.add(op); continue; }
      final path = await imageLocalPath(ref);
      final file = File(path);
      if (!await file.exists()) { result.add(op); continue; }
      final bytes = await file.readAsBytes();
      final encodedSize = (bytes.length / 3 * 4).ceil();
      if (bytes.length > _kMaxInlineImageBytes ||
          totalInlined + encodedSize > _kMaxTotalInlinedBytes) {
        result.add({'insert': _kImageOmittedText});
        changed = true;
        continue;
      }
      final ext = p.extension(ref).replaceFirst('.', '').toLowerCase();
      final mime = (ext == 'jpg' || ext == 'jpeg') ? 'image/jpeg'
          : ext == 'gif' ? 'image/gif'
          : ext == 'webp' ? 'image/webp'
          : 'image/png';
      result.add({
        ...op,
        'insert': {...insert, 'image': 'data:$mime;base64,${base64Encode(bytes)}'},
      });
      totalInlined += encodedSize;
      changed = true;
    }
    return changed ? jsonEncode(result) : content;
  } catch (_) {
    return content;
  }
}

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
