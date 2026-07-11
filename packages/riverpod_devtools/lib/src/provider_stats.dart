/// Builds the per-provider activity/health stats JSON served by
/// `GET /stats` and the `get_provider_stats` MCP tool.
///
/// This is a separate implementation from the DevTools extension's own
/// `provider_stats.dart` (the two packages don't share code): this one
/// aggregates the raw event JSON maps held by the local HTTP server's
/// ring buffer, rather than the extension's typed `ProviderEvent` model.
/// The aggregation rules are the same — see that file for the rationale.
library;

/// A provider is flagged high-frequency once its recent update rate
/// exceeds this many updates per second.
const kHighFrequencyThreshold = 10.0;

/// A provider is flagged slow-loading once any observed `loading` →
/// `data`/`error` transition takes longer than this.
const kSlowLoadThreshold = Duration(seconds: 2);

/// Width of the "recent" update-rate window.
const kRecentUpdateWindow = Duration(seconds: 10);

/// Window covered by the update-rate sparkline / histogram.
const kSparklineWindow = Duration(seconds: 30);

/// Number of buckets the sparkline window is divided into (oldest→newest).
const kSparklineBucketCount = 24;

/// Computes per-provider stats from raw event JSON maps (as produced by
/// the observer and buffered by `RiverpodDevToolsHttpServer`). [now]
/// anchors the "recent" window; defaults to the current time. When
/// [provider] is set, only that provider's stats are included.
Map<String, Object?> buildProviderStats(
  List<Map<String, Object?>> events, {
  DateTime? now,
  String? provider,
}) {
  final effectiveNow = now ?? DateTime.now();

  final byProvider = <String, List<Map<String, Object?>>>{};
  for (final event in events) {
    final name = event['provider'];
    if (name is! String) continue;
    if (provider != null && provider.isNotEmpty && name != provider) continue;
    byProvider.putIfAbsent(name, () => []).add(event);
  }

  final stats = <Map<String, Object?>>[];
  for (final entry in byProvider.entries) {
    // The buffer is append-ordered (oldest first), but sort explicitly so
    // this doesn't depend on that — loading/resolved transitions must
    // pair up in real chronological order.
    final chronological =
        entry.value.toList()
          ..sort((a, b) => _timestampOf(a).compareTo(_timestampOf(b)));

    var totalUpdates = 0;
    var recentUpdates = 0;
    var addedCount = 0;
    DateTime? loadingStartedAt;
    final loadDurations = <Duration>[];
    final buckets = List<int>.filled(kSparklineBucketCount, 0);

    for (final event in chronological) {
      final type = event['type'];
      final timestamp = _timestampOf(event);

      if (type == 'provider_added') {
        addedCount++;
        // A fresh instance starting up can't still be mid-load from a
        // previous one.
        loadingStartedAt = null;
      } else if (type == 'provider_updated') {
        totalUpdates++;
        if (effectiveNow.difference(timestamp) <= kRecentUpdateWindow) {
          recentUpdates++;
        }
        _addToBucket(buckets, effectiveNow, timestamp);
      } else if (type == 'provider_disposed') {
        // Don't let a load that never resolved before this instance was
        // torn down get paired with a later instance's resolution — that
        // would span the dispose/re-create gap and report a meaningless
        // duration.
        loadingStartedAt = null;
      }

      String? asyncState;
      if (type == 'provider_added') {
        asyncState = _asyncStateOf(event['value']);
      } else if (type == 'provider_updated') {
        asyncState = _asyncStateOf(event['newValue']);
      }

      if (asyncState == 'loading') {
        loadingStartedAt = timestamp;
      } else if (loadingStartedAt != null &&
          (asyncState == 'data' ||
              asyncState == 'error' ||
              type == 'provider_failed')) {
        loadDurations.add(timestamp.difference(loadingStartedAt));
        loadingStartedAt = null;
      }
    }

    Duration? minDuration, maxDuration, avgDuration;
    if (loadDurations.isNotEmpty) {
      minDuration = loadDurations.reduce((a, b) => a < b ? a : b);
      maxDuration = loadDurations.reduce((a, b) => a > b ? a : b);
      final totalMicros = loadDurations.fold<int>(
        0,
        (sum, d) => sum + d.inMicroseconds,
      );
      avgDuration = Duration(microseconds: totalMicros ~/ loadDurations.length);
    }

    final updatesPerSecond = recentUpdates / kRecentUpdateWindow.inSeconds;
    stats.add({
      'provider': entry.key,
      'totalUpdateCount': totalUpdates,
      'recentUpdateCount': recentUpdates,
      'updatesPerSecond': updatesPerSecond,
      'minLoadMs': minDuration?.inMilliseconds,
      'avgLoadMs': avgDuration?.inMilliseconds,
      'maxLoadMs': maxDuration?.inMilliseconds,
      'loadSampleCount': loadDurations.length,
      'churnCount': addedCount > 0 ? addedCount - 1 : 0,
      'updateBuckets': buckets,
      'isHighFrequency': updatesPerSecond > kHighFrequencyThreshold,
      'isSlowLoading': maxDuration != null && maxDuration > kSlowLoadThreshold,
    });
  }

  stats.sort(
    (a, b) => (a['provider'] as String).compareTo(b['provider'] as String),
  );
  return {'providers': stats, 'generatedAt': effectiveNow.toIso8601String()};
}

/// Increments the sparkline bucket for an update at [timestamp], mapping
/// the newest edge of the window to the last bucket. Updates older than
/// [kSparklineWindow] are ignored.
void _addToBucket(List<int> buckets, DateTime now, DateTime timestamp) {
  final ageMs = now.difference(timestamp).inMilliseconds;
  if (ageMs < 0 || ageMs > kSparklineWindow.inMilliseconds) return;
  final bucketMs = kSparklineWindow.inMilliseconds / kSparklineBucketCount;
  var index = kSparklineBucketCount - 1 - (ageMs / bucketMs).floor();
  if (index < 0) index = 0;
  if (index >= kSparklineBucketCount) index = kSparklineBucketCount - 1;
  buckets[index]++;
}

DateTime _timestampOf(Map<String, Object?> event) {
  final raw = event['timestamp'];
  if (raw is int) return DateTime.fromMillisecondsSinceEpoch(raw);
  return DateTime.fromMillisecondsSinceEpoch(0);
}

String? _asyncStateOf(Object? value) {
  if (value is Map) return value['asyncState'] as String?;
  return null;
}
