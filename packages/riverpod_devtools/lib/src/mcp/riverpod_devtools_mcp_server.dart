import 'dart:async';
import 'dart:convert';
import 'dart:io' as io;

import 'package:dart_mcp/server.dart';

import '../mcp_constants.dart';

base class RiverpodDevToolsMcpServer extends MCPServer with ToolsSupport {
  RiverpodDevToolsMcpServer(super.channel)
    : super.fromStreamChannel(
        implementation: Implementation(
          name: 'riverpod-devtools-mcp',
          version: '0.1.0',
        ),
        instructions:
            'Exposes Riverpod provider event logs from a running Flutter app in debug mode. '
            'The Flutter app must have riverpod_devtools configured with RiverpodDevToolsObserver.',
      ) {
    registerTool(_getRiverpodLogsTool, _getRiverpodLogs);
    registerTool(_clearRiverpodLogsTool, _clearRiverpodLogs);
  }

  final _getRiverpodLogsTool = Tool(
    name: 'get_riverpod_logs',
    description:
        'Get Riverpod provider state-change events from the running Flutter app. '
        'This is NOT a general app log or console output — it captures only Riverpod '
        'provider lifecycle events: provider_added (initial value), provider_updated '
        '(previous/new value diff), and provider_disposed. '
        'Use this when investigating Riverpod state bugs, unexpected re-builds, '
        'or provider lifecycle issues. '
        'The buffer can hold up to 1000 events; prefer passing "limit" (and '
        '"provider" when you know which provider you are investigating) to '
        'keep the response small. '
        'Requires the app to be running in debug mode (flutter run).',
    inputSchema: Schema.object(
      properties: {
        'limit': Schema.int(
          description:
              'Return only the most recent N events (after applying the '
              'provider filter). Omit to return the full buffer.',
          minimum: 1,
        ),
        'provider': Schema.string(
          description:
              'Return only events for the provider with this exact name '
              '(e.g. "counterProvider").',
        ),
      },
    ),
  );

  final _clearRiverpodLogsTool = Tool(
    name: 'clear_riverpod_logs',
    description:
        'Clear the Riverpod provider state-change event buffer. '
        'Use this before reproducing a specific bug or flow so that only '
        'the relevant events appear in the next get_riverpod_logs call.',
    inputSchema: Schema.object(properties: {}),
  );

  FutureOr<CallToolResult> _getRiverpodLogs(CallToolRequest request) async {
    final arguments = request.arguments ?? const {};
    final queryParameters = <String, String>{
      // dart_mcp validates arguments against the schema before this runs,
      // rejecting strings and fractional numbers — but whole doubles
      // (e.g. 50.0, as some clients encode integers) pass validation and
      // arrive here as num, so normalize via toInt().
      if (arguments['limit'] case final num limit) 'limit': '${limit.toInt()}',
      if (arguments['provider'] case final String provider
          when provider.isNotEmpty)
        'provider': provider,
    };
    return _request(
      'GET',
      '/logs',
      queryParameters: queryParameters,
      (body) => CallToolResult(content: [TextContent(text: body)]),
    );
  }

  FutureOr<CallToolResult> _clearRiverpodLogs(CallToolRequest request) async {
    return _request(
      'DELETE',
      '/logs',
      (_) =>
          CallToolResult(content: [TextContent(text: 'Log buffer cleared.')]),
    );
  }

  Future<CallToolResult> _request(
    String method,
    String path,
    CallToolResult Function(String body) onSuccess, {
    Map<String, String> queryParameters = const {},
  }) async {
    try {
      final client = io.HttpClient();
      try {
        final req = await client
            .openUrl(
              method,
              Uri(
                scheme: 'http',
                host: 'localhost',
                port: riverpodDevToolsMcpPort,
                path: path,
                queryParameters:
                    queryParameters.isEmpty ? null : queryParameters,
              ),
            )
            .timeout(const Duration(seconds: 5));
        final response = await req.close();
        final body = await response.transform(utf8.decoder).join();
        return onSuccess(body);
      } finally {
        client.close();
      }
    } catch (e) {
      return CallToolResult(
        content: [
          TextContent(
            text:
                'Error connecting to Flutter app: $e\n\n'
                'Make sure:\n'
                '1. The Flutter app is running in debug mode: flutter run\n'
                '2. riverpod_devtools is listed in pubspec.yaml dependencies\n'
                '3. RiverpodDevToolsObserver() is added to ProviderScope observers',
          ),
        ],
        isError: true,
      );
    }
  }
}
