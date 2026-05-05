import 'dart:convert';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:shared_preferences/shared_preferences.dart';
import 'app_logger.dart';

class SyncLogEntry {
  final int seq;
  final String op;        // 'upsert' | 'delete'
  final String type;      // 'note' | 'folder' | 'image'
  final int? entityId;    // for note / folder
  final String? filename; // for image
  final String deviceId;
  final String modifiedTime;

  const SyncLogEntry({
    required this.seq,
    required this.op,
    required this.type,
    this.entityId,
    this.filename,
    required this.deviceId,
    required this.modifiedTime,
  });

  factory SyncLogEntry.fromJson(Map<String, dynamic> j) => SyncLogEntry(
        seq: j['seq'] as int,
        op: j['op'] as String,
        type: j['type'] as String,
        entityId: j['entityId'] as int?,
        filename: j['filename'] as String?,
        deviceId: j['deviceId'] as String,
        modifiedTime: j['modifiedTime'] as String,
      );

  Map<String, dynamic> toJson() => {
        'seq': seq,
        'op': op,
        'type': type,
        if (entityId != null) 'entityId': entityId,
        if (filename != null) 'filename': filename,
        'deviceId': deviceId,
        'modifiedTime': modifiedTime,
      };
}

/// Manages `sync_log.json` on Drive — a lightweight change log that lets
/// every device discover what changed since its last poll without downloading
/// all notes/folders/images on each cycle.
class SyncLogService {
  static final SyncLogService instance = SyncLogService._();
  SyncLogService._();

  static const _kFileName = 'sync_log.json';
  static const _kMaxEntries = 500;
  static const _kLastSeqPrefix = 'sync_last_seq_';
  static const _kLogModTimePrefix = 'sync_log_mod_';
  static const _jsonMime = 'application/json';

  String? _cachedFileId;

  // ── Polling helpers ────────────────────────────────────────────────────────

  /// Returns the Drive server modifiedTime of sync_log.json, or null if absent.
  /// This is a cheap metadata-only call (< 200 bytes); the full file is only
  /// downloaded when this timestamp has advanced since the last poll.
  Future<String?> fetchLogModifiedTime(
      drive.DriveApi api, String appFolderId) async {
    try {
      final r = await api.files.list(
        q: "name='$_kFileName' and '$appFolderId' in parents and trashed=false",
        spaces: 'drive',
        $fields: 'files(id,modifiedTime)',
      );
      if (r.files?.isEmpty != false) return null;
      _cachedFileId = r.files!.first.id;
      return r.files!.first.modifiedTime?.toIso8601String();
    } catch (e) {
      AppLogger.instance.error('SyncLogService', 'fetchLogModifiedTime failed', e);
      return null;
    }
  }

  /// Downloads the full log and returns entries with seq > [lastSeq] whose
  /// deviceId differs from [myDeviceId].  Also returns the highest seq found.
  /// Returns null if the download fails (caller should retry next poll).
  Future<({List<SyncLogEntry> entries, int maxSeq})?> fetchEntriesSince(
      drive.DriveApi api,
      String appFolderId,
      int lastSeq,
      String myDeviceId) async {
    try {
      final fileId = await _ensureFileId(api, appFolderId);
      if (fileId == null) return (entries: <SyncLogEntry>[], maxSeq: lastSeq);
      final media = await api.files.get(
        fileId,
        downloadOptions: drive.DownloadOptions.fullMedia,
      ) as drive.Media;
      final chunks = <int>[];
      await for (final c in media.stream) {
        chunks.addAll(c);
      }
      final json = jsonDecode(utf8.decode(chunks)) as Map<String, dynamic>;
      final all = (json['entries'] as List<dynamic>? ?? [])
          .map((e) => SyncLogEntry.fromJson(e as Map<String, dynamic>))
          .toList();
      final newer = all
          .where((e) => e.seq > lastSeq && e.deviceId != myDeviceId)
          .toList();
      final maxSeq = all.isEmpty ? lastSeq : all.map((e) => e.seq).reduce((a, b) => a > b ? a : b);
      return (entries: newer, maxSeq: maxSeq);
    } catch (e) {
      AppLogger.instance.error('SyncLogService', 'fetchEntriesSince failed', e);
      return null;
    }
  }

  // ── Write ──────────────────────────────────────────────────────────────────

  /// Appends a new entry and returns the assigned seq.
  /// Compacts to [_kMaxEntries] if the log grows too large.
  Future<int> appendEntry(drive.DriveApi api, String appFolderId,
      {required String op,
      required String type,
      int? entityId,
      String? filename,
      required String deviceId,
      required String modifiedTime}) =>
      appendEntries(api, appFolderId, [(
        op: op, type: type, entityId: entityId,
        filename: filename, deviceId: deviceId, modifiedTime: modifiedTime,
      )]);

  /// Appends multiple entries in a single read-modify-write cycle and returns
  /// the highest seq assigned. Use this for batch operations (e.g. bulk moves)
  /// so all entries land in one Drive write and the receiving device sees them
  /// all on its next poll.
  Future<int> appendEntries(
      drive.DriveApi api,
      String appFolderId,
      List<({String op, String type, int? entityId, String? filename,
             String deviceId, String modifiedTime})> batch) async {
    final fileId = await _ensureFileId(api, appFolderId);
    Map<String, dynamic> log;
    if (fileId != null) {
      try {
        final media = await api.files.get(
          fileId,
          downloadOptions: drive.DownloadOptions.fullMedia,
        ) as drive.Media;
        final chunks = <int>[];
        await for (final c in media.stream) {
          chunks.addAll(c);
        }
        log = jsonDecode(utf8.decode(chunks)) as Map<String, dynamic>;
      } catch (_) {
        log = {'nextSeq': 1, 'entries': <dynamic>[]};
      }
    } else {
      log = {'nextSeq': 1, 'entries': <dynamic>[]};
    }
    int seq = log['nextSeq'] as int;
    final entries = log['entries'] as List<dynamic>;
    for (final e in batch) {
      entries.add(SyncLogEntry(
        seq: seq++, op: e.op, type: e.type, entityId: e.entityId,
        filename: e.filename, deviceId: e.deviceId, modifiedTime: e.modifiedTime,
      ).toJson());
    }
    log['nextSeq'] = seq;
    if (entries.length > _kMaxEntries) {
      entries.removeRange(0, entries.length - _kMaxEntries);
    }
    await _writeLog(api, appFolderId, fileId, log);
    return seq - 1; // highest seq assigned
  }

  Future<void> _writeLog(drive.DriveApi api, String appFolderId,
      String? existingId, Map<String, dynamic> log) async {
    final bytes = utf8.encode(jsonEncode(log));
    final media = drive.Media(Stream.value(bytes), bytes.length,
        contentType: _jsonMime);
    if (existingId != null) {
      await api.files.update(drive.File()..name = _kFileName, existingId,
          uploadMedia: media);
    } else {
      final created = await api.files.create(
        drive.File()..name = _kFileName..parents = [appFolderId],
        uploadMedia: media,
      );
      _cachedFileId = created.id;
    }
  }

  Future<String?> _ensureFileId(
      drive.DriveApi api, String appFolderId) async {
    if (_cachedFileId != null) return _cachedFileId;
    await fetchLogModifiedTime(api, appFolderId);
    return _cachedFileId;
  }

  // ── Persistence ────────────────────────────────────────────────────────────

  Future<void> saveLastSeq(String userId, int seq) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('$_kLastSeqPrefix$userId', seq);
  }

  Future<int> loadLastSeq(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt('$_kLastSeqPrefix$userId') ?? 0;
  }

  Future<void> saveLogModTime(String userId, String modTime) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('$_kLogModTimePrefix$userId', modTime);
  }

  Future<String?> loadLogModTime(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('$_kLogModTimePrefix$userId');
  }

  /// Returns true when [lastSeq] is older than the oldest entry in the log,
  /// meaning some entries were compacted and a full sync is required.
  Future<bool> hasLogGap(
      drive.DriveApi api, String appFolderId, int lastSeq) async {
    try {
      final fileId = await _ensureFileId(api, appFolderId);
      if (fileId == null) return false;
      final media = await api.files.get(
        fileId,
        downloadOptions: drive.DownloadOptions.fullMedia,
      ) as drive.Media;
      final chunks = <int>[];
      await for (final c in media.stream) {
        chunks.addAll(c);
      }
      final json = jsonDecode(utf8.decode(chunks)) as Map<String, dynamic>;
      final entries = json['entries'] as List<dynamic>? ?? [];
      if (entries.isEmpty) return false;
      final oldestSeq =
          (entries.first as Map<String, dynamic>)['seq'] as int;
      return lastSeq < oldestSeq - 1;
    } catch (_) {
      return false;
    }
  }
}
