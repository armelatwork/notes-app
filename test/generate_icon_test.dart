// Run once to regenerate the app icon:
//   flutter test test/generate_icon_test.dart
// Not part of the regular test suite.
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _loadMaterialIcons() async {
  // Load the bundled MaterialIcons font so the icon glyph renders correctly.
  final candidates = [
    '/opt/homebrew/share/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
    '/usr/local/share/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
    Platform.environment['HOME']! +
        '/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
  ];
  late final Uint8List fontBytes;
  for (final path in candidates) {
    final f = File(path);
    if (f.existsSync()) {
      fontBytes = f.readAsBytesSync();
      break;
    }
  }
  final loader = FontLoader('MaterialIcons')
    ..addFont(Future.value(ByteData.view(fontBytes.buffer)));
  await loader.load();
}

void main() {
  testWidgets('generate_app_icon', (WidgetTester tester) async {
    await _loadMaterialIcons();

    const double size = 1024;
    tester.view.physicalSize = const Size(size, size);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final repaintKey = GlobalKey();

    await tester.pumpWidget(
      RepaintBoundary(
        key: repaintKey,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          home: Scaffold(
            backgroundColor: const Color(0xFFFFFCDC),
            body: const Center(
              child: Icon(
                Icons.note_alt_outlined,
                size: 780,
                color: Color(0xFFFFD60A),
              ),
            ),
          ),
        ),
      ),
    );

    // One pump is enough — no animations to settle.
    await tester.pump();

    final boundary = repaintKey.currentContext!.findRenderObject()!
        as RenderRepaintBoundary;
    final ui.Image image = await boundary.toImage(pixelRatio: 1.0);
    final ByteData? byteData =
        await image.toByteData(format: ui.ImageByteFormat.png);
    final Uint8List bytes = byteData!.buffer.asUint8List();

    final file = File('assets/icon/app_icon.png');
    file.createSync(recursive: true);
    file.writeAsBytesSync(bytes);
    print('Written assets/icon/app_icon.png (${bytes.length} bytes)');
  });
}
