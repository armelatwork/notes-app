import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../models/app_user.dart';
import '../models/folder.dart';
import '../models/note.dart';
import '../providers/app_provider.dart';
import '../providers/sharing_provider.dart';
import '../services/sharing_service.dart';
import 'share_dialog.dart';

part 'note_tile.dart';
part 'shared_notes_panel.dart';

const _kSelectedTileOpacity = 0.12;
const _kRecentDaysThreshold = 7;

class NotesListPanel extends ConsumerWidget {
  const NotesListPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sharedSection = ref.watch(sharedSectionProvider);
    if (sharedSection != null) {
      return _SharedNotesPanel(isSharedWithMe: sharedSection);
    }

    final notesAsync = ref.watch(notesProvider);
    final selectedNote = ref.watch(selectedNoteProvider);
    final selectedFolder = ref.watch(selectedFolderProvider);
    final isGoogleUser =
        ref.watch(appUserProvider)?.type == AuthType.google;

    return Container(
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
              data: (notes) {
                if (notes.isEmpty) {
                  return _EmptyState(selectedFolder: selectedFolder);
                }
                final isWideLayout =
                    MediaQuery.of(context).size.width >= 800;
                final supportsDrag =
                    defaultTargetPlatform == TargetPlatform.macOS ||
                    (defaultTargetPlatform == TargetPlatform.android &&
                        isWideLayout);

                Widget buildItem(Note note) {
                  final isSelected = selectedNote?.id == note.id;
                  final tile = _NoteTile(
                    note: note,
                    isSelected: isSelected,
                    isDragMode: supportsDrag,
                    onTap: () =>
                        ref.read(selectedNoteProvider.notifier).state = note,
                    onDelete: () =>
                        ref.read(notesProvider.notifier).deleteNote(note.id),
                    onMoveToFolder: () =>
                        _showFolderPicker(context, ref, note),
                    onDuplicate: () =>
                        ref.read(notesProvider.notifier).duplicateNote(note),
                    onShare: isGoogleUser
                        ? () => showShareDialog(context, note,
                            onNoteUpdated: () =>
                                ref.read(notesProvider.notifier).reload())
                        : null,
                    onPin: () =>
                        ref.read(notesProvider.notifier).togglePin(note.id),
                  );
                  if (!supportsDrag) return tile;
                  final draggable = LongPressDraggable<Note>(
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
                  return Dismissible(
                    key: ValueKey(note.id),
                    direction: DismissDirection.endToStart,
                    background: Container(
                      alignment: Alignment.centerRight,
                      padding: const EdgeInsets.only(right: 20),
                      color: Colors.red,
                      child: const Icon(Icons.delete_outline,
                          color: Colors.white),
                    ),
                    onDismissed: (_) =>
                        ref.read(notesProvider.notifier).deleteNote(note.id),
                    child: draggable,
                  );
                }

                final isPinnedView = selectedFolder == kFolderPinnedNotes;
                final pinned = isPinnedView
                    ? <Note>[]
                    : notes.where((n) => n.isPinned).toList();
                final unpinned = isPinnedView
                    ? notes
                    : notes.where((n) => !n.isPinned).toList();
                final dividerColor =
                    Theme.of(context).colorScheme.outlineVariant;

                return CustomScrollView(
                  slivers: [
                    if (pinned.isNotEmpty) ...[
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(14, 8, 14, 4),
                          child: Text('PINNED',
                              style: Theme.of(context)
                                  .textTheme
                                  .labelSmall
                                  ?.copyWith(
                                      color: Colors.grey[600],
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: 0.8)),
                        ),
                      ),
                      SliverList(
                        delegate: SliverChildBuilderDelegate(
                          (_, i) => Column(
                            children: [
                              buildItem(pinned[i]),
                              if (i < pinned.length - 1)
                                Divider(height: 1, color: dividerColor),
                            ],
                          ),
                          childCount: pinned.length,
                        ),
                      ),
                      SliverToBoxAdapter(
                          child: Divider(height: 1, color: dividerColor)),
                    ],
                    SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (_, i) => Column(
                          children: [
                            buildItem(unpinned[i]),
                            if (i < unpinned.length - 1)
                              Divider(height: 1, color: dividerColor),
                          ],
                        ),
                        childCount: unpinned.length,
                      ),
                    ),
                  ],
                );
              },
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
    if (selectedFolder == kFolderPinnedNotes) return 'Pinned Notes';
    if (selectedFolder == kFolderAllNotes) return 'All Notes';
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
              final folderId =
                  (selectedFolder == kFolderAllNotes ||
                          selectedFolder == kFolderPinnedNotes)
                      ? null
                      : selectedFolder;
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
    final isPinnedView = selectedFolder == kFolderPinnedNotes;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isPinnedView ? Icons.push_pin_outlined : Icons.note_outlined,
            size: 48,
            color: Colors.grey[400],
          ),
          const SizedBox(height: 12),
          Text(
            isPinnedView ? 'No pinned notes' : 'No notes yet',
            style: TextStyle(color: Colors.grey[500]),
          ),
          if (!isPinnedView) ...[
            const SizedBox(height: 8),
            FilledButton.icon(
              icon: const Icon(Icons.add),
              label: const Text('New Note'),
              onPressed: () async {
                final folderId =
                    selectedFolder == kFolderAllNotes ? null : selectedFolder;
                final note = await ref
                    .read(notesProvider.notifier)
                    .createNote(folderId: folderId);
                ref.read(selectedNoteProvider.notifier).state = note;
              },
            ),
          ],
        ],
      ),
    );
  }
}


