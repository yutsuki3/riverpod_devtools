import '../models/event_type.dart';
import '../models/provider_event.dart';

/// A provider is flagged high-frequency once its recent update rate
/// exceeds this many updates per second.
const kHighFrequencyThreshold = 10.0;

/// A provider is flagged slow-loading once any observed `loading` →
/// `data`/`error` transition takes longer than this.
const kSlowLoadThreshold = Duration(seconds: 2);

/// Width of the "recent" update-rate window.
const kRecentUpdateWindow = Duration(seconds: 10);

/// Aggregated activity/health signals for one provider, computed from its
/// event history by [computeProviderStats]. Answers "is something wrong
/// with this provider?" without eyeballing the raw event log.
class ProviderStats {
  final String providerName;

  /// Total `provider_updated` events seen (bounded by however much of the
  /// event history is retained — the ring buffer holds up to 1000 events
  /// across all providers).
  final int totalUpdateCount;

  /// `provider_updated` events within [kRecentUpdateWindow] of when the
  /// stats were computed.
  final int recentUpdateCount;

  /// [recentUpdateCount] expressed as a rate, for sorting/threshold checks.
  final double updatesPerSecond;

  /// Shortest, average, and longest observed `loading` → `data`/`error`
  /// transition. All null if no such transition was observed.
  final Duration? minLoadDuration;
  final Duration? avgLoadDuration;
  final Duration? maxLoadDuration;

  /// Number of loading→resolved transitions the duration stats are based
  /// on.
  final int loadSampleCount;

  /// How many times this provider was disposed and later re-created
  /// (`provider_added` events beyond the first imply a prior dispose).
  final int churnCount;

  bool get isHighFrequency => updatesPerSecond > kHighFrequencyThreshold;
  bool get isSlowLoading =>
      maxLoadDuration != null && maxLoadDuration! > kSlowLoadThreshold;

  const ProviderStats({
    required this.providerName,
    required this.totalUpdateCount,
    required this.recentUpdateCount,
    required this.updatesPerSecond,
    this.minLoadDuration,
    this.avgLoadDuration,
    this.maxLoadDuration,
    required this.loadSampleCount,
    required this.churnCount,
  });
}

/// Computes per-provider [ProviderStats] from [events] (any order — sorted
/// internally per provider). [now] anchors the "recent" window; defaults
/// to the current time.
List<ProviderStats> computeProviderStats(
  List<ProviderEvent> events, {
  DateTime? now,
}) {
  final effectiveNow = now ?? DateTime.now();

  final byProvider = <String, List<ProviderEvent>>{};
  for (final event in events) {
    byProvider.putIfAbsent(event.providerName, () => []).add(event);
  }

  final stats = <ProviderStats>[];
  for (final entry in byProvider.entries) {
    // state.events is newest-first; process oldest-first so loading/
    // resolved transitions pair up in the order they actually happened.
    final chronological = entry.value.toList()
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));

    var totalUpdates = 0;
    var recentUpdates = 0;
    var addedCount = 0;
    DateTime? loadingStartedAt;
    final loadDurations = <Duration>[];

    for (final event in chronological) {
      switch (event.type) {
        case EventType.added:
          addedCount++;
          // A fresh instance starting up can't still be mid-load from a
          // previous one.
          loadingStartedAt = null;
        case EventType.updated:
          totalUpdates++;
          if (effectiveNow.difference(event.timestamp) <= kRecentUpdateWindow) {
            recentUpdates++;
          }
        case EventType.failed:
          break;
        case EventType.disposed:
          // Don't let a load that never resolved before this instance was
          // torn down get paired with a later instance's resolution —
          // that would span the dispose/re-create gap and report a
          // meaningless duration.
          loadingStartedAt = null;
      }

      String? asyncState;
      if (event.type == EventType.added || event.type == EventType.updated) {
        asyncState = event.value?['asyncState'] as String?;
      }

      if (asyncState == 'loading') {
        loadingStartedAt = event.timestamp;
      } else if (loadingStartedAt != null &&
          (asyncState == 'data' ||
              asyncState == 'error' ||
              event.type == EventType.failed)) {
        loadDurations.add(event.timestamp.difference(loadingStartedAt));
        loadingStartedAt = null;
      }
    }

    Duration? minDuration, maxDuration, avgDuration;
    if (loadDurations.isNotEmpty) {
      minDuration = loadDurations.reduce((a, b) => a < b ? a : b);
      maxDuration = loadDurations.reduce((a, b) => a > b ? a : b);
      final totalMicros =
          loadDurations.fold<int>(0, (sum, d) => sum + d.inMicroseconds);
      avgDuration = Duration(microseconds: totalMicros ~/ loadDurations.length);
    }

    stats.add(ProviderStats(
      providerName: entry.key,
      totalUpdateCount: totalUpdates,
      recentUpdateCount: recentUpdates,
      updatesPerSecond: recentUpdates / kRecentUpdateWindow.inSeconds,
      minLoadDuration: minDuration,
      avgLoadDuration: avgDuration,
      maxLoadDuration: maxDuration,
      loadSampleCount: loadDurations.length,
      churnCount: addedCount > 0 ? addedCount - 1 : 0,
    ));
  }

  stats.sort((a, b) => a.providerName.compareTo(b.providerName));
  return stats;
}
