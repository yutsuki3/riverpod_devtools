import 'package:flutter_test/flutter_test.dart';
import 'package:riverpod_devtools_extension/src/models/event_type.dart';
import 'package:riverpod_devtools_extension/src/models/provider_event.dart';
import 'package:riverpod_devtools_extension/src/utils/provider_stats.dart';

ProviderEvent _event(
  EventType type,
  String provider,
  DateTime timestamp, {
  Map<String, dynamic>? value,
}) {
  return ProviderEvent(
    type: type,
    providerId: provider,
    providerName: provider,
    timestamp: timestamp,
    value: value,
  );
}

void main() {
  final base = DateTime(2026, 1, 1, 12, 0, 0);

  group('computeProviderStats', () {
    test('empty input produces no stats', () {
      expect(computeProviderStats([], now: base), isEmpty);
    });

    test('counts total and recent updates within the window', () {
      final events = [
        _event(
            EventType.updated, 'a', base.subtract(const Duration(seconds: 30))),
        _event(
            EventType.updated, 'a', base.subtract(const Duration(seconds: 5))),
        _event(
            EventType.updated, 'a', base.subtract(const Duration(seconds: 1))),
      ];

      final stats = computeProviderStats(events, now: base).single;
      expect(stats.totalUpdateCount, 3);
      // Only the two updates within the last 10s count as "recent".
      expect(stats.recentUpdateCount, 2);
      expect(stats.updatesPerSecond, 0.2);
    });

    test('an update exactly at the window boundary counts as recent', () {
      final events = [
        _event(EventType.updated, 'a', base.subtract(kRecentUpdateWindow)),
      ];
      expect(
        computeProviderStats(events, now: base).single.recentUpdateCount,
        1,
      );
    });

    test('added events do not count as updates', () {
      final events = [
        _event(EventType.added, 'a', base),
        _event(EventType.updated, 'a', base),
      ];
      final stats = computeProviderStats(events, now: base).single;
      expect(stats.totalUpdateCount, 1);
    });

    test('isHighFrequency reflects the recent-update threshold', () {
      // 11 updates in the last 10s -> 1.1/s, below the 10/s threshold.
      final busy = List.generate(
        11,
        (i) => _event(EventType.updated, 'a',
            base.subtract(Duration(milliseconds: i * 100))),
      );
      expect(computeProviderStats(busy, now: base).single.isHighFrequency,
          isFalse);

      // 101 updates in the last 10s -> 10.1/s, above the threshold.
      final hot = List.generate(
        101,
        (i) => _event(EventType.updated, 'a',
            base.subtract(Duration(milliseconds: i * 90))),
      );
      expect(
          computeProviderStats(hot, now: base).single.isHighFrequency, isTrue);
    });

    test('pairs a loading->data transition into a load duration', () {
      final events = [
        _event(EventType.added, 'a', base, value: {'asyncState': 'loading'}),
        _event(EventType.updated, 'a', base.add(const Duration(seconds: 3)),
            value: {'asyncState': 'data'}),
      ];

      final stats = computeProviderStats(events, now: base).single;
      expect(stats.loadSampleCount, 1);
      expect(stats.minLoadDuration, const Duration(seconds: 3));
      expect(stats.maxLoadDuration, const Duration(seconds: 3));
      expect(stats.avgLoadDuration, const Duration(seconds: 3));
      expect(stats.isSlowLoading, isTrue);
    });

    test('pairs a loading->error transition too', () {
      final events = [
        _event(EventType.added, 'a', base, value: {'asyncState': 'loading'}),
        _event(EventType.updated, 'a', base.add(const Duration(seconds: 1)),
            value: {'asyncState': 'error'}),
      ];

      final stats = computeProviderStats(events, now: base).single;
      expect(stats.loadSampleCount, 1);
      expect(stats.maxLoadDuration, const Duration(seconds: 1));
    });

    test('a provider_failed event resolves a pending load', () {
      final events = [
        _event(EventType.added, 'a', base, value: {'asyncState': 'loading'}),
        _event(EventType.failed, 'a', base.add(const Duration(seconds: 2))),
      ];

      final stats = computeProviderStats(events, now: base).single;
      expect(stats.loadSampleCount, 1);
      expect(stats.maxLoadDuration, const Duration(seconds: 2));
    });

    test('min/avg/max across multiple load samples', () {
      final events = [
        _event(EventType.added, 'a', base, value: {'asyncState': 'loading'}),
        _event(EventType.updated, 'a', base.add(const Duration(seconds: 1)),
            value: {'asyncState': 'data'}),
        _event(EventType.updated, 'a', base.add(const Duration(seconds: 10)),
            value: {'asyncState': 'loading'}),
        _event(EventType.updated, 'a', base.add(const Duration(seconds: 13)),
            value: {'asyncState': 'data'}),
      ];

      final stats = computeProviderStats(events, now: base).single;
      expect(stats.loadSampleCount, 2);
      expect(stats.minLoadDuration, const Duration(seconds: 1));
      expect(stats.maxLoadDuration, const Duration(seconds: 3));
      expect(stats.avgLoadDuration, const Duration(seconds: 2));
      expect(stats.isSlowLoading, isTrue);
    });

    test('no load samples when nothing ever transitioned to loading', () {
      final events = [
        _event(EventType.updated, 'a', base, value: {'asyncState': 'data'}),
      ];
      final stats = computeProviderStats(events, now: base).single;
      expect(stats.loadSampleCount, 0);
      expect(stats.minLoadDuration, isNull);
      expect(stats.avgLoadDuration, isNull);
      expect(stats.maxLoadDuration, isNull);
      expect(stats.isSlowLoading, isFalse);
    });

    test('an unresolved trailing loading state produces no sample', () {
      final events = [
        _event(EventType.added, 'a', base, value: {'asyncState': 'loading'}),
      ];
      expect(computeProviderStats(events, now: base).single.loadSampleCount, 0);
    });

    test(
        'a load pending at dispose is not paired with a later instance\'s resolution',
        () {
      // The first instance starts loading and is torn down before it
      // resolves; the second instance loads for 1s. The sample must
      // reflect the second instance's 1s load, not 6s spanning the gap.
      final events = [
        _event(EventType.added, 'a', base, value: {'asyncState': 'loading'}),
        _event(EventType.disposed, 'a', base.add(const Duration(seconds: 1))),
        _event(EventType.added, 'a', base.add(const Duration(seconds: 5)),
            value: {'asyncState': 'loading'}),
        _event(EventType.updated, 'a', base.add(const Duration(seconds: 6)),
            value: {'asyncState': 'data'}),
      ];

      final stats = computeProviderStats(events, now: base).single;
      expect(stats.loadSampleCount, 1);
      expect(stats.maxLoadDuration, const Duration(seconds: 1));
    });

    test('churn count is one less than the number of added events', () {
      final events = [
        _event(EventType.added, 'a', base),
        _event(EventType.disposed, 'a', base.add(const Duration(seconds: 1))),
        _event(EventType.added, 'a', base.add(const Duration(seconds: 2))),
        _event(EventType.disposed, 'a', base.add(const Duration(seconds: 3))),
        _event(EventType.added, 'a', base.add(const Duration(seconds: 4))),
      ];
      expect(computeProviderStats(events, now: base).single.churnCount, 2);
    });

    test('a provider seen only once has zero churn', () {
      final events = [_event(EventType.added, 'a', base)];
      expect(computeProviderStats(events, now: base).single.churnCount, 0);
    });

    test(
        'events are processed in chronological order regardless of input order',
        () {
      // Input given newest-first (as InspectorState.events is stored), but
      // the loading->data pairing must still use real chronological order.
      final events = [
        _event(EventType.updated, 'a', base.add(const Duration(seconds: 3)),
            value: {'asyncState': 'data'}),
        _event(EventType.added, 'a', base, value: {'asyncState': 'loading'}),
      ];
      final stats = computeProviderStats(events,
              now: base.add(const Duration(seconds: 3)))
          .single;
      expect(stats.loadSampleCount, 1);
      expect(stats.maxLoadDuration, const Duration(seconds: 3));
    });

    test('multiple providers are aggregated independently and sorted by name',
        () {
      final events = [
        _event(EventType.updated, 'b', base),
        _event(EventType.updated, 'a', base),
        _event(EventType.updated, 'a', base),
      ];
      final stats = computeProviderStats(events, now: base);
      expect(stats.map((s) => s.providerName), ['a', 'b']);
      expect(stats[0].totalUpdateCount, 2);
      expect(stats[1].totalUpdateCount, 1);
    });
  });
}
