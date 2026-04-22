import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/app_provider.dart';
import '../services/database_service.dart';
import '../services/persistence_service.dart';
import '../widgets/folder_sidebar.dart';
import '../widgets/notes_list_panel.dart';
import '../widgets/note_editor.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  bool _restored = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _restoreSession());
  }

  Future<void> _restoreSession() async {
    if (_restored) return;
    _restored = true;

    final lastFolderId =
        await PersistenceService.instance.loadLastFolder();
    final lastNoteId =
        await PersistenceService.instance.loadLastNote();

    ref.read(selectedFolderProvider.notifier).state = lastFolderId;

    if (lastNoteId != null) {
      final note = await DatabaseService.instance.getNote(lastNoteId);
      if (note != null && mounted) {
        ref.read(selectedNoteProvider.notifier).state = note;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Save folder selection whenever it changes
    ref.listen(selectedFolderProvider, (_, next) {
      PersistenceService.instance.saveLastFolder(next);
    });

    // Save note selection whenever it changes
    ref.listen(selectedNoteProvider, (_, next) {
      PersistenceService.instance.saveLastNote(next?.id);
    });

    final width = MediaQuery.of(context).size.width;

    if (width >= 800) {
      return Scaffold(
        body: Row(
          children: const [
            FolderSidebar(),
            NotesListPanel(),
            Expanded(child: NoteEditor()),
          ],
        ),
      );
    }

    return const _NarrowLayout();
  }
}

class _NarrowLayout extends ConsumerStatefulWidget {
  const _NarrowLayout();

  @override
  ConsumerState<_NarrowLayout> createState() => _NarrowLayoutState();
}

class _NarrowLayoutState extends ConsumerState<_NarrowLayout> {
  int _page = 0;

  @override
  Widget build(BuildContext context) {
    final selectedNote = ref.watch(selectedNoteProvider);

    if (selectedNote != null && _page == 0) {
      WidgetsBinding.instance.addPostFrameCallback(
          (_) => setState(() => _page = 1));
    }

    return Scaffold(
      appBar: AppBar(
        title: _page == 0 ? const Text('Notes') : const Text('Edit'),
        leading: _page == 1
            ? BackButton(onPressed: () {
                ref.read(selectedNoteProvider.notifier).state = null;
                setState(() => _page = 0);
              })
            : null,
        actions: [
          if (_page == 0)
            Builder(
              builder: (ctx) => IconButton(
                icon: const Icon(Icons.menu),
                onPressed: () => Scaffold.of(ctx).openDrawer(),
              ),
            ),
        ],
      ),
      drawer: const Drawer(child: FolderSidebar()),
      body: _page == 0 ? const NotesListPanel() : const NoteEditor(),
    );
  }
}
