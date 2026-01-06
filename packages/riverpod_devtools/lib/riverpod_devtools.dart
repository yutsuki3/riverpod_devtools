library riverpod_devtools;

import 'dart:convert';
import 'dart:developer' as developer;

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Dependency tracker for providers (Beta feature)
///
/// This class learns dependencies by observing update patterns.
/// Since Riverpod 3.x restricts access to internal APIs,
/// we use a learning-based approach.
///
/// How it works:
/// - Updates within 100ms are treated as one "wave"
/// - Providers updated later in a wave likely depend on those updated earlier
/// - Initial loads (didAddProvider) are excluded; only actual updates (didUpdateProvider) are learned
///
/// Limitations:
/// - Not perfect; false positives are possible
/// - Cannot detect dependencies until providers update
/// - Only detects direct dependencies (not indirect ones)
class _DependencyTracker {
  // Provider ID -> Confirmed dependency provider names
  final Map<String, Set<String>> _confirmedDependencies = {};

  // Provider ID -> Candidate dependencies with occurrence count
  final Map<String, Map<String, int>> _candidateDependencies = {};

  // Track the current update wave (batch)
  final List<_UpdateEvent> _currentBatch = [];
  DateTime? _lastUpdateTime;
  static const _batchWindowMs =
      100; // Updates within 100ms are considered the same wave

  /// Called when a provider is updated
  void recordUpdate(String providerId, String providerName,
      {required bool isUpdate}) {
    final now = DateTime.now();

    // Check if a new wave has started
    if (_lastUpdateTime == null ||
        now.difference(_lastUpdateTime!).inMilliseconds > _batchWindowMs) {
      // Process the previous wave
      _processBatch();
      _currentBatch.clear();
    }

    _currentBatch
        .add(_UpdateEvent(providerId, providerName, now, isUpdate: isUpdate));
    _lastUpdateTime = now;
  }

  /// Process the current wave to infer dependencies
  void _processBatch() {
    if (_currentBatch.length < 2) return;

    // Filter to only didUpdateProvider events (exclude didAddProvider initial loads)
    final updateEvents = _currentBatch.where((e) => e.isUpdate).toList();

    if (updateEvents.length < 2) return;

    // In a wave, providers updated later likely depend on those updated immediately before
    for (var i = 1; i < updateEvents.length; i++) {
      final current = updateEvents[i];

      // Record only the immediate predecessor (more accurate)
      final previous = updateEvents[i - 1];

      // Skip self-references
      if (current.providerId == previous.providerId) continue;

      // Record as candidate
      _candidateDependencies.putIfAbsent(current.providerId, () => {}).update(
            previous.providerName,
            (count) => count + 1,
            ifAbsent: () => 1,
          );
    }

    // Confirm dependencies from candidates
    _confirmDependencies();
  }

  /// Determine confirmed dependencies from candidates
  void _confirmDependencies() {
    const minOccurrences =
        1; // Confirm after observing once (for faster detection)

    for (final entry in _candidateDependencies.entries) {
      final providerId = entry.key;
      final candidates = entry.value;

      final confirmed = candidates.entries
          .where((e) => e.value >= minOccurrences)
          .map((e) => e.key)
          .toSet();

      if (confirmed.isNotEmpty) {
        _confirmedDependencies[providerId] = confirmed;
      }
    }
  }

  /// Get confirmed dependencies for the specified provider
  List<String> getDependencies(String providerId) {
    // Process the current wave first
    _processBatch();

    return _confirmedDependencies[providerId]?.toList() ?? [];
  }

  /// Remove a specific provider from dependency tracking
  void removeProvider(String providerId) {
    _confirmedDependencies.remove(providerId);
    _candidateDependencies.remove(providerId);
    // Also remove from current batch
    _currentBatch.removeWhere((event) => event.providerId == providerId);
  }

  /// Clear all dependency relationships
  void clear() {
    _confirmedDependencies.clear();
    _candidateDependencies.clear();
    _currentBatch.clear();
    _lastUpdateTime = null;
  }
}

class _UpdateEvent {
  final String providerId;
  final String providerName;
  final DateTime timestamp;
  final bool
      isUpdate; // true if from didUpdateProvider, false if from didAddProvider

  _UpdateEvent(this.providerId, this.providerName, this.timestamp,
      {required this.isUpdate});
}

final _dependencyTracker = _DependencyTracker();

/// A [ProviderObserver] that sends Riverpod events to the Flutter DevTools extension.
///
/// This observer monitors the lifecycle of all providers (add, update, dispose)
/// and posts events to the developer log, which the Riverpod DevTools extension listens to.
///
/// Usage:
/// ```dart
/// ProviderScope(
///   observers: [
///     RiverpodDevToolsObserver(),
///   ],
///   child: MyApp(),
/// );
/// ```
final class RiverpodDevToolsObserver extends ProviderObserver {
  @override
  void didAddProvider(
    covariant Object context,
    Object? value, [
    covariant Object? arg3, // Container in Riverpod 2.x, unused in 3.0
  ]) {
    // Support both Riverpod 2.x and 3.0:
    // - Riverpod 3.0: didAddProvider(ProviderObserverContext context, Object? value)
    // - Riverpod 2.x: didAddProvider(ProviderBase provider, Object? value, ProviderContainer container)
    // The optional arg3 allows accepting both 2 and 3 parameters
    final provider = _getProvider(context);
    final providerId = identityHashCode(provider).toString();
    final providerName = _getProviderName(provider);

    // Record update (for dependency learning)
    _dependencyTracker.recordUpdate(providerId, providerName, isUpdate: false);

    // Get dependencies for this provider
    final dependencies = _dependencyTracker.getDependencies(providerId);

    _postEvent('provider_added', {
      'providerId': providerId,
      'provider': providerName,
      'value': _serializeValue(value),
      'dependencies': dependencies,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    });
  }

  @override
  void didUpdateProvider(
    covariant Object context,
    Object? previousValue,
    Object? newValue, [
    covariant Object? arg4, // Container in Riverpod 2.x, unused in 3.0
  ]) {
    // Support both Riverpod 2.x and 3.0:
    // - Riverpod 3.0: didUpdateProvider(ProviderObserverContext context, Object? previousValue, Object? newValue)
    // - Riverpod 2.x: didUpdateProvider(ProviderBase provider, Object? previousValue, Object? newValue, ProviderContainer container)
    // The optional arg4 allows accepting both 3 and 4 parameters
    final provider = _getProvider(context);
    final providerId = identityHashCode(provider).toString();
    final providerName = _getProviderName(provider);

    // Record update (for dependency learning)
    _dependencyTracker.recordUpdate(providerId, providerName, isUpdate: true);

    // Get dependencies for this provider
    final dependencies = _dependencyTracker.getDependencies(providerId);

    _postEvent('provider_updated', {
      'providerId': providerId,
      'provider': providerName,
      'previousValue': _serializeValue(previousValue),
      'newValue': _serializeValue(newValue),
      'dependencies': dependencies,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    });
  }

  @override
  void didDisposeProvider(
    covariant Object context, [
    covariant Object? arg2, // Container in Riverpod 2.x, unused in 3.0
  ]) {
    // Support both Riverpod 2.x and 3.0:
    // - Riverpod 3.0: didDisposeProvider(ProviderObserverContext context)
    // - Riverpod 2.x: didDisposeProvider(ProviderBase provider, ProviderContainer container)
    // The optional arg2 allows accepting both 1 and 2 parameters
    final provider = _getProvider(context);
    final providerId = identityHashCode(provider).toString();

    // Clean up dependency tracking data to prevent memory leaks
    _dependencyTracker.removeProvider(providerId);

    _postEvent('provider_disposed', {
      'providerId': providerId,
      'provider': _getProviderName(provider),
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    });
  }

  /// Extracts the provider from either ProviderObserverContext (3.0) or ProviderBase (2.x)
  dynamic _getProvider(Object arg) {
    // In Riverpod 3.0, arg is ProviderObserverContext which has a 'provider' property
    // In Riverpod 2.x, arg is directly ProviderBase
    try {
      // Try to access the 'provider' property (3.0 API)
      final dynamic context = arg;
      // ignore: avoid_dynamic_calls
      return context.provider;
    } catch (_) {
      // If that fails, it's the 2.x API where arg is already the provider
      return arg;
    }
  }

  /// Gets the provider name safely
  String _getProviderName(dynamic provider) {
    try {
      // ignore: avoid_dynamic_calls
      final name = provider.name;
      return name?.toString() ?? provider.runtimeType.toString();
    } catch (_) {
      return provider.runtimeType.toString();
    }
  }

  void _postEvent(String kind, Map<String, Object?> data) {
    developer.postEvent('riverpod:$kind', data);
  }

  /// Serializes a value to a structured JSON format for DevTools
  Map<String, Object?> _serializeValue(Object? value) {
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

      // Try to parse the toString() representation for custom classes
      final parsed = _parseToString(stringValue);
      if (parsed != null) {
        return {
          'type': value.runtimeType.toString(),
          'value': parsed,
        };
      }

      // Try to extract useful information based on type
      final Map<String, Object?> result = {
        'type': value.runtimeType.toString(),
        'string': stringValue,
      };

      // For collections, try to serialize elements
      if (value is List) {
        // Try to serialize list elements
        try {
          result['items'] = value.map((item) {
            try {
              // Try JSON encode for each item
              final encoded = jsonEncode(item);
              return {
                'type': item.runtimeType.toString(),
                'value': jsonDecode(encoded),
              };
            } catch (_) {
              // If item is not JSON serializable, just store its string representation
              return {
                'type': item.runtimeType.toString(),
                'string': item.toString(),
              };
            }
          }).toList();
        } catch (_) {
          // If we can't serialize items, just keep the string representation
        }
      } else if (value is Map) {
        // Try to serialize map entries
        try {
          result['entries'] = value.entries.map((entry) {
            final key = entry.key;
            final val = entry.value;
            try {
              // Try JSON encode for the value
              final encoded = jsonEncode(val);
              return {
                'key': key.toString(),
                'value': {
                  'type': val.runtimeType.toString(),
                  'value': jsonDecode(encoded),
                },
              };
            } catch (_) {
              // If value is not JSON serializable, store its string representation
              return {
                'key': key.toString(),
                'value': {
                  'type': val.runtimeType.toString(),
                  'string': val.toString(),
                },
              };
            }
          }).toList();
        } catch (_) {
          // If we can't serialize entries, keep the string representation
          result['type'] = 'Map';
          result['string'] = value.toString();
        }
      } else if (value is Set) {
        // Try to serialize set elements (convert to list for serialization)
        try {
          result['items'] = value.map((item) {
            try {
              // Try JSON encode for each item
              final encoded = jsonEncode(item);
              return {
                'type': item.runtimeType.toString(),
                'value': jsonDecode(encoded),
              };
            } catch (_) {
              // If item is not JSON serializable, just store its string representation
              return {
                'type': item.runtimeType.toString(),
                'string': item.toString(),
              };
            }
          }).toList();
        } catch (_) {
          // If we can't serialize items, just keep the string representation
        }
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
}
