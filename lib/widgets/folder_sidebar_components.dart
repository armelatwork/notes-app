part of 'folder_sidebar.dart';

// ── User menu footer ──────────────────────────────────────────────────────────

class _UserMenuFooter extends ConsumerWidget {
  final AppUser? appUser;
  const _UserMenuFooter({required this.appUser});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (appUser == null) return const SizedBox.shrink();

    return PopupMenuButton<String>(
      offset: const Offset(0, -8),
      position: PopupMenuPosition.over,
      onSelected: (value) {
        if (value == 'settings') {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const SettingsScreen()),
          );
        } else if (value == 'signout') {
          ref.read(appUserProvider.notifier).signOut();
        }
      },
      itemBuilder: (_) => const [
        PopupMenuItem(
          value: 'settings',
          child: Row(children: [
            Icon(Icons.settings_outlined, size: 18),
            SizedBox(width: 10),
            Text('Settings'),
          ]),
        ),
        PopupMenuItem(
          value: 'signout',
          child: Row(children: [
            Icon(Icons.logout, size: 18),
            SizedBox(width: 10),
            Text('Sign out'),
          ]),
        ),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            const Icon(Icons.account_circle_outlined, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    appUser!.displayName,
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w500),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (appUser!.email != null)
                    Text(
                      appUser!.email!,
                      style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
            Icon(Icons.unfold_more, size: 16, color: Colors.grey[500]),
          ],
        ),
      ),
    );
  }
}

// ── Sidebar item / folder tile ────────────────────────────────────────────────

class _SidebarItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;
  final void Function(Note note)? onNoteDrop;

  const _SidebarItem({
    required this.icon,
    required this.label,
    required this.isSelected,
    required this.onTap,
    this.onNoteDrop,
  });

  Widget _buildTile(BuildContext context, {bool isHovered = false}) {
    return ListTile(
      dense: true,
      tileColor: isHovered
          ? Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.4)
          : null,
      leading: Icon(icon, size: 20),
      title: Text(label, style: const TextStyle(fontSize: 14)),
      selected: isSelected,
      selectedTileColor:
          Theme.of(context).colorScheme.primary.withValues(alpha: 0.12),
      onTap: onTap,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (onNoteDrop == null) return _buildTile(context);
    return DragTarget<Note>(
      builder: (_, candidateData, _) =>
          _buildTile(context, isHovered: candidateData.isNotEmpty),
      onAcceptWithDetails: (details) => onNoteDrop!(details.data),
    );
  }
}

class _FolderTile extends StatelessWidget {
  final Folder folder;
  final bool isSelected;
  final VoidCallback onTap;
  final VoidCallback onRename;
  final VoidCallback onDelete;
  final void Function(Note note)? onNoteDrop;

  const _FolderTile({
    required this.folder,
    required this.isSelected,
    required this.onTap,
    required this.onRename,
    required this.onDelete,
    this.onNoteDrop,
  });

  Widget _buildTile(BuildContext context, {bool isHovered = false}) {
    return ListTile(
      dense: true,
      tileColor: isHovered
          ? Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.4)
          : null,
      leading: const Icon(Icons.folder_outlined, size: 20),
      title: Text(folder.name, style: const TextStyle(fontSize: 14)),
      selected: isSelected,
      selectedTileColor:
          Theme.of(context).colorScheme.primary.withValues(alpha: 0.12),
      onTap: onTap,
      trailing: PopupMenuButton<String>(
        icon: const Icon(Icons.more_vert, size: 16),
        onSelected: (v) {
          if (v == 'rename') onRename();
          if (v == 'delete') onDelete();
        },
        itemBuilder: (_) => const [
          PopupMenuItem(value: 'rename', child: Text('Rename')),
          PopupMenuItem(value: 'delete', child: Text('Delete')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (onNoteDrop == null) return _buildTile(context);
    return DragTarget<Note>(
      builder: (_, candidateData, _) =>
          _buildTile(context, isHovered: candidateData.isNotEmpty),
      onAcceptWithDetails: (details) => onNoteDrop!(details.data),
    );
  }
}
