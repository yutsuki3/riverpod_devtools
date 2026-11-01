import 'package:flutter_test/flutter_test.dart';
import 'package:riverpod_devtools/src/mcp/response_status.dart';

void main() {
  group('isFailedResponse', () {
    test('4xx and 5xx are failures regardless of body', () {
      expect(isFailedResponse(400, 'Invalid "limit": expected ...'), isTrue);
      expect(isFailedResponse(404, ''), isTrue);
      expect(isFailedResponse(500, ''), isTrue);
    });

    test('200 with status:error is a failure', () {
      expect(isFailedResponse(200, '{"status":"error","message":"x"}'), isTrue);
    });

    test('ambiguous and supported:false answers are failures', () {
      expect(
        isFailedResponse(
          200,
          '{"status":"error","ambiguous":true,"candidates":["p1","p2"]}',
        ),
        isTrue,
      );
      expect(
        isFailedResponse(200, '{"status":"error","supported":false}'),
        isTrue,
      );
    });

    test('200 with status:ok is a success', () {
      expect(isFailedResponse(200, '{"status":"ok","action":"set"}'), isFalse);
    });

    test('read payloads (list / map without status) are successes', () {
      expect(isFailedResponse(200, '[{"seq":1}]'), isFalse);
      expect(isFailedResponse(200, '{"nodes":[],"edges":[]}'), isFalse);
    });

    test('non-JSON 200 and empty 204 are successes', () {
      expect(isFailedResponse(200, 'plain text'), isFalse);
      expect(isFailedResponse(204, ''), isFalse);
    });
  });
}
