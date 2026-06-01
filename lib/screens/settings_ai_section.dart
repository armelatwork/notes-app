part of 'settings_screen.dart';

// ── AI helper section ─────────────────────────────────────────────────────────

class _AiHelperSection extends ConsumerWidget {
  const _AiHelperSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final active = ref.watch(aiProviderProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildProviderDropdown(active, ref),
        _AiKeyTile(key: ValueKey(active), provider: active),
      ],
    );
  }

  Widget _buildProviderDropdown(AiProvider active, WidgetRef ref) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
        child: DropdownButtonFormField<AiProvider>(
          initialValue: active,
          decoration: const InputDecoration(
            labelText: 'AI provider',
            border: OutlineInputBorder(),
            isDense: true,
            contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
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
      );
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

  Widget _buildVerifiedTile(BuildContext context) => ListTile(
        leading: Icon(Icons.auto_awesome_outlined,
            color: Theme.of(context).colorScheme.primary),
        title: const Text('AI Helper'),
        subtitle: const Text('API key active'),
        trailing: TextButton(onPressed: _remove, child: const Text('Remove')),
      );

  Widget _buildKeyInputRow() => Row(
        children: [
          Expanded(
            child: TextField(
              controller: _keyController,
              obscureText: true,
              decoration: InputDecoration(
                hintText: _hint,
                border: const OutlineInputBorder(),
                isDense: true,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
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
      );

  Widget _buildActivationForm(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildKeyInputRow(),
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

  @override
  Widget build(BuildContext context) {
    if (_isVerified) return _buildVerifiedTile(context);
    return _buildActivationForm(context);
  }
}
