import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/app_user.dart';
import '../models/folder.dart';
import '../models/note.dart';
import '../providers/app_provider.dart';
import '../screens/settings_screen.dart';

class FolderSidebar extends ConsumerWidget {
  const FolderSidebar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final foldersAsync = ref.watch(foldersProvider);
    final selectedFolder = ref.watch(selectedFolderProvider);
    final appUser = ref.watch(appUserProvider);

    return SafeArea(
      bottom: false,
      child: Container(
      width: 220,
      color: Theme.of(context).colorScheme.surfaceContainerHigh,
      child: Column(
        children: [
          _SidebarHeader(appUser: appUser),
          _SidebarItem(
            icon: Icons.notes,
            label: 'All Notes',
            isSelected: selectedFolder == -1,
            onTap: () =>
                ref.read(selectedFolderProvider.notifier).state = -1,
          ),
          _SidebarItem(
            icon: Icons.inbox,
            label: 'Notes',
            isSelected: selectedFolder == null,
            onTap: () =>
                ref.read(selectedFolderProvider.notifier).state = null,
            onNoteDrop: (note) =>
                ref.read(notesProvider.notifier).moveNote(note, null),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 4, 4),
            child: Row(
              children: [
                Text('FOLDERS',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: Colors.grey[600],
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.8)),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.add, size: 18),
                  onPressed: () => _createFolderDialog(context, ref),
                  tooltip: 'New folder',
                ),
              ],
            ),
          ),
          foldersAsync.when(
            data: (folders) => Expanded(
              child: ListView.builder(
                itemCount: folders.length,
                itemBuilder: (_, i) => _FolderTile(
                  folder: folders[i],
                  isSelected: selectedFolder == folders[i].id,
                  onTap: () => ref
                      .read(selectedFolderProvider.notifier)
                      .state = folders[i].id,
                  onRename: () =>
                      _renameFolderDialog(context, ref, folders[i]),
                  onDelete: () =>
                      _deleteFolderDialog(context, ref, folders[i]),
                  onNoteDrop: (note) => ref
                      .read(notesProvider.notifier)
                      .moveNote(note, folders[i].id),
                ),
              ),
            ),
            loading: () =>
                const Expanded(child: Center(child: CircularProgressIndicator())),
            error: (e, _) =>
                Expanded(child: Center(child: Text('$e'))),
          ),
          const Divider(height: 1),
          _UserMenuFooter(appUser: appUser),
        ],
      ),
      ),
    );
  }

  void _createFolderDialog(BuildContext context, WidgetRef ref) {
    final ctrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('New Folder'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Folder name'),
          onSubmitted: (_) => _submitCreate(ctx, ref, ctrl.text),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => _submitCreate(ctx, ref, ctrl.text),
              child: const Text('Create')),
        ],
      ),
    );
  }

  void _submitCreate(BuildContext ctx, WidgetRef ref, String name) {
    if (name.trim().isEmpty) return;
    ref.read(foldersProvider.notifier).createFolder(name.trim());
    Navigator.pop(ctx);
  }

  void _renameFolderDialog(
      BuildContext context, WidgetRef ref, Folder folder) {
    final ctrl = TextEditingController(text: folder.name);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rename Folder'),
        content: TextField(controller: ctrl, autofocus: true),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () {
                ref
                    .read(foldersProvider.notifier)
                    .renameFolder(folder, ctrl.text.trim());
                Navigator.pop(ctx);
              },
              child: const Text('Rename')),
        ],
      ),
    );
  }

  void _deleteFolderDialog(
      BuildContext context, WidgetRef ref, Folder folder) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Folder'),
        content: Text(
            'Delete "${folder.name}"? Notes inside will be moved to root.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              ref.read(foldersProvider.notifier).deleteFolder(folder.id);
              Navigator.pop(ctx);
            },
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}

// ── Header with sync button ───────────────────────────────────────────────────

class _SidebarHeader extends ConsumerWidget {
  final AppUser? appUser;
  const _SidebarHeader({required this.appUser});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final syncStatus = ref.watch(syncStatusProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 4, 4),
          child: Row(
            children: [
              const Icon(Icons.note_alt_outlined, size: 22),
              const SizedBox(width: 8),
              const Expanded(
                child: Text('Notes',
                    style: TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 18)),
              ),
              if (appUser?.type == AuthType.google)
                _SyncIconButton(
                  status: syncStatus,
                  onPressed: () {
                    ref.read(pollTriggerProvider.notifier).state++;
                  },
                ),
            ],
          ),
        ),
        const Divider(height: 1),
      ],
    );
  }
}

class _SyncIconButton extends StatelessWidget {
  final SyncStatus status;
  final VoidCallback onPressed;
  const _SyncIconButton({required this.status, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return switch (status) {
      SyncStatus.syncing => const Padding(
          padding: EdgeInsets.all(8),
          child: SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2))),
      SyncStatus.success => IconButton(
          icon: const Icon(Icons.cloud_done, color: Colors.green),
          tooltip: 'Synced',
          onPressed: onPressed),
      SyncStatus.error => IconButton(
          icon: const Icon(Icons.cloud_off, color: Colors.red),
          tooltip: 'Sync error — tap to retry',
          onPressed: onPressed),
      SyncStatus.idle => IconButton(
          icon: const Icon(Icons.sync),
          tooltip: 'Sync now',
          onPressed: onPressed),
    };
  }
}

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
          child: Row(
            children: [
              Icon(Icons.settings_outlined, size: 18),
              SizedBox(width: 10),
              Text('Settings'),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'signout',
          child: Row(
            children: [
              Icon(Icons.logout, size: 18),
              SizedBox(width: 10),
              Text('Sign out'),
            ],
          ),
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
