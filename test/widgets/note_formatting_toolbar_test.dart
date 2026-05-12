import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notes_app/widgets/note_editor_widgets.dart';

void main() {
  group('NoteFormattingToolbar', () {
    late QuillController controller;

    setUp(() {
      controller = QuillController(
        document: Document(),
        selection: const TextSelection.collapsed(offset: 0),
      );
    });

    tearDown(() => controller.dispose());

    Widget buildSubject({FocusNode? focusNode}) => MaterialApp(
          home: Scaffold(
            body: NoteFormattingToolbar(
              quillController: controller,
              onInsertImage: () {},
              onInsertLink: () {},
              editorFocusNode: focusNode,
            ),
          ),
        );

    testWidgets(
        'build_withoutEditorFocusNode_rendersWithoutError', (tester) async {
      await tester.pumpWidget(buildSubject());
      expect(find.byType(NoteFormattingToolbar), findsOneWidget);
    });

    testWidgets(
        'build_withEditorFocusNode_rendersWithoutError', (tester) async {
      final focusNode = FocusNode();
      addTearDown(focusNode.dispose);

      await tester.pumpWidget(buildSubject(focusNode: focusNode));

      expect(find.byType(NoteFormattingToolbar), findsOneWidget);
    });

    testWidgets(
        'build_onAndroid_rendersGroupIconBar', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;

      await tester.pumpWidget(buildSubject());

      // Android renders a row of icon buttons for each group.
      expect(find.byType(IconButton), findsWidgets);

      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets(
        'build_onAndroid_withEditorFocusNode_rendersGroupIconBar', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;

      final focusNode = FocusNode();
      addTearDown(focusNode.dispose);

      await tester.pumpWidget(buildSubject(focusNode: focusNode));

      expect(find.byType(NoteFormattingToolbar), findsOneWidget);

      debugDefaultTargetPlatformOverride = null;
    });
  });
}
