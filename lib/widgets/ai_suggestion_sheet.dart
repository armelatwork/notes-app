import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/app_provider.dart';
import '../services/ai_service.dart';
import '../utils/markdown_utils.dart';

enum _SheetState { loading, retrying, loaded, error }

class AiSheetResult {
  final Document document;
  final String baseContent;
  final bool applied;
  const AiSheetResult({
    required this.document,
    required this.baseContent,
    required this.applied,
  });
}

class AiSuggestionSheet extends ConsumerStatefulWidget {
  final String noteContent;
  final Document? initialDocument;
  final String? initialPlainText;
  final void Function(AiSheetResult)? onSuggestionGenerated;

  const AiSuggestionSheet({
    super.key,
    required this.noteContent,
    this.initialDocument,
    this.initialPlainText,
    this.onSuggestionGenerated,
  });

  @override
  ConsumerState<AiSuggestionSheet> createState() => _AiSuggestionSheetState();
}

class _AiSuggestionSheetState extends ConsumerState<AiSuggestionSheet> {
  _SheetState _state = _SheetState.loading;
  Document? _document;
  QuillController? _quillController;
  String _errorMessage = '';
  late String _baseContent;
  final _refineController = TextEditingController();
  final _editorFocusNode = FocusNode(canRequestFocus: false);
  final _sheetController = DraggableScrollableController();
  double _lastKeyboardHeight = 0;

  @override
  void initState() {
    super.initState();
    _baseContent = widget.initialPlainText ?? widget.noteContent;
    if (widget.initialDocument != null) {
      _document = widget.initialDocument;
      _quillController = QuillController(
        document: widget.initialDocument!,
        selection: const TextSelection.collapsed(offset: 0),
        readOnly: true,
      );
      _state = _SheetState.loaded;
    } else {
      _generate();
    }
  }

  @override
  void dispose() {
    _quillController?.dispose();
    _refineController.dispose();
    _editorFocusNode.dispose();
    _sheetController.dispose();
    super.dispose();
  }

  Future<void> _generate({String? customInstruction}) async {
    setState(() => _state = _SheetState.loading);
    _quillController?.dispose();
    _quillController = null;

    final service = ref.read(activeAiServiceProvider);
    AiException? lastError;

    for (var attempt = 0; attempt < kMaxRewriteAttempts; attempt++) {
      if (attempt > 0) {
        if (!mounted) return;
        setState(() => _state = _SheetState.retrying);
        await Future.delayed(const Duration(seconds: 2));
      }
      try {
        final markdown = await service.rewriteNote(
          _baseContent,
          customInstruction: customInstruction,
        );
        final doc = quillDocumentFromMarkdown(markdown);
        if (mounted) {
          setState(() {
            _baseContent = markdown;
            _document = doc;
            _quillController = QuillController(
              document: doc,
              selection: const TextSelection.collapsed(offset: 0),
              readOnly: true,
            );
            _state = _SheetState.loaded;
          });
          widget.onSuggestionGenerated?.call(
            AiSheetResult(document: doc, baseContent: markdown, applied: false),
          );
        }
        return;
      } on AiException catch (e) {
        lastError = e;
        if (e.kind != AiErrorKind.timeout && e.kind != AiErrorKind.network) break;
      } catch (_) {
        if (mounted) setState(() { _errorMessage = 'An unexpected error occurred.'; _state = _SheetState.error; });
        return;
      }
    }

    if (mounted) setState(() { _errorMessage = _messageFor(lastError!); _state = _SheetState.error; });
  }

  void _submitRefine() {
    final instruction = _refineController.text.trim();
    if (instruction.isEmpty) return;
    FocusScope.of(context).unfocus();
    _generate(customInstruction: instruction);
  }

  String _messageFor(AiException e) => switch (e.kind) {
    AiErrorKind.auth =>
      'Your API key is no longer valid. Go to Settings to re-activate it.',
    AiErrorKind.rateLimit => 'Rate limit reached. Try again in a moment.',
    AiErrorKind.timeout => 'Request timed out. Check your connection.',
    AiErrorKind.network => 'No internet connection.',
    AiErrorKind.server => 'The AI service is temporarily unavailable. Try again later.',
  };

  void _apply() {
    FocusScope.of(context).unfocus();
    Navigator.of(context).pop(
      AiSheetResult(document: _document!, baseContent: _baseContent, applied: true),
    );
  }

  void _dismiss() {
    FocusScope.of(context).unfocus();
    Navigator.of(context).pop(
      _document != null
          ? AiSheetResult(document: _document!, baseContent: _baseContent, applied: false)
          : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    final keyboardHeight = MediaQuery.viewInsetsOf(context).bottom;
    if (keyboardHeight != _lastKeyboardHeight) {
      _lastKeyboardHeight = keyboardHeight;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_sheetController.isAttached) return;
        _sheetController.animateTo(
          keyboardHeight > 0 ? 0.92 : 0.45,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      });
    }
    return Padding(
      padding: EdgeInsets.only(bottom: keyboardHeight),
      child: DraggableScrollableSheet(
        controller: _sheetController,
        initialChildSize: 0.45,
        minChildSize: 0.3,
        maxChildSize: 0.95,
        expand: false,
        builder: (_, scrollController) => _SheetContent(
          state: _state,
          quillController: _quillController,
          editorFocusNode: _editorFocusNode,
          errorMessage: _errorMessage,
          scrollController: scrollController,
          refineController: _refineController,
          onApply: _apply,
          onDismiss: _dismiss,
          onRetry: () => _generate(),
          onRefine: _submitRefine,
        ),
      ),
    );
  }
}

class _SheetContent extends StatelessWidget {
  final _SheetState state;
  final QuillController? quillController;
  final FocusNode editorFocusNode;
  final String errorMessage;
  final ScrollController scrollController;
  final TextEditingController refineController;
  final VoidCallback onApply;
  final VoidCallback onDismiss;
  final VoidCallback onRetry;
  final VoidCallback onRefine;

  const _SheetContent({
    required this.state,
    required this.quillController,
    required this.editorFocusNode,
    required this.errorMessage,
    required this.scrollController,
    required this.refineController,
    required this.onApply,
    required this.onDismiss,
    required this.onRetry,
    required this.onRefine,
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
          if (state == _SheetState.loaded) _RefineField(
            controller: refineController,
            onSubmit: onRefine,
          ),
          if (state == _SheetState.loaded) _Actions(onApply: onApply, onDismiss: onDismiss),
          if (state == _SheetState.error)  _Actions(onApply: onRetry, onDismiss: onDismiss, applyLabel: 'Retry'),
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
      _SheetState.retrying => const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('Retrying…'),
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
            focusNode: editorFocusNode,
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

class _RefineField extends StatelessWidget {
  final TextEditingController controller;
  final VoidCallback onSubmit;

  const _RefineField({required this.controller, required this.onSubmit});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 8, 0),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => onSubmit(),
              decoration: InputDecoration(
                hintText: 'Refine: make it shorter, more formal…',
                hintStyle: TextStyle(
                  fontSize: 13,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                border: const OutlineInputBorder(),
                isDense: true,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              ),
              style: const TextStyle(fontSize: 13),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Regenerate',
            onPressed: onSubmit,
            style: IconButton.styleFrom(
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              padding: const EdgeInsets.all(8),
            ),
          ),
        ],
      ),
    );
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
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
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
    );
  }
}
