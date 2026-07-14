import 'dart:async';
import 'dart:convert';
import 'dart:io' as io;

import 'package:dart_mcp/server.dart';

import '../mcp_constants.dart';
import 'compact.dart';

base class RiverpodDevToolsMcpServer extends MCPServer with ToolsSupport {
  RiverpodDevToolsMcpServer(super.channel)
    : super.fromStreamChannel(
        implementation: Implementation(
          name: 'riverpod-devtools-mcp',
          version: riverpodDevToolsVersion,
        ),
        instructions:
            'Inspect Riverpod state in a running Flutter app (debug mode, '
            'with RiverpodDevToolsObserver). Read tools (logs/state/graph/'
            'stats) return a COMPACT view by default; pass view="full" for '
            'the raw data. With one app running, "port" is auto-selected.',
      ) {
    registerTool(_listRiverpodAppsTool, _listRiverpodApps);
    registerTool(_getRiverpodLogsTool, _getRiverpodLogs);
    registerTool(_getProviderStateTool, _getProviderState);
    registerTool(_getDependencyGraphTool, _getDependencyGraph);
    registerTool(_getProviderStatsTool, _getProviderStats);
    registerTool(_invalidateProviderTool, _invalidateProvider);
    registerTool(_setProviderValueTool, _setProviderValue);
    registerTool(_clearRiverpodLogsTool, _clearRiverpodLogs);
  }

  /// Shared optional `port` parameter: pins a tool call to one specific app
  /// when several are running (see `list_riverpod_apps`).
  static final _portProperty = Schema.int(
    description: 'App port (from list_riverpod_apps). Omit if only one app.',
  );

  static final _logsViewProperty = Schema.string(
    description:
        'compact (default): slim events. summary: per-provider counts + '
        'latest value, no stream. full: raw events (full value trees, stack '
        'traces, dep metadata).',
    enumValues: ['compact', 'summary', 'full'],
  );

  static final _stateViewProperty = Schema.string(
    description:
        'compact (default): provider, status, value, lastUpdated. full: raw '
        '(adds providerId, dependency list).',
    enumValues: ['compact', 'full'],
  );

  static final _graphViewProperty = Schema.string(
    description:
        'compact (default): topology only. full: adds edge source locations '
        'and per-node metadata.',
    enumValues: ['compact', 'full'],
  );

  static final _statsViewProperty = Schema.string(
    description:
        'compact (default): health signals, most-interesting-first, no '
        'sparkline. full: raw (adds updateBuckets).',
    enumValues: ['compact', 'full'],
  );

  final _listRiverpodAppsTool = Tool(
    name: 'list_riverpod_apps',
    description:
        'List running debug apps exposing Riverpod (port, provider count, '
        'event count). Only needed when several apps run — pass the chosen '
        '"port" to the other tools. A single app is auto-selected.',
    inputSchema: Schema.object(properties: {}),
  );

  final _getRiverpodLogsTool = Tool(
    name: 'get_riverpod_logs',
    description:
        'Riverpod provider lifecycle events (added / updated / failed / '
        'disposed) — state changes only, not console output. For debugging '
        'state bugs, unexpected rebuilds, or provider errors. Each event has '
        'a monotonic "seq"; updated events may carry "triggeredBy" (the '
        'inferred dependency change that caused the rebuild). Buffer holds '
        'up to 1000 events — narrow with the filters below.',
    inputSchema: Schema.object(
      properties: {
        'port': _portProperty,
        'view': _logsViewProperty,
        'limit': Schema.int(
          description: 'Most recent N events (after other filters).',
          minimum: 1,
        ),
        'provider': Schema.string(
          description: 'Only this provider name (e.g. "counterProvider").',
        ),
        'type': Schema.string(
          description:
              'Only this kind: provider_added / provider_updated / '
              'provider_failed / provider_disposed (failed = errors only).',
        ),
        'since': Schema.int(
          description: 'Only events at/after this epoch-ms time.',
        ),
        'until': Schema.int(
          description: 'Only events at/before this epoch-ms time.',
        ),
      },
    ),
  );

  final _getProviderStateTool = Tool(
    name: 'get_provider_state',
    description:
        'Current state of live providers: name, instanceId, status '
        '(active/failed), latest value, error, last-update time. Prefer this '
        'over get_riverpod_logs when you want current values, not history. '
        'When "nameIsUnique" is false, target a specific one by its '
        'instanceId. Disposed providers are omitted.',
    inputSchema: Schema.object(
      properties: {
        'port': _portProperty,
        'view': _stateViewProperty,
        'provider': Schema.string(
          description:
              'Only providers matching this name or exact instanceId '
              '(e.g. "counterProvider" or "p3"). A shared name may match '
              'several.',
        ),
      },
    ),
  );

  final _getDependencyGraphTool = Tool(
    name: 'get_dependency_graph',
    description:
        'Provider dependency graph: nodes (with runtime status) and directed '
        'edges dependent → dependency, each with its kind (watch/read/'
        'listen). Answers "what does X depend on" / "what rebuilds when X '
        'changes". Edges come from static analysis, so the app must have '
        'loaded riverpod_dependencies.json (dart run riverpod_devtools:'
        'analyze).',
    inputSchema: Schema.object(
      properties: {
        'port': _portProperty,
        'view': _graphViewProperty,
        'provider': Schema.string(
          description:
              'Focus: restrict to this provider plus its transitive '
              'dependencies and dependents.',
        ),
      },
    ),
  );

  final _getProviderStatsTool = Tool(
    name: 'get_provider_stats',
    description:
        'Aggregated per-provider health from the event log: update count + '
        'rate, async load duration (min/avg/max), dispose→recreate churn, '
        'and high-frequency / slow-loading warning flags. Answers "which '
        'provider rebuilds too much?" or "is anything loading slowly?" '
        'without scanning the log yourself.',
    inputSchema: Schema.object(
      properties: {
        'port': _portProperty,
        'view': _statsViewProperty,
        'provider': Schema.string(
          description: 'Only this provider name (e.g. "counterProvider").',
        ),
      },
    ),
  );

  final _invalidateProviderTool = Tool(
    name: 'invalidate_provider',
    description:
        'MUTATES APP STATE: invalidate a provider so it recomputes (state '
        'resets to what build() produces). By default it rebuilds on next '
        'read/listen; refresh=true rebuilds immediately. Useful to reproduce '
        'flows (clear_riverpod_logs → invalidate → trigger → get logs). The '
        'provider must have been observed; if a name is shared the call is '
        'rejected with the candidate instanceIds.',
    inputSchema: Schema.object(
      properties: {
        'port': _portProperty,
        'provider': Schema.string(
          description:
              'Provider name (when unique) or exact instanceId (e.g. "p3", '
              'required when the name is shared). Both are in '
              'get_provider_state.',
        ),
        'refresh': Schema.bool(
          description: 'Rebuild immediately, not on next read. Default false.',
        ),
      },
      required: ['provider'],
    ),
  );

  final _setProviderValueTool = Tool(
    name: 'set_provider_value',
    description:
        'MUTATES APP STATE: set a provider to a specific primitive value '
        '(number, boolean, string, or null) — unlike invalidate, which only '
        'resets it to what build() produces. Only providers with a writable '
        'notifier and primitive state are supported (StateProvider, '
        'NotifierProvider); plain/Future/Stream providers, or providers whose '
        'state is an object or AsyncValue, are rejected with supported=false. '
        'If a name is shared, pass the exact instanceId. Use it to force an '
        'edge-case state and watch how the UI reacts.',
    inputSchema: Schema.object(
      properties: {
        'port': _portProperty,
        'provider': Schema.string(
          description:
              'Provider name (when unique) or exact instanceId (e.g. "p3", '
              'required when the name is shared). Both are in '
              'get_provider_state.',
        ),
        'value': Schema.combined(
          description:
              'The new state: a primitive (number, boolean, string, or '
              "null). Its type must match the provider's current state type.",
          anyOf: [
            Schema.num(),
            Schema.bool(),
            Schema.string(),
            Schema.nil(),
          ],
        ),
      },
      required: ['provider', 'value'],
    ),
  );

  final _clearRiverpodLogsTool = Tool(
    name: 'clear_riverpod_logs',
    description:
        'Clear the event buffer so only events after this appear next. Does '
        'not affect get_provider_state (current state is unchanged).',
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
      if (arguments['since'] case final num since) 'since': '${since.toInt()}',
      if (arguments['until'] case final num until) 'until': '${until.toInt()}',
    };
    final view = arguments['view'] as String? ?? 'compact';
    return _request(
      port!,
      'GET',
      '/logs',
      queryParameters: queryParameters,
      (body) => _reshaped(body, (decoded) {
        if (decoded is! List) return decoded; // error/unknown shape
        return switch (view) {
          'summary' => summarizeEvents(decoded),
          'full' => decoded,
          _ => compactEvents(decoded),
        };
      }),
    );
  }

  FutureOr<CallToolResult> _getProviderState(CallToolRequest request) async {
    final (port, err) = await _resolvePort(request);
    if (err != null) return err;
    final view = (request.arguments ?? const {})['view'] as String? ?? 'compact';
    return _request(
      port!,
      'GET',
      '/providers',
      queryParameters: _providerQuery(request),
      (body) => _reshaped(body, (decoded) {
        if (decoded is! List) return decoded;
        return view == 'full' ? decoded : compactState(decoded);
      }),
    );
  }

  /// Parses [body], applies [transform] to the decoded JSON, and returns the
  /// re-encoded result. If the body isn't JSON (e.g. a plain-text error), it
  /// is passed through untouched so error messages still reach the caller.
  CallToolResult _reshaped(
    String body,
    Object? Function(Object? decoded) transform,
  ) {
    Object? decoded;
    try {
      decoded = jsonDecode(body);
    } catch (_) {
      return CallToolResult(content: [TextContent(text: body)]);
    }
    final reshaped = transform(decoded);
    return CallToolResult(
      content: [TextContent(text: jsonEncode(reshaped))],
    );
  }

  FutureOr<CallToolResult> _getDependencyGraph(CallToolRequest request) async {
    final (port, err) = await _resolvePort(request);
    if (err != null) return err;
    final full = (request.arguments ?? const {})['view'] == 'full';
    return _request(
      port!,
      'GET',
      '/graph',
      queryParameters: _providerQuery(request),
      (body) => _reshaped(body, (decoded) {
        if (decoded is! Map || full) return decoded;
        return compactGraph(decoded.cast<Object?, Object?>());
      }),
    );
  }

  FutureOr<CallToolResult> _getProviderStats(CallToolRequest request) async {
    final (port, err) = await _resolvePort(request);
    if (err != null) return err;
    final full = (request.arguments ?? const {})['view'] == 'full';
    return _request(
      port!,
      'GET',
      '/stats',
      queryParameters: _providerQuery(request),
      (body) => _reshaped(body, (decoded) {
        if (decoded is! Map || full) return decoded;
        return compactStats(decoded.cast<Object?, Object?>());
      }),
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

  FutureOr<CallToolResult> _setProviderValue(CallToolRequest request) async {
    final arguments = request.arguments ?? const {};
    final provider = arguments['provider'];
    if (provider is! String || provider.isEmpty) {
      return CallToolResult(
        content: [TextContent(text: 'Missing required "provider" argument.')],
        isError: true,
      );
    }
    if (!arguments.containsKey('value')) {
      return CallToolResult(
        content: [TextContent(text: 'Missing required "value" argument.')],
        isError: true,
      );
    }
    final (port, err) = await _resolvePort(request);
    if (err != null) return err;
    return _request(
      port!,
      'POST',
      '/commands',
      body: jsonEncode({
        'action': 'set',
        'provider': provider,
        'value': arguments['value'],
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
