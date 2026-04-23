import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:http/http.dart' as http;
import '../models/note.dart';
import '../models/folder.dart';
import 'auth_service.dart';
import 'database_service.dart';
import 'encryption_service.dart';

class _AuthClient extends http.BaseClient {
  final Map<String, String> _headers;
  final http.Client _inner = http.Client();

  _AuthClient(this._headers);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    request.headers.addAll(_headers);
    return _inner.send(request);
  }
}

class DriveSyncService {
  static final DriveSyncService instance = DriveSyncService._();
  DriveSyncService._();

  static const _appFolderName = 'Notes app';
  static const _notesMimeType = 'application/json';

  Future<drive.DriveApi?> _getApi() async {
    final headers = await AuthService.instance.getAuthHeaders();
    if (headers == null) return null;
    return drive.DriveApi(_AuthClient(headers));
  }

  Future<String> _getOrCreateAppFolder(drive.DriveApi api) async {
    final result = await api.files.list(
      q: "name='$_appFolderName' and mimeType='application/vnd.google-apps.folder' and trashed=false",
      spaces: 'drive',
      $fields: 'files(id,name)',
    );
    if (result.files != null && result.files!.isNotEmpty) {
      return result.files!.first.id!;
    }
    final folder = await api.files.create(
      drive.File()
        ..name = _appFolderName
        ..mimeType = 'application/vnd.google-apps.folder',
    );
    return folder.id!;
  }

  // Throws a human-readable String on failure so callers can surface it.
  Future<void> syncAll() async {
    final api = await _getApi();
    if (api == null) throw 'Not signed in to Google';

    final folderId = await _getOrCreateAppFolder(api);
    final db = DatabaseService.instance;

    final notes = await db.getNotes(allNotes: true);
    for (final note in notes) {
      await _uploadNote(api, folderId, note);
    }

    final folders = await db.getFolders();
    await _uploadFolderIndex(api, folderId, folders);
  }

  Future<void> syncNote(Note note) async {
    final api = await _getApi();
    if (api == null) throw 'Not signed in to Google';
    final folderId = await _getOrCreateAppFolder(api);
    final recreated = await _uploadNote(api, folderId, note);
    if (recreated) {
      // A Drive file was missing — re-upload everything to ensure full backup.
      await syncAll();
    }
  }

  // Returns true if the note had to be created (was missing from Drive).
  Future<bool> _uploadNote(
      drive.DriveApi api, String parentFolderId, Note note) async {
    final enc = EncryptionService.instance;
    if (!enc.isInitialized) return false;

    final encTitle = await enc.encrypt(note.title);
    final encContent = await enc.encrypt(note.content);

    final payload = jsonEncode({
      'id': note.id,
      'title': encTitle,
      'content': encContent,
      'folderId': note.folderId,
      'createdAt': note.createdAt.toIso8601String(),
      'updatedAt': note.updatedAt.toIso8601String(),
    });

    final bytes = utf8.encode(payload);
    final media = drive.Media(Stream.value(bytes), bytes.length,
        contentType: _notesMimeType);
    final fileName = 'note_${note.id}.json';

    final existing = await api.files.list(
      q: "name='$fileName' and '$parentFolderId' in parents and trashed=false",
      spaces: 'drive',
      $fields: 'files(id)',
    );
    final existingId = existing.files?.firstOrNull?.id;

    if (existingId != null) {
      await api.files.update(
        drive.File()..name = fileName,
        existingId,
        uploadMedia: media,
      );
      if (note.driveFileId != existingId) {
        note.driveFileId = existingId;
        await DatabaseService.instance.saveNote(note);
      }
      return false;
    }

    final created = await api.files.create(
      drive.File()
        ..name = fileName
        ..parents = [parentFolderId]
        ..mimeType = _notesMimeType,
      uploadMedia: media,
    );
    note.driveFileId = created.id;
    await DatabaseService.instance.saveNote(note);
    return true;
  }

  Future<void> deleteNote(String driveFileId) async {
    try {
      final api = await _getApi();
      if (api == null) return;
      await api.files.delete(driveFileId);
    } catch (e) {
      debugPrint('[DriveSyncService] deleteNote failed: $e');
    }
  }

  Future<int> countDriveNotes() async {
    try {
      final api = await _getApi();
      if (api == null) return 0;
      final folderId = await _getOrCreateAppFolder(api);
      final result = await api.files.list(
        q: "name contains 'note_' and '$folderId' in parents and trashed=false",
        spaces: 'drive',
        $fields: 'files(id)',
      );
      return result.files?.length ?? 0;
    } catch (e) {
      debugPrint('[DriveSyncService] countDriveNotes failed: $e');
      return 0;
    }
  }

  Future<void> restoreAll() async {
    final api = await _getApi();
    if (api == null) throw 'Not signed in to Google';
    final enc = EncryptionService.instance;
    if (!enc.isInitialized) throw 'Encryption not initialised';
    final folderId = await _getOrCreateAppFolder(api);
    await _restoreFolders(api, folderId);
    await _restoreNotes(api, folderId, enc);
  }

  Future<void> _restoreFolders(drive.DriveApi api, String folderId) async {
    final result = await api.files.list(
      q: "name='folders_index.json' and '$folderId' in parents and trashed=false",
      spaces: 'drive',
      $fields: 'files(id)',
    );
    if (result.files == null || result.files!.isEmpty) return;
    final media = await api.files.get(
      result.files!.first.id!,
      downloadOptions: drive.DownloadOptions.fullMedia,
    ) as drive.Media;
    final raw = await _readMedia(media);
    final List<dynamic> list = jsonDecode(raw);
    for (final f in list) {
      final folder = Folder.create(
        name: f['name'] as String,
        parentId: f['parentId'] as int?,
      );
      folder.id = f['id'] as int;
      folder.createdAt = DateTime.parse(f['createdAt'] as String);
      folder.updatedAt = DateTime.parse(f['updatedAt'] as String);
      await DatabaseService.instance.restoreFolder(folder);
    }
  }

  Future<void> _restoreNotes(
      drive.DriveApi api, String folderId, EncryptionService enc) async {
    final result = await api.files.list(
      q: "name contains 'note_' and '$folderId' in parents and trashed=false",
      spaces: 'drive',
      $fields: 'files(id,name)',
    );
    for (final file in result.files ?? []) {
      await _restoreNote(api, file, enc);
    }
  }

  Future<void> _restoreNote(
      drive.DriveApi api, drive.File file, EncryptionService enc) async {
    try {
      final media = await api.files.get(
        file.id!,
        downloadOptions: drive.DownloadOptions.fullMedia,
      ) as drive.Media;
      final raw = await _readMedia(media);
      final json = jsonDecode(raw) as Map<String, dynamic>;
      final note = Note.create(
        title: await enc.decrypt(json['title'] as String),
        content: await enc.decrypt(json['content'] as String),
        folderId: json['folderId'] as int?,
      );
      note.id = json['id'] as int;
      note.driveFileId = file.id;
      note.createdAt = DateTime.parse(json['createdAt'] as String);
      note.updatedAt = DateTime.parse(json['updatedAt'] as String);
      await DatabaseService.instance.restoreNote(note);
    } catch (e) {
      debugPrint('[DriveSyncService] restoreNote ${file.name} failed: $e');
    }
  }

  Future<String> _readMedia(drive.Media media) async {
    final chunks = <int>[];
    await for (final chunk in media.stream) {
      chunks.addAll(chunk);
    }
    return utf8.decode(chunks);
  }

  Future<void> _uploadFolderIndex(
      drive.DriveApi api, String parentFolderId, List<Folder> folders) async {
    final payload = jsonEncode(folders
        .map((f) => {
              'id': f.id,
              'name': f.name,
              'parentId': f.parentId,
              'createdAt': f.createdAt.toIso8601String(),
              'updatedAt': f.updatedAt.toIso8601String(),
            })
        .toList());

    final bytes = utf8.encode(payload);
    final media = drive.Media(Stream.value(bytes), bytes.length,
        contentType: _notesMimeType);

    final result = await api.files.list(
      q: "name='folders_index.json' and '$parentFolderId' in parents and trashed=false",
      spaces: 'drive',
      $fields: 'files(id)',
    );

    if (result.files != null && result.files!.isNotEmpty) {
      await api.files.update(
        drive.File()..name = 'folders_index.json',
        result.files!.first.id!,
        uploadMedia: media,
      );
    } else {
      await api.files.create(
        drive.File()
          ..name = 'folders_index.json'
          ..parents = [parentFolderId]
          ..mimeType = _notesMimeType,
        uploadMedia: media,
      );
    }
  }
}
