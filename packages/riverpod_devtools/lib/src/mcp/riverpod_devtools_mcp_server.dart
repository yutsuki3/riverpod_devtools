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
    registerTool(_listRiverpodAppsTool, _listRiverpodApps);
    registerTool(_getRiverpodLogsTool, _getRiverpodLogs);
    registerTool(_getProviderStateTool, _getProviderState);
    registerTool(_getDependencyGraphTool, _getDependencyGraph);
    registerTool(_getProviderStatsTool, _getProviderStats);
    registerTool(_invalidateProviderTool, _invalidateProvider);
    registerTool(_clearRiverpodLogsTool, _clearRiverpodLogs);
  }

  /// Shared optional `port` parameter: pins a tool call to one specific app
  /// when several are running (see `list_riverpod_apps`).
  static final _portProperty = Schema.int(
    description:
        'Port of the app to target (from list_riverpod_apps). Omit when only '
        'one app is running — it is selected automatically.',
  );

  final _listRiverpodAppsTool = Tool(
    name: 'list_riverpod_apps',
    description:
        'List the running Flutter apps that expose Riverpod events (each '
        'debug app with RiverpodDevToolsObserver binds a port in the range). '
        'Returns each app\'s port, provider count, and event count. Use this '
        'when more than one app is running: pass the chosen "port" to the '
        'other tools. With a single app, the other tools auto-select it and '
        'you do not need this.',
    inputSchema: Schema.object(properties: {}),
  );

  final _getRiverpodLogsTool = Tool(
    name: 'get_riverpod_logs',
    description:
        'Get Riverpod provider state-change events from the running Flutter app. '
        'This is NOT a general app log or console output — it captures only Riverpod '
        'provider lifecycle events: provider_added (initial value), provider_updated '
        '(previous/new value diff), provider_failed (error type, message, and stack '
        'trace when a provider throws or an async provider emits an error), and '
        'provider_disposed. '
        'Use this when investigating Riverpod state bugs, unexpected re-builds, '
        'or provider lifecycle issues. '
        'Each event carries a monotonic "seq" number for unambiguous ordering. '
        'provider_updated events may carry "triggeredBy" — the dependency '
        'update(s) that likely caused this recomputation, inferred from the '
        'static dependency graph plus temporal proximity — which lets you '
        'trace update cascades ("why did this provider rebuild?"). '
        'The buffer can hold up to 1000 events; prefer passing "limit" (and '
        '"provider" when you know which provider you are investigating) to '
        'keep the response small. '
        'Requires the app to be running in debug mode (flutter run).',
    inputSchema: Schema.object(
      properties: {
        'port': _portProperty,
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
        'type': Schema.string(
          description:
              'Return only events of this type: provider_added, '
              'provider_updated, provider_failed, or provider_disposed. '
              'Use "provider_failed" to fetch only errors.',
        ),
      },
    ),
  );

  final _getProviderStateTool = Tool(
    name: 'get_provider_state',
    description:
        'Get the CURRENT state of Riverpod providers in the running Flutter '
        'app: one snapshot entry per live provider with its name, a stable '
        'instanceId, status (active or failed), latest value, error details '
        'when failed, and last-update timestamp. '
        'Each entry carries an instanceId; when "nameIsUnique" is false the '
        'name is shared by several providers, so use the instanceId to '
        'target a specific one (e.g. with invalidate_provider). '
        'Prefer this over get_riverpod_logs when you need current values '
        'rather than the event history — no need to replay the log. '
        'Disposed providers are not listed. '
        'Requires the app to be running in debug mode (flutter run).',
    inputSchema: Schema.object(
      properties: {
        'port': _portProperty,
        'provider': Schema.string(
          description:
              'Return only providers matching this exact name '
              '(e.g. "counterProvider") or this exact instanceId (e.g. '
              '"p3"). A shared name may return several entries. Empty result '
              'if nothing matches or it has been disposed.',
        ),
      },
    ),
  );

  final _getDependencyGraphTool = Tool(
    name: 'get_dependency_graph',
    description:
        'Get the Riverpod provider dependency graph of the running Flutter '
        'app: nodes are providers (with runtime status: active, failed, or '
        'unknown when not yet seen by the observer) and directed edges go '
        'from dependent to dependency with the dependency kind (watch, read, '
        'listen) and its source location. '
        'Edges come from static analysis, so the app must have loaded the '
        'riverpod_dependencies.json generated by '
        '"dart run riverpod_devtools:analyze". '
        'Use this to answer "what does X depend on", "what rebuilds when X '
        'changes", or to explain update cascades from get_riverpod_logs.',
    inputSchema: Schema.object(
      properties: {
        'port': _portProperty,
        'provider': Schema.string(
          description:
              'Focus provider name: restricts the graph to this provider '
              'plus its transitive dependencies and dependents.',
        ),
      },
    ),
  );

  final _getProviderStatsTool = Tool(
    name: 'get_provider_stats',
    description:
        'Get aggregated activity/health stats per provider, computed from '
        'the event log: update count (total and in the last 10s, plus a '
        'rate), async load duration (min/avg/max of observed loading→data '
        'or loading→error transitions), and dispose→re-create churn count. '
        'Each entry also carries "isHighFrequency" (recent rate above '
        '10 updates/sec) and "isSlowLoading" (a load took over 2s) flags, '
        'plus "updateBuckets" — update counts bucketed over the last 30s '
        '(oldest→newest) to spot bursts. '
        'Use this to answer "which provider is rebuilding excessively?" or '
        '"is anything loading unusually slowly?" without pulling and '
        'analyzing the full event log yourself. '
        'Requires the app to be running in debug mode (flutter run).',
    inputSchema: Schema.object(
      properties: {
        'port': _portProperty,
        'provider': Schema.string(
          description:
              'Return only the stats for the provider with this exact name '
              '(e.g. "counterProvider").',
        ),
      },
    ),
  );

  final _invalidateProviderTool = Tool(
    name: 'invalidate_provider',
    description:
        'MUTATES APP STATE: invalidate a Riverpod provider in the running '
        'Flutter app, forcing it to recompute — its state resets to what '
        'build() produces. '
        'By default the rebuild happens when the provider is next read or '
        'has active listeners; pass refresh=true to re-read it immediately. '
        'Use this to reproduce flows during debugging (e.g. '
        'clear_riverpod_logs → invalidate_provider → trigger the flow → '
        'get_riverpod_logs) or to test how the UI reacts to a state reset. '
        'The provider must have been observed by the app (see '
        'get_provider_state). If several providers share the same name the '
        'call is rejected with the list of candidate instanceIds — pass the '
        'exact one. Debug mode only.',
    inputSchema: Schema.object(
      properties: {
        'port': _portProperty,
        'provider': Schema.string(
          description:
              'The provider to invalidate: either its exact name '
              '(e.g. "counterProvider") when unique, or its instanceId '
              '(e.g. "p3") — required when a name is shared by more than one '
              'provider. get_provider_state lists both.',
        ),
        'refresh': Schema.bool(
          description:
              'Also re-read the provider immediately so it rebuilds even '
              'without active listeners. Defaults to false.',
        ),
      },
      required: ['provider'],
    ),
  );

  final _clearRiverpodLogsTool = Tool(
    name: 'clear_riverpod_logs',
    description:
        'Clear the Riverpod provider state-change event buffer. '
        'Use this before reproducing a specific bug or flow so that only '
        'the relevant events appear in the next get_riverpod_logs call.',
    inputSchema: Schema.object(properties: {'port': _portProperty}),
  );

  FutureOr<CallToolResult> _listRiverpodApps(CallToolRequest request) async {
    final apps = await _discoverApps();
    return CallToolResult(
      content: [
        TextContent(
          text:
              apps.isEmpty
                  ? 'No running Flutter apps with riverpod_devtools were found on '
                      'ports $riverpodDevToolsMcpPort–'
                      '${riverpodDevToolsMcpPort + riverpodDevToolsMcpPortCount - 1}.'
                  : jsonEncode({'apps': apps}),
        ),
      ],
    );
  }

  FutureOr<CallToolResult> _getRiverpodLogs(CallToolRequest request) async {
    final (port, err) = await _resolvePort(request);
    if (err != null) return err;
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
      if (arguments['type'] case final String type when type.isNotEmpty)
        'type': type,
    };
    return _request(
      port!,
      'GET',
      '/logs',
      queryParameters: queryParameters,
      (body) => CallToolResult(content: [TextContent(text: body)]),
    );
  }

  FutureOr<CallToolResult> _getProviderState(CallToolRequest request) async {
    final (port, err) = await _resolvePort(request);
    if (err != null) return err;
    return _request(
      port!,
      'GET',
      '/providers',
      queryParameters: _providerQuery(request),
      (body) => CallToolResult(content: [TextContent(text: body)]),
    );
  }

  FutureOr<CallToolResult> _getDependencyGraph(CallToolRequest request) async {
    final (port, err) = await _resolvePort(request);
    if (err != null) return err;
    return _request(
      port!,
      'GET',
      '/graph',
      queryParameters: _providerQuery(request),
      (body) => CallToolResult(content: [TextContent(text: body)]),
    );
  }

  FutureOr<CallToolResult> _getProviderStats(CallToolRequest request) async {
    final (port, err) = await _resolvePort(request);
    if (err != null) return err;
    return _request(
      port!,
      'GET',
      '/stats',
      queryParameters: _providerQuery(request),
      (body) => CallToolResult(content: [TextContent(text: body)]),
    );
  }

  Map<String, String> _providerQuery(CallToolRequest request) => {
    if ((request.arguments ?? const {})['provider'] case final String provider
        when provider.isNotEmpty)
      'provider': provider,
  };

  FutureOr<CallToolResult> _invalidateProvider(CallToolRequest request) async {
    final arguments = request.arguments ?? const {};
    final provider = arguments['provider'];
    if (provider is! String || provider.isEmpty) {
      return CallToolResult(
        content: [TextContent(text: 'Missing required "provider" argument.')],
        isError: true,
      );
    }
    final (port, err) = await _resolvePort(request);
    if (err != null) return err;
    final refresh = arguments['refresh'] == true;
    return _request(
      port!,
      'POST',
      '/commands',
      body: jsonEncode({
        'action': refresh ? 'refresh' : 'invalidate',
        'provider': provider,
      }),
      (body) => CallToolResult(content: [TextContent(text: body)]),
    );
  }

  FutureOr<CallToolResult> _clearRiverpodLogs(CallToolRequest request) async {
    final (port, err) = await _resolvePort(request);
    if (err != null) return err;
    return _request(
      port!,
      'DELETE',
      '/logs',
      (_) =>
          CallToolResult(content: [TextContent(text: 'Log buffer cleared.')]),
    );
  }

  /// Resolves which app port to talk to. If the caller passed an explicit
  /// `port`, that is used. Otherwise the range is probed: exactly one
  /// running app is used automatically; zero or several return an error
  /// result (the latter asking the caller to pass `port`).
  ///
  /// Returns `(port, null)` on success or `(null, errorResult)` otherwise.
  Future<(int?, CallToolResult?)> _resolvePort(CallToolRequest request) async {
    if ((request.arguments ?? const {})['port'] case final num port) {
      return (port.toInt(), null);
    }

    final apps = await _discoverApps();
    if (apps.isEmpty) {
      return (
        null,
        CallToolResult(
          content: [
            TextContent(
              text:
                  'No running Flutter app with riverpod_devtools was found '
                  'on ports $riverpodDevToolsMcpPort–'
                  '${riverpodDevToolsMcpPort + riverpodDevToolsMcpPortCount - 1}.\n\n'
                  'Make sure:\n'
                  '1. The Flutter app is running in debug mode: flutter run\n'
                  '2. riverpod_devtools is a dependency\n'
                  '3. RiverpodDevToolsObserver() is added to ProviderScope observers',
            ),
          ],
          isError: true,
        ),
      );
    }
    if (apps.length == 1) return (apps.single['port'] as int, null);

    return (
      null,
      CallToolResult(
        content: [
          TextContent(
            text:
                'Several running apps were found. Re-run this tool with a '
                '"port" argument to pick one:\n'
                '${const JsonEncoder.withIndent('  ').convert(apps)}',
          ),
        ],
        isError: true,
      ),
    );
  }

  /// Probes every port in the range and returns the `/ping` payloads of the
  /// apps that respond.
  Future<List<Map<String, Object?>>> _discoverApps() async {
    final found = await Future.wait(riverpodDevToolsMcpPorts.map(_pingPort));
    return [
      for (final app in found)
        if (app != null) app,
    ];
  }

  Future<Map<String, Object?>?> _pingPort(int port) async {
    final client = io.HttpClient();
    try {
      final req = await client
          .getUrl(
            Uri(scheme: 'http', host: 'localhost', port: port, path: '/ping'),
          )
          .timeout(const Duration(seconds: 1));
      final response = await req.close().timeout(const Duration(seconds: 1));
      if (response.statusCode != 200) return null;
      final body = await response.transform(utf8.decoder).join();
      final decoded = jsonDecode(body);
      if (decoded is Map && decoded['riverpodDevtools'] == true) {
        return {
          'port': port,
          'providerCount': decoded['providerCount'],
          'eventCount': decoded['eventCount'],
        };
      }
      return null;
    } catch (_) {
      return null;
    } finally {
      client.close();
    }
  }

  Future<CallToolResult> _request(
    int port,
    String method,
    String path,
    CallToolResult Function(String body) onSuccess, {
    Map<String, String> queryParameters = const {},
    String? body,
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
                port: port,
                path: path,
                queryParameters:
                    queryParameters.isEmpty ? null : queryParameters,
              ),
            )
            .timeout(const Duration(seconds: 5));
        if (body != null) {
          req.headers.contentType = io.ContentType.json;
          req.write(body);
        }
        final response = await req.close();
        final responseBody = await response.transform(utf8.decoder).join();
        return onSuccess(responseBody);
      } finally {
        client.close();
      }
    } catch (e) {
      return CallToolResult(
        content: [
          TextContent(
            text:
                'Error connecting to the Flutter app on port $port: $e\n\n'
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
