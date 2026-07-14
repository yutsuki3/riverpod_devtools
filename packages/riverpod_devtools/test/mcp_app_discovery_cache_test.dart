import 'package:flutter_test/flutter_test.dart';
import 'package:riverpod_devtools/src/mcp/app_discovery_cache.dart';

void main() {
  group('AppDiscoveryCache', () {
    late int calls;
    late DiscoveredApps result;
    late DateTime clock;

    AppDiscoveryCache build({Duration ttl = const Duration(seconds: 5)}) {
      return AppDiscoveryCache(
        ttl: ttl,
        now: () => clock,
        discover: () async {
          calls++;
          return result;
        },
      );
    }

    setUp(() {
      calls = 0;
      result = [
        {'port': 8788},
      ];
      clock = DateTime(2026, 1, 1, 12, 0, 0);
    });

    test('get() scans on the first call', () async {
      final cache = build();

      expect(await cache.get(), result);
      expect(calls, 1);
    });

    test('get() serves a fresh cache without re-scanning', () async {
      final cache = build();

      await cache.get();
      clock = clock.add(const Duration(seconds: 4)); // still within the TTL
      await cache.get();

      expect(calls, 1);
    });

    test('get() re-scans once the cache has expired', () async {
      final cache = build();

      await cache.get();
      clock = clock.add(const Duration(seconds: 6)); // past the TTL
      await cache.get();

      expect(calls, 2);
    });

    test('refresh() always re-scans and primes the cache', () async {
      final cache = build();

      await cache.refresh();
      await cache.refresh();
      expect(calls, 2);

      // A get() right after a refresh is served from cache.
      await cache.get();
      expect(calls, 2);
    });

    test('invalidate() forces the next get() to re-scan', () async {
      final cache = build();

      await cache.get();
      cache.invalidate();
      await cache.get();

      expect(calls, 2);
    });

    test('a re-scan after invalidate reflects a moved port', () async {
      final cache = build();

      expect((await cache.get()).single['port'], 8788);

      // App restarted onto a different port; the old port is now dead.
      result = [
        {'port': 8789},
      ];
      cache.invalidate();

      expect((await cache.get()).single['port'], 8789);
    });
  });
}
