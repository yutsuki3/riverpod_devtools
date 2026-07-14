import 'dart:async';

/// The list of discovered apps, as returned by the port-range scan. Each entry
/// is a `/ping` payload (at least `{'port': int, ...}`).
typedef DiscoveredApps = List<Map<String, Object?>>;

/// Caches the result of MCP app discovery (the 8788–8797 port scan) for a short
/// window, so a burst of tool calls in one AI session does not re-ping every
/// port on every call.
///
/// - [get] returns the cached scan while it is fresh (younger than [ttl]),
///   otherwise runs [discover] and caches the result.
/// - [refresh] always runs [discover] and primes the cache. Use it for the
///   explicit "what apps are running?" request, which must not return stale
///   data.
/// - [invalidate] drops the cached entry so the next [get] re-scans. Call it
///   when a request to a previously discovered port fails, so an app that was
///   restarted onto a different port is picked up instead of being retried
///   against the dead port.
///
/// Behavior is unchanged versus scanning every time — the cache only affects
/// *when* [discover] runs, never *what* a resolved port talks to.
class AppDiscoveryCache {
  AppDiscoveryCache({
    required this.discover,
    this.ttl = const Duration(seconds: 5),
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  /// Runs the actual port-range scan. Injected so it can be faked in tests.
  final Future<DiscoveredApps> Function() discover;

  /// How long a scan result stays fresh.
  final Duration ttl;

  final DateTime Function() _now;

  DiscoveredApps? _apps;
  DateTime? _at;

  /// Returns the cached scan if still fresh, otherwise scans and caches.
  Future<DiscoveredApps> get() async {
    final apps = _apps;
    final at = _at;
    if (apps != null && at != null && _now().difference(at) < ttl) {
      return apps;
    }
    return refresh();
  }

  /// Forces a fresh scan and stores it as the current cache entry.
  Future<DiscoveredApps> refresh() async {
    final fresh = await discover();
    _apps = fresh;
    _at = _now();
    return fresh;
  }

  /// Drops the cached entry; the next [get] will re-scan.
  void invalidate() {
    _apps = null;
    _at = null;
  }
}
