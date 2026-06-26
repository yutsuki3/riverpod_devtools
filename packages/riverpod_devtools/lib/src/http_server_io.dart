import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';

class RiverpodDevToolsHttpServer {
  RiverpodDevToolsHttpServer({int maxBufferSize = 1000})
      : _maxBufferSize = maxBufferSize;

  final int _maxBufferSize;
  final List<Map<String, Object?>> _buffer = [];
  HttpServer? _server;

  Future<void> start() async {
    try {
      _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 8788);
      _server!.listen(_handleRequest, onError: (_) {});
    } catch (error, stackTrace) {
      developer.log(
        'riverpod_devtools: failed to start the local HTTP server on port '
        '8788. The get_riverpod_logs MCP tool will not be able to connect '
        'until this app is restarted with the port free.',
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
      _buffer.removeAt(0);
    }
    _buffer.add(event);
  }

  void clearEvents() {
    _buffer.clear();
  }

  Future<void> _handleRequest(HttpRequest request) async {
    try {
      if (request.method == 'GET' && request.uri.path == '/logs') {
        final json =
            jsonEncode(_buffer, toEncodable: (obj) => obj.toString());
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
