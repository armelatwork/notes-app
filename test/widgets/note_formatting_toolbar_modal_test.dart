import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notes_app/widgets/note_editor_widgets.dart';

// Regression tests for the heading and font-size sub-menu fix.
//
// Root cause: Quill's heading and font-size buttons use MenuController.open()
// inside a StatefulWidget that also registers controller.addListener(setState).
// On real Android hardware the controller notification arrives before the menu
// frame renders; the setState rebuild drops the pending open silently.
//
// Fix: _HeadingMenuButton and _FontSizeMenuButton mirror font family exactly —
// MenuAnchor + MenuController, NO controller listener — and are hosted inside
// QuillSimpleToolbar via customButtons so they share the same widget-tree
// context as the working font family button.
//
// Note: tests render NoteFormattingToolbar inside a SizedBox(height: 600) to
// ensure the persistent sheet content receives bounded height constraints.
// Without this the test-environment showBottomSheet passes unbounded height
// and QuillSimpleToolbar's internal Wrap overflows.

Widget _buildApp(QuillController ctrl, {double width = 400}) => MaterialApp(
      localizationsDelegates: const [FlutterQuillLocalizations.delegate],
      home: Scaffold(
        body: SizedBox(
          height: 600,
          width: width,
          child: NoteFormattingToolbar(
            quillController: ctrl,
            onInsertImage: () {},
            onInsertLink: () {},
          ),
        ),
      ),
    );

QuillController _makeController() {
  final doc = Document()..insert(0, 'hello world');
  return QuillController(
    document: doc,
    selection: const TextSelection(baseOffset: 0, extentOffset: 11),
  );
}

void main() {
  group('NoteFormattingToolbar Android heading sub-menu', () {
    testWidgets(
        'headingButton_tapped_opensSubMenuWithAllOptions', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;

      final ctrl = _makeController();
      addTearDown(ctrl.dispose);

      await tester.pumpWidget(_buildApp(ctrl));
      await tester.tap(find.byIcon(Icons.text_format));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Heading'));
      await tester.pumpAndSettle();

      expect(find.text('Normal'), findsOneWidget);
      expect(find.text('Heading 1'), findsOneWidget);
      expect(find.text('Heading 2'), findsOneWidget);
      expect(find.text('Heading 3'), findsOneWidget);

      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets(
        'headingSubMenu_heading1Selected_appliesH1Attribute', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;

      final ctrl = _makeController();
      addTearDown(ctrl.dispose);

      await tester.pumpWidget(_buildApp(ctrl));
      await tester.tap(find.byIcon(Icons.text_format));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Heading'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Heading 1'));
      await tester.pump();

      final attr = ctrl.getSelectionStyle().attributes[Attribute.header.key];
      expect(attr?.value, equals(1));

      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets(
        'headingSubMenu_normalSelected_clearsHeadingAttribute', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;

      final ctrl = _makeController();
      addTearDown(ctrl.dispose);
      ctrl.formatSelection(Attribute.h2);

      await tester.pumpWidget(_buildApp(ctrl));
      await tester.tap(find.byIcon(Icons.text_format));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Heading'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Normal'));
      await tester.pump();

      final attr = ctrl.getSelectionStyle().attributes[Attribute.header.key];
      expect(attr, isNull);

      debugDefaultTargetPlatformOverride = null;
    });
  });

  group('NoteFormattingToolbar Android font-size sub-menu', () {
    testWidgets(
        'fontSizeButton_tapped_opensSubMenuWithAllOptions', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;

      final ctrl = _makeController();
      addTearDown(ctrl.dispose);

      await tester.pumpWidget(_buildApp(ctrl));
      await tester.tap(find.byIcon(Icons.text_format));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Font size'));
      await tester.pumpAndSettle();

      expect(find.text('Small'), findsOneWidget);
      expect(find.text('Normal'), findsOneWidget);
      expect(find.text('Large'), findsOneWidget);
      expect(find.text('Huge'), findsOneWidget);

      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets(
        'fontSizeSubMenu_largeSelected_appliesLargeAttribute', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;

      final ctrl = _makeController();
      addTearDown(ctrl.dispose);

      await tester.pumpWidget(_buildApp(ctrl));
      await tester.tap(find.byIcon(Icons.text_format));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Font size'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Large'));
      await tester.pump();

      final attr = ctrl.getSelectionStyle().attributes[Attribute.size.key];
      expect(attr?.value, equals('large'));

      debugDefaultTargetPlatformOverride = null;
    });
  });
}
