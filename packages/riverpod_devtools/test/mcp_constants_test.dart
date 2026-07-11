import 'package:flutter_test/flutter_test.dart';
import 'package:riverpod_devtools/src/mcp_constants.dart';

void main() {
  group('riverpodDevToolsMcpPorts', () {
    test('starts at the base port', () {
      expect(riverpodDevToolsMcpPorts.first, riverpodDevToolsMcpPort);
    });

    test('spans exactly the configured count of consecutive ports', () {
      final ports = riverpodDevToolsMcpPorts.toList();
      expect(ports, hasLength(riverpodDevToolsMcpPortCount));
      for (var i = 1; i < ports.length; i++) {
        expect(ports[i], ports[i - 1] + 1);
      }
      expect(ports.last,
          riverpodDevToolsMcpPort + riverpodDevToolsMcpPortCount - 1);
    });
  });
}
