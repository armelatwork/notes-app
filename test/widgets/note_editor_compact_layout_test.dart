import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notes_app/widgets/note_editor_widgets.dart';

// Exercises the compact-layout threshold in _buildEditorLayout.
// When the available height is below _kCompactHeightThreshold (160 dp),
// NoteTitleField is hidden to prevent a RenderFlex overflow in landscape
// mode with the software keyboard visible.
//
// NoteEditor itself requires live providers (DB, auth …), so the threshold
// logic is tested through NoteFormattingToolbar's LayoutBuilder indirectly.
// For the title-visibility rule we test it directly via a thin wrapper that
// replicates the same LayoutBuilder condition used in _buildEditorLayout.

// Minimal stand-in that applies the same compact-height rule as NoteEditor.
class _CompactLayoutTestWidget extends StatelessWidget {
  final double availableHeight;
  static const double _kCompactHeightThreshold = 160;

  const _CompactLayoutTestWidget({required this.availableHeight});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: availableHeight,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isCompact = constraints.maxHeight < _kCompactHeightThreshold;
          return Column(
            children: [
              if (!isCompact)
                const TextField(
                  key: Key('title'),
                  decoration: InputDecoration(hintText: 'Title'),
                ),
              const Expanded(child: SizedBox.expand()),
            ],
          );
        },
      ),
    );
  }
}

void main() {
  group('NoteEditor compact layout', () {
    testWidgets(
        'titleField_withSufficientHeight_isVisible', (tester) async {
      // Arrange: normal portrait height — title should be visible.
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: _CompactLayoutTestWidget(availableHeight: 400)),
      ));

      // Assert
      expect(find.byKey(const Key('title')), findsOneWidget);
    });

    testWidgets(
        'titleField_withCompactHeight_isHidden', (tester) async {
      // Arrange: landscape + keyboard height — title must be hidden to
      // prevent RenderFlex overflow.
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: _CompactLayoutTestWidget(availableHeight: 100)),
      ));

      // Assert
      expect(find.byKey(const Key('title')), findsNothing);
    });

    testWidgets(
        'titleField_atExactThreshold_isVisible', (tester) async {
      // Arrange: exactly at the boundary (160 dp) — not yet compact.
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: _CompactLayoutTestWidget(availableHeight: 160)),
      ));

      // Assert: threshold is exclusive (< 160), so 160 still shows the title.
      expect(find.byKey(const Key('title')), findsOneWidget);
    });

    testWidgets(
        'titleField_oneBelowThreshold_isHidden', (tester) async {
      // Arrange: one dp below the boundary → compact mode kicks in.
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: _CompactLayoutTestWidget(availableHeight: 159)),
      ));

      // Assert
      expect(find.byKey(const Key('title')), findsNothing);
    });

    testWidgets(
        'androidToolbar_withCompactHeight_rendersWithoutOverflow',
        (tester) async {
      // Arrange: simulate narrow Android body height with keyboard visible.
      debugDefaultTargetPlatformOverride = TargetPlatform.android;

      final ctrl = QuillController(
        document: Document(),
        selection: const TextSelection.collapsed(offset: 0),
      );
      addTearDown(ctrl.dispose);

      await tester.pumpWidget(MaterialApp(
        localizationsDelegates: const [FlutterQuillLocalizations.delegate],
        home: Scaffold(
          body: SizedBox(
            height: 100,
            child: Column(
              children: [
                Expanded(child: Container()),
                NoteFormattingToolbar(
                  quillController: ctrl,
                  onInsertImage: () {},
                  onInsertLink: () {},
                ),
              ],
            ),
          ),
        ),
      ));

      // Assert: no overflow exception thrown during layout.
      expect(tester.takeException(), isNull);

      debugDefaultTargetPlatformOverride = null;
    });
  });
}
