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
    await _uploadNote(api, folderId, note);
  }

  Future<void> _uploadNote(
      drive.DriveApi api, String parentFolderId, Note note) async {
    final enc = EncryptionService.instance;
    if (!enc.isInitialized) return;

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

    if (note.driveFileId != null) {
      try {
        await api.files.update(
          drive.File()..name = fileName,
          note.driveFileId!,
          uploadMedia: media,
        );
        return;
      } catch (e) {
        debugPrint('[DriveSyncService] update failed (will create): $e');
      }
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
