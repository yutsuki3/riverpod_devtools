import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:riverpod_devtools_extension/src/models/event_type.dart';
import 'package:riverpod_devtools_extension/src/models/provider_event.dart';
import 'package:riverpod_devtools_extension/src/models/provider_info.dart';
import 'package:riverpod_devtools_extension/src/utils/session_io.dart';

void main() {
  group('encodeSession / decodeSession', () {
    test('round-trips providers and events losslessly through JSON', () {
      final loadedAt = DateTime(2026, 1, 1, 12, 0, 0);
      final generatedAt = DateTime(2026, 1, 1, 11, 0, 0);

      final providers = <String, ProviderInfo>{
        'counterProvider': ProviderInfo(
          id: '1',
          name: 'counterProvider',
          value: const {'type': 'int', 'value': 3},
          status: ProviderStatus.active,
          dependenciesSource: DependencySource.static,
          dependenciesLoadedAt: loadedAt,
          dependenciesGeneratedAt: generatedAt,
        ),
        'doubledProvider': ProviderInfo(
          id: '2',
          name: 'doubledProvider',
          value: const {'type': 'int', 'value': 6},
          status: ProviderStatus.active,
          dependencies: const ['counterProvider'],
          dependenciesSource: DependencySource.static,
          dependencyDetails: const [
            DependencyDetail(
              providerName: 'counterProvider',
              type: 'watch',
              file: 'lib/providers.dart',
              line: 12,
            ),
          ],
        ),
        'userProvider(1)': ProviderInfo(
          id: '3',
          name: 'userProvider(1)',
          value: const {'type': 'User', 'string': 'User(1)'},
          status: ProviderStatus.disposed,
          family: 'userProvider',
          argument: '1',
        ),
        'brokenProvider': ProviderInfo(
          id: '4',
          name: 'brokenProvider',
          value: const {'type': 'null', 'value': null},
          status: ProviderStatus.active,
          lastError: const {
            'type': 'StateError',
            'message': 'boom',
            'stackTrace': '#0 ...',
          },
        ),
      };

      final events = <ProviderEvent>[
        ProviderEvent(
          type: EventType.updated,
          providerId: '2',
          providerName: 'doubledProvider',
          previousValue: const {'type': 'int', 'value': 4},
          value: const {'type': 'int', 'value': 6},
          timestamp: DateTime(2026, 1, 1, 12, 0, 5),
          seq: 8,
          triggeredBy: const [TriggerRef(provider: 'counterProvider', seq: 7)],
        ),
        ProviderEvent(
          type: EventType.failed,
          providerId: '4',
          providerName: 'brokenProvider',
          timestamp: DateTime(2026, 1, 1, 12, 0, 3),
          seq: 5,
          error: const {'type': 'StateError', 'message': 'boom'},
        ),
        ProviderEvent(
          type: EventType.added,
          providerId: '1',
          providerName: 'counterProvider',
          value: const {'type': 'int', 'value': 1},
          timestamp: DateTime(2026, 1, 1, 12, 0, 0),
          seq: 1,
        ),
      ];

      // Encode -> JSON string -> decode, to prove it survives real
      // serialization, not just the in-memory map.
      final encoded = encodeSession(providers: providers, events: events);
      final roundTripped =
          decodeSession(jsonDecode(jsonEncode(encoded)) as Map<String, dynamic>);

      expect(roundTripped.providers.keys, providers.keys);
      expect(roundTripped.events.length, events.length);

      final doubled = roundTripped.providers['doubledProvider']!;
      expect(doubled.dependencies, ['counterProvider']);
      expect(doubled.dependenciesSource, DependencySource.static);
      expect(doubled.dependencyDetails.single.type, 'watch');
      expect(doubled.dependencyDetails.single.line, 12);

      final counter = roundTripped.providers['counterProvider']!;
      expect(counter.dependenciesLoadedAt, loadedAt);
      expect(counter.dependenciesGeneratedAt, generatedAt);

      final family = roundTripped.providers['userProvider(1)']!;
      expect(family.family, 'userProvider');
      expect(family.argument, '1');
      expect(family.status, ProviderStatus.disposed);

      final broken = roundTripped.providers['brokenProvider']!;
      expect(broken.lastError!['message'], 'boom');

      final update = roundTripped.events.first;
      expect(update.type, EventType.updated);
      expect(update.previousValue, {'type': 'int', 'value': 4});
      expect(update.value, {'type': 'int', 'value': 6});
      expect(update.seq, 8);
      expect(update.triggeredBy.single.provider, 'counterProvider');
      expect(update.triggeredBy.single.seq, 7);

      final failed = roundTripped.events[1];
      expect(failed.type, EventType.failed);
      expect(failed.error!['message'], 'boom');
    });

    test('rejects JSON without a formatVersion', () {
      expect(
        () => decodeSession(const {'providers': [], 'events': []}),
        throwsA(isA<SessionDecodeException>()),
      );
    });

    test('rejects a newer format version', () {
      expect(
        () => decodeSession({
          'formatVersion': kSessionFormatVersion + 1,
          'providers': const [],
          'events': const [],
        }),
        throwsA(isA<SessionDecodeException>()),
      );
    });

    test('tolerates missing optional fields', () {
      final decoded = decodeSession({
        'formatVersion': kSessionFormatVersion,
        'providers': [
          {'id': '1', 'name': 'p', 'value': null, 'status': 'active'},
        ],
        'events': [
          {'type': 'added', 'providerId': '1', 'providerName': 'p'},
        ],
      });
      expect(decoded.providers['p']!.dependencies, isEmpty);
      expect(decoded.providers['p']!.family, isNull);
      expect(decoded.events.single.type, EventType.added);
    });
  });
}
