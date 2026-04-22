import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

const _kClipboardChannel = MethodChannel('com.armelchao.notesApp/clipboard');

const _kImageExtensions = {'.png', '.jpg', '.jpeg', '.gif', '.webp', '.bmp'};

bool isImagePath(String path) =>
    _kImageExtensions.contains(p.extension(path).toLowerCase());

Future<void> pasteImageFromClipboard(QuillController controller) async {
  try {
    final result = await _kClipboardChannel.invokeMethod<Map>('getImageData');
    if (result == null) return;
    final bytes = result['data'] as Uint8List;
    final ext = result['ext'] as String? ?? 'png';
    final fileName = '${DateTime.now().millisecondsSinceEpoch}.$ext';
    final dest = await _resolveImageDestination(fileName);
    await File(dest).writeAsBytes(bytes);
    embedImageIntoEditor(controller, dest);
  } catch (e) {
    debugPrint('[NoteImageHandler] clipboard paste failed: $e');
  }
}

Future<void> embedImageFile(
    QuillController controller, String sourcePath) async {
  final dest = await _resolveImageDestination(p.basename(sourcePath));
  await File(sourcePath).copy(dest);
  embedImageIntoEditor(controller, dest);
}

void embedImageIntoEditor(QuillController controller, String dest) {
  final index = controller.selection.baseOffset
      .clamp(0, controller.document.length - 1);
  controller.document.insert(index, BlockEmbed.image(dest));
}

Future<String> _resolveImageDestination(String fileName) async {
  final appDir = await getApplicationDocumentsDirectory();
  final imagesDir = Directory(p.join(appDir.path, 'note_images'));
  await imagesDir.create(recursive: true);
  return p.join(imagesDir.path, fileName);
}

class NoteImageEmbedBuilder extends EmbedBuilder {
  final QuillController controller;

  const NoteImageEmbedBuilder({required this.controller});

  @override
  String get key => BlockEmbed.imageType;

  @override
  Widget build(BuildContext context, EmbedContext embedContext) {
    final imageUrl = embedContext.node.value.data as String;
    final file = File(imageUrl);
    return GestureDetector(
      onSecondaryTapUp: (details) => _onRightClick(context, details, imageUrl),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600, maxHeight: 400),
          child: file.existsSync()
              ? Image.file(file, fit: BoxFit.contain)
              : Text('[Image not found: $imageUrl]'),
        ),
      ),
    );
  }

  Future<void> _onRightClick(
      BuildContext context, TapUpDetails details, String imageUrl) async {
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
    if (result == 'delete') _deleteImage(imageUrl);
  }

  void _deleteImage(String imageUrl) {
    final delta = controller.document.toDelta();
    var offset = 0;
    for (final op in delta.toList()) {
      if (op.isInsert) {
        final data = op.data;
        if (data is Map && data['image'] == imageUrl) {
          controller.replaceText(offset, 1, '', null);
          return;
        }
        offset += op.length ?? 0;
      }
    }
  }
}
