import 'package:shared_preferences/shared_preferences.dart';

class PersistenceService {
  static final PersistenceService instance = PersistenceService._();
  PersistenceService._();

  static const _folderKey = 'last_folder_id';
  static const _noteKey = 'last_note_id';
  static const _userKey = 'last_user_id';

  // 0 is a sentinel for null (Inbox) since Isar IDs start at 1.
  // Absent key means the user has never set a preference → default to All Notes.
  static const _kInboxSentinel = 0;

  // -1 means "All Notes", null means "No folder selected (root)"
  Future<void> saveLastFolder(int? folderId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_folderKey, folderId ?? _kInboxSentinel);
  }

  Future<int?> loadLastFolder() async {
    final prefs = await SharedPreferences.getInstance();
    if (!prefs.containsKey(_folderKey)) return -1; // first login → All Notes
    final raw = prefs.getInt(_folderKey)!;
    return raw == _kInboxSentinel ? null : raw;
  }

  Future<void> saveLastNote(int? noteId) async {
    final prefs = await SharedPreferences.getInstance();
    if (noteId == null) {
      await prefs.remove(_noteKey);
    } else {
      await prefs.setInt(_noteKey, noteId);
    }
  }

  Future<int?> loadLastNote() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_noteKey);
  }

  Future<String?> loadLastUserId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_userKey);
  }

  Future<void> saveLastUserId(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_userKey, userId);
  }
}
