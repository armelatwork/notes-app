part of 'notes_list_panel.dart';

Future<void> _showFolderPicker(
    BuildContext context, WidgetRef ref, Note note) async {
  final folders = ref.read(foldersProvider).valueOrNull ?? [];
  final hasInboxOption = note.folderId != null;
  final validFolders =
      folders.where((Folder f) => f.id != note.folderId).toList();

  if (!hasInboxOption && validFolders.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No other folders available')));
    return;
  }

  await showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Move to Folder'),
      contentPadding: const EdgeInsets.symmetric(vertical: 8),
      content: SizedBox(
        width: 280,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (hasInboxOption)
              ListTile(
                leading: const Icon(Icons.inbox),
                title: const Text('Notes (Inbox)'),
                onTap: () {
                  Navigator.pop(ctx);
                  ref.read(notesProvider.notifier).moveNote(note, null);
                },
              ),
            if (hasInboxOption && validFolders.isNotEmpty)
              const Divider(height: 1),
            ...validFolders.map((folder) => ListTile(
                  leading: const Icon(Icons.folder_outlined),
                  title: Text(folder.name),
                  onTap: () {
                    Navigator.pop(ctx);
                    ref.read(notesProvider.notifier).moveNote(note, folder.id);
                  },
                )),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Cancel'),
        ),
      ],
    ),
  );
}

class _NoteTile extends StatelessWidget {
  final Note note;
  final bool isSelected;
  final VoidCallback onTap;
  final VoidCallback onDelete;
  final VoidCallback onMoveToFolder;

  const _NoteTile({
    required this.note,
    required this.isSelected,
    required this.onTap,
    required this.onDelete,
    required this.onMoveToFolder,
  });

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
    return GestureDetector(
      onSecondaryTapUp: defaultTargetPlatform == TargetPlatform.macOS
          ? (details) => _showContextMenu(context, details)
          : null,
      child: ListTile(
        dense: true,
        selected: isSelected,
        selectedTileColor: Theme.of(context)
            .colorScheme
            .primary
            .withValues(alpha: _kSelectedTileOpacity),
        onTap: onTap,
        onLongPress: () => _showLongPressActions(context),
        title: Text(
          note.title.isEmpty ? 'New Note' : note.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
              fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
              fontSize: 14),
        ),
        subtitle: Row(
          children: [
            Text(_formatDate(note.updatedAt),
                style: TextStyle(fontSize: 11, color: Colors.grey[500])),
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

  void _showLongPressActions(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.drive_file_move_outlined),
              title: const Text('Move to Folder'),
              onTap: () {
                Navigator.pop(ctx);
                onMoveToFolder();
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: Colors.red),
              title: const Text('Delete',
                  style: TextStyle(color: Colors.red)),
              onTap: () {
                Navigator.pop(ctx);
                _showDeleteConfirmation(context);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showDeleteConfirmation(BuildContext context) {
    showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Note'),
        content: Text(
            'Delete "${note.title.isEmpty ? 'this note' : note.title}"?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              onDelete();
            },
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  void _showContextMenu(BuildContext context, TapUpDetails details) async {
    final result = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        details.globalPosition.dx,
        details.globalPosition.dy,
        details.globalPosition.dx + 1,
        details.globalPosition.dy + 1,
      ),
      items: const [
        PopupMenuItem(value: 'move', child: Text('Move to Folder')),
        PopupMenuItem(value: 'delete', child: Text('Delete Note')),
      ],
    );
    if (result == 'move') onMoveToFolder();
    if (result == 'delete') onDelete();
  }
}
