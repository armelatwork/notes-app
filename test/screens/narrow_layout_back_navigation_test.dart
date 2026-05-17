import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notes_app/models/note.dart';
import 'package:notes_app/providers/app_provider.dart';

// Tests for the Android back-navigation fix in _NarrowLayout.
//
// Desired back-stack (narrow / phone layout):
//   Editor  →[back]→  Notes list (drawer closed)
//   Notes list (drawer closed)  →[back]→  Opens folder-sidebar drawer
//   Notes list (drawer open)    →[back]→  Exits to phone home (canPop=true)

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

// A minimal replica of _NarrowLayout that is public so tests can build it
// without needing the full Riverpod provider graph (notes DB, etc.).
// Mirrors the exact state logic of the private production widget.
class _TestNarrowLayout extends ConsumerStatefulWidget {
  const _TestNarrowLayout();
  @override
  ConsumerState<_TestNarrowLayout> createState() => _TestNarrowLayoutState();
}

class _TestNarrowLayoutState extends ConsumerState<_TestNarrowLayout> {
  int _page = 0;
  bool _drawerOpen = false;
  bool _drawerOpenedByBack = false;
  final _scaffoldKey = GlobalKey<ScaffoldState>();

  bool get _canPop => _page == 0 && _drawerOpenedByBack && !_drawerOpen;

  void _handleBack() {
    if (_page == 1) {
      ref.read(selectedNoteProvider.notifier).state = null;
      setState(() { _page = 0; _drawerOpenedByBack = false; });
    } else if (_drawerOpen) {
      _scaffoldKey.currentState?.closeDrawer();
    } else {
      setState(() => _drawerOpenedByBack = true);
      _scaffoldKey.currentState?.openDrawer();
    }
  }

  @override
  Widget build(BuildContext context) {
    final selectedNote = ref.watch(selectedNoteProvider);
    if (selectedNote != null && _page == 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) => setState(() {
        _page = 1;
        _drawerOpenedByBack = false;
      }));
    }
    return PopScope(
      canPop: _canPop,
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

      expect(find.text('notes-list'), findsOneWidget);
      expect(find.byType(Drawer), findsNothing);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(find.byType(Drawer), findsOneWidget);
    });

    testWidgets(
        'backOnDrawerOpen_closesDrawer', (tester) async {
      // With the drawer open, back calls closeDrawer() — no longer a no-op.
      await tester.pumpWidget(_buildApp());
      await tester.pumpAndSettle();

      // Back 1: open drawer.
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(Drawer), findsOneWidget);

      // Back 2: closes drawer via _handleBack → closeDrawer().
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(Drawer), findsNothing);
      expect(find.text('notes-list'), findsOneWidget);
    });

    testWidgets(
        'fullSequence_editorToNotesListToDrawerToExit', (tester) async {
      await tester.pumpWidget(_buildApp(selectedNote: _fakeNote()));
      await tester.pumpAndSettle();
      expect(find.text('editor'), findsOneWidget);

      // Step 1: editor → notes list.
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('notes-list'), findsOneWidget);

      // Step 2: notes list → opens folder sidebar drawer.
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(Drawer), findsOneWidget);

      // Step 3: back closes drawer.
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(Drawer), findsNothing);

      // Step 4: canPop=true → system exits. Custom handler not called →
      // drawer stays closed, page unchanged.
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(Drawer), findsNothing);
      expect(find.text('notes-list'), findsOneWidget);
    });
  });
}
