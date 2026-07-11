import 'package:flutter/material.dart';
import '../../utils/json_diff.dart';

/// Renders a [JsonDiffNode] tree with per-line change highlighting:
/// green = added, red = removed, amber = changed (old → new), dim = same.
class JsonDiffView extends StatelessWidget {
  final JsonDiffNode root;

  /// Hide unchanged leaves so only the differences (plus the interior nodes
  /// on the way to them) show. Toggled by the diff dialog.
  final bool changesOnly;

  const JsonDiffView({
    super.key,
    required this.root,
    this.changesOnly = false,
  });

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (final child in root.children) {
      _build(context, child, 0, rows);
    }
    if (rows.isEmpty) {
      return Text(
        changesOnly ? 'No differences' : 'No values',
        style: TextStyle(
          fontSize: 11,
          fontStyle: FontStyle.italic,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: rows,
    );
  }

  void _build(
    BuildContext context,
    JsonDiffNode node,
    int depth,
    List<Widget> out,
  ) {
    if (changesOnly && !node.hasChange) return;

    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final (color, marker) = _styleFor(node.kind, isDark);

    if (node.isLeaf) {
      out.add(_row(
        depth: depth,
        marker: marker,
        color: color,
        content: _leafSpans(node, color, theme),
      ));
      return;
    }

    // Interior node: header line then children.
    out.add(_row(
      depth: depth,
      marker: marker,
      color: color,
      content: [
        TextSpan(
          text: node.key.isEmpty ? '(root)' : node.key,
          style: TextStyle(fontWeight: FontWeight.w600, color: color),
        ),
      ],
    ));
    for (final child in node.children) {
      _build(context, child, depth + 1, out);
    }
  }

  Widget _row({
    required int depth,
    required String marker,
    required Color color,
    required List<InlineSpan> content,
  }) {
    return Padding(
      padding: EdgeInsets.only(left: depth * 14.0, top: 1, bottom: 1),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 12,
            child: Text(
              marker,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
          ),
          Expanded(
            child: Text.rich(
              TextSpan(
                style: const TextStyle(fontSize: 11),
                children: content,
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<InlineSpan> _leafSpans(
      JsonDiffNode node, Color color, ThemeData theme) {
    final keyLabel = node.key.isEmpty ? '' : '${node.key}: ';
    switch (node.kind) {
      case JsonDiffKind.changed:
        return [
          TextSpan(text: keyLabel, style: TextStyle(color: color)),
          TextSpan(
            text: _fmt(node.oldValue),
            style: TextStyle(
              color: color,
              decoration: TextDecoration.lineThrough,
            ),
          ),
          TextSpan(text: '  →  ', style: TextStyle(color: color)),
          TextSpan(
            text: _fmt(node.newValue),
            style: TextStyle(color: color, fontWeight: FontWeight.w600),
          ),
        ];
      case JsonDiffKind.added:
        return [
          TextSpan(text: keyLabel, style: TextStyle(color: color)),
          TextSpan(text: _fmt(node.newValue), style: TextStyle(color: color)),
        ];
      case JsonDiffKind.removed:
        return [
          TextSpan(text: keyLabel, style: TextStyle(color: color)),
          TextSpan(text: _fmt(node.oldValue), style: TextStyle(color: color)),
        ];
      case JsonDiffKind.unchanged:
        return [
          TextSpan(text: keyLabel, style: TextStyle(color: color)),
          TextSpan(text: _fmt(node.newValue), style: TextStyle(color: color)),
        ];
    }
  }

  (Color, String) _styleFor(JsonDiffKind kind, bool isDark) {
    switch (kind) {
      case JsonDiffKind.added:
        return (
          isDark ? const Color(0xFF86EFAC) : const Color(0xFF2E7D32),
          '+',
        );
      case JsonDiffKind.removed:
        return (
          isDark ? const Color(0xFFFFB4AB) : const Color(0xFFD32F2F),
          '−',
        );
      case JsonDiffKind.changed:
        return (
          isDark ? const Color(0xFFFFD54F) : const Color(0xFFE65100),
          '~',
        );
      case JsonDiffKind.unchanged:
        return (
          isDark
              ? Colors.white.withValues(alpha: 0.45)
              : Colors.black.withValues(alpha: 0.45),
          ' ',
        );
    }
  }

  String _fmt(Object? value) {
    if (value == null) return 'null';
    if (value is String) return '"$value"';
    if (value is Map || value is List) {
      final s = value.toString();
      return s.length > 120 ? '${s.substring(0, 120)}…' : s;
    }
    return value.toString();
  }
}
