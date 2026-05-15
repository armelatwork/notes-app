import 'dart:async';
import 'dart:convert';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
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
import '../utils/font_utils.dart';
import '../utils/image_utils.dart';
import '../utils/note_utils.dart';
import 'note_editor_widgets.dart';
import 'note_image_handler.dart';
import 'note_link_handler.dart';
import 'note_tab_embed.dart';
import 'note_table_embed.dart';

part 'note_editor_mac_menu.dart';
part 'note_editor_context_menus.dart';
part 'note_editor_format_painter.dart';

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
  void deactivate() {
    // ref is still valid in deactivate() but is invalidated by Riverpod before
    // dispose() is called, so all ref-based cleanup must happen here.
    _discardIfEmpty();
    ref.read(editorMenuProvider.notifier).state = null;
    super.deactivate();
  }

  @override
  void dispose() {
    _formatPainterTimer?.cancel();
    _controller?.dispose();
    _focusNode.dispose();
    _titleController.dispose();
    super.dispose();
  }

  // ── Clipboard ──────────────────────────────────────────────────────────────

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

  // ── Note lifecycle ─────────────────────────────────────────────────────────

  bool _isNewEmptyNote() {
    final note = _currentNote;
    if (note == null || _controller == null || _isDirty) return false;
    if (!isDefaultNoteTitle(note.title)) return false;
    return _controller!.document.toPlainText().trim().isEmpty;
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
    _initNoteController(doc);
    setState(() {});
  }

  void _initNoteController(Document doc) {
    _controller?.dispose();
    _controller = QuillController(
      document: doc,
      selection: const TextSelection.collapsed(offset: 0),
    );
    _controller!.document.changes.listen((_) => _scheduleSave());
    _controller!.addListener(_applyFormatPainterIfActive);
    ref.read(editorMenuProvider.notifier).state = _controller;
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

  // ── Build ──────────────────────────────────────────────────────────────────

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
          if (isImagePath(file.path)) await embedImageFile(_controller!, file.path);
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
    // ValueKey forces toolbar rebuild on controller change so the history
    // buttons re-subscribe to the new controller.changes stream.
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

  // ── Editor widget ──────────────────────────────────────────────────────────

  Widget _buildEditor() {
    final editor = QuillEditor.basic(
      controller: _controller!,
      focusNode: _focusNode,
      config: _buildEditorConfig(),
    );
    return defaultTargetPlatform != TargetPlatform.macOS
        ? _buildAndroidListener(editor)
        : _buildMacListener(editor);
  }

  QuillEditorConfig _buildEditorConfig() {
    return QuillEditorConfig(
      placeholder: 'Start writing…',
      enableInteractiveSelection: true,
      // Quill's selection toolbar overlaps the toolbar on macOS; use showMenu.
      enableSelectionToolbar: defaultTargetPlatform != TargetPlatform.macOS,
      customStyleBuilder: defaultTargetPlatform == TargetPlatform.macOS
          ? macFontStyleBuilder
          : null,
      embedBuilders: [
        NoteImageEmbedBuilder(controller: _controller!),
        const NoteTabEmbedBuilder(),
        const NoteTableEmbedBuilder(),
      ],
      // ignore: experimental_member_use
      onKeyPressed: _onEditorKeyPressed,
      onTapUp: _onEditorTapUp,
      quillMagnifierBuilder: defaultTargetPlatform == TargetPlatform.android
          ? defaultQuillMagnifierBuilder
          : null,
      onLaunchUrl: _onEditorLaunchUrl,
      contextMenuBuilder: defaultTargetPlatform == TargetPlatform.macOS
          ? null
          : (ctx, rawEditorState) => _buildContextMenu(ctx, rawEditorState),
    );
  }

  KeyEventResult? _onEditorKeyPressed(KeyEvent event, Node? node) {
    if (event is! KeyDownEvent) return null;
    if (event.logicalKey == LogicalKeyboardKey.tab) {
      _insertTab();
      return KeyEventResult.handled;
    }
    // Intercept Cmd+C/X/V (macOS) and Ctrl+C/X/V (other platforms) so
    // Quill's built-in plain-text handlers never run.
    final isMac = defaultTargetPlatform == TargetPlatform.macOS;
    final modifierDown = isMac
        ? HardwareKeyboard.instance.isMetaPressed
        : HardwareKeyboard.instance.isControlPressed;
    if (!modifierDown) return null;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.keyV) { _handlePaste(); return KeyEventResult.handled; }
    if (key == LogicalKeyboardKey.keyC) { _handleCopy(); return KeyEventResult.handled; }
    if (key == LogicalKeyboardKey.keyX) { _handleCut();  return KeyEventResult.handled; }
    return null;
  }

  bool _onEditorTapUp(
      TapUpDetails details, TextPosition Function(Offset) getPosition) {
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
  }

  Future<void> _onEditorLaunchUrl(String url) async {
    final uri = Uri.tryParse(url);
    if (uri != null && await canLaunchUrl(uri)) {
      launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  Widget _buildAndroidListener(Widget editor) => Listener(
        onPointerDown: (_) => _primaryPointerDown = true,
        onPointerUp: (_) {
          _primaryPointerDown = false;
          _onPrimaryPointerUp();
        },
        child: editor,
      );

  Widget _buildMacListener(Widget editor) => Listener(
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
