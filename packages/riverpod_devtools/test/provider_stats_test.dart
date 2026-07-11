import 'package:flutter_test/flutter_test.dart';
import 'package:riverpod_devtools/src/provider_stats.dart';

Map<String, Object?> _event(
  String type,
  String provider,
  DateTime timestamp, {
  Object? value,
  Object? newValue,
}) {
  return {
    'type': type,
    'provider': provider,
    'timestamp': timestamp.millisecondsSinceEpoch,
    if (value != null) 'value': value,
    if (newValue != null) 'newValue': newValue,
  };
}

void main() {
  final base = DateTime(2026, 1, 1, 12, 0, 0);

  List<Map<String, Object?>> statsFor(Map<String, Object?> result) =>
      (result['providers'] as List).cast<Map<String, Object?>>();

  group('buildProviderStats', () {
    test('empty input produces no provider entries', () {
      expect(statsFor(buildProviderStats([], now: base)), isEmpty);
    });

    test('counts total and recent updates within the window', () {
      final events = [
        _event(
          'provider_updated',
          'a',
          base.subtract(const Duration(seconds: 30)),
        ),
        _event(
          'provider_updated',
          'a',
          base.subtract(const Duration(seconds: 5)),
        ),
        _event(
          'provider_updated',
          'a',
          base.subtract(const Duration(seconds: 1)),
        ),
      ];

      final stat = statsFor(buildProviderStats(events, now: base)).single;
      expect(stat['totalUpdateCount'], 3);
      expect(stat['recentUpdateCount'], 2);
      expect(stat['updatesPerSecond'], 0.2);
    });

    test('added events do not count as updates', () {
      final events = [
        _event('provider_added', 'a', base),
        _event('provider_updated', 'a', base),
      ];
      final stat = statsFor(buildProviderStats(events, now: base)).single;
      expect(stat['totalUpdateCount'], 1);
    });

    test(
      'isHighFrequency flips once the recent rate exceeds the threshold',
      () {
        final hot = List.generate(
          101,
          (i) => _event(
            'provider_updated',
            'a',
            base.subtract(Duration(milliseconds: i * 90)),
          ),
        );
        final stat = statsFor(buildProviderStats(hot, now: base)).single;
        expect(stat['isHighFrequency'], isTrue);
      },
    );

    test('pairs a loading->data transition into a load duration', () {
      final events = [
        _event('provider_added', 'a', base, value: {'asyncState': 'loading'}),
        _event(
          'provider_updated',
          'a',
          base.add(const Duration(seconds: 3)),
          newValue: {'asyncState': 'data'},
        ),
      ];

      final stat = statsFor(buildProviderStats(events, now: base)).single;
      expect(stat['loadSampleCount'], 1);
      expect(stat['minLoadMs'], 3000);
      expect(stat['avgLoadMs'], 3000);
      expect(stat['maxLoadMs'], 3000);
      expect(stat['isSlowLoading'], isTrue);
    });

    test('a provider_failed event resolves a pending load', () {
      final events = [
        _event('provider_added', 'a', base, value: {'asyncState': 'loading'}),
        _event('provider_failed', 'a', base.add(const Duration(seconds: 2))),
      ];

      final stat = statsFor(buildProviderStats(events, now: base)).single;
      expect(stat['loadSampleCount'], 1);
      expect(stat['maxLoadMs'], 2000);
    });

    test('no load samples when nothing ever transitioned to loading', () {
      final events = [
        _event('provider_updated', 'a', base, newValue: {'asyncState': 'data'}),
      ];
      final stat = statsFor(buildProviderStats(events, now: base)).single;
      expect(stat['loadSampleCount'], 0);
      expect(stat['minLoadMs'], isNull);
      expect(stat['isSlowLoading'], isFalse);
    });

    test(
      'a load pending at dispose is not paired with a later instance\'s resolution',
      () {
        // The first instance starts loading and is torn down before it
        // resolves; the second instance loads for 1s. The sample must
        // reflect the second instance's 1s load, not 6s spanning the gap.
        final events = [
          _event('provider_added', 'a', base, value: {'asyncState': 'loading'}),
          _event(
            'provider_disposed',
            'a',
            base.add(const Duration(seconds: 1)),
          ),
          _event(
            'provider_added',
            'a',
            base.add(const Duration(seconds: 5)),
            value: {'asyncState': 'loading'},
          ),
          _event(
            'provider_updated',
            'a',
            base.add(const Duration(seconds: 6)),
            newValue: {'asyncState': 'data'},
          ),
        ];

        final stat = statsFor(buildProviderStats(events, now: base)).single;
        expect(stat['loadSampleCount'], 1);
        expect(stat['maxLoadMs'], 1000);
      },
    );

    test('churn count is one less than the number of added events', () {
      final events = [
        _event('provider_added', 'a', base),
        _event('provider_disposed', 'a', base.add(const Duration(seconds: 1))),
        _event('provider_added', 'a', base.add(const Duration(seconds: 2))),
        _event('provider_disposed', 'a', base.add(const Duration(seconds: 3))),
        _event('provider_added', 'a', base.add(const Duration(seconds: 4))),
      ];
      final stat = statsFor(buildProviderStats(events, now: base)).single;
      expect(stat['churnCount'], 2);
    });

    test(
      'events are processed in chronological order regardless of input order',
      () {
        final events = [
          _event(
            'provider_updated',
            'a',
            base.add(const Duration(seconds: 3)),
            newValue: {'asyncState': 'data'},
          ),
          _event('provider_added', 'a', base, value: {'asyncState': 'loading'}),
        ];
        final stat =
            statsFor(
              buildProviderStats(
                events,
                now: base.add(const Duration(seconds: 3)),
              ),
            ).single;
        expect(stat['loadSampleCount'], 1);
        expect(stat['maxLoadMs'], 3000);
      },
    );

    test('the provider filter restricts the result to one provider', () {
      final events = [
        _event('provider_updated', 'a', base),
        _event('provider_updated', 'b', base),
      ];
      final stats = statsFor(
        buildProviderStats(events, now: base, provider: 'a'),
      );
      expect(stats.map((s) => s['provider']), ['a']);
    });

    test(
      'multiple providers are aggregated independently and sorted by name',
      () {
        final events = [
          _event('provider_updated', 'b', base),
          _event('provider_updated', 'a', base),
          _event('provider_updated', 'a', base),
        ];
        final stats = statsFor(buildProviderStats(events, now: base));
        expect(stats.map((s) => s['provider']), ['a', 'b']);
        expect(stats[0]['totalUpdateCount'], 2);
        expect(stats[1]['totalUpdateCount'], 1);
      },
    );

    test('events with a non-string provider field are ignored', () {
      final events = [
        {'type': 'provider_updated', 'provider': 42, 'timestamp': 0},
      ];
      expect(statsFor(buildProviderStats(events, now: base)), isEmpty);
    });
  });
}
