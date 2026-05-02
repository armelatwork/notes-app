import 'dart:convert';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/note.dart';
import '../providers/app_provider.dart';
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
  String _hintTitle = 'New Note';
  // Images present when the note was loaded — used to detect deletions on save.
  List<String> _imagesAtLoad = [];

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_onKeyEvent);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKeyEvent);
    _controller?.dispose();
    _focusNode.dispose();
    _titleController.dispose();
    super.dispose();
  }

  bool _onKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent) return false;
    if (!_focusNode.hasFocus || _controller == null) return false;

    final isCmdV = HardwareKeyboard.instance.isMetaPressed &&
        event.logicalKey == LogicalKeyboardKey.keyV;
    if (isCmdV) {
      pasteImageFromClipboard(_controller!);
      return false;
    }

    return false;
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

  void _loadNote(Note note) {
    if (_currentNote?.id == note.id) return;
    _saveCurrentNote();
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
      debugPrint('[NoteEditor] failed to parse note content: $e');
      doc = Document();
    }

    _controller?.dispose();
    _controller = QuillController(
      document: doc,
      selection: const TextSelection.collapsed(offset: 0),
    );
    _controller!.document.changes.listen((_) => _scheduleSave());
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
          Column(
            children: [
              NoteTitleField(
                controller: _titleController,
                hintText: _hintTitle,
                onChanged: _scheduleSave,
              ),
              NoteFormattingToolbar(
                quillController: _controller!,
                onInsertImage: _pickAndInsertImage,
                onInsertLink: _onInsertLink,
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
                  child: _buildEditor(),
                ),
              ),
            ],
          ),
          if (_dragging) _DragOverlay(),
        ],
      ),
    );
  }

  Widget _buildEditor() {
    return QuillEditor.basic(
      controller: _controller!,
      focusNode: _focusNode,
      config: QuillEditorConfig(
        placeholder: 'Start writing…',
        enableInteractiveSelection: true,
        embedBuilders: [
          NoteImageEmbedBuilder(controller: _controller!),
          const NoteTabEmbedBuilder(),
        ],
        // ignore: experimental_member_use
        onKeyPressed: (event, node) {
          if (event is KeyDownEvent &&
              event.logicalKey == LogicalKeyboardKey.tab) {
            _insertTab();
            return KeyEventResult.handled;
          }
          return null;
        },
        onTapUp: (details, getPosition) {
          final pos = getPosition(details.localPosition);
          openLinkAtPosition(_controller!, pos.offset);
          return false;
        },
        onLaunchUrl: (url) async {
          final uri = Uri.tryParse(url);
          if (uri != null && await canLaunchUrl(uri)) launchUrl(uri);
        },
        contextMenuBuilder: (ctx, rawEditorState) =>
            _buildContextMenu(ctx, rawEditorState),
      ),
    );
  }

  Widget _buildContextMenu(
      BuildContext ctx, QuillRawEditorState rawEditorState) {
    final hasLink = _controller != null &&
        getLinkAtSelection(_controller!) != null;
    return AdaptiveTextSelectionToolbar.buttonItems(
      anchors: rawEditorState.contextMenuAnchors,
      buttonItems: [
        ...rawEditorState.contextMenuButtonItems,
        ContextMenuButtonItem(
          label: hasLink ? 'Edit Link' : 'Insert Link',
          onPressed: () {
            ContextMenuController.removeAny();
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) _onInsertLink();
            });
          },
        ),
      ],
    );
  }
}

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
