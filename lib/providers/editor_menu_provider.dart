import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Holds a reference to the currently active QuillController so the macOS
/// menu bar can subscribe to it. Updated by NoteEditor when a note is loaded
/// or the editor is closed. Never null-checked externally; null means no note
/// is open.
final editorMenuProvider = StateProvider<QuillController?>((ref) => null);
