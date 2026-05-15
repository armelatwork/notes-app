import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';

const kTableEmbedType = 'table';

/// Embeds a read-only table pasted from an external source.
/// Data format: JSON-encoded `List<List<String>>` (rows × cols).
class NoteTableEmbedBuilder extends EmbedBuilder {
  const NoteTableEmbedBuilder();

  @override
  String get key => kTableEmbedType;

  @override
  Widget build(BuildContext context, EmbedContext embedContext) {
    final raw = embedContext.node.value.data as String;
    final rows = (jsonDecode(raw) as List)
        .map((r) => (r as List).map((c) => c.toString()).toList())
        .toList();
    return _TableWidget(rows: rows);
  }
}

class _TableWidget extends StatelessWidget {
  final List<List<String>> rows;
  const _TableWidget({required this.rows});

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    final cols = rows.map((r) => r.length).fold(0, (a, b) => a > b ? a : b);
    final colWidths = List<TableColumnWidth>.filled(
        cols, const IntrinsicColumnWidth());

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Table(
          border: TableBorder.all(
            color: scheme.outlineVariant,
            width: 1,
          ),
          columnWidths: {
            for (var i = 0; i < cols; i++) i: colWidths[i],
          },
          defaultVerticalAlignment: TableCellVerticalAlignment.middle,
          children: rows.asMap().entries.map((entry) {
            final isHeader = entry.key == 0;
            return TableRow(
              decoration: BoxDecoration(
                color: isHeader
                    ? scheme.surfaceContainerHighest
                    : (entry.key.isOdd
                        ? scheme.surfaceContainerLow
                        : scheme.surface),
              ),
              children: _padRow(entry.value, cols).map((cell) {
                return Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  child: Text(
                    cell,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight:
                          isHeader ? FontWeight.w600 : FontWeight.normal,
                    ),
                  ),
                );
              }).toList(),
            );
          }).toList(),
        ),
      ),
    );
  }

  List<String> _padRow(List<String> row, int cols) {
    if (row.length >= cols) return row;
    return [...row, ...List.filled(cols - row.length, '')];
  }
}
