import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/format_painter_provider.dart';

/// Paint-brush button that copies formatting from the current selection and
/// applies it to the next selection the user makes.
class FormatPainterButton extends ConsumerStatefulWidget {
  const FormatPainterButton({super.key, required this.controller});

  final QuillController controller;

  @override
  ConsumerState<FormatPainterButton> createState() =>
      _FormatPainterButtonState();
}

class _FormatPainterButtonState extends ConsumerState<FormatPainterButton> {
  bool _hasSelection = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onControllerChanged);
    _onControllerChanged();
  }

  @override
  void didUpdateWidget(FormatPainterButton old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller.removeListener(_onControllerChanged);
      widget.controller.addListener(_onControllerChanged);
      _onControllerChanged();
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChanged);
    super.dispose();
  }

  void _onControllerChanged() {
    if (!mounted) return;
    final sel = widget.controller.selection;
    final has = sel.isValid && !sel.isCollapsed;
    if (has != _hasSelection) setState(() => _hasSelection = has);
  }

  void _onPressed(bool isActive) {
    final notifier = ref.read(formatPainterProvider.notifier);
    if (isActive) {
      notifier.clear();
      return;
    }
    final attrs = widget.controller.getSelectionStyle().attributes;
    if (attrs.isNotEmpty) notifier.capture(attrs);
  }

  @override
  Widget build(BuildContext context) {
    final isActive = ref.watch(formatPainterProvider) != null;
    final enabled = _hasSelection || isActive;

    return IconButton(
      icon: const Icon(Icons.format_paint),
      iconSize: 18,
      visualDensity: VisualDensity.compact,
      tooltip: isActive ? 'Cancel formatting' : 'Copy formatting',
      color: isActive ? Theme.of(context).colorScheme.primary : null,
      onPressed: enabled ? () => _onPressed(isActive) : null,
    );
  }
}
