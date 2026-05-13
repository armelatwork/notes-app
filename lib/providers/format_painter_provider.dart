import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Holds the formatting attributes captured by the format painter.
/// null  → painter is inactive.
/// non-null → painter is active; apply these attributes to the next selection.
class FormatPainterNotifier extends Notifier<Map<String, Attribute>?> {
  @override
  Map<String, Attribute>? build() => null;

  void capture(Map<String, Attribute> attrs) => state = Map.from(attrs);
  void clear() => state = null;
}

final formatPainterProvider =
    NotifierProvider<FormatPainterNotifier, Map<String, Attribute>?>(
        FormatPainterNotifier.new);
