import 'package:flutter_test/flutter_test.dart';
import 'package:notes_app/services/persistence_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  final persistence = PersistenceService.instance;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('PersistenceService – folder', () {
    test('loadLastFolder returns -1 (All Notes) when nothing saved', () async {
      expect(await persistence.loadLastFolder(), -1);
    });

    test('saveLastFolder then loadLastFolder round-trips a value', () async {
      await persistence.saveLastFolder(42);
      expect(await persistence.loadLastFolder(), 42);
    });

    test('saveLastFolder with null round-trips to null (Inbox)', () async {
      await persistence.saveLastFolder(42);
      await persistence.saveLastFolder(null);
      expect(await persistence.loadLastFolder(), isNull);
    });

    test('saveLastFolder with -1 (All Notes) round-trips', () async {
      await persistence.saveLastFolder(-1);
      expect(await persistence.loadLastFolder(), -1);
    });

    test('overwriting folder value replaces previous', () async {
      await persistence.saveLastFolder(1);
      await persistence.saveLastFolder(2);
      expect(await persistence.loadLastFolder(), 2);
    });
  });

  group('PersistenceService – note', () {
    test('loadLastNote returns null when nothing saved', () async {
      expect(await persistence.loadLastNote(), isNull);
    });

    test('saveLastNote then loadLastNote round-trips a value', () async {
      await persistence.saveLastNote(99);
      expect(await persistence.loadLastNote(), 99);
    });

    test('saveLastNote with null clears the stored value', () async {
      await persistence.saveLastNote(99);
      await persistence.saveLastNote(null);
      expect(await persistence.loadLastNote(), isNull);
    });

    test('overwriting note value replaces previous', () async {
      await persistence.saveLastNote(1);
      await persistence.saveLastNote(2);
      expect(await persistence.loadLastNote(), 2);
    });
  });

  group('PersistenceService – folder and note are independent', () {
    test('saving a folder does not affect the note', () async {
      await persistence.saveLastNote(5);
      await persistence.saveLastFolder(10);
      expect(await persistence.loadLastNote(), 5);
    });

    test('saving a note does not affect the folder', () async {
      await persistence.saveLastFolder(10);
      await persistence.saveLastNote(5);
      expect(await persistence.loadLastFolder(), 10);
    });
  });
}
