import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:super_clipboard/super_clipboard.dart';

// Replicates the onDecode logic from _kQuillDeltaFormat in
// rich_clipboard_service.dart. Must be kept in sync with changes there.
Future<String?> _decodeClipboardValue(
    Object value, String platformType) async {
  final raw = value is PlatformDataProvider
      ? await value.getData(platformType)
      : value;
  if (raw is Uint8List) return utf8.decode(raw);
  if (raw is String) return raw;
  return null;
}

class _MockDataProvider implements PlatformDataProvider {
  final Object? _data;
  _MockDataProvider(this._data);

  @override
  Future<Object?> getData(PlatformFormat format) async => _data;

  @override
  List<PlatformFormat> getAllFormats() => [];
}

void main() {
  const kPlatformType = 'app.mynotes.quill-delta';
  const kDeltaJson =
      '[{"insert":"Hello","attributes":{"bold":true}},{"insert":"\\n"}]';

  group('_kQuillDeltaFormat onDecode', () {
    test('decodeUint8List_utf8EncodedJson_returnsDecodedString', () async {
      // Arrange
      final bytes = Uint8List.fromList(utf8.encode(kDeltaJson));

      // Act
      final result = await _decodeClipboardValue(bytes, kPlatformType);

      // Assert
      expect(result, equals(kDeltaJson));
    });

    test('decodeString_returnsStringDirectly', () async {
      // Act
      final result = await _decodeClipboardValue(kDeltaJson, kPlatformType);

      // Assert
      expect(result, equals(kDeltaJson));
    });

    test('decodeUnknownType_returnsNull', () async {
      // Arrange — before the fix this threw: `value as String?`
      // when value is e.g. a PlatformDataProvider or any non-String/Uint8List.

      // Act
      final result = await _decodeClipboardValue(42, kPlatformType);

      // Assert
      expect(result, isNull);
    });

    test('decodePlatformDataProvider_withBytes_returnsDecodedString',
        () async {
      // Arrange — super_clipboard 0.9.x passes PlatformDataProvider instead of
      // raw bytes; the old cast `value as String?` crashed with a type error.
      final bytes = Uint8List.fromList(utf8.encode(kDeltaJson));
      final provider = _MockDataProvider(bytes);

      // Act
      final result = await _decodeClipboardValue(provider, kPlatformType);

      // Assert
      expect(result, equals(kDeltaJson));
    });

    test('decodePlatformDataProvider_withNullData_returnsNull', () async {
      // Arrange — provider returns null (data not available on platform)
      final provider = _MockDataProvider(null);

      // Act
      final result = await _decodeClipboardValue(provider, kPlatformType);

      // Assert
      expect(result, isNull);
    });
  });
}
