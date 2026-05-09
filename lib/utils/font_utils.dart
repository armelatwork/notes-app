import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';

const kMacGenericFontMap = {
  'sans-serif': 'Helvetica Neue',
  'serif': 'Times New Roman',
  'monospace': 'Menlo',
};

const kBundledFontAssets = {
  'nunito': [
    'assets/fonts/Nunito-Regular.ttf',
    'assets/fonts/Nunito-Italic.ttf',
  ],
  'pacifico': ['assets/fonts/Pacifico-Regular.ttf'],
  'roboto-mono': [
    'assets/fonts/RobotoMono-Regular.ttf',
    'assets/fonts/RobotoMono-Italic.ttf',
  ],
  'ibarra-real-nova': [
    'assets/fonts/IbarraRealNova-Regular.ttf',
    'assets/fonts/IbarraRealNova-Italic.ttf',
  ],
  'square-peg': ['assets/fonts/SquarePeg-Regular.ttf'],
};

/// Maps generic CSS font names to real macOS system fonts.
/// For decorative/bundled fonts, returns [TextStyle()] so the native
/// flutter_quill handling picks up the [FontLoader]-loaded family.
TextStyle macFontStyleBuilder(Attribute attribute) {
  if (attribute.key == Attribute.font.key && attribute.value != null) {
    final mapped = kMacGenericFontMap[attribute.value as String];
    if (mapped != null) return TextStyle(fontFamily: mapped);
  }
  return const TextStyle();
}
