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

    test('eventsFor treats limit 0 and negative limits as empty', () {
      final server = RiverpodDevToolsHttpServer();
      for (var i = 0; i < 3; i++) {
        server.addEvent(event('a', i));
      }

      expect(server.eventsFor(limit: 0), isEmpty);
      expect(server.eventsFor(limit: -1), isEmpty);
      expect(server.eventsFor(provider: 'a', limit: 0), isEmpty);
    });

    test('eventsFor with a limit larger than the buffer returns everything',
        () {
      final server = RiverpodDevToolsHttpServer();
      server.addEvent(event('a', 0));

      expect(server.eventsFor(limit: 100).length, 1);
    });

    test('eventsFor filters by event type', () {
      final server = RiverpodDevToolsHttpServer();
      server.addEvent(event('a', 0));
      server.addEvent({'type': 'provider_failed', 'provider': 'a'});
      server.addEvent(event('b', 1));

      final failed = server.eventsFor(type: 'provider_failed');
      expect(failed, hasLength(1));
      expect(failed.single['type'], 'provider_failed');
    });

    test('eventsFor combines provider and type filters with a limit', () {
      final server = RiverpodDevToolsHttpServer();
      for (var i = 0; i < 6; i++) {
        server.addEvent({
          'type': i.isEven ? 'provider_failed' : 'provider_updated',
          'provider': i < 4 ? 'a' : 'b',
          'newValue': i,
        });
      }

      final events =
          server.eventsFor(provider: 'a', type: 'provider_failed', limit: 1);
      expect(events.map((e) => e['newValue']), [2]);
    });

    test('clearEvents empties the buffer', () {
      final server = RiverpodDevToolsHttpServer();
      server.addEvent(event('a', 0));
      server.clearEvents();

      expect(server.eventsFor(), isEmpty);
    });
  });

  group('RiverpodDevToolsHttpServer provider snapshot', () {
    Map<String, Object?> lifecycleEvent(
      String type,
      String provider, {
      Object? value,
      Object? newValue,
      Object? error,
      int? seq,
    }) =>
        {
          'type': type,
          'provider': provider,
          'providerId': '1',
          if (value != null) 'value': value,
          if (newValue != null) 'newValue': newValue,
          if (error != null) 'error': error,
          'dependencies': const <String>[],
          'timestamp': 1000,
          'seq': seq,
        };

    test('tracks the latest value per provider', () {
      final server = RiverpodDevToolsHttpServer();
      server.addEvent(lifecycleEvent('provider_added', 'a', value: 1, seq: 1));
      server
          .addEvent(lifecycleEvent('provider_updated', 'a', newValue: 2, seq: 2));

      final snapshot = server.providerSnapshot();
      expect(snapshot, hasLength(1));
      expect(snapshot.single['value'], 2);
      expect(snapshot.single['status'], 'active');
      expect(snapshot.single['seq'], 2);
    });

    test('marks failed providers and keeps their previous value', () {
      final server = RiverpodDevToolsHttpServer();
      server.addEvent(lifecycleEvent('provider_added', 'a', value: 1));
      server.addEvent(lifecycleEvent('provider_failed', 'a',
          error: {'message': 'boom'}));

      final entry = server.providerSnapshot().single;
      expect(entry['status'], 'failed');
      expect(entry['value'], 1);
      expect((entry['error'] as Map)['message'], 'boom');
    });

    test('evicts disposed providers', () {
      final server = RiverpodDevToolsHttpServer();
      server.addEvent(lifecycleEvent('provider_added', 'a', value: 1));
      server.addEvent(lifecycleEvent('provider_disposed', 'a'));

      expect(server.providerSnapshot(), isEmpty);
      expect(server.providerSnapshot(provider: 'a'), isEmpty);
    });

    test('filters by provider name and sorts the full snapshot', () {
      final server = RiverpodDevToolsHttpServer();
      server.addEvent(lifecycleEvent('provider_added', 'b', value: 2));
      server.addEvent(lifecycleEvent('provider_added', 'a', value: 1));

      expect(server.providerSnapshot().map((e) => e['provider']), ['a', 'b']);
      expect(server.providerSnapshot(provider: 'b').single['value'], 2);
      expect(server.providerSnapshot(provider: 'missing'), isEmpty);
    });

    test('survives clearEvents (history is not current state)', () {
      final server = RiverpodDevToolsHttpServer();
      server.addEvent(lifecycleEvent('provider_added', 'a', value: 1));
      server.clearEvents();

      expect(server.eventsFor(), isEmpty);
      expect(server.providerSnapshot(), hasLength(1));
    });
  });
}
