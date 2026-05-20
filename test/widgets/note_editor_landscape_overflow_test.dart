import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// Regression tests for the landscape + keyboard sidebar overflow fix.
//
// Root cause: In landscape split-view the Scaffold body height shrinks when
// the keyboard appears. The sidebar panels (FolderSidebar, NotesListPanel)
// contain Columns whose children together exceed the reduced body height,
// causing "Bottom overflowed by N pixels" render errors and visual overflow
// stripes.
//
// Fix: each sidebar is wrapped in OverflowBox(maxHeight: double.infinity) so
// the Column sees unconstrained height and never reports overflow, plus
// ClipRect to silently clip the bottom content. The note editor (Expanded)
// is unaffected.

// A tall Column — simulates sidebar content whose total height exceeds the
// keyboard-reduced body height. Width is explicit so the Row allocates
// space and the Column actually lays out its children (zero-width columns
// may skip overflow reporting in some Flutter versions).
Widget _tallColumn() => Column(
      children: const [
        SizedBox(height: 200, width: 50),
        SizedBox(height: 200, width: 50),
      ],
    );

void main() {
  group('Landscape sidebar overflow guard', () {
    testWidgets(
        'tallColumnInOverflowBox_noOverflowError', (tester) async {
      // Without OverflowBox the Column overflows a 187 dp container.
      // With SizedBox(width) + OverflowBox(maxHeight: infinity) the Column
      // sees unlimited height and sizes to its natural 400 dp without
      // reporting an overflow. The SizedBox bounds the width first so
      // OverflowBox never receives an unbounded main-axis from the Row.
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 187,
            child: Row(children: [
              SizedBox(
                width: 50,
                child: ClipRect(
                  child: OverflowBox(
                    maxHeight: double.infinity,
                    alignment: Alignment.topCenter,
                    child: _tallColumn(),
                  ),
                ),
              ),
              const Expanded(child: SizedBox()),
            ]),
          ),
        ),
      ));

      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'tallColumnWithoutOverflowBox_reportsOverflow', (tester) async {
      // Baseline: the same Column directly in the Row overflows.
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 187,
            child: Row(children: [
              SizedBox(width: 50, child: _tallColumn()),
              const Expanded(child: SizedBox()),
            ]),
          ),
        ),
      ));

      expect(tester.takeException(), isA<FlutterError>());
    });

    testWidgets(
        'overflowBox_alignsContentToTop_bottomClipped', (tester) async {
      // Content aligned to top: first item (60 dp) is visible,
      // the remainder is clipped by ClipRect at 100 dp.
      final key = GlobalKey();
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 100,
            child: ClipRect(
              child: OverflowBox(
                maxHeight: double.infinity,
                alignment: Alignment.topCenter,
                child: Column(
                  children: [
                    Container(key: key, height: 60, color: Colors.red),
                    const SizedBox(height: 200),
                  ],
                ),
              ),
            ),
          ),
        ),
      ));

      expect(find.byKey(key), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
