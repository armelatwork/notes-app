import 'package:flutter/widgets.dart';
import 'package:flutter_quill/flutter_quill.dart';

const kTabEmbedType = 'tab';

const _kTabWidthFactor = 2.5;

class NoteTabEmbedBuilder extends EmbedBuilder {
  const NoteTabEmbedBuilder();

  @override
  String get key => kTabEmbedType;

  @override
  bool get expanded => false;

  @override
  Widget build(BuildContext context, EmbedContext embedContext) {
    final fontSize = embedContext.textStyle.fontSize ?? 16.0;
    return SizedBox(width: fontSize * _kTabWidthFactor, height: fontSize);
  }
}
