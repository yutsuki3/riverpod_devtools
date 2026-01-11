import 'dart:async';

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
class DependencyTracker {
  // Provider ID -> Confirmed dependency provider names
  final Map<String, Set<String>> _confirmedDependencies = {};

  // Provider ID -> Candidate dependencies with occurrence count
  final Map<String, Map<String, int>> _candidateDependencies = {};

  // Track the current update wave (batch)
  final List<_UpdateEvent> _currentBatch = [];
  DateTime? _lastUpdateTime;
  static const _batchWindowMs =
      100; // Updates within 100ms are considered the same wave

  Timer? _flushTimer;

  /// Called when a provider is updated
  void recordUpdate(String providerId, String providerName,
      {required bool isUpdate}) {
    final now = DateTime.now();

    // Check if a new wave has started (time gap exceeded)
    // Note: We also rely on the timer to process the trailing end of a wave.
    if (_lastUpdateTime != null &&
        now.difference(_lastUpdateTime!).inMilliseconds > _batchWindowMs) {
      _processBatch();
      _currentBatch.clear();
    }

    _currentBatch
        .add(_UpdateEvent(providerId, providerName, now, isUpdate: isUpdate));
    _lastUpdateTime = now;

    // Schedule flush for the end of this wave
    _flushTimer?.cancel();
    _flushTimer = Timer(const Duration(milliseconds: _batchWindowMs), () {
      _processBatch();
      _currentBatch.clear();
      _lastUpdateTime = null; // Reset ensures next event starts fresh check
    });
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
    // Reverted to 1 for faster responsiveness, as strict 2 caused "not working" feeling
    const minOccurrences = 1;

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
  ///
  /// This returns the currently known dependencies based on observed update patterns.
  /// It does not trigger a new analysis batch.
  List<String> getDependencies(String providerId) {
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
    _flushTimer?.cancel();
    _confirmedDependencies.clear();
    _candidateDependencies.clear();
    _currentBatch.clear();
    _lastUpdateTime = null;
  }

  /// Dispose of resources (cancel timers)
  void dispose() {
    _flushTimer?.cancel();
    _flushTimer = null;
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
