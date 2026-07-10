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

  /// Returns buffered events, optionally filtered by provider name and
  /// truncated to the most recent [limit] entries (chronological order is
  /// preserved).
  List<Map<String, Object?>> eventsFor({String? provider, int? limit}) {
    Iterable<Map<String, Object?>> events = _buffer;
    if (provider != null && provider.isNotEmpty) {
      events = events.where((event) => event['provider'] == provider);
    }
    final list = events.toList(growable: false);
    if (limit != null && limit >= 0 && list.length > limit) {
      return list.sublist(list.length - limit);
    }
    return list;
  }

  Future<void> _handleRequest(HttpRequest request) async {
    try {
      if (request.method == 'GET' && request.uri.path == '/logs') {
        final params = request.uri.queryParameters;
        final events = eventsFor(
          provider: params['provider'],
          limit: int.tryParse(params['limit'] ?? ''),
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
