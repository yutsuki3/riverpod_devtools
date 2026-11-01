import 'dart:async';

import 'package:dart_mcp/client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riverpod_devtools/src/mcp/riverpod_devtools_mcp_server.dart';
import 'package:stream_channel/stream_channel.dart';

void main() {
  late Map<String, Tool> tools;

  setUpAll(() async {
    final clientToServer = StreamController<String>();
    final serverToClient = StreamController<String>();
    RiverpodDevToolsMcpServer(
      StreamChannel.withGuarantees(
        clientToServer.stream,
        serverToClient.sink,
      ),
    );
    final client = MCPClient(
      Implementation(name: 'test-client', version: '0.0.0'),
    );
    final connection = client.connectServer(
      StreamChannel.withGuarantees(
        serverToClient.stream,
        clientToServer.sink,
      ),
    );
    await connection.initialize(
      InitializeRequest(
        protocolVersion: ProtocolVersion.latestSupported,
        capabilities: client.capabilities,
        clientInfo: client.implementation,
      ),
    );
    connection.notifyInitialized();
    tools = {
      for (final tool in (await connection.listTools()).tools) tool.name: tool,
    };
  });

  test('exposes the documented tool set', () {
    expect(tools.keys, {
      'list_riverpod_apps',
      'get_riverpod_logs',
      'get_provider_state',
      'get_dependency_graph',
      'get_provider_stats',
      'invalidate_provider',
      'set_provider_value',
      'clear_riverpod_logs',
    });
  });

  test('read tools are annotated read-only so clients can auto-approve', () {
    for (final name in [
      'list_riverpod_apps',
      'get_riverpod_logs',
      'get_provider_state',
      'get_dependency_graph',
      'get_provider_stats',
    ]) {
      final annotations = tools[name]!.toolAnnotations;
      expect(annotations?.readOnlyHint, isTrue, reason: name);
      expect(annotations?.openWorldHint, isFalse, reason: name);
    }
  });

  test('mutating tools are not annotated read-only', () {
    for (final name in [
      'invalidate_provider',
      'set_provider_value',
      'clear_riverpod_logs',
    ]) {
      final annotations = tools[name]!.toolAnnotations;
      expect(annotations?.readOnlyHint, isFalse, reason: name);
      expect(annotations?.destructiveHint, isTrue, reason: name);
      expect(annotations?.openWorldHint, isFalse, reason: name);
    }
  });
}
