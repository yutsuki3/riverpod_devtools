import 'dart:collection';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';

import 'graph_builder.dart';
import 'mcp_constants.dart';
import 'provider_stats.dart';
import 'utils/coerce_int.dart';

class RiverpodDevToolsHttpServer {
  RiverpodDevToolsHttpServer({int maxBufferSize = 1000})
    : _maxBufferSize = maxBufferSize;

  final int _maxBufferSize;
  // ListQueue gives O(1) eviction at the front; a plain List would shift
  // every remaining element on each removeAt(0) once the buffer is full,
  // which runs on every provider event in the observed app.
  final ListQueue<Map<String, Object?>> _buffer = ListQueue();

  /// Latest state per live provider, serving `GET /providers`. Entries are
  /// written on add/update/fail events and removed on dispose, so the map
  /// only holds providers that currently exist — unlike the ring buffer it
  /// cannot grow past the number of live providers, and it survives
  /// [clearEvents] (clearing the history does not change current state).
  final Map<String, Map<String, Object?>> _providerSnapshot = {};

  HttpServer? _server;

  /// The port this server actually bound, or null if it isn't running.
  /// May differ from [riverpodDevToolsMcpPort] when an earlier port in the
  /// range was already taken by another debug app.
  int? get boundPort => _server?.port;

  /// Executes state commands (invalidate/refresh) arriving via
  /// `POST /commands` from the MCP server. Wired up by the observer.
  Map<String, Object?> Function(String action, String provider, Object? value)?
      commandHandler;

  Future<void> start() async {
    // Avoid binding a real socket during `flutter test` runs — consumers
    // commonly construct RiverpodDevToolsObserver() in their own widget
    // tests, and a lingering HttpServer trips flutter_test's pending-timer
    // check on tear-down.
    if (Platform.environment['FLUTTER_TEST'] == 'true') return;

    // Try each port in the range so a second debug app doesn't silently
    // fail to expose its events — it just takes the next free port, which
    // the MCP server discovers by probing the range.
    for (final port in riverpodDevToolsMcpPorts) {
      try {
        _server = await HttpServer.bind(InternetAddress.loopbackIPv4, port);
        _server!.listen(_handleRequest, onError: (_) {});
        if (port != riverpodDevToolsMcpPort) {
          developer.log(
            'riverpod_devtools: port $riverpodDevToolsMcpPort was busy; '
            'this app is exposing its Riverpod events on port $port instead. '
            'MCP tools discover it automatically.',
            name: 'riverpod_devtools',
          );
        }
        return;
      } on SocketException {
        // Port in use (likely another debug app or an unrelated process);
        // try the next one.
        continue;
      } catch (error, stackTrace) {
        developer.log(
          'riverpod_devtools: unexpected error binding port $port.',
          name: 'riverpod_devtools',
          error: error,
          stackTrace: stackTrace,
        );
        return;
      }
    }

    developer.log(
      'riverpod_devtools: no free port found in '
      '$riverpodDevToolsMcpPort–${riverpodDevToolsMcpPort + riverpodDevToolsMcpPortCount - 1}. '
      'MCP tools will not be able to connect to this app.',
      name: 'riverpod_devtools',
    );
  }

  void stop() {
    _server?.close();
    _server = null;
  }

  /// [isStateReset] only matters for `provider_disposed`: the disposal is a
  /// state reset from an `invalidate` / `refresh` command rather than a
  /// removal. Riverpod sends no update when the rebuild yields an equal value,
  /// so the snapshot entry is kept instead of waiting for an event that never
  /// comes.
  void addEvent(
    Map<String, Object?> event, {
    bool isStateReset = false,
  }) {
    if (_buffer.length >= _maxBufferSize) {
      _buffer.removeFirst();
    }
    _buffer.add(event);
    _updateSnapshot(event, isStateReset: isStateReset);
  }

  void _updateSnapshot(
    Map<String, Object?> event, {
    required bool isStateReset,
  }) {
    final provider = event['provider'];
    if (provider is! String) return;
    // Key the snapshot by the stable, session-unique instanceId — NOT the
    // display name, which can be shared by several providers (unnamed, or a
    // duplicated `name:`). Keying by name silently dropped all but one of
    // them. Fall back to the name only for payloads from older observers
    // that predate instanceId.
    final key = event['instanceId'] is String
        ? event['instanceId'] as String
        : provider;

    Map<String, Object?> entry(String status, Object? value) => {
      'provider': provider,
      if (event['instanceId'] != null) 'instanceId': event['instanceId'],
      if (event['nameIsUnique'] == false) 'nameIsUnique': false,
      'providerId': event['providerId'],
      'status': status,
      'value': value,
      'dependencies': event['dependencies'],
      'lastUpdated': event['timestamp'],
      'seq': event['seq'],
    };

    switch (event['type']) {
      case 'provider_added':
        _providerSnapshot[key] = entry('active', event['value']);
      case 'provider_updated':
        _providerSnapshot[key] = entry('active', event['newValue']);
      case 'provider_failed':
        // The element still exists and holds its previous value; record the
        // failure alongside it.
        _providerSnapshot[key] = entry(
          'failed',
          _providerSnapshot[key]?['value'],
        )..['error'] = event['error'];
      case 'provider_disposed':
        if (!isStateReset) _providerSnapshot.remove(key);
    }
  }

  /// Current state of live providers (sorted by name), or just those
  /// matching [provider] when given — [provider] matches either a display
  /// name (may return several entries when the name is shared) or an exact
  /// instanceId. Empty if nothing matches / was disposed.
  List<Map<String, Object?>> providerSnapshot({String? provider}) {
    Iterable<Map<String, Object?>> entries = _providerSnapshot.values;
    if (provider != null && provider.isNotEmpty) {
      entries = entries.where(
        (e) => e['provider'] == provider || e['instanceId'] == provider,
      );
    }
    return entries.toList(growable: false)..sort(
      (a, b) => (a['provider'] as String).compareTo(b['provider'] as String),
    );
  }

  /// Runtime status per live provider (by display name), merged into the
  /// dependency graph — which is keyed on definition names. When several
  /// instances share a name, "active" wins over "failed" so the graph node
  /// isn't marked failed just because one same-named instance failed.
  Map<String, String> get _runtimeStatuses {
    final byName = <String, String>{};
    for (final entry in _providerSnapshot.values) {
      final name = entry['provider'] as String;
      final status = entry['status'] as String;
      if (byName[name] != 'active') byName[name] = status;
    }
    return byName;
  }

  void clearEvents() {
    _buffer.clear();
  }

  /// `seq` of the oldest event still buffered, or null when the buffer is
  /// empty (or holds no sequenced events). Anything older was evicted by the
  /// size cap or dropped by [clearEvents]; a client that last saw `seq` N can
  /// tell it missed events when this is greater than N + 1.
  int? get oldestSeq {
    if (_buffer.isEmpty) return null;
    final seq = _buffer.first['seq'];
    return seq is int ? seq : null;
  }

  /// Returns buffered events, optionally filtered by provider name, event
  /// [type] (e.g. `provider_failed`), and/or a timestamp window ([since] /
  /// [until], inclusive, in milliseconds since epoch) and/or to events newer
  /// than [sinceSeq] (exclusive — pass the last `seq` already seen to fetch
  /// only what came after it), truncated to the most
  /// recent [limit] entries (chronological order is preserved). A negative
  /// [limit] is treated as 0 (empty result).
  List<Map<String, Object?>> eventsFor({
    String? provider,
    String? type,
    int? limit,
    int? since,
    int? until,
    int? sinceSeq,
  }) {
    if (limit != null && limit < 0) limit = 0;
    final hasProvider = provider != null && provider.isNotEmpty;
    final hasType = type != null && type.isNotEmpty;
    final hasWindow = since != null || until != null;
    final hasSinceSeq = sinceSeq != null;
    if (hasProvider || hasType || hasWindow || hasSinceSeq) {
      bool matches(Map<String, Object?> event) {
        if (hasSinceSeq) {
          final seq = event['seq'];
          if (seq is! int || seq <= sinceSeq) return false;
        }
        if (hasProvider && event['provider'] != provider) return false;
        if (hasType && event['type'] != type) return false;
        if (hasWindow) {
          final ts = event['timestamp'];
          final tsMs = ts is int ? ts : null;
          if (since != null && (tsMs == null || tsMs < since)) return false;
          if (until != null && (tsMs == null || tsMs > until)) return false;
        }
        return true;
      }

      final list = _buffer.where(matches).toList(growable: false);
      if (limit == null || list.length <= limit) return list;
      return list.sublist(list.length - limit);
    }
    // No filter: take the tail directly so only `limit` elements are ever
    // materialized instead of copying the whole buffer first.
    if (limit == null || _buffer.length <= limit) {
      return _buffer.toList(growable: false);
    }
    return _buffer.skip(_buffer.length - limit).toList(growable: false);
  }

  /// How many events matching these filters were left out because of
  /// [limit] (which keeps only the most recent ones). 0 when nothing was cut.
  int omittedByLimit({
    String? provider,
    String? type,
    int? limit,
    int? since,
    int? until,
    int? sinceSeq,
  }) {
    if (limit == null) return 0;
    final matching = eventsFor(
      provider: provider,
      type: type,
      since: since,
      until: until,
      sinceSeq: sinceSeq,
    ).length;
    final omitted = matching - (limit < 0 ? 0 : limit);
    return omitted > 0 ? omitted : 0;
  }

  Future<void> _handleRequest(HttpRequest request) async {
    try {
      if (request.method == 'GET' && request.uri.path == '/ping') {
        // Lightweight discovery endpoint: the MCP server probes every port
        // in the range and uses this to tell instances apart.
        await _writeJson(request, {
          'riverpodDevtools': true,
          'port': _server?.port,
          'providerCount': _providerSnapshot.length,
          'eventCount': _buffer.length,
        });
      } else if (request.method == 'GET' && request.uri.path == '/logs') {
        final params = request.uri.queryParameters;

        int? limit;
        final rawLimit = params['limit'];
        if (rawLimit != null) {
          // Accept "50" and "50.0" (some clients format integers as
          // doubles); reject anything else explicitly instead of silently
          // returning the full buffer.
          limit = coerceInt(rawLimit);
          if (limit == null || limit < 0) {
            request.response
              ..statusCode = 400
              ..write('Invalid "limit": expected a non-negative integer.');
            await request.response.close();
            return;
          }
        }

        int? since, until, sinceSeq;
        for (final name in const ['since', 'until', 'sinceSeq']) {
          final raw = params[name];
          if (raw == null) continue;
          final parsed = coerceInt(raw);
          if (parsed == null) {
            request.response
              ..statusCode = 400
              ..write(
                name == 'sinceSeq'
                    ? 'Invalid "sinceSeq": expected an integer event seq.'
                    : 'Invalid "$name": expected epoch milliseconds.',
              );
            await request.response.close();
            return;
          }
          switch (name) {
            case 'since':
              since = parsed;
            case 'until':
              until = parsed;
            default:
              sinceSeq = parsed;
          }
        }

        final events = eventsFor(
          provider: params['provider'],
          type: params['type'],
          limit: limit,
          since: since,
          until: until,
          sinceSeq: sinceSeq,
        );
        // A `sinceSeq` poll that `limit` cut short would otherwise skip the
        // older events silently; report how many.
        final omitted = sinceSeq == null
            ? 0
            : omittedByLimit(
                provider: params['provider'],
                type: params['type'],
                limit: limit,
                since: since,
                until: until,
                sinceSeq: sinceSeq,
              );
        await _writeJson(
          request,
          events,
          // Lets the MCP side flag events lost to eviction/clear (or cut by
          // `limit`) without changing the response body (a plain event list).
          headers: {
            'x-riverpod-oldest-seq': '${oldestSeq ?? ''}',
            if (omitted > 0) 'x-riverpod-omitted-by-limit': '$omitted',
          },
        );
      } else if (request.method == 'GET' && request.uri.path == '/providers') {
        final snapshot = providerSnapshot(
          provider: request.uri.queryParameters['provider'],
        );
        await _writeJson(request, snapshot);
      } else if (request.method == 'GET' && request.uri.path == '/graph') {
        final graph = buildDependencyGraph(
          runtimeStatus: _runtimeStatuses,
          focusProvider: request.uri.queryParameters['provider'],
        );
        await _writeJson(request, graph);
      } else if (request.method == 'GET' && request.uri.path == '/stats') {
        final stats = buildProviderStats(
          _buffer.toList(growable: false),
          provider: request.uri.queryParameters['provider'],
        );
        await _writeJson(request, stats);
      } else if (request.method == 'POST' && request.uri.path == '/commands') {
        await _handleCommand(request);
      } else if (request.method == 'DELETE' && request.uri.path == '/logs') {
        clearEvents();
        request.response.statusCode = 204;
        await request.response.close();
      } else {
        request.response.statusCode = 404;
        await request.response.close();
      }
    } catch (_) {
      try {
        request.response.statusCode = 500;
        await request.response.close();
      } catch (_) {}
    }
  }

  /// `POST /commands` with `{"action": "invalidate"|"refresh"|"set",
  /// "provider": name, "value"?: <primitive>}`. Always answers 200 with a JSON body
  /// carrying `status: ok | error` — the MCP server relays the body as-is.
  Future<void> _handleCommand(HttpRequest request) async {
    final handler = commandHandler;
    if (handler == null) {
      await _writeJson(request, {
        'status': 'error',
        'message': 'Command handler not ready (no observer attached).',
      });
      return;
    }

    Object? payload;
    try {
      payload = jsonDecode(await utf8.decoder.bind(request).join());
    } catch (_) {
      // Falls through to the shape check below.
    }
    if (payload is! Map ||
        payload['action'] is! String ||
        payload['provider'] is! String) {
      await _writeJson(request, {
        'status': 'error',
        'message':
            'Expected JSON body {"action": "invalidate"|"refresh"|"set", '
            '"provider": "<name>", "value"?: <primitive>}.',
      });
      return;
    }

    final action = payload['action'] as String;
    // The "set" action carries the new value; require the key so an omitted
    // value is a clear error rather than a silent set-to-null.
    if (action == 'set' && !payload.containsKey('value')) {
      await _writeJson(request, {
        'status': 'error',
        'message': 'The "set" action requires a "value" field '
            '(a primitive: number, boolean, string, or null).',
      });
      return;
    }

    await _writeJson(
      request,
      handler(action, payload['provider'] as String, payload['value']),
    );
  }

  Future<void> _writeJson(
    HttpRequest request,
    Object payload, {
    Map<String, String> headers = const {},
  }) async {
    final json = jsonEncode(payload, toEncodable: (obj) => obj.toString());
    request.response
      ..statusCode = 200
      ..headers.contentType = ContentType.json;
    headers.forEach(request.response.headers.set);
    request.response.write(json);
    await request.response.close();
  }
}
