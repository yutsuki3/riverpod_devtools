import 'dart:collection';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';

import 'graph_builder.dart';
import 'mcp_constants.dart';
import 'provider_stats.dart';

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
  Map<String, Object?> Function(String action, String provider)? commandHandler;

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

  void addEvent(Map<String, Object?> event) {
    if (_buffer.length >= _maxBufferSize) {
      _buffer.removeFirst();
    }
    _buffer.add(event);
    _updateSnapshot(event);
  }

  void _updateSnapshot(Map<String, Object?> event) {
    final provider = event['provider'];
    if (provider is! String) return;

    Map<String, Object?> entry(String status, Object? value) => {
      'provider': provider,
      'providerId': event['providerId'],
      'status': status,
      'value': value,
      'dependencies': event['dependencies'],
      'lastUpdated': event['timestamp'],
      'seq': event['seq'],
    };

    switch (event['type']) {
      case 'provider_added':
        _providerSnapshot[provider] = entry('active', event['value']);
      case 'provider_updated':
        _providerSnapshot[provider] = entry('active', event['newValue']);
      case 'provider_failed':
        // The element still exists and holds its previous value; record the
        // failure alongside it.
        _providerSnapshot[provider] = entry(
          'failed',
          _providerSnapshot[provider]?['value'],
        )..['error'] = event['error'];
      case 'provider_disposed':
        _providerSnapshot.remove(provider);
    }
  }

  /// Current state of live providers (sorted by name), or just [provider]'s
  /// entry when given — empty if it does not exist / was disposed.
  List<Map<String, Object?>> providerSnapshot({String? provider}) {
    if (provider != null && provider.isNotEmpty) {
      final entry = _providerSnapshot[provider];
      return entry == null ? const [] : [entry];
    }
    return _providerSnapshot.values.toList(growable: false)..sort(
      (a, b) => (a['provider'] as String).compareTo(b['provider'] as String),
    );
  }

  /// Runtime status per live provider, merged into the dependency graph.
  Map<String, String> get _runtimeStatuses => {
    for (final entry in _providerSnapshot.entries)
      entry.key: entry.value['status'] as String,
  };

  void clearEvents() {
    _buffer.clear();
  }

  /// Returns buffered events, optionally filtered by provider name and/or
  /// event [type] (e.g. `provider_failed`), truncated to the most recent
  /// [limit] entries (chronological order is preserved). A negative
  /// [limit] is treated as 0 (empty result).
  List<Map<String, Object?>> eventsFor({
    String? provider,
    String? type,
    int? limit,
  }) {
    if (limit != null && limit < 0) limit = 0;
    final hasProvider = provider != null && provider.isNotEmpty;
    final hasType = type != null && type.isNotEmpty;
    if (hasProvider || hasType) {
      final list = _buffer
          .where(
            (event) =>
                (!hasProvider || event['provider'] == provider) &&
                (!hasType || event['type'] == type),
          )
          .toList(growable: false);
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
          limit = int.tryParse(rawLimit) ?? num.tryParse(rawLimit)?.toInt();
          if (limit == null || limit < 0) {
            request.response
              ..statusCode = 400
              ..write('Invalid "limit": expected a non-negative integer.');
            await request.response.close();
            return;
          }
        }

        final events = eventsFor(
          provider: params['provider'],
          type: params['type'],
          limit: limit,
        );
        await _writeJson(request, events);
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

  /// `POST /commands` with `{"action": "invalidate"|"refresh",
  /// "provider": name}`. Always answers 200 with a JSON body carrying
  /// `status: ok | error` — the MCP server relays the body as-is.
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
            'Expected JSON body '
            '{"action": "invalidate"|"refresh", "provider": "<name>"}.',
      });
      return;
    }

    await _writeJson(
      request,
      handler(payload['action'] as String, payload['provider'] as String),
    );
  }

  Future<void> _writeJson(HttpRequest request, Object payload) async {
    final json = jsonEncode(payload, toEncodable: (obj) => obj.toString());
    request.response
      ..statusCode = 200
      ..headers.contentType = ContentType.json
      ..write(json);
    await request.response.close();
  }
}
