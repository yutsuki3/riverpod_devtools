// Token-efficient reshaping of the raw HTTP payloads for the MCP (AI-facing)
// layer. The app's HTTP endpoints return a verbose, GUI-oriented structure
// (every event repeats static-dependency metadata, and each value is a
// nested `{type, string, items/entries, ...}` tree). Relaying that verbatim
// floods an AI's context with low-signal tokens, so these pure functions
// collapse it to the essentials while keeping a `view: 'full'` escape hatch
// for the complete data.
//
// All functions here are pure (JSON in, JSON out) so they are cheap to unit
// test exhaustively.
library;

/// Values longer than this (as their compact string form) are truncated, and
/// structured `value` payloads larger than this (JSON-encoded) are summarized
/// instead of inlined.
const int _maxValueChars = 200;

/// Collapses one serialized value — the `{type, string, items/entries,
/// value, asyncState}` tree produced by `serializeValue` — to a concise form:
/// a scalar or short string where possible, a small inline structure when it
/// stays under [_maxValueChars], or a `Type(n)` / `{…n}` summary otherwise.
/// An `asyncState` (loading/data/error) is preserved as a wrapper.
Object? compactValue(Object? value) {
  if (value is! Map) return value;

  final asyncState = value['asyncState'];
  final lossy = value['lossy'] == true;
  final core = _compactCore(value);
  if (asyncState is String || lossy) {
    return {
      if (asyncState is String) 'asyncState': asyncState,
      if (lossy) 'lossy': true,
      'value': core,
    };
  }
  return core;
}

Object? _compactCore(Map<Object?, Object?> value) {
  // toJson()/parsed/null path: a direct (already-sanitized) value.
  if (value.containsKey('value')) {
    return _capStructured(value['value']);
  }
  // Collections keep both a `string` (toString) and structured items/entries.
  // The toString is the most compact readable form; fall back to a count
  // summary when it is too long to be worth the tokens.
  final string = value['string'];
  if (string is String) {
    if (string.length <= _maxValueChars) return string;
    final type = value['type'];
    if (value['items'] is List) {
      return '$type(${(value['items'] as List).length} items)';
    }
    if (value['entries'] is List) {
      return '$type(${(value['entries'] as List).length} entries)';
    }
    return '${string.substring(0, _maxValueChars - 1)}…';
  }
  // No string: summarize whatever structure is present.
  if (value['items'] is List) {
    return '${value['type']}(${(value['items'] as List).length} items)';
  }
  if (value['entries'] is List) {
    return '${value['type']}(${(value['entries'] as List).length} entries)';
  }
  return value['type'];
}

/// Inlines a primitive/small structure as-is, or summarizes it when its
/// JSON form would be large.
Object? _capStructured(Object? value) {
  if (value == null || value is num || value is bool) return value;
  if (value is String) {
    return value.length <= _maxValueChars
        ? value
        : '${value.substring(0, _maxValueChars - 1)}…';
  }
  final measured = _estimateLength(value);
  if (measured <= _maxValueChars) return value;
  if (value is List) return '[…${value.length} items]';
  if (value is Map) return '{…${value.length} keys}';
  return value.toString();
}

/// Cheap size estimate of a JSON-ish value without allocating its full
/// encoding (stops counting once the cap is exceeded).
int _estimateLength(Object? value, [int budget = _maxValueChars + 1]) {
  if (budget <= 0) return _maxValueChars + 1;
  if (value == null) return 4;
  if (value is String) return value.length + 2;
  if (value is num || value is bool) return value.toString().length;
  if (value is List) {
    var total = 2;
    for (final item in value) {
      total += _estimateLength(item, budget - total) + 1;
      if (total > budget) return total;
    }
    return total;
  }
  if (value is Map) {
    var total = 2;
    for (final entry in value.entries) {
      total += '${entry.key}'.length + 3;
      total += _estimateLength(entry.value, budget - total) + 1;
      if (total > budget) return total;
    }
    return total;
  }
  return value.toString().length;
}

/// The short event kind, dropping the `provider_` prefix (e.g.
/// `provider_updated` → `updated`).
String _shortType(Object? type) {
  final s = type?.toString() ?? '';
  return s.startsWith('provider_') ? s.substring('provider_'.length) : s;
}

/// Slims one raw event to the fields that carry signal per token: seq, short
/// type, provider, timestamp, the compacted value(s), inferred triggers, and
/// (only when the name is ambiguous) the instanceId needed to target it.
/// Drops the repeated static-dependency metadata, providerId, family/argument
/// (derivable from the name), and — for failures — the stack trace.
Map<String, Object?> compactEvent(Map<Object?, Object?> event) {
  final type = _shortType(event['type']);
  final out = <String, Object?>{
    if (event['seq'] != null) 'seq': event['seq'],
    'type': type,
    'provider': event['provider'],
    if (event['nameIsUnique'] == false && event['instanceId'] != null)
      'instanceId': event['instanceId'],
    if (event['timestamp'] != null) 'ts': event['timestamp'],
  };

  switch (type) {
    case 'added':
      out['value'] = compactValue(event['value']);
    case 'updated':
      out['prev'] = compactValue(event['previousValue']);
      out['value'] = compactValue(event['newValue']);
      final triggers = _compactTriggers(event['triggeredBy']);
      if (triggers.isNotEmpty) out['triggeredBy'] = triggers;
    case 'failed':
      out['error'] = _compactError(event['error']);
    case 'disposed':
      break;
    default:
      // Unknown kind: keep whatever value-ish fields exist, compacted.
      if (event.containsKey('value')) {
        out['value'] = compactValue(event['value']);
      }
  }
  return out;
}

/// Trigger references collapsed to just the provider names (the full
/// `{provider, seq}` form is available in the `full` view).
List<Object?> _compactTriggers(Object? triggeredBy) {
  if (triggeredBy is! List) return const [];
  return [
    for (final t in triggeredBy)
      if (t is Map && t['provider'] != null) t['provider'],
  ];
}

/// Error reduced to type + message; the (potentially long) stack trace is
/// dropped in the compact view.
Map<String, Object?>? _compactError(Object? error) {
  if (error is! Map) return null;
  return {
    if (error['type'] != null) 'type': error['type'],
    if (error['message'] != null) 'message': error['message'],
  };
}

/// Maps a raw event list to compact events.
List<Map<String, Object?>> compactEvents(List<Object?> events) => [
      for (final e in events)
        if (e is Map) compactEvent(e.cast<Object?, Object?>()),
    ];

/// Aggregates a raw event list into a per-provider summary — counts by kind,
/// plus each provider's most recent value — so an AI can grasp "what
/// happened" without reading the whole stream. Providers are ordered by
/// total activity (most active first), then by name.
Map<String, Object?> summarizeEvents(List<Object?> events) {
  final byProvider = <String, _ProviderTally>{};
  var counted = 0;
  for (final raw in events) {
    if (raw is! Map) continue;
    counted++;
    final name = raw['provider']?.toString() ?? 'Unknown';
    final tally = byProvider.putIfAbsent(name, () => _ProviderTally(name));
    tally.record(raw);
  }

  final providers = byProvider.values.toList()
    ..sort((a, b) {
      final byTotal = b.total.compareTo(a.total);
      return byTotal != 0 ? byTotal : a.name.compareTo(b.name);
    });

  return {
    'eventCount': counted,
    'providerCount': providers.length,
    'providers': [for (final p in providers) p.toJson()],
  };
}

class _ProviderTally {
  _ProviderTally(this.name);
  final String name;
  int added = 0, updated = 0, failed = 0, disposed = 0;
  int _lastSeq = -1;
  Object? _lastValue;

  int get total => added + updated + failed + disposed;

  void record(Map<Object?, Object?> event) {
    switch (_shortType(event['type'])) {
      case 'added':
        added++;
        _maybeValue(event, event['value']);
      case 'updated':
        updated++;
        _maybeValue(event, event['newValue']);
      case 'failed':
        failed++;
      case 'disposed':
        disposed++;
    }
  }

  void _maybeValue(Map<Object?, Object?> event, Object? value) {
    final seq = event['seq'];
    // Prefer the highest seq; fall back to last-seen when seq is absent.
    if (seq is int) {
      if (seq >= _lastSeq) {
        _lastSeq = seq;
        _lastValue = compactValue(value);
      }
    } else {
      _lastValue = compactValue(value);
    }
  }

  Map<String, Object?> toJson() => {
        'provider': name,
        if (added > 0) 'added': added,
        if (updated > 0) 'updated': updated,
        if (failed > 0) 'failed': failed,
        if (disposed > 0) 'disposed': disposed,
        if (_lastValue != null) 'lastValue': _lastValue,
      };
}

/// Slims one `/providers` snapshot entry: name, status, compact value, and
/// (only when ambiguous) the instanceId. Drops providerId, the static
/// dependency list, and the internal seq.
Map<String, Object?> compactStateEntry(Map<Object?, Object?> entry) {
  return {
    'provider': entry['provider'],
    if (entry['nameIsUnique'] == false && entry['instanceId'] != null)
      'instanceId': entry['instanceId'],
    'status': entry['status'],
    'value': compactValue(entry['value']),
    if (entry['error'] != null) 'error': _compactError(entry['error']),
    if (entry['lastUpdated'] != null) 'lastUpdated': entry['lastUpdated'],
  };
}

/// Maps a raw `/providers` snapshot list to compact entries.
List<Map<String, Object?>> compactState(List<Object?> entries) => [
      for (final e in entries)
        if (e is Map) compactStateEntry(e.cast<Object?, Object?>()),
    ];

/// Slims the `/graph` payload to the topology an AI reasons over: node
/// names with their status (dropped when `unknown`), and edges as
/// dependent → dependency + kind. The per-edge source location
/// (file/line/column) and the `hasStaticMetadata`/`generatedAt` bookkeeping
/// are dropped — they are available in the `full` view.
Map<String, Object?> compactGraph(Map<Object?, Object?> graph) {
  final rawNodes = graph['nodes'];
  final rawEdges = graph['edges'];
  return {
    'nodes': [
      if (rawNodes is List)
        for (final n in rawNodes)
          if (n is Map)
            {
              'name': n['name'],
              if (n['status'] != null && n['status'] != 'unknown')
                'status': n['status'],
            },
    ],
    'edges': [
      if (rawEdges is List)
        for (final e in rawEdges)
          if (e is Map)
            {
              'from': e['from'],
              'to': e['to'],
              if (e['type'] != null) 'type': e['type'],
            },
    ],
    // Keep the setup hint (why `edges` is empty) — it's the whole point of
    // surfacing it, and it must survive the compact view.
    if (graph['edgesNote'] != null) 'edgesNote': graph['edgesNote'],
  };
}

/// Rounds an updates-per-second rate to 2 decimals, as a plain number.
num _round2(Object? rate) {
  final value = rate is num ? rate : 0;
  return num.parse(value.toStringAsFixed(2));
}

/// Slims the `/stats` payload: drops the 24-bucket sparkline array (a GUI
/// concern) and the redundant/near-zero fields, keeping the health signals
/// (update volume + rate, churn, load min/avg/max, and the warning flags).
/// Providers are ordered most-interesting-first: flagged, then by rate,
/// then by name — so "which provider is misbehaving?" is answered from the
/// top of the list.
Map<String, Object?> compactStats(Map<Object?, Object?> stats) {
  final rawProviders = stats['providers'];
  final providers = <Map<String, Object?>>[
    if (rawProviders is List)
      for (final p in rawProviders)
        if (p is Map) _compactStatEntry(p.cast<Object?, Object?>()),
  ]..sort(_compareStatInterest);
  return {'providers': providers};
}

Map<String, Object?> _compactStatEntry(Map<Object?, Object?> p) {
  final highFrequency = p['isHighFrequency'] == true;
  final slowLoading = p['isSlowLoading'] == true;
  final total = p['totalUpdateCount'];
  final churn = p['churnCount'];
  final loadSamples = p['loadSampleCount'];
  return {
    'provider': p['provider'],
    if (total is int && total > 0) 'updates': total,
    if (p['updatesPerSecond'] is num && (p['updatesPerSecond'] as num) > 0)
      'rate': _round2(p['updatesPerSecond']),
    if (churn is int && churn > 0) 'churn': churn,
    if (loadSamples is int && loadSamples > 0)
      'load': {
        'minMs': p['minLoadMs'],
        'avgMs': p['avgLoadMs'],
        'maxMs': p['maxLoadMs'],
        'n': loadSamples,
      },
    if (highFrequency) 'highFrequency': true,
    if (slowLoading) 'slowLoading': true,
  };
}

/// Orders compact stat entries most-interesting-first: any warning flag,
/// then higher rate, then name.
int _compareStatInterest(Map<String, Object?> a, Map<String, Object?> b) {
  int warnRank(Map<String, Object?> e) =>
      (e['highFrequency'] == true || e['slowLoading'] == true) ? 0 : 1;
  final byWarn = warnRank(a).compareTo(warnRank(b));
  if (byWarn != 0) return byWarn;
  final byRate =
      ((b['rate'] as num?) ?? 0).compareTo((a['rate'] as num?) ?? 0);
  if (byRate != 0) return byRate;
  return '${a['provider']}'.compareTo('${b['provider']}');
}
