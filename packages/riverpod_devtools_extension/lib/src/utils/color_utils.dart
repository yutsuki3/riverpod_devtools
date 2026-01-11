import 'package:flutter/material.dart';
import '../models/event_type.dart';

Color getEventColor(EventType type, bool isDark) {
  switch (type) {
    case EventType.added:
      return isDark ? const Color(0xFF81C784) : const Color(0xFF4CAF50);
    case EventType.updated:
      return isDark ? const Color(0xFF64B5F6) : const Color(0xFF2196F3);
    case EventType.disposed:
      return isDark ? const Color(0xFF9E9E9E) : const Color(0xFF757575);
  }
}

Color getValueColor(dynamic value, ThemeData theme) {
  if (value == null) return theme.colorScheme.onSurfaceVariant;
  final isDark = theme.brightness == Brightness.dark;

  if (value is String) {
    return isDark
        ? const Color(0xFFCE9178) // VS Code String
        : const Color(0xFFA31515); // VS Code Light String (Deep Red)
  }
  if (value is num) {
    return isDark
        ? const Color(0xFFB5CEA8) // VS Code Number
        : const Color(0xFF098658); // VS Code Light Number (Deep Green)
  }
  if (value is bool) {
    return isDark
        ? const Color(0xFF569CD6) // VS Code Keyword/Constant
        : const Color(0xFF0000FF); // VS Code Light Keyword (Blue)
  }
  return theme.colorScheme.onSurface;
}
