import 'package:flutter_test/flutter_test.dart';
import 'package:riverpod_devtools/src/mcp/compact.dart';
import 'package:riverpod_devtools/src/utils/serialization.dart';

void main() {
  group('compactValue', () {
    test('collapses a serialized scalar to its string form', () {
      expect(compactValue(serializeValue(5)), '5');
      expect(compactValue(serializeValue('hi')), 'hi');
      expect(compactValue(serializeValue(true)), 'true');
    });

    test('null serializes to a null core', () {
      expect(compactValue(serializeValue(null)), isNull);
    });

    test('collapses a small list to its toString', () {
      expect(compactValue(serializeValue([1, 2, 3])), '[1, 2, 3]');
    });

    test('summarizes a large collection instead of inlining it', () {
      // A collection past the serializer's element cap comes through as a
      // lossy wrapper, and the summary reports the true (pre-cap) size.
      final big = List<int>.generate(500, (i) => i);
      final compact = compactValue(serializeValue(big)) as Map;
      expect(compact['lossy'], true);
      final summary = compact['value'] as String;
      expect(summary, contains('500 items'));
      expect(summary.length, lessThan(40));
    });

    test('keeps a toJson() structure inline when small', () {
      final value = serializeValue(_Model());
      // _Model.toJson() => {'a': 1, 'b': 'x'}
      expect(compactValue(value), {'a': 1, 'b': 'x'});
    });

    test('summarizes a large toJson() map', () {
      final value = serializeValue(_BigModel());
      final compact = compactValue(value);
      expect(compact, isA<String>());
      expect(compact as String, matches(RegExp(r'\{…\d+ keys\}')));
    });

    test('preserves asyncState as a wrapper', () {
      final value = serializeValue(_FakeAsyncData());
      final compact = compactValue(value) as Map;
      expect(compact['asyncState'], 'data');
      expect(compact.containsKey('value'), isTrue);
    });

    test('passes through a already-primitive value', () {
      expect(compactValue(42), 42);
      expect(compactValue('raw'), 'raw');
    });

    test('preserves the lossy flag as a wrapper', () {
      final compact = compactValue({
        'type': 'Foo',
        'value': '<Cyclic Reference>',
        'lossy': true,
      }) as Map;
      expect(compact['lossy'], true);
      expect(compact['value'], '<Cyclic Reference>');
    });
  });

  group('compactEvent', () {
    Map<Object?, Object?> raw(Map<String, Object?> extra) => {
          'seq': 7,
          'type': 'provider_updated',
          'providerId': '12345',
          'provider': 'counterProvider',
          'nameIsUnique': true,
          'family': null,
          'dependencies': ['a', 'b'],
          'dependenciesSource': 'static',
          'dependenciesLoadedAt': 111,
          'dependenciesGeneratedAt': 222,
          'timestamp': 1000,
          ...extra,
        };

    test('updated: keeps seq/type/provider/ts/prev/value, drops metadata', () {
      final event = compactEvent(raw({
        'previousValue': serializeValue(1),
        'newValue': serializeValue(2),
      }));
      expect(event, {
        'seq': 7,
        'type': 'updated',
        'provider': 'counterProvider',
        'ts': 1000,
        'prev': '1',
        'value': '2',
      });
      // Explicitly gone:
      expect(event.containsKey('providerId'), isFalse);
      expect(event.containsKey('dependencies'), isFalse);
      expect(event.containsKey('dependenciesLoadedAt'), isFalse);
    });

    test('added: carries the value only', () {
      final event = compactEvent(raw({
        'type': 'provider_added',
        'value': serializeValue(0),
      }));
      expect(event['type'], 'added');
      expect(event['value'], '0');
      expect(event.containsKey('prev'), isFalse);
    });

    test('failed: keeps error type + message, drops the stack trace', () {
      final event = compactEvent(raw({
        'type': 'provider_failed',
        'error': {
          'type': 'HttpException',
          'message': '401',
          'stackTrace': '#0 a\n#1 b\n#2 c',
        },
      }));
      expect(event['type'], 'failed');
      expect(event['error'], {'type': 'HttpException', 'message': '401'});
    });

    test('disposed: no value fields', () {
      final event = compactEvent(raw({'type': 'provider_disposed'}));
      expect(event, {
        'seq': 7,
        'type': 'disposed',
        'provider': 'counterProvider',
        'ts': 1000,
      });
    });

    test('includes instanceId only when the name is ambiguous', () {
      final unique = compactEvent(raw({
        'type': 'provider_added',
        'instanceId': 'p3',
        'value': serializeValue(0),
      }));
      expect(unique.containsKey('instanceId'), isFalse);

      final ambiguous = compactEvent(raw({
        'type': 'provider_added',
        'nameIsUnique': false,
        'instanceId': 'p3',
        'value': serializeValue(0),
      }));
      expect(ambiguous['instanceId'], 'p3');
    });

    test('reduces triggeredBy to provider names', () {
      final event = compactEvent(raw({
        'previousValue': serializeValue(1),
        'newValue': serializeValue(2),
        'triggeredBy': [
          {'provider': 'authProvider', 'seq': 3},
          {'provider': 'configProvider', 'seq': 4},
        ],
      }));
      expect(event['triggeredBy'], ['authProvider', 'configProvider']);
    });
  });

  group('summarizeEvents', () {
    test('tallies per provider and reports the most recent value', () {
      final events = <Object?>[
        {
          'seq': 1,
          'type': 'provider_added',
          'provider': 'a',
          'value': serializeValue(0),
        },
        {
          'seq': 2,
          'type': 'provider_updated',
          'provider': 'a',
          'newValue': serializeValue(1),
        },
        {
          'seq': 3,
          'type': 'provider_updated',
          'provider': 'a',
          'newValue': serializeValue(2),
        },
        {'seq': 4, 'type': 'provider_failed', 'provider': 'b'},
      ];

      final summary = summarizeEvents(events);
      expect(summary['eventCount'], 4);
      expect(summary['providerCount'], 2);

      final providers = (summary['providers'] as List).cast<Map>();
      // 'a' has more activity, so it sorts first.
      expect(providers.first['provider'], 'a');
      expect(providers.first['added'], 1);
      expect(providers.first['updated'], 2);
      expect(providers.first['lastValue'], '2');
      // 'b' failed once, no lastValue.
      final b = providers.firstWhere((p) => p['provider'] == 'b');
      expect(b['failed'], 1);
      expect(b.containsKey('lastValue'), isFalse);
    });

    test('uses the highest seq for the most recent value regardless of order',
        () {
      final events = <Object?>[
        {
          'seq': 5,
          'type': 'provider_updated',
          'provider': 'a',
          'newValue': serializeValue('newest'),
        },
        {
          'seq': 2,
          'type': 'provider_updated',
          'provider': 'a',
          'newValue': serializeValue('older'),
        },
      ];
      final providers =
          (summarizeEvents(events)['providers'] as List).cast<Map>();
      expect(providers.single['lastValue'], 'newest');
    });
  });

  group('compactStateEntry', () {
    test('keeps name/status/value/lastUpdated, drops providerId + deps', () {
      final entry = compactStateEntry({
        'provider': 'counterProvider',
        'providerId': '999',
        'nameIsUnique': true,
        'instanceId': 'p0',
        'status': 'active',
        'value': serializeValue(42),
        'dependencies': ['x', 'y'],
        'lastUpdated': 1000,
        'seq': 9,
      });
      expect(entry, {
        'provider': 'counterProvider',
        'status': 'active',
        'value': '42',
        'lastUpdated': 1000,
      });
    });

    test('keeps instanceId + error for an ambiguous failed provider', () {
      final entry = compactStateEntry({
        'provider': 'dupe',
        'nameIsUnique': false,
        'instanceId': 'p1',
        'status': 'failed',
        'value': serializeValue(1),
        'error': {'type': 'E', 'message': 'boom', 'stackTrace': '#0 x'},
        'lastUpdated': 2000,
      });
      expect(entry['instanceId'], 'p1');
      expect(entry['status'], 'failed');
      expect(entry['error'], {'type': 'E', 'message': 'boom'});
    });
  });

  group('compactGraph', () {
    test('preserves the edgesNote setup hint', () {
      final compact = compactGraph({
        'nodes': [],
        'edges': [],
        'edgesNote': 'run analyze',
      });
      expect(compact['edgesNote'], 'run analyze');
    });

    test('keeps topology, drops source locations and bookkeeping', () {
      final raw = {
        'nodes': [
          {'name': 'a', 'status': 'active', 'hasStaticMetadata': true},
          {'name': 'b', 'status': 'unknown', 'hasStaticMetadata': false},
        ],
        'edges': [
          {
            'from': 'a',
            'to': 'b',
            'type': 'watch',
            'file': 'lib/a.dart',
            'line': 12,
            'column': 5,
          },
        ],
        'generatedAt': '2026-01-01T00:00:00.000',
      };
      final compact = compactGraph(raw);
      expect(compact['nodes'], [
        {'name': 'a', 'status': 'active'},
        {'name': 'b'}, // unknown status dropped
      ]);
      expect(compact['edges'], [
        {'from': 'a', 'to': 'b', 'type': 'watch'},
      ]);
      expect(compact.containsKey('generatedAt'), isFalse);
    });
  });

  group('compactStats', () {
    test('drops the sparkline buckets and near-zero fields', () {
      final raw = {
        'providers': [
          {
            'provider': 'a',
            'totalUpdateCount': 5,
            'recentUpdateCount': 3,
            'updatesPerSecond': 0.3333333,
            'minLoadMs': null,
            'avgLoadMs': null,
            'maxLoadMs': null,
            'loadSampleCount': 0,
            'churnCount': 0,
            'updateBuckets': List.filled(24, 0),
            'isHighFrequency': false,
            'isSlowLoading': false,
          },
        ],
      };
      final entry = (compactStats(raw)['providers'] as List).single as Map;
      expect(entry, {'provider': 'a', 'updates': 5, 'rate': 0.33});
      expect(entry.containsKey('updateBuckets'), isFalse);
      expect(entry.containsKey('churn'), isFalse);
      expect(entry.containsKey('load'), isFalse);
    });

    test('keeps load stats and flags when present', () {
      final raw = {
        'providers': [
          {
            'provider': 'slow',
            'totalUpdateCount': 1,
            'updatesPerSecond': 0.1,
            'minLoadMs': 100,
            'avgLoadMs': 2500,
            'maxLoadMs': 3000,
            'loadSampleCount': 2,
            'churnCount': 3,
            'updateBuckets': List.filled(24, 0),
            'isHighFrequency': false,
            'isSlowLoading': true,
          },
        ],
      };
      final entry = (compactStats(raw)['providers'] as List).single as Map;
      expect(entry['load'], {'minMs': 100, 'avgMs': 2500, 'maxMs': 3000, 'n': 2});
      expect(entry['churn'], 3);
      expect(entry['slowLoading'], true);
      expect(entry.containsKey('highFrequency'), isFalse);
    });

    test('orders flagged and high-rate providers first', () {
      final raw = {
        'providers': [
          {'provider': 'quiet', 'totalUpdateCount': 1, 'updatesPerSecond': 0.1},
          {
            'provider': 'busy',
            'totalUpdateCount': 200,
            'updatesPerSecond': 20.0,
            'isHighFrequency': true,
          },
          {'provider': 'medium', 'totalUpdateCount': 5, 'updatesPerSecond': 0.5},
        ],
      };
      final order = (compactStats(raw)['providers'] as List)
          .map((e) => (e as Map)['provider'])
          .toList();
      expect(order, ['busy', 'medium', 'quiet']);
    });
  });

  test('compact output is dramatically smaller than the raw payload', () {
    // A realistic updated event with all the metadata the observer attaches.
    final rawEvent = {
      'seq': 42,
      'type': 'provider_updated',
      'providerId': '558123456',
      'instanceId': 'p7',
      'provider': 'cartProvider',
      'nameIsUnique': true,
      'dependencies': ['authProvider', 'apiClientProvider'],
      'dependenciesSource': 'static',
      'dependenciesLoadedAt': 1727000000000,
      'dependenciesGeneratedAt': 1726999999000,
      'timestamp': 1727000001234,
      'previousValue': serializeValue({'itemCount': 1, 'total': 19.0}),
      'newValue': serializeValue({'itemCount': 2, 'total': 42.5}),
    };
    final rawLen = rawEvent.toString().length;
    final compactLen = compactEvent(rawEvent).toString().length;
    expect(compactLen, lessThan(rawLen ~/ 2),
        reason: 'compact ($compactLen) should be < half of raw ($rawLen)');
  });
}

class _Model {
  Map<String, Object?> toJson() => {'a': 1, 'b': 'x'};
}

class _BigModel {
  Map<String, Object?> toJson() =>
      {for (var i = 0; i < 60; i++) 'field$i': i};
}

class _FakeAsyncData {
  @override
  String toString() => 'AsyncData<int>(value: 5)';
}
