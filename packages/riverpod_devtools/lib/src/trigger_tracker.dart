/// Infers which recent provider updates likely triggered a dependent
/// provider's update.
///
/// Riverpod rebuilds dependents synchronously (or within the same frame)
/// after a dependency changes, so an update of provider P that lands right
/// after an update of one of P's static dependencies was almost certainly
/// caused by it. This tracker keeps a small window of recent updates and
/// intersects it with the static dependency list on each new update.
///
/// The result is a heuristic — static dependencies + temporal proximity —
/// and is labeled as inferred in the event payload rather than presented
/// as proven causation.
class UpdateTriggerTracker {
  UpdateTriggerTracker({
    this.windowMs = defaultWindowMs,
    this.capacity = defaultCapacity,
  });

  /// How far back (in milliseconds) an update can be and still count as a
  /// trigger. Synchronous rebuilds land well under 1ms after their trigger;
  /// the margin covers frame scheduling without pulling in unrelated
  /// updates.
  static const int defaultWindowMs = 50;

  /// Maximum number of recent updates retained.
  static const int defaultCapacity = 32;

  final int windowMs;
  final int capacity;

  final List<_RecentUpdate> _recent = [];

  /// Returns the recent updates (newest first) that are in [dependencies]
  /// and happened within [windowMs] of [nowMs], as
  /// `{'provider': name, 'seq': seq}` maps ready for the event payload.
  /// At most one entry per provider (the most recent one) is returned.
  List<Map<String, Object?>> triggersFor(
    String providerName,
    List<String> dependencies,
    int nowMs,
  ) {
    if (dependencies.isEmpty || _recent.isEmpty) return const [];

    final seen = <String>{};
    final triggers = <Map<String, Object?>>[];
    for (var i = _recent.length - 1; i >= 0; i--) {
      final update = _recent[i];
      if (nowMs - update.timeMs > windowMs) break;
      if (update.provider == providerName) continue;
      if (!dependencies.contains(update.provider)) continue;
      if (!seen.add(update.provider)) continue;
      triggers.add({'provider': update.provider, 'seq': update.seq});
    }
    return triggers;
  }

  /// Records that [providerName] updated with event sequence [seq] at
  /// [nowMs], evicting entries outside the window or over capacity.
  void recordUpdate(String providerName, int seq, int nowMs) {
    _recent.removeWhere((update) => nowMs - update.timeMs > windowMs);
    if (_recent.length >= capacity) _recent.removeAt(0);
    _recent.add(_RecentUpdate(providerName, seq, nowMs));
  }
}

class _RecentUpdate {
  const _RecentUpdate(this.provider, this.seq, this.timeMs);

  final String provider;
  final int seq;
  final int timeMs;
}
