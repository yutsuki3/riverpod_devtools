enum ProviderStatus { active, disposed }

/// One dependency of a provider with the detail the static analyzer
/// extracted: how it is consumed (`watch` / `read` / `listen`) and where.
/// Sent by the observer on provider_added events.
class DependencyDetail {
  final String providerName;

  /// `watch`, `read`, or `listen`; null when the payload predates detail
  /// support.
  final String? type;
  final String? file;
  final int? line;

  const DependencyDetail({
    required this.providerName,
    this.type,
    this.file,
    this.line,
  });
}

enum DependencySource {
  /// Dependencies detected from static analysis (CLI tool)
  static,

  /// The dependency JSON was found but failed to parse (see
  /// [ProviderInfo.dependenciesLoadError] for the reason)
  loadError,

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

  /// Why loading the dependency JSON failed (from the observer's
  /// `dependenciesLoadError` event field). Only set when
  /// [dependenciesSource] is [DependencySource.loadError].
  final String? dependenciesLoadError;

  /// Error details (`type`, `message`, `stackTrace`) from the most recent
  /// provider_failed event. Null while the provider is healthy — cleared
  /// when a later add/update event arrives.
  final Map<String, dynamic>? lastError;

  /// Dependency kind + source location per dependency (from
  /// provider_added events). Empty when the observer predates detail
  /// support — fall back to [dependencies].
  final List<DependencyDetail> dependencyDetails;

  /// For a `.family` instance, the base family name shared across
  /// instances (e.g. `userProvider`); null for ordinary providers. Used
  /// to group family instances in the provider list.
  final String? family;

  /// For a `.family` instance, the string form of its argument (e.g.
  /// `1`); null for ordinary providers.
  final String? argument;

  ProviderInfo({
    required this.id,
    required this.name,
    required this.value,
    required this.status,
    this.dependencies = const [],
    this.dependenciesSource = DependencySource.none,
    this.dependenciesLoadedAt,
    this.dependenciesGeneratedAt,
    this.dependenciesLoadError,
    this.lastError,
    this.dependencyDetails = const [],
    this.family,
    this.argument,
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
