import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notes_app/providers/editor_menu_provider.dart';
import 'package:notes_app/widgets/macos_edit_menu.dart';

Widget _wrap({QuillController? ctrl, required Widget child}) =>
    ProviderScope(
      overrides: [
        if (ctrl != null) editorMenuProvider.overrideWith((ref) => ctrl),
      ],
      child: MaterialApp(home: MacOSEditMenu(child: child)),
    );

void main() {
  group('MacOSEditMenu', () {
    testWidgets(
        'build_onAndroid_returnsChildDirectly', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;

      const sentinel = Text('hello');
      await tester.pumpWidget(_wrap(child: sentinel));

      expect(find.text('hello'), findsOneWidget);

      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets(
        'build_withNoController_rendersChildWithoutError', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;

      await tester.pumpWidget(_wrap(child: const Text('content')));
      expect(find.text('content'), findsOneWidget);

      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets(
        'build_withController_rendersChildWithoutError', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;

      final ctrl = QuillController(
        document: Document(),
        selection: const TextSelection.collapsed(offset: 0),
      );
      addTearDown(ctrl.dispose);

      await tester.pumpWidget(_wrap(ctrl: ctrl, child: const Text('content')));
      expect(find.text('content'), findsOneWidget);

      debugDefaultTargetPlatformOverride = null;
    });
  });

  group('editorMenuProvider', () {
    test('initialState_isNull', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(container.read(editorMenuProvider), isNull);
    });

    test('setState_toController_holdsReference', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final ctrl = QuillController(
        document: Document(),
        selection: const TextSelection.collapsed(offset: 0),
      );
      addTearDown(ctrl.dispose);

      container.read(editorMenuProvider.notifier).state = ctrl;

      expect(container.read(editorMenuProvider), same(ctrl));
    });

    test('setState_toNull_clearsReference', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final ctrl = QuillController(
        document: Document(),
        selection: const TextSelection.collapsed(offset: 0),
      );
      addTearDown(ctrl.dispose);

      container.read(editorMenuProvider.notifier).state = ctrl;
      container.read(editorMenuProvider.notifier).state = null;

      expect(container.read(editorMenuProvider), isNull);
    });
  });
}
