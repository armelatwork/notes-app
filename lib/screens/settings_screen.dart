import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/app_user.dart';
import '../providers/app_provider.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appUser = ref.watch(appUserProvider);

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
          if (appUser?.type == AuthType.google) ...[
            const Divider(),
            _SectionHeader(label: 'Google Drive Sync'),
            ListTile(
              leading: const Icon(Icons.folder_outlined),
              title: const Text('Drive location'),
              subtitle: const Text('Notes app/'),
            ),
            ListTile(
              leading: const Icon(Icons.info_outline),
              title: const Text('Sync now'),
              subtitle: const Text(
                  'Use the sync button in the sidebar to push and pull changes.'),
            ),
          ],
          const Divider(),
          ListTile(
            leading: const Icon(Icons.logout),
            title: const Text('Sign out'),
            onTap: () {
              Navigator.pop(context);
              ref.read(appUserProvider.notifier).signOut();
            },
          ),
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
