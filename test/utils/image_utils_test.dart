import 'package:flutter_test/flutter_test.dart';
import 'package:notes_app/utils/image_utils.dart';

void main() {
  group('isNewImageRef', () {
    test('isNewImageRef_uuidFilename_returnsTrue', () {
      expect(isNewImageRef('img_abc123.jpg'), isTrue);
    });

    test('isNewImageRef_uuidFilenameWithExtension_returnsTrue', () {
      expect(isNewImageRef('img_550e8400-e29b-41d4-a716-446655440000.png'), isTrue);
    });

    test('isNewImageRef_absolutePath_returnsFalse', () {
      expect(isNewImageRef('/Users/alice/Documents/photo.jpg'), isFalse);
    });

    test('isNewImageRef_relativePath_returnsFalse', () {
      expect(isNewImageRef('images/photo.jpg'), isFalse);
    });

    test('isNewImageRef_noImgPrefix_returnsFalse', () {
      expect(isNewImageRef('photo.jpg'), isFalse);
    });

    test('isNewImageRef_windowsPath_returnsFalse', () {
      expect(isNewImageRef('C:\\Users\\alice\\photo.jpg'), isFalse);
    });

    test('isNewImageRef_emptyString_returnsFalse', () {
      expect(isNewImageRef(''), isFalse);
    });
  });

  group('generateImageFilename', () {
    test('generateImageFilename_preservesExtension', () {
      final name = generateImageFilename('/path/to/photo.png');
      expect(name.endsWith('.png'), isTrue);
    });

    test('generateImageFilename_startsWithImgPrefix', () {
      final name = generateImageFilename('/path/to/photo.jpg');
      expect(name.startsWith('img_'), isTrue);
    });

    test('generateImageFilename_lowercasesExtension', () {
      final name = generateImageFilename('/path/to/photo.JPG');
      expect(name.endsWith('.jpg'), isTrue);
    });

    test('generateImageFilename_twoCallsProduceDifferentNames', () {
      final a = generateImageFilename('photo.png');
      final b = generateImageFilename('photo.png');
      expect(a, isNot(equals(b)));
    });

    test('generateImageFilename_resultPassesIsNewImageRef', () {
      final name = generateImageFilename('/some/path/image.jpeg');
      expect(isNewImageRef(name), isTrue);
    });
  });

  group('extractImageFilenames', () {
    test('extractImageFilenames_emptyContent_returnsEmpty', () {
      expect(extractImageFilenames('{"ops":[{"insert":"\\n"}]}'), isEmpty);
    });

    test('extractImageFilenames_noImages_returnsEmpty', () {
      const content = '{"ops":[{"insert":"hello world"}]}';
      expect(extractImageFilenames(content), isEmpty);
    });

    test('extractImageFilenames_oneUuidImage_returnsIt', () {
      const filename = 'img_abc.jpg';
      final content = '{"ops":[{"insert":{"image":"$filename"}},{"insert":"\\n"}]}';
      expect(extractImageFilenames(content), equals([filename]));
    });

    test('extractImageFilenames_multipleImages_returnsAll', () {
      const content = '{"ops":['
          '{"insert":{"image":"img_a.png"}},'
          '{"insert":{"image":"img_b.jpg"}},'
          '{"insert":"\\n"}'
          ']}';
      expect(extractImageFilenames(content), containsAll(['img_a.png', 'img_b.jpg']));
    });

    test('extractImageFilenames_legacyAbsolutePathImage_excluded', () {
      const content = '{"ops":[{"insert":{"image":"/abs/path/photo.jpg"}},{"insert":"\\n"}]}';
      expect(extractImageFilenames(content), isEmpty);
    });

    test('extractImageFilenames_mixedNewAndLegacy_returnsOnlyNew', () {
      const content = '{"ops":['
          '{"insert":{"image":"img_new.png"}},'
          '{"insert":{"image":"/old/path.jpg"}}'
          ']}';
      expect(extractImageFilenames(content), equals(['img_new.png']));
    });

    test('extractImageFilenames_invalidJson_returnsEmpty', () {
      expect(extractImageFilenames('not json at all'), isEmpty);
    });

    test('extractImageFilenames_listFormat_returnsImages', () {
      const content = '[{"insert":{"image":"img_list.png"}},{"insert":"\\n"}]';
      expect(extractImageFilenames(content), equals(['img_list.png']));
    });
  });
}
