import 'dart:convert';
import 'dart:io';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:url_launcher/url_launcher.dart';
import '../models/note.dart';
import '../providers/app_provider.dart';
import '../utils/note_utils.dart';

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

  static const _clipboardChannel =
      MethodChannel('com.armelchao.notesApp/clipboard');

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
    final isMeta = HardwareKeyboard.instance.isMetaPressed;
    if (isMeta && event.logicalKey == LogicalKeyboardKey.keyV) {
      if (_focusNode.hasFocus || _titleController.value.composing != TextRange.empty) {
        _pasteFromClipboard();
        return false;
      }
    }
    return false;
  }

  Future<void> _pasteFromClipboard() async {
    if (_controller == null) return;
    try {
      final result = await _clipboardChannel.invokeMethod<Map>('getImageData');
      if (result == null) return;
      final bytes = (result['data'] as Uint8List);
      final ext = result['ext'] as String? ?? 'png';
      final appDir = await getApplicationDocumentsDirectory();
      final imagesDir = Directory(p.join(appDir.path, 'note_images'));
      await imagesDir.create(recursive: true);
      final fileName = '${DateTime.now().millisecondsSinceEpoch}.$ext';
      final dest = p.join(imagesDir.path, fileName);
      await File(dest).writeAsBytes(bytes);
      await _embedImageFile(dest);
    } catch (_) {
      // Not an image in clipboard — let default paste handle text
    }
  }

  void _loadNote(Note note) {
    if (_currentNote?.id == note.id) return;
    _saveCurrentNote();

    _currentNote = note;
    _isDirty = false;

    // Default titles show as hint text; user-entered titles show as real text.
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
    } catch (_) {
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
    Future.delayed(const Duration(milliseconds: 800), _saveCurrentNote);
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
    note.preview = preview.length > 120 ? preview.substring(0, 120) : preview;

    await ref.read(notesProvider.notifier).saveNote(note);
  }

  Future<void> _insertImage() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery);
    if (picked == null || _controller == null) return;
    await _embedImageFile(picked.path);
  }

  Future<void> _embedImageFile(String sourcePath) async {
    if (_controller == null) return;
    final appDir = await getApplicationDocumentsDirectory();
    final imagesDir = Directory(p.join(appDir.path, 'note_images'));
    await imagesDir.create(recursive: true);
    final dest = p.join(imagesDir.path, p.basename(sourcePath));
    await File(sourcePath).copy(dest);
    final index = _controller!.selection.baseOffset.clamp(
        0, _controller!.document.length - 1);
    _controller!.document.insert(index, BlockEmbed.image(dest));
    if (mounted) setState(() {});
  }

  static bool _isImagePath(String path) {
    final ext = p.extension(path).toLowerCase();
    return const {'.png', '.jpg', '.jpeg', '.gif', '.webp', '.bmp'}.contains(ext);
  }

  // Returns the URL of the link at the current selection, if any.
  String? _getLinkAtSelection() {
    if (_controller == null) return null;
    final style = _controller!.getSelectionStyle();
    return style.attributes[Attribute.link.key]?.value as String?;
  }

  void _insertLink() {
    if (_controller == null) return;

    // Capture selection before dialog steals focus
    final sel = _controller!.selection;
    final selStart = sel.start;
    final selLength = sel.end - sel.start;
    final selectedText = selLength > 0
        ? _controller!.document.getPlainText(selStart, selLength).trimRight()
        : '';

    // If cursor is inside existing linked text, pre-fill the URL for editing
    final existingUrl = _getLinkAtSelection();

    final urlController = TextEditingController(text: existingUrl ?? '');
    final textController = TextEditingController(text: selectedText);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(existingUrl != null ? 'Edit Link' : 'Insert Link'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: textController,
              decoration: const InputDecoration(labelText: 'Display text'),
              autofocus: selectedText.isEmpty && existingUrl == null,
            ),
            const SizedBox(height: 8),
            TextField(
              controller: urlController,
              decoration: const InputDecoration(labelText: 'URL'),
              keyboardType: TextInputType.url,
              autofocus: selectedText.isNotEmpty || existingUrl != null,
            ),
          ],
        ),
        actions: [
          if (existingUrl != null)
            TextButton(
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              onPressed: () {
                // Remove the link from the selection
                _controller!.formatText(
                    selStart, selLength > 0 ? selLength : 1,
                    const LinkAttribute(null));
                Navigator.pop(ctx);
              },
              child: const Text('Remove link'),
            ),
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              final url = urlController.text.trim();
              if (url.isEmpty) {
                Navigator.pop(ctx);
                return;
              }
              final displayText = textController.text.trim().isEmpty
                  ? url
                  : textController.text.trim();

              if (selLength > 0) {
                // Replace selected text with (possibly edited) display text
                _controller!.replaceText(selStart, selLength, displayText, null);
              } else if (existingUrl == null) {
                // No selection, no existing link — insert fresh text at cursor
                _controller!.document.insert(selStart, displayText);
              }
              // Apply (or update) the link attribute
              _controller!.formatText(
                  selStart, displayText.length, LinkAttribute(url));

              Navigator.pop(ctx);
            },
            child: const Text('Apply'),
          ),
        ],
      ),
    );
  }

  // Opens the URL at the tapped document position, if any.
  void _openLinkAtPosition(int docOffset) {
    final node = _controller?.document.queryChild(docOffset);
    if (node == null) return;
    final leaf = node.node;
    if (leaf == null) return;
    final url = leaf.style.attributes[Attribute.link.key]?.value as String?;
    if (url != null) {
      final uri = Uri.tryParse(url);
      if (uri != null) launchUrl(uri);
    }
  }

  @override
  Widget build(BuildContext context) {
    final note = ref.watch(selectedNoteProvider);

    if (note == null) {
      return const _EmptyEditorPlaceholder();
    }

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
          if (_isImagePath(file.path)) {
            await _embedImageFile(file.path);
          }
        }
      },
      child: Stack(
        children: [
          Column(
            children: [
              _TitleField(
                controller: _titleController,
                hintText: _hintTitle,
                onChanged: _scheduleSave,
              ),
              _FormattingToolbar(
                quillController: _controller!,
                onInsertImage: _insertImage,
                onInsertLink: _insertLink,
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
                  child: QuillEditor.basic(
                    controller: _controller!,
                    focusNode: _focusNode,
                    config: QuillEditorConfig(
                      placeholder: 'Start writing…',
                      enableInteractiveSelection: true,
                      embedBuilders: [_ImageEmbedBuilder(controller: _controller!)],
                      onTapUp: (details, getPosition) {
                        if (_controller == null) return false;
                        final pos = getPosition(details.localPosition);
                        _openLinkAtPosition(pos.offset);
                        return false;
                      },
                      onLaunchUrl: (url) async {
                        final uri = Uri.tryParse(url);
                        if (uri != null && await canLaunchUrl(uri)) {
                          await launchUrl(uri);
                        }
                      },
                      contextMenuBuilder: (ctx, rawEditorState) {
                        return AdaptiveTextSelectionToolbar.buttonItems(
                          anchors: rawEditorState.contextMenuAnchors,
                          buttonItems: [
                            ...rawEditorState.contextMenuButtonItems,
                            ContextMenuButtonItem(
                              label: _getLinkAtSelection() != null
                                  ? 'Edit Link'
                                  : 'Insert Link',
                              onPressed: () {
                                ContextMenuController.removeAny();
                                // Defer until context menu is fully gone
                                WidgetsBinding.instance
                                    .addPostFrameCallback((_) {
                                  if (mounted) _insertLink();
                                });
                              },
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                ),
              ),
            ],
          ),
          if (_dragging)
            Container(
              color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.12),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.image_outlined,
                        size: 48,
                        color: Theme.of(context).colorScheme.primary),
                    const SizedBox(height: 8),
                    Text('Drop image to insert',
                        style: TextStyle(
                            color: Theme.of(context).colorScheme.primary,
                            fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _TitleField extends StatelessWidget {
  final TextEditingController controller;
  final String hintText;
  final VoidCallback onChanged;

  const _TitleField(
      {required this.controller, required this.hintText, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
      child: TextField(
        controller: controller,
        onChanged: (_) => onChanged(),
        style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
        decoration: InputDecoration(
          border: InputBorder.none,
          hintText: hintText,
          hintStyle: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: Colors.grey),
        ),
      ),
    );
  }
}

class _FormattingToolbar extends StatelessWidget {
  final QuillController quillController;
  final VoidCallback onInsertImage;
  final VoidCallback onInsertLink;

  const _FormattingToolbar({
    required this.quillController,
    required this.onInsertImage,
    required this.onInsertLink,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        border: Border(
            bottom: BorderSide(
                color: Theme.of(context).colorScheme.outlineVariant)),
        color: Theme.of(context).colorScheme.surfaceContainerLow,
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: QuillSimpleToolbar(
          controller: quillController,
          config: QuillSimpleToolbarConfig(
            showFontFamily: true,
            showFontSize: true,
            showBoldButton: true,
            showItalicButton: true,
            showUnderLineButton: true,
            showStrikeThrough: false,
            showColorButton: true,
            showBackgroundColorButton: true,
            showClearFormat: true,
            showAlignmentButtons: true,
            showLeftAlignment: true,
            showCenterAlignment: true,
            showRightAlignment: true,
            showHeaderStyle: true,
            showListNumbers: true,
            showListBullets: true,
            showListCheck: true,
            showCodeBlock: false,
            showQuote: false,
            showIndent: true,
            showLink: false,
            showUndo: true,
            showRedo: true,
            customButtons: [
              QuillToolbarCustomButtonOptions(
                icon: const Icon(Icons.link, size: 18),
                tooltip: 'Insert / edit link',
                onPressed: onInsertLink,
              ),
              QuillToolbarCustomButtonOptions(
                icon: const Icon(Icons.image_outlined, size: 18),
                tooltip: 'Insert image',
                onPressed: onInsertImage,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ImageEmbedBuilder extends EmbedBuilder {
  final QuillController controller;

  const _ImageEmbedBuilder({required this.controller});

  @override
  String get key => BlockEmbed.imageType;

  @override
  Widget build(BuildContext context, EmbedContext embedContext) {
    final imageUrl = embedContext.node.value.data as String;
    final file = File(imageUrl);
    return GestureDetector(
      onSecondaryTapUp: (details) async {
        final result = await showMenu<String>(
          context: context,
          position: RelativeRect.fromLTRB(
            details.globalPosition.dx,
            details.globalPosition.dy,
            details.globalPosition.dx + 1,
            details.globalPosition.dy + 1,
          ),
          items: const [
            PopupMenuItem(value: 'delete', child: Text('Delete image')),
          ],
        );
        if (result == 'delete') {
          final doc = controller.document;
          final delta = doc.toDelta();
          var offset = 0;
          for (final op in delta.toList()) {
            if (op.isInsert) {
              final data = op.data;
              if (data is Map && data['image'] == imageUrl) {
                controller.replaceText(offset, 1, '', null);
                break;
              }
              offset += op.length ?? 0;
            }
          }
        }
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: ConstrainedBox(
          constraints:
              const BoxConstraints(maxWidth: 600, maxHeight: 400),
          child: file.existsSync()
              ? Image.file(file, fit: BoxFit.contain)
              : Text('[Image not found: $imageUrl]'),
        ),
      ),
    );
  }
}

class _EmptyEditorPlaceholder extends StatelessWidget {
  const _EmptyEditorPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.edit_note, size: 64, color: Colors.grey[300]),
          const SizedBox(height: 12),
          Text('Select a note or create a new one',
              style:
                  TextStyle(color: Colors.grey[400], fontSize: 16)),
        ],
      ),
    );
  }
}
