/// Serializes a value to a structured JSON format for DevTools
Map<String, Object?> serializeValue(
  Object? value, {
  int depth = 0,
  Set<Object>? visited,
}) {
  const maxDepth = 10;
  // Breadth/size caps. Depth alone doesn't bound the work per event: a single
  // huge List/Map/Set, or an object with a very long toString(), is otherwise
  // fully serialized on *every* provider add/update (for both previous and new
  // value). These caps keep per-event cost and payload size bounded; anything
  // trimmed is flagged with `lossy: true` (plus `totalItems` for collections)
  // so both the UI and the AI know truncation happened.
  const maxItems = 100;
  const maxStringChars = 4000;

  if (value == null) {
    return {
      'type': 'null',
      'value': null,
    };
  }

  // Depth limit. Checked before cycle tracking so the early return can't
  // leave `value` in `visited` — a leak that would make a later,
  // non-cyclic occurrence of the same object be misreported as a cycle.
  // A depth-exceeded value is not recursed into, so it needs no tracking.
  if (depth > maxDepth) {
    return {
      'type': value.runtimeType.toString(),
      'value': '<Max Depth Exceeded>',
      'lossy': true,
    };
  }

  // Cycle detection. Identity-based on purpose: cycles are a property of the
  // object graph, and identity checks avoid invoking potentially deep (or
  // even cyclic) user-defined ==/hashCode implementations on every event.
  visited ??= Set<Object>.identity();
  // Primitives and strings are safe, no need to track
  if (value is! num && value is! bool && value is! String) {
    if (visited.contains(value)) {
      return {
        'type': value.runtimeType.toString(),
        'value': '<Cyclic Reference>',
        'lossy': true,
      };
    }
    visited.add(value);
  }

  // Helper to continue serialization
  Map<String, Object?> recurse(Object? val) {
    return serializeValue(val, depth: depth + 1, visited: visited);
  }

  try {
    // Check if the object has a toJson() method first (most specific).
    // Do this before computing toString() so objects that serialize via
    // toJson() never pay for building their (possibly large) string form.
    try {
      final dynamic obj = value;
      // ignore: avoid_dynamic_calls
      final json = obj.toJson();
      // If toJson returns a primitive or simple Map/List, use it directly
      // Avoid re-encoding unless we need to ensure it's pure JSON safe,
      // but typically we can trust toJson or handle the result recursively.
      if (json is Map || json is List) {
        // Sanitize the result: toJson() implementations may nest values that
        // json.encode can't handle (DateTime, enums, custom objects), and
        // developer.postEvent encodes the event without a toEncodable
        // fallback — an unencodable leaf would make the whole event throw.
        return {
          'type': value.runtimeType.toString(),
          'value': _jsonSafe(json, 0),
        };
      }
    } catch (_) {
      // toJson() doesn't exist or failed
    }

    final rawString = value.toString();
    // Cap the stored string form. A long toString() is both a large payload
    // and (below) expensive to re-parse character-by-character.
    final stringTooLong = rawString.length > maxStringChars;
    final stringValue =
        stringTooLong ? '${rawString.substring(0, maxStringChars)}…' : rawString;

    // Try to extract useful information based on type
    final Map<String, Object?> result = {
      'type': value.runtimeType.toString(),
      'string': stringValue,
    };
    if (stringTooLong) result['lossy'] = true;

    // For collections. Only the first `maxItems` elements are recursed; the
    // rest are summarized with `truncated`/`totalItems` so the payload (and the
    // work to build it) stays bounded regardless of collection size.
    if (value is List) {
      _addItems(result, value, value.length, maxItems, recurse);
      return result;
    } else if (value is Map) {
      final total = value.length;
      result['entries'] = value.entries.take(maxItems).map((entry) {
        return {
          'key': entry.key.toString(),
          'value': recurse(entry.value),
        };
      }).toList();
      _markTruncated(result, total, maxItems);
      return result;
    } else if (value is Set) {
      _addItems(result, value, value.length, maxItems, recurse);
      return result;
    }

    // For AsyncValue from Riverpod. Detect this before the toString() parsing
    // below, because e.g. 'AsyncData<int>(value: 5)' also matches the
    // "ClassName(prop: val)" pattern and would return early without it.
    String? asyncState;
    if (rawString.startsWith('AsyncData')) {
      asyncState = 'data';
    } else if (rawString.startsWith('AsyncLoading')) {
      asyncState = 'loading';
    } else if (rawString.startsWith('AsyncError')) {
      asyncState = 'error';
    }

    // Try to parse the toString() representation for custom classes. Skip the
    // (character-by-character) parse when the string was truncated: parsing a
    // cut-off "ClassName(...)" would produce misleading structure.
    if (!stringTooLong) {
      final parsed = _parseToString(rawString);
      if (parsed != null) {
        return {
          'type': value.runtimeType.toString(),
          'value': parsed,
          if (asyncState != null) 'asyncState': asyncState,
        };
      }
    }

    if (asyncState != null) {
      result['asyncState'] = asyncState;
    }

    return result;
  } finally {
    if (value is! num && value is! bool && value is! String) {
      visited.remove(value);
    }
  }
}

/// Serializes the first [maxItems] elements of [iterable] into `result['items']`
/// and flags truncation when the collection is larger.
void _addItems(
  Map<String, Object?> result,
  Iterable<Object?> iterable,
  int total,
  int maxItems,
  Map<String, Object?> Function(Object?) recurse,
) {
  result['items'] = iterable.take(maxItems).map(recurse).toList();
  _markTruncated(result, total, maxItems);
}

/// Adds `truncated`/`totalItems`/`lossy` markers when [total] exceeds [maxItems].
void _markTruncated(Map<String, Object?> result, int total, int maxItems) {
  if (total > maxItems) {
    result['truncated'] = true;
    result['totalItems'] = total;
    result['lossy'] = true;
  }
}

/// Deep-copies a toJson() result, converting any leaf that json.encode
/// cannot handle (DateTime, enums, custom objects) to its toString() form.
Object? _jsonSafe(Object? value, int depth) {
  const maxDepth = 10;
  if (value == null || value is num || value is bool || value is String) {
    return value;
  }
  if (depth > maxDepth) return value.toString();
  if (value is Map) {
    return {
      for (final entry in value.entries)
        entry.key.toString(): _jsonSafe(entry.value, depth + 1),
    };
  }
  if (value is List) {
    return [for (final item in value) _jsonSafe(item, depth + 1)];
  }
  return value.toString();
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
