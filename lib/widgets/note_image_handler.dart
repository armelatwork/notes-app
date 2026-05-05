import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:path/path.dart' as p;
import '../services/app_logger.dart';
import '../services/drive_sync_service.dart';
import '../utils/image_utils.dart';

const _kClipboardChannel = MethodChannel('com.armelchao.notesApp/clipboard');
const _kImageExtensions = {'.png', '.jpg', '.jpeg', '.gif', '.webp', '.bmp'};

bool isImagePath(String path) =>
    _kImageExtensions.contains(p.extension(path).toLowerCase());

/// Copies [sourcePath] into note_images/ under a UUID filename and embeds it.
/// Uses readAsBytes+writeAsBytes to avoid macOS sandbox EPERM from copyfile().
Future<void> embedImageFile(
    QuillController controller, String sourcePath) async {
  final filename = generateImageFilename(sourcePath);
  final dest = await imageLocalPath(filename);
  await File(dest).writeAsBytes(await File(sourcePath).readAsBytes());
  _embed(controller, filename);
}

Future<void> pasteImageFromClipboard(QuillController controller) async {
  try {
    final result = await _kClipboardChannel.invokeMethod<Map>('getImageData');
    if (result == null) return;
    final bytes = result['data'] as Uint8List;
    final ext = result['ext'] as String? ?? 'png';
    final filename = 'img_${DateTime.now().millisecondsSinceEpoch}.$ext';
    final dest = await imageLocalPath(filename);
    await File(dest).writeAsBytes(bytes);
    _embed(controller, filename);
  } catch (e) {
    AppLogger.instance.error('NoteImageHandler', 'clipboard paste failed', e);
  }
}

void _embed(QuillController controller, String filename) {
  final index =
      controller.selection.baseOffset.clamp(0, controller.document.length - 1);
  controller.document.insert(index, BlockEmbed.image(filename));
}

// ── Embed builder ────────────────────────────────────────────────────────────

class NoteImageEmbedBuilder extends EmbedBuilder {
  final QuillController controller;
  const NoteImageEmbedBuilder({required this.controller});

  @override
  String get key => BlockEmbed.imageType;

  @override
  Widget build(BuildContext context, EmbedContext embedContext) {
    final ref = embedContext.node.value.data as String;
    if (!isNewImageRef(ref)) {
      return _LegacyImageTile(path: ref, controller: controller);
    }
    return _ImageTile(filename: ref, controller: controller);
  }
}

// ── UUID image tile (new format) ─────────────────────────────────────────────

class _ImageTile extends StatefulWidget {
  final String filename;
  final QuillController controller;
  const _ImageTile({required this.filename, required this.controller});

  @override
  State<_ImageTile> createState() => _ImageTileState();
}

class _ImageTileState extends State<_ImageTile> {
  String? _localPath;
  bool _loading = true;
  bool? _notOnDrive; // null=unknown, true=not found on Drive, false=error

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  Future<void> _resolve() async {
    if (mounted) setState(() { _loading = true; _notOnDrive = null; });
    try {
      final path = await imageLocalPath(widget.filename);
      if (!await File(path).exists()) {
        final found =
            await DriveSyncService.instance.downloadImage(widget.filename, path);
        if (!found) {
          if (mounted) setState(() { _loading = false; _notOnDrive = true; });
          return;
        }
      }
      if (mounted) setState(() { _localPath = path; _loading = false; });
    } catch (e) {
      AppLogger.instance.error('ImageTile', 'download failed', e);
      if (mounted) setState(() { _loading = false; _notOnDrive = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return _frame(const SizedBox(
          height: 60,
          child: Center(child: CircularProgressIndicator(strokeWidth: 2))));
    }
    if (_localPath == null || !File(_localPath!).existsSync()) {
      final msg = _notOnDrive == true
          ? 'Not synced yet — sync both devices, then tap to retry'
          : 'Download failed — tap to retry';
      return _frame(GestureDetector(
        onTap: _resolve,
        child: Container(
          height: 60,
          color: Colors.grey[200],
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.image_not_supported_outlined, color: Colors.grey[500]),
                const SizedBox(height: 4),
                Text(msg,
                    style: TextStyle(color: Colors.grey[600], fontSize: 12)),
              ],
            ),
          ),
        ),
      ));
    }
    return GestureDetector(
      onSecondaryTapUp: (d) =>
          _showDeleteMenu(context, d, widget.filename, widget.controller),
      onLongPress: () =>
          _showDeleteMenu(context, null, widget.filename, widget.controller),
      child: _frame(Image.file(File(_localPath!), fit: BoxFit.contain)),
    );
  }
}

// ── Legacy absolute-path tile ─────────────────────────────────────────────────

class _LegacyImageTile extends StatefulWidget {
  final String path;
  final QuillController controller;
  const _LegacyImageTile({required this.path, required this.controller});

  @override
  State<_LegacyImageTile> createState() => _LegacyImageTileState();
}

class _LegacyImageTileState extends State<_LegacyImageTile> {
  Uint8List? _bytes;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final file = File(widget.path);
      if (await file.exists()) {
        final bytes = await file.readAsBytes();
        if (mounted) setState(() { _bytes = bytes; _loading = false; });
        return;
      }
    } catch (_) {}
    if (mounted) setState(() { _loading = false; });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return _frame(const SizedBox(
          height: 60,
          child: Center(child: CircularProgressIndicator(strokeWidth: 2))));
    }
    return GestureDetector(
      onSecondaryTapUp: _bytes != null
          ? (d) => _showDeleteMenu(context, d, widget.path, widget.controller)
          : null,
      child: _frame(_bytes != null
          ? Image.memory(_bytes!, fit: BoxFit.contain)
          : const Text('[Image not found]')),
    );
  }
}

// ── Shared helpers ────────────────────────────────────────────────────────────

Widget _frame(Widget child) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 600, maxHeight: 400),
        child: child,
      ),
    );

Future<void> _showDeleteMenu(BuildContext context, TapUpDetails? details,
    String imageRef, QuillController controller) async {
  final pos = details != null
      ? RelativeRect.fromLTRB(details.globalPosition.dx,
          details.globalPosition.dy, details.globalPosition.dx + 1,
          details.globalPosition.dy + 1)
      : RelativeRect.fill;
  final result = await showMenu<String>(
    context: context,
    position: pos,
    items: const [PopupMenuItem(value: 'delete', child: Text('Delete image'))],
  );
  if (result == 'delete') _deleteImageFromEditor(imageRef, controller);
}

void _deleteImageFromEditor(String imageRef, QuillController controller) {
  final delta = controller.document.toDelta();
  var offset = 0;
  for (final op in delta.toList()) {
    if (op.isInsert) {
      final data = op.data;
      if (data is Map && data['image'] == imageRef) {
        controller.replaceText(offset, 1, '', null);
        return;
      }
      offset += op.length ?? 0;
    }
  }
}
