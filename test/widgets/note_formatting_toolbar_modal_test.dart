import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notes_app/widgets/note_editor_widgets.dart';

// Regression tests for the heading and font-size sub-menu fix.
//
// Root cause: Quill's QuillToolbarSelectHeaderStyleDropdownButton and
// QuillToolbarFontSizeButton both extend QuillToolbarBaseButtonState, which
// registers controller.addListener(setState). On real Android hardware, a
// focus/selection change fires that listener before the MenuController.open()
// frame renders, so setState rebuilds the widget and the pending menu open is
// silently dropped. Font family (different base class, no listener) works fine.
//
// Fix: the Heading and Size buttons in the Android bottom sheet now open a
// showModalBottomSheet picker instead of a MenuAnchor dropdown. A modal route
// is pushed to the Navigator synchronously inside onPressed and cannot be
// cancelled by a concurrent setState rebuild.

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
        'headingButton_tapped_opensSubMenuWithOptions', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;

      final ctrl = _makeController();
      addTearDown(ctrl.dispose);

      // Arrange: narrow screen → Fonts group contains "Heading" button
      await tester.pumpWidget(_buildApp(ctrl));
      await tester.tap(find.byIcon(Icons.text_format));
      await tester.pumpAndSettle();

      // Act: tap the Heading button inside the sheet
      await tester.tap(find.text('Heading'));
      await tester.pumpAndSettle();

      // Assert: sub-menu picker is open with all heading options visible
      expect(find.text('Normal'), findsOneWidget);
      expect(find.text('Heading 1'), findsOneWidget);
      expect(find.text('Heading 2'), findsOneWidget);
      expect(find.text('Heading 3'), findsOneWidget);

      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets(
        'headingSubMenu_h1Selected_appliesH1Attribute', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;

      final ctrl = _makeController();
      addTearDown(ctrl.dispose);

      await tester.pumpWidget(_buildApp(ctrl));
      await tester.tap(find.byIcon(Icons.text_format));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Heading'));
      await tester.pumpAndSettle();

      // Act: select Heading 1
      await tester.tap(find.text('Heading 1'));
      await tester.pump();

      // Assert
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
        'sizeButton_tapped_opensSubMenuWithOptions', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;

      final ctrl = _makeController();
      addTearDown(ctrl.dispose);

      await tester.pumpWidget(_buildApp(ctrl));
      await tester.tap(find.byIcon(Icons.text_format));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Size'));
      await tester.pumpAndSettle();

      // Assert: sub-menu picker shows size options
      expect(find.text('Small'), findsOneWidget);
      expect(find.text('Large'), findsOneWidget);
      expect(find.text('Huge'), findsOneWidget);

      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets(
        'sizeSubMenu_largeSelected_appliesLargeAttribute', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;

      final ctrl = _makeController();
      addTearDown(ctrl.dispose);

      await tester.pumpWidget(_buildApp(ctrl));
      await tester.tap(find.byIcon(Icons.text_format));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Size'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Large'));
      await tester.pump();

      final attr = ctrl.getSelectionStyle().attributes[Attribute.size.key];
      expect(attr?.value, equals('large'));

      debugDefaultTargetPlatformOverride = null;
    });
  });
}
