import 'event_type.dart';

class ProviderEvent {
  final EventType type;
  final String providerId;
  final String providerName;
  final Map<String, dynamic>? previousValue;
  final Map<String, dynamic>? value;
  final DateTime timestamp;

  /// Unique ID for this event (used for expansion state tracking)
  late final String id;

  ProviderEvent({
    required this.type,
    required this.providerId,
    required this.providerName,
    this.previousValue,
    this.value,
    required this.timestamp,
  }) {
    // Generate unique ID based on timestamp and provider ID
    id = '${timestamp.microsecondsSinceEpoch}_$providerId';
  }

  String? _valueStringCache;
  String? _previousValueStringCache;

  /// Get string representation for display
  String getValueString() {
    if (value == null) return 'null';
    return _valueStringCache ??= _formatValueForDisplay(value!);
  }

  String getPreviousValueString() {
    if (previousValue == null) return 'null';
    return _previousValueStringCache ??= _formatValueForDisplay(previousValue!);
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
