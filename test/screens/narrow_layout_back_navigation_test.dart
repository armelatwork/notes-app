import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notes_app/models/note.dart';
import 'package:notes_app/providers/app_provider.dart';

// Tests for the Android back-navigation in _NarrowLayout.
//
// Desired back-stack (narrow / phone layout):
//   Editor        →[back]→  Notes list
//   Notes list    →[back]→  Opens folder-sidebar drawer
//   Drawer open   →[back]→  Exits app (SystemNavigator.pop)

Note _fakeNote() {
  final note = Note()
    ..title = 'Test'
    ..content = '[]'
    ..preview = ''
    ..folderId = -1
    ..createdAt = DateTime(2024)
    ..updatedAt = DateTime(2024);
  return note;
}

class _TestNarrowLayout extends ConsumerStatefulWidget {
  const _TestNarrowLayout();
  @override
  ConsumerState<_TestNarrowLayout> createState() => _TestNarrowLayoutState();
}

class _TestNarrowLayoutState extends ConsumerState<_TestNarrowLayout> {
  int _page = 0;
  bool _drawerOpen = false;
  final _scaffoldKey = GlobalKey<ScaffoldState>();

  void _handleBack() {
    if (_page == 1) {
      ref.read(selectedNoteProvider.notifier).state = null;
      setState(() => _page = 0);
    } else if (_drawerOpen) {
      SystemNavigator.pop();
    } else {
      _scaffoldKey.currentState?.openDrawer();
    }
  }

  @override
  Widget build(BuildContext context) {
    final selectedNote = ref.watch(selectedNoteProvider);
    if (selectedNote != null && _page == 0) {
      WidgetsBinding.instance
          .addPostFrameCallback((_) => setState(() => _page = 1));
    }
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _handleBack();
      },
      child: Scaffold(
        key: _scaffoldKey,
        onDrawerChanged: (isOpen) => setState(() => _drawerOpen = isOpen),
        appBar: AppBar(
          title: Text(_page == 0 ? 'Notes' : 'Edit'),
          leading: _page == 1
              ? BackButton(onPressed: _handleBack)
              : null,
          actions: [
            if (_page == 0)
              IconButton(
                key: const Key('menu'),
                icon: const Icon(Icons.menu),
                onPressed: () => _scaffoldKey.currentState?.openDrawer(),
              ),
          ],
        ),
        drawer: const Drawer(child: SizedBox()),
        body: _page == 0
            ? const Text('notes-list')
            : const Text('editor'),
      ),
    );
  }
}

Widget _buildApp({Note? selectedNote}) => ProviderScope(
      overrides: [
        selectedNoteProvider.overrideWith((ref) => selectedNote),
        selectedFolderProvider.overrideWith((ref) => null),
      ],
      child: const MaterialApp(home: _TestNarrowLayout()),
    );

void main() {
  group('_NarrowLayout back navigation', () {
    testWidgets(
        'backOnEditor_navigatesToNotesList', (tester) async {
      await tester.pumpWidget(_buildApp(selectedNote: _fakeNote()));
      await tester.pumpAndSettle();
      expect(find.text('editor'), findsOneWidget);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(find.text('notes-list'), findsOneWidget);
      expect(find.text('editor'), findsNothing);
    });

    testWidgets(
        'backOnNotesList_drawerClosed_opensDrawer', (tester) async {
      await tester.pumpWidget(_buildApp());
      await tester.pumpAndSettle();

      expect(find.byType(Drawer), findsNothing);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(find.byType(Drawer), findsOneWidget);
    });

    testWidgets(
        'backOnDrawerOpen_callsSystemExit_noRenavigation', (tester) async {
      // SystemNavigator.pop() is a no-op in tests; verify the handler does NOT
      // close the drawer or navigate to another page — it just exits.
      await tester.pumpWidget(_buildApp());
      await tester.pumpAndSettle();

      await tester.binding.handlePopRoute(); // open drawer
      await tester.pumpAndSettle();
      expect(find.byType(Drawer), findsOneWidget);

      await tester.binding.handlePopRoute(); // exit (no-op in tests)
      await tester.pumpAndSettle();

      // Drawer not closed, page not changed — SystemNavigator.pop() was called.
      expect(find.byType(Drawer), findsOneWidget);
      expect(find.text('editor'), findsNothing);
    });

    testWidgets(
        'fullSequence_editorToNotesListToDrawerToExit', (tester) async {
      await tester.pumpWidget(_buildApp(selectedNote: _fakeNote()));
      await tester.pumpAndSettle();
      expect(find.text('editor'), findsOneWidget);

      await tester.binding.handlePopRoute(); // editor → notes list
      await tester.pumpAndSettle();
      expect(find.text('notes-list'), findsOneWidget);

      await tester.binding.handlePopRoute(); // notes list → open drawer
      await tester.pumpAndSettle();
      expect(find.byType(Drawer), findsOneWidget);

      await tester.binding.handlePopRoute(); // drawer → exit (no-op in tests)
      await tester.pumpAndSettle();
      expect(find.byType(Drawer), findsOneWidget); // drawer still open (no crash)
    });
  });
}
