import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';

const kTabEmbedType = 'tab';

class NoteTabEmbedBuilder extends EmbedBuilder {
  @override
  String get key => kTabEmbedType;

  @override
  bool get expanded => false;

  @override
  Widget build(BuildContext context, EmbedContext embedContext) {
    final fontSize = DefaultTextStyle.of(context).style.fontSize ?? 14;
    return SizedBox(width: fontSize * 2.5);
  }
}
