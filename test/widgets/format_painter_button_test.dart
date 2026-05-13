import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notes_app/providers/format_painter_provider.dart';
import 'package:notes_app/widgets/format_painter_button.dart';

QuillController _makeController({String text = 'hello world'}) {
  final doc = Document.fromJson([
    {'insert': text},
    {'insert': '\n'},
  ]);
  return QuillController(
      document: doc, selection: const TextSelection.collapsed(offset: 0));
}

Widget _wrap(QuillController ctrl, {List<Override> overrides = const []}) =>
    ProviderScope(
      overrides: overrides,
      child: MaterialApp(
        home: Scaffold(body: FormatPainterButton(controller: ctrl)),
      ),
    );

void main() {
  group('FormatPainterButton', () {
    testWidgets('button_withNoSelection_andInactive_isDisabled',
        (tester) async {
      final ctrl = _makeController();
      addTearDown(ctrl.dispose);

      await tester.pumpWidget(_wrap(ctrl));

      final btn = tester.widget<IconButton>(find.byType(IconButton));
      expect(btn.onPressed, isNull);
    });

    testWidgets('button_withSelection_andInactive_isEnabled', (tester) async {
      final ctrl = _makeController();
      addTearDown(ctrl.dispose);
      ctrl.updateSelection(
          const TextSelection(baseOffset: 0, extentOffset: 5),
          ChangeSource.local);

      await tester.pumpWidget(_wrap(ctrl));
      await tester.pump();

      final btn = tester.widget<IconButton>(find.byType(IconButton));
      expect(btn.onPressed, isNotNull);
    });

    testWidgets('button_whenPainterActive_isEnabled_withNoSelection',
        (tester) async {
      final ctrl = _makeController();
      addTearDown(ctrl.dispose);

      await tester.pumpWidget(_wrap(ctrl));

      // Activate painter via provider
      final container = tester.element(find.byType(FormatPainterButton));
      final ref = ProviderScope.containerOf(container);
      ref.read(formatPainterProvider.notifier).capture({
        Attribute.bold.key: Attribute.bold,
      });

      await tester.pump();

      final btn = tester.widget<IconButton>(find.byType(IconButton));
      expect(btn.onPressed, isNotNull);
    });

    testWidgets('button_whenActive_showsPrimaryColor', (tester) async {
      final ctrl = _makeController();
      addTearDown(ctrl.dispose);

      await tester.pumpWidget(_wrap(ctrl));

      final container = tester.element(find.byType(FormatPainterButton));
      final ref = ProviderScope.containerOf(container);
      ref.read(formatPainterProvider.notifier).capture({
        Attribute.bold.key: Attribute.bold,
      });

      await tester.pump();

      final btn = tester.widget<IconButton>(find.byType(IconButton));
      final primary = Theme.of(
              tester.element(find.byType(FormatPainterButton)))
          .colorScheme
          .primary;
      expect(btn.color, equals(primary));
    });

    testWidgets('button_whenInactive_hasNullColor', (tester) async {
      final ctrl = _makeController();
      addTearDown(ctrl.dispose);

      await tester.pumpWidget(_wrap(ctrl));

      final btn = tester.widget<IconButton>(find.byType(IconButton));
      expect(btn.color, isNull);
    });

    testWidgets(
        'button_withSelection_onPress_capturesFormattingAndActivatesPainter',
        (tester) async {
      // Build a document with bold text at positions 0–5.
      final doc = Document.fromJson([
        {
          'insert': 'hello',
          'attributes': {'bold': true},
        },
        {'insert': ' world\n'},
      ]);
      final ctrl = QuillController(
          document: doc, selection: const TextSelection.collapsed(offset: 0));
      addTearDown(ctrl.dispose);

      ctrl.updateSelection(
          const TextSelection(baseOffset: 0, extentOffset: 5),
          ChangeSource.local);

      await tester.pumpWidget(_wrap(ctrl));
      await tester.pump();

      await tester.tap(find.byType(IconButton));
      await tester.pump();

      final container = tester.element(find.byType(FormatPainterButton));
      final ref = ProviderScope.containerOf(container);
      final state = ref.read(formatPainterProvider);
      expect(state, isNotNull);
      expect(state!.containsKey(Attribute.bold.key), isTrue);
    });

    testWidgets(
        'button_withPlainTextSelection_onPress_activatesPainterWithEmptyMap',
        (tester) async {
      // Plain text has no formatting attributes — painter should still activate.
      final ctrl = _makeController(text: 'plain text');
      addTearDown(ctrl.dispose);
      ctrl.updateSelection(
          const TextSelection(baseOffset: 0, extentOffset: 5),
          ChangeSource.local);

      await tester.pumpWidget(_wrap(ctrl));
      await tester.pump();

      await tester.tap(find.byType(IconButton));
      await tester.pump();

      final container = tester.element(find.byType(FormatPainterButton));
      final ref = ProviderScope.containerOf(container);
      final state = ref.read(formatPainterProvider);
      // State must be non-null (active) even though it captured an empty map.
      expect(state, isNotNull);
      expect(state, isEmpty);
    });

    testWidgets('button_whenActive_onPress_clearsPainter', (tester) async {
      final ctrl = _makeController();
      addTearDown(ctrl.dispose);

      await tester.pumpWidget(_wrap(ctrl));

      final container = tester.element(find.byType(FormatPainterButton));
      final ref = ProviderScope.containerOf(container);
      ref.read(formatPainterProvider.notifier).capture({
        Attribute.bold.key: Attribute.bold,
      });

      await tester.pump();

      await tester.tap(find.byType(IconButton));
      await tester.pump();

      expect(ref.read(formatPainterProvider), isNull);
    });
  });
}
