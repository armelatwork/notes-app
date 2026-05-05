import 'package:flutter_test/flutter_test.dart';
import 'package:notes_app/services/sync_log_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  // SyncLogService network methods (appendEntry, fetchEntriesSince, etc.) require
  // a real Drive API and cannot be unit-tested without mocks. We test the parts
  // that are pure: SyncLogEntry serialisation and the SharedPreferences helpers.

  group('SyncLogEntry – serialisation', () {
    test('fromJson_roundTrip_preservesAllFields', () {
      const entry = SyncLogEntry(
        seq: 42,
        op: 'upsert',
        type: 'note',
        entityId: 7,
        filename: null,
        deviceId: 'device-abc',
        modifiedTime: '2026-01-01T00:00:00.000Z',
      );
      final json = entry.toJson();
      final restored = SyncLogEntry.fromJson(json);

      expect(restored.seq, equals(entry.seq));
      expect(restored.op, equals(entry.op));
      expect(restored.type, equals(entry.type));
      expect(restored.entityId, equals(entry.entityId));
      expect(restored.filename, isNull);
      expect(restored.deviceId, equals(entry.deviceId));
      expect(restored.modifiedTime, equals(entry.modifiedTime));
    });

    test('fromJson_imageEntry_preservesFilename', () {
      const entry = SyncLogEntry(
        seq: 1,
        op: 'delete',
        type: 'image',
        filename: 'img_abc.jpg',
        deviceId: 'dev',
        modifiedTime: '2026-01-01T00:00:00.000Z',
      );
      final restored = SyncLogEntry.fromJson(entry.toJson());
      expect(restored.filename, equals('img_abc.jpg'));
      expect(restored.entityId, isNull);
    });

    test('toJson_omitsNullEntityId', () {
      const entry = SyncLogEntry(
        seq: 1, op: 'upsert', type: 'folder',
        deviceId: 'dev', modifiedTime: '2026-01-01T00:00:00.000Z',
      );
      expect(entry.toJson().containsKey('entityId'), isFalse);
    });

    test('toJson_omitsNullFilename', () {
      const entry = SyncLogEntry(
        seq: 1, op: 'upsert', type: 'note', entityId: 3,
        deviceId: 'dev', modifiedTime: '2026-01-01T00:00:00.000Z',
      );
      expect(entry.toJson().containsKey('filename'), isFalse);
    });
  });

  group('SyncLogService – SharedPreferences helpers', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('saveLastSeq_thenLoadLastSeq_roundTrips', () async {
      await SyncLogService.instance.saveLastSeq('user1', 99);
      final seq = await SyncLogService.instance.loadLastSeq('user1');
      expect(seq, equals(99));
    });

    test('loadLastSeq_withoutSave_returnsZero', () async {
      final seq = await SyncLogService.instance.loadLastSeq('unknown-user');
      expect(seq, equals(0));
    });

    test('saveLastSeq_differentUsers_areIsolated', () async {
      await SyncLogService.instance.saveLastSeq('userA', 10);
      await SyncLogService.instance.saveLastSeq('userB', 20);
      expect(await SyncLogService.instance.loadLastSeq('userA'), equals(10));
      expect(await SyncLogService.instance.loadLastSeq('userB'), equals(20));
    });

    test('saveLogModTime_thenLoadLogModTime_roundTrips', () async {
      const modTime = '2026-05-01T12:00:00.000Z';
      await SyncLogService.instance.saveLogModTime('user1', modTime);
      final loaded = await SyncLogService.instance.loadLogModTime('user1');
      expect(loaded, equals(modTime));
    });

    test('loadLogModTime_withoutSave_returnsNull', () async {
      final loaded = await SyncLogService.instance.loadLogModTime('nobody');
      expect(loaded, isNull);
    });

    test('saveLogModTime_differentUsers_areIsolated', () async {
      await SyncLogService.instance.saveLogModTime('userA', 'timeA');
      await SyncLogService.instance.saveLogModTime('userB', 'timeB');
      expect(await SyncLogService.instance.loadLogModTime('userA'), equals('timeA'));
      expect(await SyncLogService.instance.loadLogModTime('userB'), equals('timeB'));
    });
  });
}
