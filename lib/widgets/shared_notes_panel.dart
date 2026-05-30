part of 'notes_list_panel.dart';

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
                onShare: () async {
                  final note = await ref
                      .read(notesProvider.notifier)
                      .openSharedNote(data);
                  if (context.mounted) {
                    showShareDialog(context, note, onNoteUpdated: () {});
                  }
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
                onShare: () => showShareDialog(context, note,
                    onNoteUpdated: () =>
                        ref.read(notesProvider.notifier).reload()),
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
