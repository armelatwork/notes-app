import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notes_app/widgets/note_editor_widgets.dart';

// Regression tests for the heading, font-size, and font-family sub-menu fix.
//
// Root cause: Quill's built-in font buttons either race with setState listeners
// or open MenuAnchor downward without accounting for keyboard height, hiding
// items behind the keyboard on Android.
//
// Fix: _HeadingMenuButton, _FontSizeMenuButton, and _FontFamilyMenuButton all
// use MenuAnchor + MenuController with an explicit upward offset when the
// keyboard is up, and are hosted in QuillSimpleToolbar via customButtons.
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

      // Button label is dynamic: 'Normal' when no heading is active.
      await tester.tap(find.byKey(const ValueKey('heading-selector')));
      await tester.pumpAndSettle();

      // heading label 'Normal' + font-size label 'Normal' + menu item 'Normal' → three widgets.
      expect(find.text('Normal'), findsNWidgets(3));
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
      await tester.tap(find.byKey(const ValueKey('heading-selector')));
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
      // Button shows 'Heading 2' because H2 is pre-applied.
      await tester.tap(find.byKey(const ValueKey('heading-selector')));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(MenuItemButton, 'Normal'));
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

      await tester.tap(find.byKey(const ValueKey('font-size-selector')));
      await tester.pumpAndSettle();

      expect(find.text('Small'), findsOneWidget);
      // heading button shows 'Normal' + font-size button shows 'Normal' + menu item 'Normal' → three
      expect(find.text('Normal'), findsNWidgets(3));
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
      await tester.tap(find.byKey(const ValueKey('font-size-selector')));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Large'));
      await tester.pump();

      final attr = ctrl.getSelectionStyle().attributes[Attribute.size.key];
      expect(attr?.value, equals('large'));

      debugDefaultTargetPlatformOverride = null;
    });
  });

  group('NoteFormattingToolbar Android font-family sub-menu', () {
    testWidgets(
        'fontFamilyButton_tapped_opensSubMenuWithAllFonts', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;

      final ctrl = _makeController();
      addTearDown(ctrl.dispose);

      await tester.pumpWidget(_buildApp(ctrl));
      await tester.tap(find.byIcon(Icons.text_format));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('font-family-selector')));
      await tester.pumpAndSettle();

      expect(find.text('Sans Serif'), findsOneWidget);
      expect(find.text('Serif'), findsOneWidget);
      expect(find.text('Nunito'), findsOneWidget);
      expect(find.text('Pacifico'), findsOneWidget);
      expect(find.text('Roboto Mono'), findsOneWidget);
      expect(find.text('Clear'), findsOneWidget);

      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets(
        'fontFamilySubMenu_nunitoSelected_appliesFontAttribute', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;

      final ctrl = _makeController();
      addTearDown(ctrl.dispose);

      await tester.pumpWidget(_buildApp(ctrl));
      await tester.tap(find.byIcon(Icons.text_format));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('font-family-selector')));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Nunito'));
      await tester.pump();

      final attr = ctrl.getSelectionStyle().attributes[Attribute.font.key];
      expect(attr?.value, equals('nunito'));

      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets(
        'fontFamilySubMenu_clearSelected_removesFontAttribute', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;

      final ctrl = _makeController();
      addTearDown(ctrl.dispose);
      ctrl.formatSelection(
          Attribute.fromKeyValue(Attribute.font.key, 'nunito'));

      await tester.pumpWidget(_buildApp(ctrl));
      await tester.tap(find.byIcon(Icons.text_format));
      await tester.pumpAndSettle();
      // Button shows 'Nunito' because the font is pre-applied.
      await tester.tap(find.byKey(const ValueKey('font-family-selector')));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(MenuItemButton, 'Clear'));
      await tester.pump();

      final attr = ctrl.getSelectionStyle().attributes[Attribute.font.key];
      expect(attr, isNull);

      debugDefaultTargetPlatformOverride = null;
    });
  });
}
