import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notes_app/widgets/note_editor_widgets.dart';

// Regression test for the heading and font-size sub-menu fix.
//
// Root cause: commit 556687e removed hidesKeyboard: true from the Fonts and
// Text toolbar groups. That flag made those groups open via showModalBottomSheet,
// which traps focus inside the modal — so tapping the heading/font-size button
// does not trigger an editor focus change, the QuillController never fires its
// notification, and MenuController.open() succeeds. Switching to a persistent
// sheet (showBottomSheet) broke focus trapping: the controller notification
// fires before the menu frame renders, the setState rebuild drops the pending
// open, and the menu silently never appears.
//
// Fix: restore hidesKeyboard: true on both the narrow Fonts group and the wide
// Text group so they continue to use showModalBottomSheet.

Widget _buildApp(QuillController ctrl, {double width = 400}) => MaterialApp(
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
  group('NoteFormattingToolbar Android Fonts/Text groups use modal sheet', () {
    testWidgets(
        'fontsGroup_tapped_onNarrowScreen_opensModalSheet', (tester) async {
      // Arrange: narrow screen (< 600 px) → Fonts group
      debugDefaultTargetPlatformOverride = TargetPlatform.android;

      final ctrl = _makeController();
      addTearDown(ctrl.dispose);

      await tester.pumpWidget(_buildApp(ctrl, width: 400));
      final countBefore = find.byType(ModalBarrier).evaluate().length;

      // Act
      await tester.tap(find.byIcon(Icons.text_format));
      await tester.pumpAndSettle();

      // Assert: hidesKeyboard: true → showModalBottomSheet → extra ModalBarrier.
      expect(
        find.byType(ModalBarrier).evaluate().length,
        greaterThan(countBefore),
      );

      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets(
        'textGroup_tapped_onWideScreen_opensModalSheet', (tester) async {
      // Arrange: wide screen (≥ 600 px) → Text group
      debugDefaultTargetPlatformOverride = TargetPlatform.android;

      tester.view.physicalSize = const Size(1200, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final ctrl = _makeController();
      addTearDown(ctrl.dispose);

      await tester.pumpWidget(_buildApp(ctrl, width: 700));
      final countBefore = find.byType(ModalBarrier).evaluate().length;

      // Act
      await tester.tap(find.byIcon(Icons.text_fields));
      await tester.pumpAndSettle();

      // Assert
      expect(
        find.byType(ModalBarrier).evaluate().length,
        greaterThan(countBefore),
      );

      debugDefaultTargetPlatformOverride = null;
    });
  });
}
