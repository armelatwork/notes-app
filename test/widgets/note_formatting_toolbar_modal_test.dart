import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notes_app/widgets/note_editor_widgets.dart';

// Verify that the custom heading and font-size selectors inside the Android
// formatting toolbar correctly apply Quill attributes when tapped.
//
// Background: Quill's built-in heading/font-size buttons use MenuController
// with a QuillController listener that calls setState(). On real Android
// hardware, the controller notification arrives before the menu frame renders,
// the setState rebuild races with the pending MenuController.open(), and the
// menu silently never appears. The custom TextButton selectors bypass this
// entirely by applying attributes directly.

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
  group('NoteFormattingToolbar Android custom heading selector', () {
    testWidgets(
        'h1Button_tapped_appliesH1Attribute', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;

      final ctrl = _makeController();
      addTearDown(ctrl.dispose);

      // Arrange: open the Fonts sheet (narrow screen → text_format icon)
      await tester.pumpWidget(_buildApp(ctrl));
      await tester.tap(find.byIcon(Icons.text_format));
      await tester.pumpAndSettle();

      // Act
      await tester.tap(find.text('H1'));
      await tester.pump();

      // Assert
      final attr = ctrl.getSelectionStyle().attributes[Attribute.header.key];
      expect(attr?.value, equals(1));

      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets(
        'h2Button_tapped_appliesH2Attribute', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;

      final ctrl = _makeController();
      addTearDown(ctrl.dispose);

      await tester.pumpWidget(_buildApp(ctrl));
      await tester.tap(find.byIcon(Icons.text_format));
      await tester.pumpAndSettle();

      await tester.tap(find.text('H2'));
      await tester.pump();

      final attr = ctrl.getSelectionStyle().attributes[Attribute.header.key];
      expect(attr?.value, equals(2));

      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets(
        'normalButton_tapped_clearsHeadingAttribute', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;

      final ctrl = _makeController();
      addTearDown(ctrl.dispose);

      ctrl.formatSelection(Attribute.h1);

      await tester.pumpWidget(_buildApp(ctrl));
      await tester.tap(find.byIcon(Icons.text_format));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Normal'));
      await tester.pump();

      final attr = ctrl.getSelectionStyle().attributes[Attribute.header.key];
      expect(attr, isNull);

      debugDefaultTargetPlatformOverride = null;
    });
  });

  group('NoteFormattingToolbar Android custom font-size selector', () {
    testWidgets(
        'sButton_tapped_appliesSmallSizeAttribute', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;

      final ctrl = _makeController();
      addTearDown(ctrl.dispose);

      await tester.pumpWidget(_buildApp(ctrl));
      await tester.tap(find.byIcon(Icons.text_format));
      await tester.pumpAndSettle();

      await tester.tap(find.text('S'));
      await tester.pump();

      final attr = ctrl.getSelectionStyle().attributes[Attribute.size.key];
      expect(attr?.value, equals('small'));

      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets(
        'xlButton_tapped_appliesHugeSizeAttribute', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;

      final ctrl = _makeController();
      addTearDown(ctrl.dispose);

      await tester.pumpWidget(_buildApp(ctrl));
      await tester.tap(find.byIcon(Icons.text_format));
      await tester.pumpAndSettle();

      await tester.tap(find.text('XL'));
      await tester.pump();

      final attr = ctrl.getSelectionStyle().attributes[Attribute.size.key];
      expect(attr?.value, equals('huge'));

      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets(
        'mButton_tapped_clearsSizeAttribute', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;

      final ctrl = _makeController();
      addTearDown(ctrl.dispose);

      ctrl.formatSelection(const SizeAttribute('large'));

      await tester.pumpWidget(_buildApp(ctrl));
      await tester.tap(find.byIcon(Icons.text_format));
      await tester.pumpAndSettle();

      await tester.tap(find.text('M'));
      await tester.pump();

      final attr = ctrl.getSelectionStyle().attributes[Attribute.size.key];
      expect(attr, isNull);

      debugDefaultTargetPlatformOverride = null;
    });
  });
}
