enum ProviderStatus { active, disposed }

enum DependencySource {
  /// Dependencies detected from static analysis (CLI tool)
  static,

  /// JSON was loaded but provider name doesn't match
  nameMismatch,

  /// No dependency metadata available - CLI tool not used
  none,
}

class ProviderInfo {
  final String id;
  final String name;
  final Map<String, dynamic> value;
  final ProviderStatus status;
  final List<String> dependencies;
  final DependencySource dependenciesSource;
  final DateTime? dependenciesLoadedAt;
  final DateTime? dependenciesGeneratedAt;

  ProviderInfo({
    required this.id,
    required this.name,
    required this.value,
    required this.status,
    this.dependencies = const [],
    this.dependenciesSource = DependencySource.none,
    this.dependenciesLoadedAt,
    this.dependenciesGeneratedAt,
  });

  String? _valueStringCache;

  /// Get string representation of value for display
  String getValueString() {
    if (_valueStringCache != null) return _valueStringCache!;

    // If it has 'string', use that
    return _valueStringCache = _formatValueForDisplay(value);
  }

  String _formatValueForDisplay(Map<String, dynamic> data) {
    // Check if the value is a "wrapped" metadata Map
    final bool isWrapped = data.containsKey('type') ||
        data.containsKey('value') ||
        data.containsKey('items') ||
        data.containsKey('entries') ||
        data.containsKey('string');

    if (!isWrapped) {
      return _safeToString(data);
    }

    if (data.containsKey('value')) {
      return _safeToString(data['value']);
    } else if (data.containsKey('items')) {
      final items = data['items'] as List;
      return '[${items.length} items]';
    } else if (data.containsKey('entries')) {
      final entries = data['entries'] as List;
      return '{${entries.length} entries}';
    } else if (data.containsKey('string')) {
      return data['string'] as String;
    }

    return _safeToString(data);
  }

  String _safeToString(dynamic value) {
    if (value == null) return 'null';
    if (value is String) return value;
    if (value is num || value is bool) return value.toString();

    if (value is List) {
      if (value.length > 5) {
        return '[${value.take(5).map((e) => _safeToString(e)).join(', ')}, ...]';
      }
      return value.toString();
    }
    if (value is Map) {
      if (value.length > 3) {
        final entries = value.entries
            .take(3)
            .map((e) => '${e.key}: ${_safeToString(e.value)}')
            .join(', ');
        return '{$entries, ...}';
      }
      return value.toString();
    }
    return value.toString();
  }
}
