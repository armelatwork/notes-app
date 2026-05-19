import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../models/folder.dart';
import '../models/note.dart';
import '../providers/app_provider.dart';
import '../providers/sharing_provider.dart';
import '../services/sharing_service.dart';

part 'note_tile.dart';

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
                        final isWideLayout =
                            MediaQuery.of(context).size.width >= 800;
                        final supportsDrag =
                            defaultTargetPlatform == TargetPlatform.macOS ||
                            (defaultTargetPlatform == TargetPlatform.android &&
                                isWideLayout);
                        final tile = _NoteTile(
                          note: note,
                          isSelected: isSelected,
                          isDragMode: supportsDrag,
                          onTap: () => ref
                              .read(selectedNoteProvider.notifier)
                              .state = note,
                          onDelete: () =>
                              ref.read(notesProvider.notifier).deleteNote(note.id),
                          onMoveToFolder: () =>
                              _showFolderPicker(context, ref, note),
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
                          onDismissed: (_) => ref
                              .read(notesProvider.notifier)
                              .deleteNote(note.id),
                          child: draggable,
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

// ── Shared notes panel ─────────────────────────────────────────────────────────

class _SharedNotesPanel extends ConsumerWidget {
  final bool isSharedWithMe;
  const _SharedNotesPanel({required this.isSharedWithMe});

  BoxDecoration _containerDecoration(BuildContext context) => BoxDecoration(
        border: Border(
          right: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
          left: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
        ),
        color: Theme.of(context).colorScheme.surfaceContainerLow,
      );

  Widget _emptyState(BuildContext context) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.people_outline, size: 48, color: Colors.grey[400]),
            const SizedBox(height: 12),
            Text(
              isSharedWithMe ? 'No notes shared with you' : 'No notes shared',
              style: TextStyle(color: Colors.grey[500]),
            ),
          ],
        ),
      );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedNote = ref.watch(selectedNoteProvider);
    final title = isSharedWithMe ? 'Shared with me' : 'Shared by me';

    Widget body;
    if (isSharedWithMe) {
      final notesAsync = ref.watch(sharedWithMeProvider);
      body = notesAsync.when(
        data: (notes) {
          if (notes.isEmpty) return _emptyState(context);
          return ListView.separated(
            itemCount: notes.length,
            separatorBuilder: (_, index) => Divider(
                height: 1,
                color: Theme.of(context).colorScheme.outlineVariant),
            itemBuilder: (_, i) {
              final data = notes[i];
              return _SharedWithMeTile(
                data: data,
                isSelected: selectedNote?.firestoreId == data.firestoreId,
                onTap: () async {
                  final note = await ref
                      .read(notesProvider.notifier)
                      .openSharedNote(data);
                  ref.read(selectedNoteProvider.notifier).state = note;
                },
              );
            },
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
      );
    } else {
      final notesAsync = ref.watch(localSharedByMeProvider);
      body = notesAsync.when(
        data: (notes) {
          if (notes.isEmpty) return _emptyState(context);
          return ListView.separated(
            itemCount: notes.length,
            separatorBuilder: (_, index) => Divider(
                height: 1,
                color: Theme.of(context).colorScheme.outlineVariant),
            itemBuilder: (_, i) {
              final note = notes[i];
              return _NoteTile(
                note: note,
                isSelected: selectedNote?.id == note.id,
                isDragMode: false,
                onTap: () =>
                    ref.read(selectedNoteProvider.notifier).state = note,
                onDelete: () async {
                  if (note.firestoreId != null) {
                    await SharingService.instance
                        .unshareNote(note.firestoreId!);
                  }
                  ref.read(notesProvider.notifier).deleteNote(note.id);
                },
                onMoveToFolder: () => _showFolderPicker(context, ref, note),
              );
            },
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
      );
    }

    return Container(
      decoration: _containerDecoration(context),
      child: Column(
        children: [
          _SharedPanelHeader(title: title),
          const Divider(height: 1),
          Expanded(child: body),
        ],
      ),
    );
  }
}

class _SharedPanelHeader extends StatelessWidget {
  final String title;
  const _SharedPanelHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Text(title,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
    );
  }
}

class _SharedWithMeTile extends StatelessWidget {
  final SharedNoteData data;
  final bool isSelected;
  final VoidCallback onTap;
  const _SharedWithMeTile(
      {required this.data, required this.isSelected, required this.onTap});

  String _formatDate(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inDays == 0) return DateFormat.jm().format(dt);
    if (diff.inDays == 1) return 'Yesterday';
    if (diff.inDays < _kRecentDaysThreshold) return DateFormat.EEEE().format(dt);
    return DateFormat.yMd().format(dt);
  }

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      selected: isSelected,
      selectedTileColor: Theme.of(context)
          .colorScheme
          .primary
          .withValues(alpha: _kSelectedTileOpacity),
      onTap: onTap,
      title: Row(
        children: [
          Expanded(
            child: Text(
              data.title.isEmpty ? 'New Note' : data.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 14),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(left: 4),
            child: Icon(Icons.people_outline, size: 16, color: Colors.grey[500]),
          ),
        ],
      ),
      subtitle: Text(
        '${_formatDate(data.updatedAt)} · ${data.ownerEmail}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(fontSize: 11, color: Colors.grey[500]),
      ),
    );
  }
}
