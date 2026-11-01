import 'package:flutter_test/flutter_test.dart';
import 'package:riverpod_devtools_extension/src/models/event_type.dart';
import 'package:riverpod_devtools_extension/src/models/provider_event.dart';
import 'package:riverpod_devtools_extension/src/models/provider_info.dart';
import 'package:riverpod_devtools_extension/src/utils/provider_brief.dart';

ProviderInfo _info({
  Map<String, dynamic> value = const {'type': 'int', 'value': 3},
  Map<String, dynamic>? lastError,
  DependencySource source = DependencySource.static,
  List<String> dependencies = const [],
  List<DependencyDetail> details = const [],
  String? loadError,
}) =>
    ProviderInfo(
      id: '1',
      name: 'counterProvider',
      value: value,
      status: ProviderStatus.active,
      lastError: lastError,
      dependenciesSource: source,
      dependencies: dependencies,
      dependencyDetails: details,
      dependenciesLoadError: loadError,
    );

ProviderEvent _event(EventType type,
        {int? seq, dynamic prev, dynamic value, List<TriggerRef>? by}) =>
    ProviderEvent(
      type: type,
      providerId: '1',
      providerName: 'counterProvider',
      previousValue: prev == null ? null : {'type': 'int', 'value': prev},
      value: value == null ? null : {'type': 'int', 'value': value},
      timestamp: DateTime(2026, 1, 1, 9, 5, 7),
      seq: seq,
      triggeredBy: by ?? const [],
    );

void main() {
  group('buildProviderBrief', () {
    test('unwraps the serializer wrappers into plain JSON', () {
      final text = buildProviderBrief(
        _info(value: {
          'type': 'Map',
          'string': '{a: 1}',
          'entries': [
            {
              'key': 'a',
              'value': {'type': 'int', 'string': '1', 'value': 1},
            },
            {
              'key': 'list',
              'value': {
                'type': 'List',
                'string': '[x]',
                'items': [
                  {'type': 'String', 'value': 'x'},
                ],
              },
            },
          ],
        }),
        usedBy: const [],
        events: const [],
      );

      expect(text, contains('"a": 1'));
      expect(text, contains('"list": [\n    "x"\n  ]'));
      expect(text, isNot(contains('"type"')));
    });

    test('flags truncated values', () {
      final long = 'x' * 3000;
      final text = buildProviderBrief(
        _info(value: {'type': 'String', 'value': long}),
        usedBy: const [],
        events: const [],
      );
      expect(text, contains('### Current value (truncated)'));
      expect(text, contains('…'));

      final lossy = buildProviderBrief(
        _info(value: {'type': 'Foo', 'string': 'foo', 'lossy': true}),
        usedBy: const [],
        events: const [],
      );
      expect(lossy, contains('(truncated)'));
    });

    test('includes the error with a trimmed stack trace', () {
      final stack = List.generate(30, (i) => '#$i frame').join('\n');
      final text = buildProviderBrief(
        _info(lastError: {
          'type': 'StateError',
          'message': 'boom',
          'stackTrace': stack,
        }),
        usedBy: const [],
        events: const [],
      );
      expect(text, contains('### Error'));
      expect(text, contains('StateError'));
      expect(text, contains('boom'));
      expect(text, contains('#9 frame'));
      expect(text, isNot(contains('#10 frame')));
    });

    test('omits the error section for a healthy provider', () {
      expect(
        buildProviderBrief(_info(), usedBy: const [], events: const []),
        isNot(contains('### Error')),
      );
    });

    test('lists dependencies with their kind, and dependents', () {
      final text = buildProviderBrief(
        _info(
          dependencies: ['a', 'b'],
          details: const [DependencyDetail(providerName: 'a', type: 'watch')],
        ),
        usedBy: const ['ui'],
        events: const [],
      );
      expect(text, contains('- Depends on: a (watch), b'));
      expect(text, contains('- Used by: ui'));
    });

    test('says why dependencies are unavailable instead of "none"', () {
      for (final (source, needle) in [
        (DependencySource.none, 'no static dependency data loaded'),
        (DependencySource.nameMismatch, 'no static data matches'),
        (DependencySource.loadError, 'failed to load (bad json)'),
      ]) {
        final text = buildProviderBrief(
          _info(source: source, loadError: 'bad json'),
          usedBy: const [],
          events: const [],
        );
        expect(text, contains(needle), reason: '$source');
        // Every unavailable case tells the reader how to get the data back.
        expect(text, contains('dart run riverpod_devtools:analyze'),
            reason: '$source');
        expect(text, isNot(contains('Depends on: none')), reason: '$source');
      }
    });

    test('shows the newest events first, capped, with seq and trigger', () {
      final events = [
        _event(EventType.updated,
            seq: 9,
            prev: 2,
            value: 3,
            by: const [TriggerRef(provider: 'other', seq: 8)]),
        for (var i = 8; i >= 1; i--)
          _event(EventType.updated, seq: i, prev: i, value: i + 1),
      ];
      final text =
          buildProviderBrief(_info(), usedBy: const [], events: events);

      expect(
          text, contains('- #9 09:05:07 updated: 2 -> 3 (triggered by other)'));
      expect(text, contains('#5 '));
      expect(text, isNot(contains('#4 ')), reason: 'capped at 5 events');
    });

    test('notes when there are no events', () {
      expect(
        buildProviderBrief(_info(), usedBy: const [], events: const []),
        contains('- none recorded'),
      );
    });
  });
}
