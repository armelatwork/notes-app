import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/app_user.dart';
import '../providers/app_provider.dart';
import '../services/ai_service.dart';
import '../services/app_logger.dart';
import '../services/claude_api_service.dart';
import '../services/gemini_api_service.dart';
import '../services/openai_api_service.dart';
import '../services/perplexity_api_service.dart';
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
          _SectionHeader(label: 'AI Helper (Beta)'),
          const _AiHelperSection(),
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

class _AiHelperSection extends ConsumerWidget {
  const _AiHelperSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final active = ref.watch(aiProviderProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: DropdownButtonFormField<AiProvider>(
            initialValue: active,
            decoration: const InputDecoration(
              labelText: 'AI provider',
              border: OutlineInputBorder(),
              isDense: true,
              contentPadding:
                  EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            ),
            items: const [
              DropdownMenuItem(value: AiProvider.claude, child: Text('Claude (Anthropic)')),
              DropdownMenuItem(value: AiProvider.perplexity, child: Text('Perplexity')),
              DropdownMenuItem(value: AiProvider.gemini, child: Text('Gemini (Google)')),
              DropdownMenuItem(value: AiProvider.chatgpt, child: Text('ChatGPT (OpenAI)')),
            ],
            onChanged: (p) {
              if (p != null) ref.read(aiProviderProvider.notifier).select(p);
            },
          ),
        ),
        _AiKeyTile(
          key: ValueKey(active),
          provider: active,
        ),
      ],
    );
  }
}

class _AiKeyTile extends ConsumerStatefulWidget {
  final AiProvider provider;
  const _AiKeyTile({super.key, required this.provider});

  @override
  ConsumerState<_AiKeyTile> createState() => _AiKeyTileState();
}

class _AiKeyTileState extends ConsumerState<_AiKeyTile> {
  final _keyController = TextEditingController();
  bool _isLoading = false;
  bool _isVerified = false;
  String? _error;

  AiService get _service => switch (widget.provider) {
    AiProvider.claude => ClaudeApiService.instance,
    AiProvider.perplexity => PerplexityApiService.instance,
    AiProvider.gemini => GeminiApiService.instance,
    AiProvider.chatgpt => OpenAiApiService.instance,
  };

  String get _hint => switch (widget.provider) {
    AiProvider.claude => 'Anthropic API key (sk-ant-…)',
    AiProvider.perplexity => 'Perplexity API key (pplx-…)',
    AiProvider.gemini => 'Google AI API key (AIza…)',
    AiProvider.chatgpt => 'OpenAI API key (sk-…)',
  };

  @override
  void initState() {
    super.initState();
    _service.isVerified().then((v) {
      if (mounted) setState(() => _isVerified = v);
    }).catchError((Object _) {});
  }

  @override
  void dispose() {
    _keyController.dispose();
    super.dispose();
  }

  Future<void> _activate() async {
    setState(() { _isLoading = true; _error = null; });
    final error = await _service.activateKey(_keyController.text);
    if (!mounted) return;
    if (error != null) {
      setState(() { _isLoading = false; _error = error; });
      return;
    }
    _keyController.clear();
    ref.invalidate(aiKeyVerifiedProvider);
    ref.invalidate(claudeKeyVerifiedProvider);
    setState(() { _isLoading = false; _isVerified = true; _error = null; });
  }

  Future<void> _remove() async {
    await _service.clearKey();
    if (!mounted) return;
    ref.invalidate(aiKeyVerifiedProvider);
    ref.invalidate(claudeKeyVerifiedProvider);
    setState(() { _isVerified = false; _error = null; });
    AppLogger.instance.info('SettingsScreen', '${widget.provider.name} API key removed');
  }

  @override
  Widget build(BuildContext context) {
    if (_isVerified) {
      return ListTile(
        leading: Icon(Icons.auto_awesome_outlined,
            color: Theme.of(context).colorScheme.primary),
        title: const Text('AI Helper'),
        subtitle: const Text('API key active'),
        trailing: TextButton(onPressed: _remove, child: const Text('Remove')),
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _keyController,
                  obscureText: true,
                  decoration: InputDecoration(
                    hintText: _hint,
                    border: const OutlineInputBorder(),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: _isLoading ? null : _activate,
                child: _isLoading
                    ? const SizedBox(
                        width: 16, height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const Text('Activate'),
              ),
            ],
          ),
          if (_error != null) ...[
            const SizedBox(height: 6),
            Text(_error!,
                style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.error)),
          ],
        ],
      ),
    );
  }
}
