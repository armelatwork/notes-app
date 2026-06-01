import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/app_provider.dart';
import '../services/ai_service.dart';
import '../utils/markdown_utils.dart';

enum _SheetState { loading, loaded, error }

class AiSuggestionSheet extends ConsumerStatefulWidget {
  final String noteContent;

  const AiSuggestionSheet({super.key, required this.noteContent});

  @override
  ConsumerState<AiSuggestionSheet> createState() => _AiSuggestionSheetState();
}

class _AiSuggestionSheetState extends ConsumerState<AiSuggestionSheet> {
  _SheetState _state = _SheetState.loading;
  Document? _document;
  QuillController? _quillController;
  String _errorMessage = '';

  @override
  void initState() {
    super.initState();
    _rewrite();
  }

  @override
  void dispose() {
    _quillController?.dispose();
    super.dispose();
  }

  Future<void> _rewrite() async {
    setState(() => _state = _SheetState.loading);
    _quillController?.dispose();
    _quillController = null;
    try {
      final service = ref.read(activeAiServiceProvider);
      final markdown = await service.rewriteNote(widget.noteContent);
      final doc = quillDocumentFromMarkdown(markdown);
      if (mounted) {
        setState(() {
          _document = doc;
          _quillController = QuillController(
            document: doc,
            selection: const TextSelection.collapsed(offset: 0),
            readOnly: true,
          );
          _state = _SheetState.loaded;
        });
      }
    } on AiException catch (e) {
      if (mounted) setState(() { _errorMessage = _messageFor(e); _state = _SheetState.error; });
    } catch (_) {
      if (mounted) setState(() { _errorMessage = 'An unexpected error occurred.'; _state = _SheetState.error; });
    }
  }

  String _messageFor(AiException e) => switch (e.kind) {
    AiErrorKind.auth =>
      'Your API key is no longer valid. Go to Settings to re-activate it.',
    AiErrorKind.rateLimit => 'Rate limit reached. Try again in a moment.',
    AiErrorKind.timeout => 'Request timed out. Check your connection.',
    AiErrorKind.network => 'No internet connection.',
    AiErrorKind.server => 'The AI service is temporarily unavailable. Try again later.',
  };

  void _apply() => Navigator.of(context).pop(_document);
  void _dismiss() => Navigator.of(context).pop();

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.45,
      minChildSize: 0.3,
      maxChildSize: 0.9,
      expand: false,
      builder: (_, scrollController) => _SheetContent(
        state: _state,
        quillController: _quillController,
        errorMessage: _errorMessage,
        scrollController: scrollController,
        onApply: _apply,
        onDismiss: _dismiss,
        onRetry: _rewrite,
      ),
    );
  }
}

class _SheetContent extends StatelessWidget {
  final _SheetState state;
  final QuillController? quillController;
  final String errorMessage;
  final ScrollController scrollController;
  final VoidCallback onApply;
  final VoidCallback onDismiss;
  final VoidCallback onRetry;

  const _SheetContent({
    required this.state,
    required this.quillController,
    required this.errorMessage,
    required this.scrollController,
    required this.onApply,
    required this.onDismiss,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: Column(
        children: [
          _Handle(),
          _Header(onDismiss: onDismiss),
          const Divider(height: 1),
          Expanded(child: _body(context)),
          if (state == _SheetState.loaded) _Actions(onApply: onApply, onDismiss: onDismiss),
          if (state == _SheetState.error) _Actions(onApply: onRetry, onDismiss: onDismiss, applyLabel: 'Retry'),
        ],
      ),
    );
  }

  Widget _body(BuildContext context) {
    return switch (state) {
      _SheetState.loading => const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('Generating suggestion…'),
            ],
          ),
        ),
      _SheetState.error => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              errorMessage,
              textAlign: TextAlign.center,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        ),
      _SheetState.loaded => Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
          child: QuillEditor.basic(
            controller: quillController!,
            scrollController: scrollController,
            config: const QuillEditorConfig(
              enableInteractiveSelection: true,
              enableSelectionToolbar: false,
            ),
          ),
        ),
    };
  }
}

class _Handle extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 10, bottom: 6),
      child: Container(
        width: 36,
        height: 4,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.outlineVariant,
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final VoidCallback onDismiss;
  const _Header({required this.onDismiss});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 8, 8),
      child: Row(
        children: [
          const Icon(Icons.auto_awesome_outlined, size: 18),
          const SizedBox(width: 8),
          const Text('AI Suggestion', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
          const Spacer(),
          IconButton(icon: const Icon(Icons.close, size: 20), onPressed: onDismiss),
        ],
      ),
    );
  }
}

class _Actions extends StatelessWidget {
  final VoidCallback onApply;
  final VoidCallback onDismiss;
  final String applyLabel;

  const _Actions({
    required this.onApply,
    required this.onDismiss,
    this.applyLabel = 'Apply',
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: Row(
          children: [
            Expanded(
              child: OutlinedButton(onPressed: onDismiss, child: const Text('Dismiss')),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton(onPressed: onApply, child: Text(applyLabel)),
            ),
          ],
        ),
      ),
    );
  }
}
