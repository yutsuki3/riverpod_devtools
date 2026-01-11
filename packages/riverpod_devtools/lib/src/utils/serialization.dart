import 'dart:convert';

/// Serializes a value to a structured JSON format for DevTools
Map<String, Object?> serializeValue(Object? value) {
  if (value == null) {
    return {
      'type': 'null',
      'value': null,
    };
  }

  // Capture toString() early
  final stringValue = value.toString();

  // Try JSON serialization first
  try {
    final encoded = jsonEncode(value);
    return {
      'type': value.runtimeType.toString(),
      'value': jsonDecode(encoded), // Store as decoded JSON for structure
    };
  } catch (e) {
    // Check if the object has a toJson() method
    try {
      final dynamic obj = value;
      // ignore: avoid_dynamic_calls
      final json = obj.toJson();
      if (json is Map<String, dynamic>) {
        final encoded = jsonEncode(json);
        return {
          'type': value.runtimeType.toString(),
          'value': jsonDecode(encoded),
        };
      }
    } catch (_) {
      // toJson() doesn't exist or failed, continue with manual extraction
    }

    // Try to extract useful information based on type
    final Map<String, Object?> result = {
      'type': value.runtimeType.toString(),
      'string': stringValue,
    };

    // For collections, try to serialize elements
    // We do this BEFORE _parseToString to avoid hijacking List.toString()
    if (value is List) {
      // Recursively serialize list elements
      try {
        result['items'] = value.map(serializeValue).toList();
        return result;
      } catch (_) {
        // If we can't serialize items, just keep the string representation
      }
    } else if (value is Map) {
      // Recursively serialize map entries
      try {
        result['entries'] = value.entries.map((entry) {
          return {
            'key': entry.key.toString(),
            'value': serializeValue(entry.value),
          };
        }).toList();
        return result;
      } catch (_) {
        // If we can't serialize entries, keep the string representation
        result['type'] = 'Map';
        result['string'] = value.toString();
        return result;
      }
    } else if (value is Set) {
      // Recursively serialize set elements
      try {
        result['items'] = value.map(serializeValue).toList();
        return result;
      } catch (_) {
        // If we can't serialize items, just keep the string representation
      }
    }

    // Try to parse the toString() representation for custom classes
    final parsed = _parseToString(stringValue);
    if (parsed != null) {
      return {
        'type': value.runtimeType.toString(),
        'value': parsed,
      };
    }

    // For AsyncValue from Riverpod
    if (stringValue.startsWith('AsyncData')) {
      result['asyncState'] = 'data';
    } else if (stringValue.startsWith('AsyncLoading')) {
      result['asyncState'] = 'loading';
    } else if (stringValue.startsWith('AsyncError')) {
      result['asyncState'] = 'error';
    }

    return result;
  }
}

/// Parses a string representation of an object (e.g., from toString())
/// into a structured Map if it follows the "ClassName(prop: val, ...)" pattern.
Map<String, Object?>? _parseToString(String s) {
  s = s.trim();
  if (s.isEmpty) return null;

  // Guard: actual lists or maps output by toString() should not be parsed as custom classes
  if (s.startsWith('[') || s.startsWith('{')) return null;

  final openParen = s.indexOf('(');
  final closeParen = s.lastIndexOf(')');

  if (openParen == -1 || closeParen == -1 || closeParen <= openParen) {
    return null;
  }

  // Basic check for "ClassName(...)"
  final content = s.substring(openParen + 1, closeParen).trim();
  if (content.isEmpty) return {};

  final result = <String, Object?>{};
  final parts = _splitRecursive(content, ',');

  for (final part in parts) {
    final colonIndex = part.indexOf(':');
    if (colonIndex != -1) {
      final key = part.substring(0, colonIndex).trim();
      final valStr = part.substring(colonIndex + 1).trim();
      result[key] = _parseValue(valStr);
    }
  }

  return result.isNotEmpty ? result : null;
}

/// Helper to split by separator while respecting parentheses/brackets
List<String> _splitRecursive(String s, String separator) {
  final result = <String>[];
  var current = StringBuffer();
  var depth = 0;

  for (var i = 0; i < s.length; i++) {
    final char = s[i];
    if (char == '(' || char == '[' || char == '{') {
      depth++;
    } else if (char == ')' || char == ']' || char == '}') {
      depth--;
    }

    if (depth == 0 && char == separator) {
      result.add(current.toString().trim());
      current = StringBuffer();
    } else {
      current.write(char);
    }
  }
  if (current.isNotEmpty) {
    result.add(current.toString().trim());
  }
  return result;
}

/// Minimal value wrapper for parsed strings
Object? _parseValue(String s) {
  s = s.trim();
  if (s == 'null') return null;
  if (s == 'true') return true;
  if (s == 'false') return false;

  // Try numeric
  final numVal = num.tryParse(s);
  if (numVal != null) return numVal;

  // Try ClassName(...) recursive parse
  final nestedObject = _parseToString(s);
  if (nestedObject != null) {
    return {
      'type': s.substring(0, s.indexOf('(')).trim(),
      'value': nestedObject,
    };
  }

  // Try List [...] parse
  if (s.startsWith('[') && s.endsWith(']')) {
    final content = s.substring(1, s.length - 1).trim();
    if (content.isEmpty) return [];

    final parts = _splitRecursive(content, ',');
    return parts.map(_parseValue).toList();
  }

  // Fallback to string (strip quotes if present)
  if (s.startsWith('"') && s.endsWith('"') && s.length >= 2) {
    return s.substring(1, s.length - 1);
  }
  if (s.startsWith("'") && s.endsWith("'") && s.length >= 2) {
    return s.substring(1, s.length - 1);
  }

  return s;
}
