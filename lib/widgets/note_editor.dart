import 'dart:async';
import 'dart:convert';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/note.dart';
import '../providers/app_provider.dart';
import '../providers/editor_menu_provider.dart';
import '../providers/format_painter_provider.dart';
import '../services/app_logger.dart';
import '../services/rich_clipboard_service.dart';
import 'note_table_embed.dart';
import '../utils/font_utils.dart';
import '../utils/image_utils.dart';
import '../utils/note_utils.dart';
import 'note_editor_widgets.dart';
import 'note_image_handler.dart';
import 'note_link_handler.dart';
import 'note_tab_embed.dart';

const _kSaveDebounceMs = 800;
const _kPreviewMaxLength = 120;
const _kDragOverlayOpacity = 0.12;

class NoteEditor extends ConsumerStatefulWidget {
  const NoteEditor({super.key});

  @override
  ConsumerState<NoteEditor> createState() => _NoteEditorState();
}

class _NoteEditorState extends ConsumerState<NoteEditor> {
  QuillController? _controller;
  final FocusNode _focusNode = FocusNode();
  final TextEditingController _titleController = TextEditingController();
  Note? _currentNote;
  bool _saving = false;
  bool _dragging = false;
  bool _isDirty = false;
  bool _secondaryButtonActive = false;
  bool _primaryPointerDown = false;
  Timer? _formatPainterTimer;
  int _primaryTapCount = 0;
  DateTime? _lastPrimaryTapTime;
  static const Duration _kTripleTapMaxGap = Duration(milliseconds: 400);
  String _hintTitle = 'New Note';
  List<String> _imagesAtLoad = [];

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    _formatPainterTimer?.cancel();
    _discardIfEmpty();
    ref.read(editorMenuProvider.notifier).state = null;
    _controller?.dispose();
    _focusNode.dispose();
    _titleController.dispose();
    super.dispose();
  }

  void _handleCopy() {
    final ctrl = _controller;
    if (ctrl == null) return;
    RichClipboardService.instance.copy(ctrl);
  }

  void _handleCut() {
    final ctrl = _controller;
    if (ctrl == null) return;
    RichClipboardService.instance.copy(ctrl);
    final sel = ctrl.selection;
    if (sel.isValid && !sel.isCollapsed) {
      ctrl.replaceText(sel.start, sel.end - sel.start, '', null);
    }
  }

  Future<void> _handlePaste() async {
    final ctrl = _controller;
    if (ctrl == null) return;
    // Set the flag synchronously before any await so the macOS native Paste
    // menu action (which fires almost simultaneously) is suppressed.
    RichClipboardService.instance.beginKeyboardPaste();
    try {
      final imagePasted = await pasteImageFromClipboard(ctrl);
      if (!imagePasted) {
        await RichClipboardService.instance.paste(ctrl, fromKeyboard: true);
      }
    } finally {
      RichClipboardService.instance.endKeyboardPaste();
    }
  }

  void _insertTab() {
    if (_controller == null) return;
    final sel = _controller!.selection;
    if (!sel.isCollapsed) {
      _controller!.replaceText(sel.start, sel.end - sel.start, '', null);
    }
    _controller!.document.insert(sel.start, const Embeddable(kTabEmbedType, ''));
    _controller!.updateSelection(
      TextSelection.collapsed(offset: sel.start + 1),
      ChangeSource.local,
    );
  }

  bool _isNewEmptyNote() {
    final note = _currentNote;
    if (note == null || _controller == null || _isDirty) return false;
    if (!isDefaultNoteTitle(note.title)) return false;
    return _controller!.document.toPlainText().trim().isEmpty;
  }

  // Controller listener: debounce for keyboard-driven selection changes only.
  // Suppressed while a pointer button is held (_primaryPointerDown) because
  // pointer-based selection is handled by _onPrimaryPointerUp instead, which
  // fires after the drag ends and always has the final selection.
  void _applyFormatPainterIfActive() {
    if (!mounted || _controller == null) return;
    if (ref.read(formatPainterProvider) == null) return;
    if (_primaryPointerDown) return;
    final sel = _controller!.selection;
    if (!sel.isValid || sel.isCollapsed) return;
    _formatPainterTimer?.cancel();
    _formatPainterTimer =
        Timer(const Duration(milliseconds: 300), _applyFormatPainterNow);
  }

  // Called on primary pointer-up (mouse release / touch lift).
  // Listener.onPointerUp fires before Quill's gesture recognizer, so the
  // controller selection still reflects the completed drag. We snapshot the
  // range here and apply immediately — no frame deferral needed.
  void _onPrimaryPointerUp() {
    if (ref.read(formatPainterProvider) == null) return;
    final sel = _controller?.selection;
    if (sel == null || !sel.isValid || sel.isCollapsed) return;
    _formatPainterTimer?.cancel();
    _formatPainterTimer = null;
    _applyFormatPainterToRange(sel.start, sel.end - sel.start);
  }

  // Keyboard-fallback path: timer fires after selection settles.
  void _applyFormatPainterNow() {
    _formatPainterTimer = null;
    if (!mounted || _controller == null) return;
    final sel = _controller!.selection;
    if (!sel.isValid || sel.isCollapsed) return;
    _applyFormatPainterToRange(sel.start, sel.end - sel.start);
  }

  void _applyFormatPainterToRange(int start, int len) {
    if (!mounted || _controller == null) return;
    final attrs = ref.read(formatPainterProvider);
    if (attrs == null) return;
    final ctrl = _controller!;
    if (attrs.isEmpty) {
      _clearTextStyle(ctrl, start, len);
    } else {
      for (final attr in attrs.values) {
        ctrl.formatText(start, len, attr);
      }
    }
    ref.read(formatPainterProvider.notifier).clear();
  }

  // Removes all common inline and block text formatting from [start, start+len).
  // Used when the painter was activated on plain (unstyled) text.
  void _clearTextStyle(QuillController ctrl, int start, int len) {
    for (final attr in <Attribute>[
      Attribute.bold, Attribute.italic, Attribute.underline,
      Attribute.strikeThrough, Attribute.inlineCode, Attribute.subscript,
    ]) {
      ctrl.formatText(start, len, Attribute.clone(attr, null));
    }
    // header is a block attribute; clearing with h1's key removes any level.
    ctrl.formatText(start, len, Attribute.clone(Attribute.h1, null));
  }

  void _discardIfEmpty() {
    if (!_isNewEmptyNote()) return;
    ref.read(notesProvider.notifier).deleteNote(_currentNote!.id);
    _currentNote = null;
  }

  void _loadNote(Note note) {
    if (_currentNote?.id == note.id) return;
    _formatPainterTimer?.cancel();
    _formatPainterTimer = null;
    ref.read(formatPainterProvider.notifier).clear();
    if (_isNewEmptyNote()) {
      ref.read(notesProvider.notifier).deleteNote(_currentNote!.id);
    } else {
      _saveCurrentNote();
    }
    _currentNote = note;
    _isDirty = false;
    _imagesAtLoad = extractImageFilenames(note.content);

    if (isDefaultNoteTitle(note.title)) {
      _hintTitle = note.title;
      _titleController.text = '';
    } else {
      _hintTitle = 'New Note';
      _titleController.text = note.title;
    }

    Document doc;
    try {
      final json = jsonDecode(note.content) as List;
      doc = Document.fromJson(json);
    } catch (e) {
      AppLogger.instance.warn('NoteEditor', 'failed to parse note content', e);
      doc = Document();
    }

    _controller?.dispose();
    _controller = QuillController(
      document: doc,
      selection: const TextSelection.collapsed(offset: 0),
    );
    _controller!.document.changes.listen((_) => _scheduleSave());
    _controller!.addListener(_applyFormatPainterIfActive);
    ref.read(editorMenuProvider.notifier).state = _controller;
    setState(() {});
  }

  void _scheduleSave() {
    _isDirty = true;
    if (_saving) return;
    _saving = true;
    Future.delayed(
        const Duration(milliseconds: _kSaveDebounceMs), _saveCurrentNote);
  }

  Future<void> _saveCurrentNote() async {
    _saving = false;
    if (!_isDirty) return;
    _isDirty = false;
    final note = _currentNote;
    if (note == null || _controller == null) return;

    final delta = _controller!.document.toDelta();
    final contentJson = jsonEncode(delta.toJson());
    final plainText = _controller!.document.toPlainText();
    final preview = plainText.trim().replaceAll('\n', ' ');

    final typedTitle = _titleController.text.trim();
    note.title = typedTitle.isEmpty ? _hintTitle : typedTitle;
    note.content = contentJson;
    note.preview = preview.length > _kPreviewMaxLength
        ? preview.substring(0, _kPreviewMaxLength)
        : preview;

    final currentImages = extractImageFilenames(contentJson);
    final deletedImages =
        _imagesAtLoad.where((f) => !currentImages.contains(f)).toList();
    _imagesAtLoad = currentImages;

    await ref.read(notesProvider.notifier).saveNote(note,
        deletedImageFilenames: deletedImages);
  }

  Future<void> _pickAndInsertImage() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery);
    if (picked == null || _controller == null) return;
    await embedImageFile(_controller!, picked.path);
    if (mounted) setState(() {});
  }

  void _onInsertLink() {
    if (_controller == null) return;
    showInsertLinkDialog(context, _controller!);
  }

  @override
  Widget build(BuildContext context) {
    final note = ref.watch(selectedNoteProvider);
    if (note == null) return const NoteEmptyPlaceholder();

    if (note.id != _currentNote?.id) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _loadNote(note));
    }
    if (_controller == null) {
      return const Center(child: CircularProgressIndicator());
    }

    return DropTarget(
      onDragEntered: (_) => setState(() => _dragging = true),
      onDragExited: (_) => setState(() => _dragging = false),
      onDragDone: (detail) async {
        setState(() => _dragging = false);
        for (final file in detail.files) {
          if (isImagePath(file.path)) {
            await embedImageFile(_controller!, file.path);
          }
        }
        if (mounted) setState(() {});
      },
      child: Stack(
        children: [
          _buildEditorLayout(),
          if (_dragging) _DragOverlay(),
        ],
      ),
    );
  }

  Widget _buildEditorLayout() {
    // ValueKey ensures the toolbar subtree (including QuillToolbarHistoryButton)
    // is destroyed and recreated whenever the controller changes. Without this,
    // the StatefulWidget elements are reused across note loads, so initState is
    // never called again and the history buttons stay subscribed to the old
    // (closed) controller.changes stream — leaving undo/redo permanently disabled.
    final toolbar = NoteFormattingToolbar(
      key: ValueKey(_controller),
      quillController: _controller!,
      onInsertImage: _pickAndInsertImage,
      onInsertLink: _onInsertLink,
      editorFocusNode: _focusNode,
    );
    final isMacOS = defaultTargetPlatform == TargetPlatform.macOS;
    return Column(
      children: [
        NoteTitleField(
          controller: _titleController,
          hintText: _hintTitle,
          onChanged: _scheduleSave,
        ),
        if (isMacOS) toolbar,
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
            child: _buildEditor(),
          ),
        ),
        if (!isMacOS) toolbar,
      ],
    );
  }

  Widget _buildEditor() {
    final editor = QuillEditor.basic(
      controller: _controller!,
      focusNode: _focusNode,
      config: QuillEditorConfig(
        placeholder: 'Start writing…',
        enableInteractiveSelection: true,
        // Disable flutter_quill's selection toolbar on macOS: its
        // EditorTextSelectionOverlay inserts handle OverlayEntries above the
        // toolbar, which absorb clicks before they reach the menu buttons.
        // Right-click on macOS is handled by the Listener below via showMenu.
        enableSelectionToolbar:
            defaultTargetPlatform != TargetPlatform.macOS,
        customStyleBuilder: defaultTargetPlatform == TargetPlatform.macOS
            ? macFontStyleBuilder
            : null,
        embedBuilders: [
          NoteImageEmbedBuilder(controller: _controller!),
          const NoteTabEmbedBuilder(),
          const NoteTableEmbedBuilder(),
        ],
        // ignore: experimental_member_use
        onKeyPressed: (event, node) {
          if (event is! KeyDownEvent) return null;
          if (event.logicalKey == LogicalKeyboardKey.tab) {
            _insertTab();
            return KeyEventResult.handled;
          }
          // Intercept Cmd+C/X/V (macOS) and Ctrl+C/X/V (all other platforms)
          // so Quill's built-in plain-text clipboard handlers never run —
          // our rich service handles all three.
          final isMac = defaultTargetPlatform == TargetPlatform.macOS;
          final modifierDown = isMac
              ? HardwareKeyboard.instance.isMetaPressed
              : HardwareKeyboard.instance.isControlPressed;
          if (modifierDown) {
            final key = event.logicalKey;
            if (key == LogicalKeyboardKey.keyV) {
              _handlePaste();
              return KeyEventResult.handled;
            }
            if (key == LogicalKeyboardKey.keyC) {
              _handleCopy();
              return KeyEventResult.handled;
            }
            if (key == LogicalKeyboardKey.keyX) {
              _handleCut();
              return KeyEventResult.handled;
            }
          }
          return null;
        },
        onTapUp: (details, getPosition) {
          final pos = getPosition(details.localPosition);
          if (defaultTargetPlatform == TargetPlatform.macOS) {
            // Cmd+click opens link; plain click just positions the cursor.
            if (HardwareKeyboard.instance.isMetaPressed) {
              openLinkAtPosition(_controller!, pos.offset);
            }
          } else {
            openLinkAtPosition(_controller!, pos.offset);
          }
          return false;
        },
        quillMagnifierBuilder: defaultTargetPlatform == TargetPlatform.android
            ? defaultQuillMagnifierBuilder
            : null,
        onLaunchUrl: (url) async {
          final uri = Uri.tryParse(url);
          if (uri != null && await canLaunchUrl(uri)) {
            launchUrl(uri, mode: LaunchMode.externalApplication);
          }
        },
        contextMenuBuilder: defaultTargetPlatform == TargetPlatform.macOS
            ? null
            : (ctx, rawEditorState) => _buildContextMenu(ctx, rawEditorState),
      ),
    );

    if (defaultTargetPlatform != TargetPlatform.macOS) {
      return Listener(
        onPointerDown: (_) => _primaryPointerDown = true,
        onPointerUp: (_) {
          _primaryPointerDown = false;
          _onPrimaryPointerUp();
        },
        child: editor,
      );
    }

    // On macOS, use showMenu (a Navigator Route) for the context menu.
    // Routes sit above the overlay stack, so clicks always reach the items.
    return Listener(
      onPointerDown: (event) {
        if (event.buttons == kSecondaryMouseButton) {
          _secondaryButtonActive = true;
        } else if (event.buttons == kPrimaryMouseButton) {
          _primaryPointerDown = true;
          _trackPrimaryTap();
        }
      },
      onPointerUp: (event) {
        if (_secondaryButtonActive) {
          _secondaryButtonActive = false;
          // Fire on pointer-UP, not pointer-DOWN, so that flutter_quill's
          // onSecondarySingleTapUp has already moved the cursor to the
          // right-click position before we check for a link there.
          final pos = event.position;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _showMacContextMenu(pos);
          });
          return;
        }
        _primaryPointerDown = false;
        _onPrimaryPointerUp();
      },
      child: editor,
    );
  }

  // ── macOS context menu (showMenu = Navigator Route, always clickable) ─────────

  Future<void> _showMacContextMenu(Offset globalPos) async {
    final ctrl = _controller;
    if (ctrl == null) return;

    final sel = ctrl.selection;
    final hasSelection = sel.isValid && !sel.isCollapsed;
    // Cursor is now at the right-click position (moved by flutter_quill's
    // onSecondarySingleTapUp before this post-frame callback fired).
    final linkUrl = getLinkAtSelection(ctrl);
    final hasLink = linkUrl != null;

    final overlayBox =
        Overlay.of(context).context.findRenderObject()! as RenderBox;
    final position = RelativeRect.fromRect(
      globalPos & const Size(1, 1),
      Offset.zero & overlayBox.size,
    );

    final choice = await showMenu<_MacMenuAction>(
      context: context,
      position: position,
      items: [
        if (hasLink) ...[
          const PopupMenuItem(
              height: 32,
              value: _MacMenuAction.openLink,
              child: Text('Open Link')),
          const PopupMenuDivider(height: 8),
        ],
        if (hasSelection)
          const PopupMenuItem(
              height: 32, value: _MacMenuAction.cut, child: Text('Cut')),
        if (hasSelection)
          const PopupMenuItem(
              height: 32, value: _MacMenuAction.copy, child: Text('Copy')),
        const PopupMenuItem(
            height: 32, value: _MacMenuAction.paste, child: Text('Paste')),
        const PopupMenuItem(
            height: 32,
            value: _MacMenuAction.selectAll,
            child: Text('Select All')),
        PopupMenuItem(
          height: 32,
          value: _MacMenuAction.link,
          child: Text(hasLink ? 'Edit Link' : 'Insert Link'),
        ),
      ],
    );

    if (!mounted || choice == null) return;

    switch (choice) {
      case _MacMenuAction.openLink:
        final uri = Uri.tryParse(linkUrl ?? '');
        if (uri != null) launchUrl(uri, mode: LaunchMode.externalApplication);
      case _MacMenuAction.cut:
        _handleCopy();
        ctrl.replaceText(sel.start, sel.end - sel.start, '', null);
      case _MacMenuAction.copy:
        _handleCopy();
      case _MacMenuAction.paste:
        await RichClipboardService.instance.paste(ctrl);
      case _MacMenuAction.selectAll:
        ctrl.updateSelection(
          TextSelection(
              baseOffset: 0, extentOffset: ctrl.document.length - 1),
          ChangeSource.local,
        );
      case _MacMenuAction.link:
        final savedSel = ctrl.selection;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || _controller == null) return;
          _controller!.updateSelection(savedSel, ChangeSource.local);
          _onInsertLink();
        });
    }
  }

  void _trackPrimaryTap() {
    final now = DateTime.now();
    final last = _lastPrimaryTapTime;
    if (last != null && now.difference(last) < _kTripleTapMaxGap) {
      _primaryTapCount++;
    } else {
      _primaryTapCount = 1;
    }
    _lastPrimaryTapTime = now;
    if (_primaryTapCount >= 3) {
      _primaryTapCount = 0;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _selectParagraphAtCursor();
      });
    }
  }

  void _selectParagraphAtCursor() {
    final ctrl = _controller;
    if (ctrl == null) return;
    final text = ctrl.document.toPlainText();
    final offset = ctrl.selection.baseOffset.clamp(0, text.length);
    var start = offset;
    while (start > 0 && text[start - 1] != '\n') {
      start--;
    }
    var end = offset;
    while (end < text.length && text[end] != '\n') {
      end++;
    }
    ctrl.updateSelection(
      TextSelection(baseOffset: start, extentOffset: end),
      ChangeSource.local,
    );
  }

  // ── Android / other platforms context menu ────────────────────────────────────

  Widget _buildContextMenu(
      BuildContext ctx, QuillRawEditorState rawEditorState) {
    final sel = rawEditorState.textEditingValue.selection;
    final hasSelection = sel.isValid && !sel.isCollapsed;
    final hasLink =
        _controller != null && getLinkAtSelection(_controller!) != null;

    return AdaptiveTextSelectionToolbar.buttonItems(
      anchors: rawEditorState.contextMenuAnchors,
      buttonItems: [
        if (hasSelection)
          ContextMenuButtonItem(
            label: 'Cut',
            onPressed: () =>
                rawEditorState.cutSelection(SelectionChangedCause.toolbar),
          ),
        if (hasSelection)
          ContextMenuButtonItem(
            label: 'Copy',
            onPressed: () =>
                rawEditorState.copySelection(SelectionChangedCause.toolbar),
          ),
        ContextMenuButtonItem(
          label: 'Paste',
          onPressed: () {
            if (_controller != null) {
              RichClipboardService.instance.paste(_controller!);
            }
          },
        ),
        ContextMenuButtonItem(
          label: 'Select All',
          onPressed: () =>
              rawEditorState.selectAll(SelectionChangedCause.toolbar),
        ),
        ContextMenuButtonItem(
          label: hasLink ? 'Edit Link' : 'Insert Link',
          onPressed: () {
            final savedSelection = _controller!.selection;
            rawEditorState.hideToolbar();
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted || _controller == null) return;
              _controller!
                  .updateSelection(savedSelection, ChangeSource.local);
              _onInsertLink();
            });
          },
        ),
      ],
    );
  }
}

enum _MacMenuAction { openLink, cut, copy, paste, selectAll, link }

class _DragOverlay extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      color: Theme.of(context)
          .colorScheme
          .primary
          .withValues(alpha: _kDragOverlayOpacity),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.image_outlined,
                size: 48, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 8),
            Text(
              'Drop image to insert',
              style: TextStyle(
                color: Theme.of(context).colorScheme.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
