import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/app_user.dart';
import '../models/folder.dart';
import '../providers/app_provider.dart';
import '../services/drive_sync_service.dart';

extension _SyncSnackBar on BuildContext {
  void showSyncSnackBar(String message, {bool isError = false}) {
    ScaffoldMessenger.of(this)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 3),
        backgroundColor: isError ? Colors.red[700] : null,
      ));
  }
}

class FolderSidebar extends ConsumerWidget {
  const FolderSidebar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final foldersAsync = ref.watch(foldersProvider);
    final selectedFolder = ref.watch(selectedFolderProvider);
    final appUser = ref.watch(appUserProvider);

    return Container(
      width: 220,
      color: Theme.of(context).colorScheme.surfaceContainerHigh,
      child: Column(
        children: [
          _SidebarHeader(appUser: appUser),
          _SidebarItem(
            icon: Icons.notes,
            label: 'All Notes',
            isSelected: selectedFolder == -1,
            onTap: () => ref.read(selectedFolderProvider.notifier).state = -1,
          ),
          _SidebarItem(
            icon: Icons.inbox,
            label: 'Notes',
            isSelected: selectedFolder == null,
            onTap: () => ref.read(selectedFolderProvider.notifier).state = null,
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
                  onPressed: () => _showCreateFolder(context, ref),
                  tooltip: 'New folder',
                ),
              ],
            ),
          ),
          foldersAsync.when(
            data: (folders) => Expanded(
              child: ListView.builder(
                itemCount: folders.length,
                itemBuilder: (context, i) {
                  final folder = folders[i];
                  return _FolderTile(
                    folder: folder,
                    isSelected: selectedFolder == folder.id,
                    onTap: () => ref
                        .read(selectedFolderProvider.notifier)
                        .state = folder.id,
                    onRename: () => _showRenameFolder(context, ref, folder),
                    onDelete: () => _confirmDeleteFolder(context, ref, folder),
                  );
                },
              ),
            ),
            loading: () => const Expanded(
                child: Center(child: CircularProgressIndicator())),
            error: (e, _) => Expanded(child: Center(child: Text('$e'))),
          ),
        ],
      ),
    );
  }

  void _showCreateFolder(BuildContext context, WidgetRef ref) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('New Folder'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Folder name'),
          onSubmitted: (_) => _createFolder(ctx, ref, controller.text),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => _createFolder(ctx, ref, controller.text),
              child: const Text('Create')),
        ],
      ),
    );
  }

  void _createFolder(BuildContext context, WidgetRef ref, String name) {
    if (name.trim().isEmpty) return;
    ref.read(foldersProvider.notifier).createFolder(name.trim());
    Navigator.pop(context);
  }

  void _showRenameFolder(BuildContext context, WidgetRef ref, Folder folder) {
    final controller = TextEditingController(text: folder.name);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rename Folder'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Folder name'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () {
                ref
                    .read(foldersProvider.notifier)
                    .renameFolder(folder, controller.text.trim());
                Navigator.pop(ctx);
              },
              child: const Text('Rename')),
        ],
      ),
    );
  }

  void _confirmDeleteFolder(BuildContext context, WidgetRef ref, Folder folder) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Folder'),
        content: Text(
            'Delete "${folder.name}"? Notes inside will be moved to the root.'),
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
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
              ),
              if (appUser?.type == AuthType.google)
                _SyncButton(syncStatus: syncStatus, onPressed: () async {
                  final account = appUser!.email ?? appUser!.displayName;
                  ref.read(syncStatusProvider.notifier).state = SyncStatus.syncing;
                  context.showSyncSnackBar(
                      'Syncing to Google Drive ($account) → "Notes app"…');
                  try {
                    await DriveSyncService.instance.syncAll();
                    ref.read(syncStatusProvider.notifier).state = SyncStatus.success;
                    if (context.mounted) {
                      context.showSyncSnackBar(
                          'Synced to Google Drive ($account) → "Notes app"');
                    }
                  } catch (e) {
                    ref.read(syncStatusProvider.notifier).state = SyncStatus.error;
                    if (context.mounted) {
                      context.showSyncSnackBar(
                          'Sync failed: $e', isError: true);
                    }
                  }
                }),
              IconButton(
                icon: const Icon(Icons.logout, size: 20),
                tooltip: 'Sign out',
                onPressed: () => ref.read(appUserProvider.notifier).signOut(),
              ),
            ],
          ),
        ),
        if (appUser != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: Text(
              appUser!.email ?? appUser!.displayName,
              style: TextStyle(fontSize: 11, color: Colors.grey[600]),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        const Divider(height: 1),
      ],
    );
  }
}

class _SyncButton extends StatelessWidget {
  final SyncStatus syncStatus;
  final VoidCallback onPressed;
  const _SyncButton({required this.syncStatus, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    if (syncStatus == SyncStatus.syncing) {
      return const Padding(
        padding: EdgeInsets.all(12),
        child: SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    final (icon, color, tooltip) = switch (syncStatus) {
      SyncStatus.success => (Icons.cloud_done, Colors.green, 'Synced — tap to sync again'),
      SyncStatus.error   => (Icons.cloud_off,  Colors.red,   'Sync failed — tap to retry'),
      _                  => (Icons.cloud_sync,  (null as Color?), 'Sync to Drive'),
    };
    return IconButton(
      icon: Icon(icon, size: 20, color: color),
      tooltip: tooltip,
      onPressed: onPressed,
    );
  }
}

class _SidebarItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _SidebarItem({
    required this.icon,
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      leading: Icon(icon,
          size: 18,
          color: isSelected
              ? Theme.of(context).colorScheme.primary
              : Colors.grey[700]),
      title: Text(label,
          style: TextStyle(
              fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
              color: isSelected
                  ? Theme.of(context).colorScheme.primary
                  : null)),
      selected: isSelected,
      selectedTileColor:
          Theme.of(context).colorScheme.primary.withValues(alpha: 0.12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      onTap: onTap,
    );
  }
}

class _FolderTile extends StatelessWidget {
  final Folder folder;
  final bool isSelected;
  final VoidCallback onTap;
  final VoidCallback onRename;
  final VoidCallback onDelete;

  const _FolderTile({
    required this.folder,
    required this.isSelected,
    required this.onTap,
    required this.onRename,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      leading: Icon(Icons.folder_outlined,
          size: 18,
          color: isSelected
              ? Theme.of(context).colorScheme.primary
              : Colors.grey[700]),
      title: Text(folder.name,
          style: TextStyle(
              fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
              color: isSelected
                  ? Theme.of(context).colorScheme.primary
                  : null)),
      trailing: PopupMenuButton<String>(
        iconSize: 16,
        onSelected: (v) {
          if (v == 'rename') onRename();
          if (v == 'delete') onDelete();
        },
        itemBuilder: (_) => const [
          PopupMenuItem(value: 'rename', child: Text('Rename')),
          PopupMenuItem(value: 'delete', child: Text('Delete')),
        ],
      ),
      selected: isSelected,
      selectedTileColor:
          Theme.of(context).colorScheme.primary.withValues(alpha: 0.12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      onTap: onTap,
    );
  }
}
