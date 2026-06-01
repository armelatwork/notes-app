import 'dart:async';
import 'dart:convert';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_quill/quill_delta.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/note.dart';
import '../providers/app_provider.dart';
import '../providers/editor_menu_provider.dart';
import '../providers/format_painter_provider.dart';
import '../providers/sharing_provider.dart';
import '../services/app_logger.dart';
import '../services/sharing_service.dart';
import 'share_dialog.dart';
import '../services/rich_clipboard_service.dart';
import '../utils/font_utils.dart';
import '../utils/image_utils.dart';
import '../utils/note_utils.dart';
import 'ai_suggestion_sheet.dart';
import 'note_editor_widgets.dart';
import 'note_image_handler.dart';
import 'note_link_handler.dart';
import 'note_tab_embed.dart';
import 'note_table_embed.dart';

part 'note_editor_mac_menu.dart';
part 'note_editor_context_menus.dart';
part 'note_editor_format_painter.dart';
part 'note_editor_clipboard.dart';
part 'note_editor_ai.dart';
part 'note_editor_lifecycle.dart';
part 'note_editor_builders.dart';

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
  bool _isAiSheetOpen = false;
  Document? _sessionAiDocument;
  String? _sessionAiBaseContent;
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
    // ref is still valid here, but Riverpod forbids mutating providers during
    // deactivate() (the tree is mid-rebuild). Capture the notifier objects now
    // and schedule the mutations for the next frame. Notifiers live in the
    // Riverpod container and remain valid after this widget is gone.
    final editorMenu = ref.read(editorMenuProvider.notifier);
    NotesNotifier? notesNotifier;
    int? discardId;
    if (_isNewEmptyNote()) {
      discardId = _currentNote!.id;
      notesNotifier = ref.read(notesProvider.notifier);
      _currentNote = null;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      editorMenu.state = null;
      if (notesNotifier != null && discardId != null) {
        notesNotifier.deleteNote(discardId);
      }
    });
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

  // Forwarding helper so extension part-files can call setState without
  // triggering the invalid_use_of_protected_member lint.
  void _rebuild(VoidCallback fn) => setState(fn);

  bool _isNewEmptyNote() {
    final note = _currentNote;
    if (note == null || _controller == null || _isDirty) return false;
    if (!isDefaultNoteTitle(note.title)) return false;
    return _controller!.document.toPlainText().trim().isEmpty;
  }

  @override
  Widget build(BuildContext context) {
    final note = ref.watch(selectedNoteProvider);
    if (note == null) return const NoteEmptyPlaceholder();
    if (note.id != _currentNote?.id) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _loadNote(note));
    } else if (_currentNote != null && note.isPinned != _currentNote!.isPinned) {
      _currentNote!.isPinned = note.isPinned;
    }
    if (_controller == null) {
      return const Center(child: CircularProgressIndicator());
    }
    _registerListeners(note);
    return _buildDropTarget();
  }
}
