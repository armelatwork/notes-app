import 'package:isar/isar.dart';
import 'package:path_provider/path_provider.dart';
import '../models/note.dart';
import '../models/folder.dart';

class DatabaseService {
  static DatabaseService? _instance;
  static Isar? _isar;

  DatabaseService._();

  static DatabaseService get instance {
    _instance ??= DatabaseService._();
    return _instance!;
  }

  Future<Isar> get db async {
    if (_isar != null) return _isar!;
    final dir = await getApplicationDocumentsDirectory();
    _isar = await Isar.open(
      [NoteSchema, FolderSchema],
      directory: dir.path,
    );
    return _isar!;
  }

  // ── Notes ────────────────────────────────────────────────────────────────

  Future<List<Note>> getNotes({int? folderId, bool allNotes = false}) async {
    final isar = await db;
    if (allNotes) {
      return isar.notes.where().sortByUpdatedAtDesc().findAll();
    }
    if (folderId == null) {
      return isar.notes.filter().folderIdIsNull().sortByUpdatedAtDesc().findAll();
    }
    return isar.notes.filter().folderIdEqualTo(folderId).sortByUpdatedAtDesc().findAll();
  }

  Future<Note?> getNote(int id) async {
    final isar = await db;
    return isar.notes.get(id);
  }

  Future<int> saveNote(Note note) async {
    final isar = await db;
    note.updatedAt = DateTime.now();
    return isar.writeTxn(() => isar.notes.put(note));
  }

  Future<void> deleteNote(int id) async {
    final isar = await db;
    await isar.writeTxn(() => isar.notes.delete(id));
  }

  Future<List<Note>> searchNotes(String query) async {
    final isar = await db;
    final lower = query.toLowerCase();
    final all = await isar.notes.where().sortByUpdatedAtDesc().findAll();
    return all
        .where((n) =>
            n.title.toLowerCase().contains(lower) ||
            n.preview.toLowerCase().contains(lower))
        .toList();
  }

  // ── Folders ──────────────────────────────────────────────────────────────

  Future<List<Folder>> getFolders({int? parentId}) async {
    final isar = await db;
    if (parentId == null) {
      return isar.folders.filter().parentIdIsNull().sortByName().findAll();
    }
    return isar.folders.filter().parentIdEqualTo(parentId).sortByName().findAll();
  }

  Future<int> saveFolder(Folder folder) async {
    final isar = await db;
    folder.updatedAt = DateTime.now();
    return isar.writeTxn(() => isar.folders.put(folder));
  }

  Future<void> deleteFolder(int id) async {
    final isar = await db;
    await isar.writeTxn(() async {
      // Move notes in this folder to root
      final notes = await isar.notes.filter().folderIdEqualTo(id).findAll();
      for (final note in notes) {
        note.folderId = null;
        await isar.notes.put(note);
      }
      // Delete sub-folders recursively
      final subFolders = await isar.folders.filter().parentIdEqualTo(id).findAll();
      for (final sub in subFolders) {
        await isar.folders.delete(sub.id);
      }
      await isar.folders.delete(id);
    });
  }

  /// Inserts or replaces a note WITHOUT updating updatedAt — used during sync.
  Future<void> upsertNote(Note note) async {
    final isar = await db;
    await isar.writeTxn(() => isar.notes.put(note));
  }

  /// Inserts or replaces a folder WITHOUT updating updatedAt — used during sync.
  Future<void> upsertFolder(Folder folder) async {
    final isar = await db;
    await isar.writeTxn(() => isar.folders.put(folder));
  }

  Future<void> clearAll() async {
    final isar = await db;
    await isar.writeTxn(() async {
      await isar.notes.clear();
      await isar.folders.clear();
    });
  }

  Future<void> close() async {
    await _isar?.close();
    _isar = null;
  }
}
