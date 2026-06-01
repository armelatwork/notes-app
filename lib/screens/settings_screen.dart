import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/app_user.dart';
import '../providers/app_provider.dart';
import '../services/app_logger.dart';
import '../services/persistence_service.dart';
import '../widgets/feedback_dialog.dart';

const _kWebsiteUrl = 'https://thechaos-mynotes.web.app';

String _deleteErrorReason(Object e) {
  if (e is SocketException) return 'No internet connection.';
  if (e is TimeoutException) return 'The request timed out.';
  final s = e.toString().toLowerCase();
  if (s.contains('drive') || s.contains('googleapis')) {
    return 'Google Drive is unavailable.';
  }
  if (s.contains('firestore') || s.contains('cloud_firestore')) {
    return 'Could not reach Firestore.';
  }
  return 'An unexpected error occurred.';
}

Future<void> _signOut(BuildContext context, WidgetRef ref) async {
  final notifier = ref.read(notesProvider.notifier);
  if (!notifier.hasPendingSync) {
    await ref.read(appUserProvider.notifier).signOut();
    return;
  }

  // There are unsaved notes still waiting on their debounce timer. Show a
  // dialog so the user knows what's happening, and let them bail early if
  // they prefer not to wait.
  final syncDone = Completer<void>();
  notifier.flushAndDrain().then((_) {
    if (!syncDone.isCompleted) syncDone.complete();
  });

  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) {
      syncDone.future.then((_) {
        if (ctx.mounted) Navigator.pop(ctx);
      });
      return AlertDialog(
        title: const Text('Saving your notes…'),
        content: const Row(children: [
          CircularProgressIndicator(),
          SizedBox(width: 16),
          Expanded(child: Text('Syncing with Drive before signing out.')),
        ]),
        actions: [
          TextButton(
            onPressed: () {
              if (!syncDone.isCompleted) syncDone.complete();
              Navigator.pop(ctx);
            },
            child: const Text('Sign out & discard unsynced changes'),
          ),
        ],
      );
    },
  );

  if (!context.mounted) return;
  await ref.read(appUserProvider.notifier).signOut();
}

Future<void> _confirmDeleteAccount(BuildContext context, WidgetRef ref) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Delete account'),
      content: const Text(
        'This will permanently delete all your notes, folders, and your '
        'Drive backup. This cannot be undone.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          style: FilledButton.styleFrom(backgroundColor: Colors.red),
          child: const Text('Delete everything'),
        ),
      ],
    ),
  );
  if (confirmed != true || !context.mounted) return;

  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (_) => const AlertDialog(
      content: Row(children: [
        CircularProgressIndicator(),
        SizedBox(width: 16),
        Expanded(child: Text('Deleting account…')),
      ]),
    ),
  );

  try {
    await ref.read(appUserProvider.notifier).deleteAccount();
    // Pop the loading dialog and the Settings screen in one step so
    // AuthGate's AuthScreen (already showing since state = null) is revealed.
    if (context.mounted) {
      Navigator.of(context).popUntil((route) => route.isFirst);
    }
  } catch (e) {
    AppLogger.instance.error('SettingsScreen', 'deleteAccount failed', e);
    if (!context.mounted) return;
    Navigator.pop(context); // dismiss loading dialog
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Deletion failed'),
        content: Text(
          'Could not delete all your data. Your account has not been deleted. '
          'Please try again. Reason: ${_deleteErrorReason(e)}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }
}

final _packageInfoProvider = FutureProvider<PackageInfo>(
  (_) => PackageInfo.fromPlatform(),
);

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen(appUserProvider, (prev, next) {
      if (prev != null && next == null && context.mounted) {
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
    });
    final appUser = ref.watch(appUserProvider);
    final packageInfo = ref.watch(_packageInfoProvider);

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
          ],
          const Divider(),
          _SectionHeader(label: 'Appearance'),
          const _ThemePicker(),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.logout),
            title: const Text('Sign out'),
            onTap: () => _signOut(context, ref),
          ),
          const Divider(),
          _SectionHeader(label: 'Danger Zone'),
          ListTile(
            leading: const Icon(Icons.delete_forever_outlined, color: Colors.red),
            title: const Text('Delete account',
                style: TextStyle(color: Colors.red)),
            subtitle: const Text(
                'Permanently deletes all notes, folders, and Drive backup'),
            onTap: () => _confirmDeleteAccount(context, ref),
          ),
          const Divider(),
          _SectionHeader(label: 'Support'),
          ListTile(
            leading: const Icon(Icons.feedback_outlined),
            title: const Text('Send Feedback'),
            subtitle: const Text('Report a bug or suggest an improvement'),
            onTap: () => showDialog<void>(
              context: context,
              builder: (_) => const FeedbackDialog(),
            ),
          ),
          const Divider(),
          _SectionHeader(label: 'About'),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text('Version'),
            trailing: packageInfo.whenOrNull(
              data: (info) => Text(
                info.version,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Colors.grey[600],
                    ),
              ),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.open_in_new),
            title: const Text('Website'),
            subtitle: const Text(_kWebsiteUrl),
            onTap: () => launchUrl(
              Uri.parse(_kWebsiteUrl),
              mode: LaunchMode.externalApplication,
            ),
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

class _ThemePicker extends ConsumerWidget {
  const _ThemePicker();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: SegmentedButton<ThemeMode>(
        segments: const [
          ButtonSegment(
            value: ThemeMode.system,
            icon: Icon(Icons.brightness_auto),
            label: Text('System'),
          ),
          ButtonSegment(
            value: ThemeMode.light,
            icon: Icon(Icons.light_mode),
            label: Text('Light'),
          ),
          ButtonSegment(
            value: ThemeMode.dark,
            icon: Icon(Icons.dark_mode),
            label: Text('Dark'),
          ),
        ],
        selected: {themeMode},
        onSelectionChanged: (selection) {
          final mode = selection.first;
          ref.read(themeModeProvider.notifier).state = mode;
          PersistenceService.instance.saveThemeMode(mode);
        },
      ),
    );
  }
}
