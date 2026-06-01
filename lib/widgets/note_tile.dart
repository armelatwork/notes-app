part of 'notes_list_panel.dart';

// ── Shared-with-me tile ────────────────────────────────────────────────────────

class _SharedWithMeTile extends StatelessWidget {
  final SharedNoteData data;
  final bool isSelected;
  final VoidCallback onTap;
  final VoidCallback? onShare;

  const _SharedWithMeTile({
    required this.data,
    required this.isSelected,
    required this.onTap,
    this.onShare,
  });

  String _formatDate(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inDays == 0) return DateFormat.jm().format(dt);
    if (diff.inDays == 1) return 'Yesterday';
    if (diff.inDays < _kRecentDaysThreshold) return DateFormat.EEEE().format(dt);
    return DateFormat.yMd().format(dt);
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
        PopupMenuItem(value: 'share', child: Text('Share')),
      ],
    );
    if (result == 'share') onShare?.call();
  }

  void _showLongPressActions(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.share_outlined),
              title: const Text('Share'),
              onTap: () {
                Navigator.pop(ctx);
                onShare?.call();
              },
            ),
          ],
        ),
      ),
    );
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
      ),
    );
  }
}

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
  final bool isDragMode;
  final VoidCallback onTap;
  final VoidCallback onDelete;
  final VoidCallback onMoveToFolder;
  final VoidCallback onDuplicate;
  final VoidCallback? onShare;
  final VoidCallback? onPin;

  const _NoteTile({
    required this.note,
    required this.isSelected,
    required this.isDragMode,
    required this.onTap,
    required this.onDelete,
    required this.onMoveToFolder,
    required this.onDuplicate,
    this.onShare,
    this.onPin,
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
        onLongPress: isDragMode ? null : () => _showLongPressActions(context),
        title: _buildTitleRow(context),
        subtitle: _buildSubtitle(),
      ),
    );
  }

  Widget _buildTitleRow(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            note.title.isEmpty ? 'New Note' : note.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                fontSize: 14),
          ),
        ),
        if (note.isPinned)
          Padding(
            padding: const EdgeInsets.only(left: 4),
            child: Icon(Icons.push_pin,
                size: 13, color: Theme.of(context).colorScheme.primary),
          ),
        if (note.isShared)
          Padding(
            padding: const EdgeInsets.only(left: 4),
            child: Icon(
              note.isSharedByMe ? Icons.people : Icons.people_outline,
              size: 14,
              color: note.isSharedByMe
                  ? Theme.of(context).colorScheme.primary
                  : Colors.grey[400],
            ),
          ),
      ],
    );
  }

  Widget _buildSubtitle() {
    return Row(
      children: [
        Text(_formatDate(note.updatedAt),
            style: TextStyle(fontSize: 11, color: Colors.grey[500])),
        const SizedBox(width: 6),
        Expanded(
          child: Text(note.preview,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11, color: Colors.grey[500])),
        ),
      ],
    );
  }

  void _showLongPressActions(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      builder: (_) => _NoteActionsSheet(
        note: note,
        onPin: onPin,
        onShare: onShare,
        onMoveToFolder: onMoveToFolder,
        onDuplicate: onDuplicate,
        onDeleteRequested: () => _showDeleteConfirmation(context),
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
      items: [
        if (onPin != null)
          PopupMenuItem(
              value: 'pin',
              child: Text(note.isPinned ? 'Unpin Note' : 'Pin Note')),
        if (onShare != null)
          const PopupMenuItem(value: 'share', child: Text('Share')),
        const PopupMenuItem(value: 'move', child: Text('Move to Folder')),
        const PopupMenuItem(value: 'duplicate', child: Text('Duplicate')),
        const PopupMenuItem(value: 'delete', child: Text('Delete Note')),
      ],
    );
    if (result == 'pin') onPin?.call();
    if (result == 'share') onShare?.call();
    if (result == 'move') onMoveToFolder();
    if (result == 'duplicate') onDuplicate();
    if (result == 'delete') onDelete();
  }
}

// ── Note actions bottom sheet ─────────────────────────────────────────────────

class _NoteActionsSheet extends StatelessWidget {
  final Note note;
  final VoidCallback? onPin;
  final VoidCallback? onShare;
  final VoidCallback onMoveToFolder;
  final VoidCallback onDuplicate;
  final VoidCallback onDeleteRequested;

  const _NoteActionsSheet({
    required this.note,
    required this.onMoveToFolder,
    required this.onDuplicate,
    required this.onDeleteRequested,
    this.onPin,
    this.onShare,
  });

  ListTile _tile(BuildContext ctx,
      {required IconData icon,
      required String label,
      Color? color,
      required VoidCallback action}) {
    return ListTile(
      leading: Icon(icon, color: color),
      title: Text(label,
          style: color != null ? TextStyle(color: color) : null),
      onTap: () { Navigator.pop(ctx); action(); },
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (onPin != null)
            _tile(context,
                icon: note.isPinned
                    ? Icons.push_pin_outlined
                    : Icons.push_pin,
                label: note.isPinned ? 'Unpin' : 'Pin Note',
                action: onPin!),
          if (onShare != null)
            _tile(context,
                icon: Icons.share_outlined,
                label: 'Share',
                action: onShare!),
          _tile(context,
              icon: Icons.drive_file_move_outlined,
              label: 'Move to Folder',
              action: onMoveToFolder),
          _tile(context,
              icon: Icons.copy_outlined,
              label: 'Duplicate',
              action: onDuplicate),
          _tile(context,
              icon: Icons.delete_outline,
              label: 'Delete',
              color: Colors.red,
              action: onDeleteRequested),
        ],
      ),
    );
  }
}
