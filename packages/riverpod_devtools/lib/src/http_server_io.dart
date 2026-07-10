import 'dart:collection';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';

import 'mcp_constants.dart';

class RiverpodDevToolsHttpServer {
  RiverpodDevToolsHttpServer({int maxBufferSize = 1000})
    : _maxBufferSize = maxBufferSize;

  final int _maxBufferSize;
  // ListQueue gives O(1) eviction at the front; a plain List would shift
  // every remaining element on each removeAt(0) once the buffer is full,
  // which runs on every provider event in the observed app.
  final ListQueue<Map<String, Object?>> _buffer = ListQueue();
  HttpServer? _server;

  Future<void> start() async {
    // Avoid binding a real socket during `flutter test` runs — consumers
    // commonly construct RiverpodDevToolsObserver() in their own widget
    // tests, and a lingering HttpServer trips flutter_test's pending-timer
    // check on tear-down.
    if (Platform.environment['FLUTTER_TEST'] == 'true') return;

    try {
      _server = await HttpServer.bind(
        InternetAddress.loopbackIPv4,
        riverpodDevToolsMcpPort,
      );
      _server!.listen(_handleRequest, onError: (_) {});
    } catch (error, stackTrace) {
      developer.log(
        'riverpod_devtools: failed to start the local HTTP server on port '
        '$riverpodDevToolsMcpPort. The get_riverpod_logs MCP tool will not '
        'be able to connect until this app is restarted with the port free.',
        name: 'riverpod_devtools',
        error: error,
        stackTrace: stackTrace,
      );
    }
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
  }

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
          .where((event) =>
              (!hasProvider || event['provider'] == provider) &&
              (!hasType || event['type'] == type))
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
      if (request.method == 'GET' && request.uri.path == '/logs') {
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
        final json = jsonEncode(events, toEncodable: (obj) => obj.toString());
        request.response
          ..statusCode = 200
          ..headers.contentType = ContentType.json
          ..write(json);
        await request.response.close();
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
}
