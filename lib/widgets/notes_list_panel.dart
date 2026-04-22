import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../models/note.dart';
import '../providers/app_provider.dart';

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
                      separatorBuilder: (context, index) =>
                          Divider(height: 1, color: Theme.of(context).colorScheme.outlineVariant),
                      itemBuilder: (context, i) {
                        final note = notes[i];
                        final isSelected = selectedNote?.id == note.id;
                        return _NoteTile(
                          note: note,
                          isSelected: isSelected,
                          onTap: () => ref
                              .read(selectedNoteProvider.notifier)
                              .state = note,
                          onDelete: () =>
                              ref.read(notesProvider.notifier).deleteNote(note.id),
                        );
                      },
                    ),
              loading: () =>
                  const Center(child: CircularProgressIndicator()),
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
          fillColor: Colors.grey.shade200,
          contentPadding:
              const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
        ),
      ),
    );
  }
}

class _NoteTile extends StatelessWidget {
  final Note note;
  final bool isSelected;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _NoteTile({
    required this.note,
    required this.isSelected,
    required this.onTap,
    required this.onDelete,
  });

  String _formatDate(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inDays == 0) return DateFormat.jm().format(dt);
    if (diff.inDays == 1) return 'Yesterday';
    if (diff.inDays < 7) return DateFormat.EEEE().format(dt);
    return DateFormat.yMd().format(dt);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onSecondaryTapUp: (details) => _showContextMenu(context, details),
      child: ListTile(
        dense: true,
        selected: isSelected,
        selectedTileColor:
            Theme.of(context).colorScheme.primary.withValues(alpha: 0.12),
        onTap: onTap,
        title: Text(
          note.title.isEmpty ? 'New Note' : note.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
              fontWeight:
                  isSelected ? FontWeight.w600 : FontWeight.w500,
              fontSize: 14),
        ),
        subtitle: Row(
          children: [
            Text(_formatDate(note.updatedAt),
                style: TextStyle(
                    fontSize: 11, color: Colors.grey[500])),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                note.preview,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11, color: Colors.grey[500]),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showContextMenu(
      BuildContext context, TapUpDetails details) async {
    final result = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        details.globalPosition.dx,
        details.globalPosition.dy,
        details.globalPosition.dx + 1,
        details.globalPosition.dy + 1,
      ),
      items: const [
        PopupMenuItem(value: 'delete', child: Text('Delete Note')),
      ],
    );
    if (result == 'delete') onDelete();
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
              final folderId =
                  selectedFolder == -1 ? null : selectedFolder;
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
          Text('No notes yet',
              style: TextStyle(color: Colors.grey[500])),
          const SizedBox(height: 8),
          FilledButton.icon(
            icon: const Icon(Icons.add),
            label: const Text('New Note'),
            onPressed: () async {
              final folderId =
                  selectedFolder == -1 ? null : selectedFolder;
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
