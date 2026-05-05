import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../models/folder.dart';
import '../models/note.dart';
import '../providers/app_provider.dart';

part 'note_tile.dart';

const _kSelectedTileOpacity = 0.12;
const _kRecentDaysThreshold = 7;

class NotesListPanel extends ConsumerWidget {
  const NotesListPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notesAsync = ref.watch(notesProvider);
    final selectedNote = ref.watch(selectedNoteProvider);
    final selectedFolder = ref.watch(selectedFolderProvider);

    return Container(
      width: 260,
      decoration: BoxDecoration(
        border: Border(
          right: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
          left: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
        ),
        color: Theme.of(context).colorScheme.surfaceContainerLow,
      ),
      child: Column(
        children: [
          _PanelHeader(selectedFolder: selectedFolder),
          _SearchBar(),
          const Divider(height: 1),
          Expanded(
            child: notesAsync.when(
              data: (notes) => notes.isEmpty
                  ? _EmptyState(selectedFolder: selectedFolder)
                  : ListView.separated(
                      itemCount: notes.length,
                      separatorBuilder: (context, index) => Divider(
                          height: 1,
                          color: Theme.of(context).colorScheme.outlineVariant),
                      itemBuilder: (context, i) {
                        final note = notes[i];
                        final isSelected = selectedNote?.id == note.id;
                        final tile = _NoteTile(
                          note: note,
                          isSelected: isSelected,
                          onTap: () => ref
                              .read(selectedNoteProvider.notifier)
                              .state = note,
                          onDelete: () =>
                              ref.read(notesProvider.notifier).deleteNote(note.id),
                          onMoveToFolder: () =>
                              _showFolderPicker(context, ref, note),
                        );
                        if (defaultTargetPlatform != TargetPlatform.macOS) {
                          return tile;
                        }
                        return Draggable<Note>(
                          data: note,
                          feedback: Material(
                            elevation: 4,
                            borderRadius: BorderRadius.circular(8),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 8),
                              child: Text(
                                note.title.isEmpty ? 'New Note' : note.title,
                                style: const TextStyle(fontSize: 14),
                              ),
                            ),
                          ),
                          childWhenDragging: Opacity(opacity: 0.4, child: tile),
                          child: tile,
                        );
                      },
                    ),
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('$e')),
            ),
          ),
          _PanelFooter(selectedFolder: selectedFolder),
        ],
      ),
    );
  }
}

class _PanelHeader extends ConsumerWidget {
  final int? selectedFolder;
  const _PanelHeader({required this.selectedFolder});

  String _title(WidgetRef ref) {
    if (selectedFolder == -1) return 'All Notes';
    if (selectedFolder == null) return 'Notes';
    final folders = ref.watch(foldersProvider).valueOrNull ?? [];
    final folder = folders.where((f) => f.id == selectedFolder).firstOrNull;
    return folder?.name ?? 'Notes';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          Expanded(
            child: Text(_title(ref),
                style: const TextStyle(
                    fontWeight: FontWeight.bold, fontSize: 16)),
          ),
        ],
      ),
    );
  }
}

class _SearchBar extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
      child: TextField(
        onChanged: (v) =>
            ref.read(searchQueryProvider.notifier).state = v,
        decoration: InputDecoration(
          hintText: 'Search',
          prefixIcon: const Icon(Icons.search, size: 18),
          isDense: true,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide.none,
          ),
          filled: true,
          fillColor: Theme.of(context).colorScheme.surfaceContainerHighest,
          contentPadding:
              const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
        ),
      ),
    );
  }
}

class _PanelFooter extends ConsumerWidget {
  final int? selectedFolder;
  const _PanelFooter({required this.selectedFolder});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: Colors.grey.shade300)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton(
            icon: const Icon(Icons.add_circle_outline),
            tooltip: 'New Note',
            onPressed: () async {
              final folderId = selectedFolder == -1 ? null : selectedFolder;
              final note = await ref
                  .read(notesProvider.notifier)
                  .createNote(folderId: folderId);
              ref.read(selectedNoteProvider.notifier).state = note;
            },
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends ConsumerWidget {
  final int? selectedFolder;
  const _EmptyState({required this.selectedFolder});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.note_outlined, size: 48, color: Colors.grey[400]),
          const SizedBox(height: 12),
          Text('No notes yet', style: TextStyle(color: Colors.grey[500])),
          const SizedBox(height: 8),
          FilledButton.icon(
            icon: const Icon(Icons.add),
            label: const Text('New Note'),
            onPressed: () async {
              final folderId = selectedFolder == -1 ? null : selectedFolder;
              final note = await ref
                  .read(notesProvider.notifier)
                  .createNote(folderId: folderId);
              ref.read(selectedNoteProvider.notifier).state = note;
            },
          ),
        ],
      ),
    );
  }
}
