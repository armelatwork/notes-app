import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/app_user.dart';
import '../providers/app_provider.dart';
import '../services/database_service.dart';
import '../services/drive_sync_service.dart';
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

    final appUser = ref.read(appUserProvider);
    final isHealthy = await DatabaseService.instance.isHealthy();
    final notes = isHealthy
        ? await DatabaseService.instance.getNotes(allNotes: true)
        : <dynamic>[];

    if (appUser?.type == AuthType.google && notes.isEmpty) {
      final driveCount = await DriveSyncService.instance.countDriveNotes();
      if (driveCount > 0 && mounted) {
        await _showRestoreDialog(driveCount);
      }
    }

    final lastFolderId = await PersistenceService.instance.loadLastFolder();
    final lastNoteId = await PersistenceService.instance.loadLastNote();

    ref.read(selectedFolderProvider.notifier).state = lastFolderId;

    if (lastNoteId != null) {
      final note = await DatabaseService.instance.getNote(lastNoteId);
      if (note != null && mounted) {
        ref.read(selectedNoteProvider.notifier).state = note;
      }
    }
  }

  Future<void> _showRestoreDialog(int driveCount) async {
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Restore from backup?'),
        content: Text(
          'Your local notes are empty. We found $driveCount note${driveCount == 1 ? '' : 's'} '
          'in your Google Drive backup. Would you like to restore them?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Skip'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Restore'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
      const SnackBar(content: Text('Restoring from Google Drive…')),
    );

    try {
      await DriveSyncService.instance.restoreAll();
      ref.invalidate(notesProvider);
      ref.invalidate(foldersProvider);
      if (mounted) {
        messenger
          ..hideCurrentSnackBar()
          ..showSnackBar(
            const SnackBar(content: Text('Notes restored successfully.')),
          );
      }
    } catch (e) {
      if (mounted) {
        messenger
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              content: Text('Restore failed: $e'),
              backgroundColor: Colors.red[700],
            ),
          );
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
      ),
      drawer: Drawer(
        child: SafeArea(child: FolderSidebar()),
      ),
      body: _page == 0 ? const NotesListPanel() : const NoteEditor(),
    );
  }
}
