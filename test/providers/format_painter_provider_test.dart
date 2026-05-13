import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notes_app/providers/format_painter_provider.dart';

ProviderContainer _makeContainer() {
  final c = ProviderContainer();
  addTearDown(c.dispose);
  return c;
}

void main() {
  group('FormatPainterNotifier', () {
    test('build_initialState_returnsNull', () {
      final container = _makeContainer();

      expect(container.read(formatPainterProvider), isNull);
    });

    test('capture_withAttributes_storesAttributes', () {
      final container = _makeContainer();
      final attrs = <String, Attribute>{
        Attribute.bold.key: Attribute.bold,
        Attribute.italic.key: Attribute.italic,
      };

      container.read(formatPainterProvider.notifier).capture(attrs);

      expect(container.read(formatPainterProvider), equals(attrs));
    });

    test('clear_whenActive_returnsNull', () {
      final container = _makeContainer();
      container
          .read(formatPainterProvider.notifier)
          .capture({Attribute.bold.key: Attribute.bold});

      container.read(formatPainterProvider.notifier).clear();

      expect(container.read(formatPainterProvider), isNull);
    });

    test('capture_createsDefensiveCopy_originalMutationDoesNotAffectState', () {
      final container = _makeContainer();
      final attrs = <String, Attribute>{Attribute.bold.key: Attribute.bold};

      container.read(formatPainterProvider.notifier).capture(attrs);
      attrs[Attribute.italic.key] = Attribute.italic;

      expect(
        container.read(formatPainterProvider)!.containsKey(Attribute.italic.key),
        isFalse,
      );
    });

    test('capture_thenCapture_replacesStoredAttributes', () {
      final container = _makeContainer();
      container
          .read(formatPainterProvider.notifier)
          .capture({Attribute.bold.key: Attribute.bold});

      container
          .read(formatPainterProvider.notifier)
          .capture({Attribute.italic.key: Attribute.italic});

      final state = container.read(formatPainterProvider)!;
      expect(state.containsKey(Attribute.italic.key), isTrue);
      expect(state.containsKey(Attribute.bold.key), isFalse);
    });

    test('clear_whenAlreadyNull_remainsNull', () {
      final container = _makeContainer();

      container.read(formatPainterProvider.notifier).clear();

      expect(container.read(formatPainterProvider), isNull);
    });
  });
}
