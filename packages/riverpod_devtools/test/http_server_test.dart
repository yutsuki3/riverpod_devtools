import 'package:flutter_test/flutter_test.dart';
import 'package:riverpod_devtools/src/http_server_io.dart';

void main() {
  group('RiverpodDevToolsHttpServer event buffer', () {
    Map<String, Object?> event(String provider, int i) => {
          'type': 'provider_updated',
          'provider': provider,
          'newValue': i,
        };

    test('evicts oldest events once maxBufferSize is reached', () {
      final server = RiverpodDevToolsHttpServer(maxBufferSize: 3);
      for (var i = 0; i < 5; i++) {
        server.addEvent(event('a', i));
      }

      final events = server.eventsFor();
      expect(events.map((e) => e['newValue']), [2, 3, 4]);
    });

    test('eventsFor returns all events by default', () {
      final server = RiverpodDevToolsHttpServer();
      server.addEvent(event('a', 0));
      server.addEvent(event('b', 1));

      expect(server.eventsFor().length, 2);
    });

    test('eventsFor filters by provider name', () {
      final server = RiverpodDevToolsHttpServer();
      server.addEvent(event('a', 0));
      server.addEvent(event('b', 1));
      server.addEvent(event('a', 2));

      final events = server.eventsFor(provider: 'a');
      expect(events.map((e) => e['newValue']), [0, 2]);
    });

    test('eventsFor keeps the most recent events when limited', () {
      final server = RiverpodDevToolsHttpServer();
      for (var i = 0; i < 10; i++) {
        server.addEvent(event('a', i));
      }

      final events = server.eventsFor(limit: 3);
      expect(events.map((e) => e['newValue']), [7, 8, 9]);
    });

    test('eventsFor applies the provider filter before the limit', () {
      final server = RiverpodDevToolsHttpServer();
      for (var i = 0; i < 10; i++) {
        server.addEvent(event(i.isEven ? 'a' : 'b', i));
      }

      final events = server.eventsFor(provider: 'a', limit: 2);
      expect(events.map((e) => e['newValue']), [6, 8]);
    });

    test('eventsFor with a limit larger than the buffer returns everything',
        () {
      final server = RiverpodDevToolsHttpServer();
      server.addEvent(event('a', 0));

      expect(server.eventsFor(limit: 100).length, 1);
    });

    test('clearEvents empties the buffer', () {
      final server = RiverpodDevToolsHttpServer();
      server.addEvent(event('a', 0));
      server.clearEvents();

      expect(server.eventsFor(), isEmpty);
    });
  });
}
