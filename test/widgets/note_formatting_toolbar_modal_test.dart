import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notes_app/widgets/note_editor_widgets.dart';

// Verify that toolbar groups containing Quill DropdownButton widgets (heading
// style, font size, font family) open via showModalBottomSheet, not the
// persistent showBottomSheet.
//
// showModalBottomSheet pushes a new Navigator route, adding an extra
// ModalBarrier to the tree. showBottomSheet (persistent) does not.
// The initial page route always contributes one ModalBarrier, so:
//   modal sheet  → count increases by ≥ 1
//   persistent   → count stays the same

Widget _buildApp({required double width, required QuillController ctrl}) =>
    MaterialApp(
      localizationsDelegates: const [FlutterQuillLocalizations.delegate],
      home: Scaffold(
        body: SizedBox(
          width: width,
          child: NoteFormattingToolbar(
            quillController: ctrl,
            onInsertImage: () {},
            onInsertLink: () {},
          ),
        ),
      ),
    );

QuillController _makeController() => QuillController(
      document: Document(),
      selection: const TextSelection.collapsed(offset: 0),
    );

void main() {
  group('NoteFormattingToolbar Android modal sheets', () {
    testWidgets(
        'fontsGroup_tapped_onNarrowScreen_addsModalBarrier', (tester) async {
      // debugDefaultTargetPlatformOverride must be reset in the test body —
      // the framework's _verifyInvariants fires before addTearDown callbacks.
      debugDefaultTargetPlatformOverride = TargetPlatform.android;

      final ctrl = _makeController();
      addTearDown(ctrl.dispose);

      // Arrange: width < 600 → "Fonts" group combines heading + font size
      await tester.pumpWidget(_buildApp(width: 400, ctrl: ctrl));
      final countBefore = find.byType(ModalBarrier).evaluate().length;

      // Act
      await tester.tap(find.byIcon(Icons.text_format));
      await tester.pumpAndSettle();

      // Assert: modal sheet pushes a new route → ModalBarrier count increases.
      final countAfter = find.byType(ModalBarrier).evaluate().length;
      expect(countAfter, greaterThan(countBefore));

      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets(
        'textGroup_tapped_onWideScreen_addsModalBarrier', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;

      tester.view.physicalSize = const Size(1200, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final ctrl = _makeController();
      addTearDown(ctrl.dispose);

      // Arrange: width ≥ 600 → "Text" group shown separately
      await tester.pumpWidget(_buildApp(width: 700, ctrl: ctrl));
      final countBefore = find.byType(ModalBarrier).evaluate().length;

      // Act
      await tester.tap(find.byIcon(Icons.text_fields));
      await tester.pumpAndSettle();

      // Assert
      final countAfter = find.byType(ModalBarrier).evaluate().length;
      expect(countAfter, greaterThan(countBefore));

      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets(
        'historyGroup_tapped_onNarrowScreen_doesNotAddModalBarrier',
        (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;

      final ctrl = _makeController();
      addTearDown(ctrl.dispose);

      // Arrange: History group uses plain toggle buttons → persistent sheet
      await tester.pumpWidget(_buildApp(width: 400, ctrl: ctrl));
      final countBefore = find.byType(ModalBarrier).evaluate().length;

      // Act
      await tester.tap(find.byIcon(Icons.history));
      await tester.pumpAndSettle();

      // Assert: persistent sheet does not push a route → count unchanged.
      final countAfter = find.byType(ModalBarrier).evaluate().length;
      expect(countAfter, equals(countBefore));

      debugDefaultTargetPlatformOverride = null;
    });
  });
}
