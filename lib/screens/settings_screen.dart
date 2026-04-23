import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/app_user.dart';
import '../providers/app_provider.dart';
import '../providers/backup_provider.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appUser = ref.watch(appUserProvider);
    final backupAsync = ref.watch(backupProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          _SectionHeader(label: 'Account'),
          ListTile(
            leading: const Icon(Icons.person_outline),
            title: Text(appUser?.displayName ?? 'Guest'),
            subtitle: appUser?.email != null ? Text(appUser!.email!) : null,
          ),
          const Divider(),
          if (appUser?.type == AuthType.google) ...[
            _SectionHeader(label: 'Backup'),
            backupAsync.when(
              data: (state) => _BackupSection(state: state, ref: ref),
              loading: () =>
                  const ListTile(title: Center(child: CircularProgressIndicator())),
              error: (e, _) => ListTile(
                leading: const Icon(Icons.error_outline, color: Colors.red),
                title: Text('Failed to load backup settings: $e'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String label;
  const _SectionHeader({required this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
      child: Text(
        label.toUpperCase(),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: Colors.grey[600],
              fontWeight: FontWeight.bold,
              letterSpacing: 0.8,
            ),
      ),
    );
  }
}

class _BackupSection extends ConsumerWidget {
  final BackupState state;
  final WidgetRef ref;

  const _BackupSection({required this.state, required this.ref});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      children: [
        SwitchListTile(
          secondary: const Icon(Icons.backup_outlined),
          title: const Text('Automatic backup'),
          subtitle: const Text('Back up notes to Google Drive after changes'),
          value: state.enabled,
          onChanged: (_) => ref.read(backupProvider.notifier).toggle(),
        ),
        ListTile(
          leading: const Icon(Icons.folder_outlined),
          title: const Text('Drive location'),
          subtitle: const Text('Notes app/'),
        ),
        ListTile(
          leading: const Icon(Icons.schedule_outlined),
          title: const Text('Last backup'),
          subtitle: Text(_formatLastBackup(state.lastBackupAt)),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: Row(
            children: [
              if (state.status == BackupStatus.syncing)
                const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else if (state.status == BackupStatus.success)
                const Icon(Icons.check_circle_outline,
                    color: Colors.green, size: 20)
              else if (state.status == BackupStatus.error)
                const Icon(Icons.error_outline, color: Colors.red, size: 20),
              if (state.status != BackupStatus.idle) const SizedBox(width: 8),
              FilledButton.tonalIcon(
                onPressed: state.status == BackupStatus.syncing
                    ? null
                    : () => ref.read(backupProvider.notifier).backupNow(),
                icon: const Icon(Icons.cloud_upload_outlined, size: 18),
                label: const Text('Back up now'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  String _formatLastBackup(DateTime? dt) {
    if (dt == null) return 'Never';
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${dt.day}/${dt.month}/${dt.year}';
  }
}
