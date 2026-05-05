import 'package:flutter_test/flutter_test.dart';
import 'package:notes_app/services/device_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('DeviceService', () {
    test('id_firstCall_generatesAndPersistsUuid', () async {
      final id = await DeviceService.instance.id;
      expect(id, isNotEmpty);
      // UUID v4 format: 8-4-4-4-12 hex chars
      expect(RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$')
          .hasMatch(id), isTrue);
    });

    test('id_secondCall_returnsSameId', () async {
      final first = await DeviceService.instance.id;
      final second = await DeviceService.instance.id;
      expect(first, equals(second));
    });

    test('id_isValidUuidV4Format', () async {
      final id = await DeviceService.instance.id;
      // UUID v4: version nibble = 4, variant nibble = 8, 9, a, or b
      final uuidV4 = RegExp(
          r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$');
      expect(uuidV4.hasMatch(id), isTrue);
    });
  });
}
