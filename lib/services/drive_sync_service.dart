import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:http/http.dart' as http;
import '../models/folder.dart';
import '../models/note.dart';
import 'auth_service.dart';
import 'database_service.dart';
import 'encryption_service.dart';

const _kRequestTimeout = Duration(seconds: 30);

class _AuthClient extends http.BaseClient {
  final Map<String, String> _headers;
  final http.Client _inner = http.Client();
  _AuthClient(this._headers);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    request.headers.addAll(_headers);
    return _inner.send(request).timeout(_kRequestTimeout);
  }
}

class DriveSyncService {
  static final DriveSyncService instance = DriveSyncService._();
  DriveSyncService._();

  static const _appFolderName = 'Notes app';
  static const _imagesFolderName = 'images';
  static const _keyFileName = 'encryption_key.b64';
  static const _folderIndexName = 'folders_index.json';
  static const _jsonMime = 'application/json';

  // ── Auth ───────────────────────────────────────────────────────────────────
  Future<drive.DriveApi?> getApi() async {
    final headers = await AuthService.instance.getAuthHeaders();
    if (headers == null) return null;
    return drive.DriveApi(_AuthClient(headers));
  }

  // ── Folder helpers ─────────────────────────────────────────────────────────
  Future<String> getOrCreateAppFolder(drive.DriveApi api) async {
    final r = await api.files.list(
      q: "name='$_appFolderName' and "
          "mimeType='application/vnd.google-apps.folder' and trashed=false",
      spaces: 'drive',
      $fields: 'files(id)',
    );
    if (r.files?.isNotEmpty == true) return r.files!.first.id!;
    final f = await api.files.create(
      drive.File()
        ..name = _appFolderName
        ..mimeType = 'application/vnd.google-apps.folder',
    );
    return f.id!;
  }
  Future<String> _getOrCreateImagesFolder(
      drive.DriveApi api, String appFolderId) async {
    final r = await api.files.list(
      q: "name='$_imagesFolderName' and '$appFolderId' in parents and "
          "mimeType='application/vnd.google-apps.folder' and trashed=false",
      spaces: 'drive',
      $fields: 'files(id)',
    );
    if (r.files?.isNotEmpty == true) return r.files!.first.id!;
    final f = await api.files.create(
      drive.File()
        ..name = _imagesFolderName
        ..mimeType = 'application/vnd.google-apps.folder'
        ..parents = [appFolderId],
    );
    return f.id!;
  }

  // ── Encryption key ─────────────────────────────────────────────────────────
  Future<String?> fetchEncryptionKey(drive.DriveApi api, String appFolderId) async {
    try {
      final r = await api.files.list(
        q: "name='$_keyFileName' and '$appFolderId' in parents and trashed=false",
        spaces: 'drive',
        $fields: 'files(id)',
      );
      if (r.files?.isEmpty != false) return null;
      final media = await api.files.get(
        r.files!.first.id!,
        downloadOptions: drive.DownloadOptions.fullMedia,
      ) as drive.Media;
      return _readMedia(media);
    } catch (e) {
      debugPrint('[DriveSyncService] fetchEncryptionKey failed: $e');
      return null;
    }
  }
  Future<void> uploadEncryptionKey(
      drive.DriveApi api, String appFolderId, String keyBase64) async {
    final bytes = utf8.encode(keyBase64);
    final media = drive.Media(Stream.value(bytes), bytes.length,
        contentType: 'text/plain');
    final existing = await api.files.list(
      q: "name='$_keyFileName' and '$appFolderId' in parents and trashed=false",
      spaces: 'drive',
      $fields: 'files(id)',
    );
    final id = existing.files?.firstOrNull?.id;
    if (id != null) {
      await api.files.update(drive.File(), id, uploadMedia: media);
    } else {
      await api.files.create(
        drive.File()..name = _keyFileName..parents = [appFolderId],
        uploadMedia: media,
      );
    }
  }

  // ── Notes ──────────────────────────────────────────────────────────────────
  /// Uploads a note to Drive. Returns the Drive server modifiedTime.
  Future<String> uploadNote(
      drive.DriveApi api, String appFolderId, Note note) async {
    final enc = EncryptionService.instance;
    if (!enc.isInitialized) throw StateError('Encryption not initialised');
    final payload = jsonEncode({
      'id': note.id,
      'title': await enc.encrypt(note.title),
      'content': await enc.encrypt(note.content),
      'folderId': note.folderId,
      'createdAt': note.createdAt.toIso8601String(),
      'updatedAt': note.updatedAt.toIso8601String(),
    });
    final bytes = utf8.encode(payload);
    final media = drive.Media(Stream.value(bytes), bytes.length,
        contentType: _jsonMime);
    final fileName = 'note_${note.id}.json';
    drive.File result;
    if (note.driveFileId != null) {
      result = await api.files.update(
        drive.File()..name = fileName,
        note.driveFileId!,
        uploadMedia: media,
        $fields: 'id,modifiedTime',
      );
      if (result.modifiedTime == null) {
        result = await api.files.get(note.driveFileId!,
            $fields: 'id,modifiedTime') as drive.File;
      }
    } else {
      result = await api.files.create(
        drive.File()..name = fileName..parents = [appFolderId],
        uploadMedia: media,
        $fields: 'id,modifiedTime',
      );
      note.driveFileId = result.id;
      await DatabaseService.instance.saveNote(note);
    }
    return result.modifiedTime?.toIso8601String() ?? DateTime.now().toIso8601String();
  }

  /// Downloads and decrypts a note from Drive by its local DB id.
  Future<Note?> downloadNote(
      drive.DriveApi api, String appFolderId, int noteId) async {
    try {
      final enc = EncryptionService.instance;
      if (!enc.isInitialized) return null;
      final r = await api.files.list(
        q: "name='note_$noteId.json' and '$appFolderId' in parents and trashed=false",
        spaces: 'drive',
        $fields: 'files(id)',
      );
      if (r.files?.isEmpty != false) return null;
      final fileId = r.files!.first.id!;
      final media = await api.files.get(
        fileId,
        downloadOptions: drive.DownloadOptions.fullMedia,
      ) as drive.Media;
      final json = jsonDecode(await _readMedia(media)) as Map<String, dynamic>;
      final note = Note.create(
        title: await enc.decrypt(json['title'] as String),
        content: await enc.decrypt(json['content'] as String),
        folderId: json['folderId'] as int?,
      );
      note.id = json['id'] as int;
      note.driveFileId = fileId;
      note.createdAt = DateTime.parse(json['createdAt'] as String);
      note.updatedAt = DateTime.parse(json['updatedAt'] as String);
      return note;
    } catch (e) {
      debugPrint('[DriveSyncService] downloadNote $noteId failed: $e');
      return null;
    }
  }
  Future<void> deleteNoteFile(drive.DriveApi api, String driveFileId) async {
    try {
      await api.files.delete(driveFileId);
    } catch (e) {
      debugPrint('[DriveSyncService] deleteNoteFile failed: $e');
    }
  }

  // ── Folder index ───────────────────────────────────────────────────────────
  /// Uploads the full folder list. Returns Drive server modifiedTime.
  Future<String> uploadFolderIndex(
      drive.DriveApi api, String appFolderId, List<Folder> folders) async {
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
        contentType: _jsonMime);
    final existing = await api.files.list(
      q: "name='$_folderIndexName' and '$appFolderId' in parents and trashed=false",
      spaces: 'drive',
      $fields: 'files(id)',
    );
    final existingId = existing.files?.firstOrNull?.id;
    drive.File result;
    if (existingId != null) {
      result = await api.files.update(
        drive.File()..name = _folderIndexName,
        existingId,
        uploadMedia: media,
        $fields: 'id,modifiedTime',
      );
      if (result.modifiedTime == null) {
        result = await api.files.get(existingId, $fields: 'id,modifiedTime')
            as drive.File;
      }
    } else {
      result = await api.files.create(
        drive.File()..name = _folderIndexName..parents = [appFolderId],
        uploadMedia: media,
        $fields: 'id,modifiedTime',
      );
    }
    return result.modifiedTime?.toIso8601String() ?? DateTime.now().toIso8601String();
  }

  Future<List<Folder>?> downloadFolderIndex(
      drive.DriveApi api, String appFolderId) async {
    try {
      final r = await api.files.list(
        q: "name='$_folderIndexName' and '$appFolderId' in parents and trashed=false",
        spaces: 'drive',
        $fields: 'files(id)',
      );
      if (r.files?.isEmpty != false) return [];
      final media = await api.files.get(
        r.files!.first.id!,
        downloadOptions: drive.DownloadOptions.fullMedia,
      ) as drive.Media;
      final list = jsonDecode(await _readMedia(media)) as List<dynamic>;
      return list.map((f) {
        final folder = Folder.create(
            name: f['name'] as String, parentId: f['parentId'] as int?);
        folder.id = f['id'] as int;
        folder.createdAt = DateTime.parse(f['createdAt'] as String);
        folder.updatedAt = DateTime.parse(f['updatedAt'] as String);
        return folder;
      }).toList();
    } catch (e) {
      debugPrint('[DriveSyncService] downloadFolderIndex failed: $e');
      return null;
    }
  }

  // ── Images ─────────────────────────────────────────────────────────────────
  /// Uploads an image file to Drive. Returns Drive server modifiedTime, or null.
  Future<String?> uploadImage(
      drive.DriveApi api, String appFolderId, String filename,
      String localPath) async {
    try {
      final imgFolderId = await _getOrCreateImagesFolder(api, appFolderId);
      final bytes = await File(localPath).readAsBytes();
      final existing = await api.files.list(
        q: "name='$filename' and '$imgFolderId' in parents and trashed=false",
        spaces: 'drive',
        $fields: 'files(id)',
      );
      final existingId = existing.files?.firstOrNull?.id;
      final media = drive.Media(Stream.value(bytes), bytes.length,
          contentType: 'application/octet-stream');
      drive.File result;
      if (existingId != null) {
        result = await api.files.update(drive.File(), existingId,
            uploadMedia: media, $fields: 'id,modifiedTime');
      } else {
        result = await api.files.create(
          drive.File()..name = filename..parents = [imgFolderId],
          uploadMedia: media,
          $fields: 'id,modifiedTime',
        );
      }
      return result.modifiedTime?.toIso8601String();
    } catch (e) {
      debugPrint('[DriveSyncService] uploadImage $filename failed: $e');
      return null;
    }
  }

  /// Downloads a single image to [localPath]. Returns true if found and written.
  Future<bool> downloadImage(String filename, String localPath) async {
    final api = await getApi();
    if (api == null) return false;
    final appFolderId = await getOrCreateAppFolder(api);
    final imgFolderId = await _getOrCreateImagesFolder(api, appFolderId);
    final r = await api.files.list(
      q: "name='$filename' and '$imgFolderId' in parents and trashed=false",
      spaces: 'drive',
      $fields: 'files(id)',
    );
    if (r.files?.isEmpty != false) return false;
    final media = await api.files.get(
      r.files!.first.id!,
      downloadOptions: drive.DownloadOptions.fullMedia,
    ) as drive.Media;
    final bytes = <int>[];
    await for (final chunk in media.stream) {
      bytes.addAll(chunk);
    }
    await File(localPath).writeAsBytes(bytes);
    return true;
  }

  Future<void> deleteImageFile(
      drive.DriveApi api, String appFolderId, String filename) async {
    try {
      final imgFolderId = await _getOrCreateImagesFolder(api, appFolderId);
      final r = await api.files.list(
        q: "name='$filename' and '$imgFolderId' in parents and trashed=false",
        spaces: 'drive',
        $fields: 'files(id)',
      );
      final id = r.files?.firstOrNull?.id;
      if (id != null) await api.files.delete(id);
    } catch (e) {
      debugPrint('[DriveSyncService] deleteImageFile $filename failed: $e');
    }
  }
  // ── Utilities ──────────────────────────────────────────────────────────────
  /// Returns all Drive file IDs for note files in the app folder.
  Future<List<String>> listNoteFileIds(
      drive.DriveApi api, String appFolderId) async {
    final r = await api.files.list(
      q: "name contains 'note_' and '$appFolderId' in parents and trashed=false",
      spaces: 'drive',
      $fields: 'files(id,name)',
    );
    return r.files?.map((f) => f.id!).toList() ?? [];
  }

  Future<Note?> downloadNoteById(
      drive.DriveApi api, String driveFileId) async {
    try {
      final enc = EncryptionService.instance;
      if (!enc.isInitialized) return null;
      final media = await api.files.get(
        driveFileId,
        downloadOptions: drive.DownloadOptions.fullMedia,
      ) as drive.Media;
      final json =
          jsonDecode(await _readMedia(media)) as Map<String, dynamic>;
      final note = Note.create(
        title: await enc.decrypt(json['title'] as String),
        content: await enc.decrypt(json['content'] as String),
        folderId: json['folderId'] as int?,
      );
      note.id = json['id'] as int;
      note.driveFileId = driveFileId;
      note.createdAt = DateTime.parse(json['createdAt'] as String);
      note.updatedAt = DateTime.parse(json['updatedAt'] as String);
      return note;
    } catch (e) {
      debugPrint('[DriveSyncService] downloadNoteById failed: $e');
      return null;
    }
  }

  Future<int> countNotes(drive.DriveApi api, String appFolderId) async {
    final r = await api.files.list(
      q: "name contains 'note_' and '$appFolderId' in parents and trashed=false",
      spaces: 'drive',
      $fields: 'files(id)',
    );
    return r.files?.length ?? 0;
  }

  Future<String> _readMedia(drive.Media media) async {
    final chunks = <int>[];
    await for (final chunk in media.stream) {
      chunks.addAll(chunk);
    }
    return utf8.decode(chunks);
  }
}
