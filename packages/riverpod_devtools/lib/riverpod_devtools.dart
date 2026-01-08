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
/// - Tracks all preceding providers in a wave, not just immediate predecessor
/// - Uses confidence scoring based on observation frequency
/// - Prunes false positives that stop appearing
///
/// Improvements:
/// - Higher minimum occurrence threshold (2) to reduce false positives
/// - Tracks observation and non-observation counts for confidence scoring
/// - Decays confidence for dependencies not observed recently
/// - Detects both direct and some indirect dependencies within waves
///
/// Limitations:
/// - Not perfect; false positives are still possible
/// - Cannot detect dependencies until providers update
/// - Cross-wave indirect dependencies may not be detected
class _DependencyTracker {
  // Provider ID -> Confirmed dependency provider names with confidence scores
  final Map<String, Map<String, double>> _confirmedDependencies = {};

  // Provider ID -> Candidate dependencies with positive/negative observation counts
  final Map<String, Map<String, _DependencyStats>> _candidateDependencies = {};

  // Track the current update wave (batch)
  final List<_UpdateEvent> _currentBatch = [];
  DateTime? _lastUpdateTime;
  static const _batchWindowMs =
      100; // Updates within 100ms are considered the same wave

  // Minimum number of observations to confirm a dependency
  static const _minConfirmations = 2;

  // Confidence threshold for confirmed dependencies
  static const _confidenceThreshold = 0.6;

  // Maximum number of waves to track for decay
  static const _maxWavesForDecay = 50;
  int _waveCount = 0;

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

    _waveCount++;

    // Track which providers appeared in this wave
    final providersInWave = updateEvents.map((e) => e.providerId).toSet();

    // In a wave, providers updated later likely depend on those updated earlier
    // Track ALL preceding providers, not just immediate predecessor
    for (var i = 1; i < updateEvents.length; i++) {
      final current = updateEvents[i];
      final currentId = current.providerId;

      // Consider all providers that updated before this one
      for (var j = 0; j < i; j++) {
        final previous = updateEvents[j];

        // Skip self-references
        if (currentId == previous.providerId) continue;

        // Record positive observation (this provider depends on the previous one)
        final stats = _candidateDependencies
            .putIfAbsent(currentId, () => {})
            .putIfAbsent(previous.providerName, () => _DependencyStats());

        stats.positiveObservations++;
        stats.lastObservedWave = _waveCount;
      }

      // Track negative observations: providers in wave that did NOT precede this one
      // This helps identify false positives
      for (final entry in _candidateDependencies[currentId]?.entries ?? <MapEntry<String, _DependencyStats>>[]) {
        final candidateName = entry.key;
        final stats = entry.value;

        // Find if this candidate appeared in the current wave
        final candidateInWave = updateEvents.any((e) => e.providerName == candidateName);

        // If candidate was in wave but didn't precede current, it's a negative observation
        if (candidateInWave) {
          final candidatePreceded = updateEvents
              .sublist(0, i)
              .any((e) => e.providerName == candidateName);

          if (!candidatePreceded) {
            stats.negativeObservations++;
          }
        }
      }
    }

    // Apply decay to old dependencies
    _applyDecay();

    // Confirm dependencies from candidates
    _confirmDependencies();
  }

  /// Apply decay to dependencies not observed recently
  void _applyDecay() {
    for (final entry in _candidateDependencies.entries) {
      final candidates = entry.value;

      // Remove candidates that haven't been observed in recent waves
      candidates.removeWhere((name, stats) {
        final wavesSinceObservation = _waveCount - stats.lastObservedWave;
        return wavesSinceObservation > _maxWavesForDecay;
      });
    }
  }

  /// Determine confirmed dependencies from candidates using confidence scoring
  void _confirmDependencies() {
    _confirmedDependencies.clear();

    for (final entry in _candidateDependencies.entries) {
      final providerId = entry.key;
      final candidates = entry.value;

      final confirmed = <String, double>{};

      for (final candidate in candidates.entries) {
        final name = candidate.key;
        final stats = candidate.value;

        // Calculate confidence score
        // Confidence = positive / (positive + negative)
        final total = stats.positiveObservations + stats.negativeObservations;
        if (total == 0) continue;

        final confidence = stats.positiveObservations / total;

        // Confirm if we have enough observations and high confidence
        if (stats.positiveObservations >= _minConfirmations &&
            confidence >= _confidenceThreshold) {
          confirmed[name] = confidence;
        }
      }

      if (confirmed.isNotEmpty) {
        _confirmedDependencies[providerId] = confirmed;
      }
    }
  }

  /// Get confirmed dependencies for the specified provider
  List<String> getDependencies(String providerId) {
    // Process the current wave first
    _processBatch();

    // Return dependency names sorted by confidence (highest first)
    final deps = _confirmedDependencies[providerId];
    if (deps == null) return [];

    final sortedDeps = deps.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return sortedDeps.map((e) => e.key).toList();
  }

  /// Get confidence score for a specific dependency
  double getConfidence(String providerId, String dependencyName) {
    return _confirmedDependencies[providerId]?[dependencyName] ?? 0.0;
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
    _waveCount = 0;
  }
}

/// Statistics for tracking dependency observations
class _DependencyStats {
  int positiveObservations = 0; // Times this dependency was observed
  int negativeObservations = 0; // Times it should have appeared but didn't
  int lastObservedWave = 0; // Last wave number when this was observed
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
          result['items'] = value.map(_serializeValue).toList();
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
              'value': _serializeValue(entry.value),
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
          result['items'] = value.map(_serializeValue).toList();
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
}
