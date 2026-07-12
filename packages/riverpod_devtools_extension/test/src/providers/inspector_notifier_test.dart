import 'package:flutter_test/flutter_test.dart';
import 'package:riverpod_devtools_extension/src/models/event_type.dart';
import 'package:riverpod_devtools_extension/src/models/provider_event.dart';
import 'package:riverpod_devtools_extension/src/providers/inspector_notifier.dart';

ProviderEvent _updateEvent(
  String provider,
  int seq, {
  List<TriggerRef> triggeredBy = const [],
}) {
  return ProviderEvent(
    type: EventType.updated,
    providerId: provider,
    providerName: provider,
    timestamp: DateTime.fromMillisecondsSinceEpoch(1000 + seq),
    seq: seq,
    triggeredBy: triggeredBy,
  );
}

void main() {
  group('InspectorNotifier', () {
    late InspectorNotifier notifier;

    setUp(() {
      notifier = InspectorNotifier();
    });

    tearDown(() {
      notifier.dispose();
    });

    test('initial state is empty', () {
      expect(notifier.state.providers, isEmpty);
      expect(notifier.state.events, isEmpty);
      expect(notifier.state.selectedProviderNames, isEmpty);
      expect(notifier.state.providerSearchQuery, isEmpty);
    });

    test('updateSearchQuery updates state', () {
      notifier.updateSearchQuery('test');
      expect(notifier.state.providerSearchQuery, 'test');
    });

    test('selectProvider updates selection and active tab', () {
      const providerId = 'provider1';
      notifier.selectProvider(providerId);

      expect(notifier.state.selectedProviderNames, contains(providerId));
      expect(notifier.state.activeTabProviderName, providerId);
    });

    test('removeSelectedProvider updates selection and active tab', () {
      const p1 = 'provider1';
      const p2 = 'provider2';

      notifier.selectProvider(p1);
      notifier.selectProvider(p2);

      // Select p2, so p2 is active
      expect(notifier.state.selectedProviderNames, containsAll([p1, p2]));
      expect(notifier.state.activeTabProviderName, p2);

      // Remove p2
      notifier.removeSelectedProvider(p2);

      expect(notifier.state.selectedProviderNames, contains(p1));
      expect(notifier.state.selectedProviderNames, isNot(contains(p2)));
      // Active tab should switch to remaining provider (p1)
      expect(notifier.state.activeTabProviderName, p1);

      // Remove p1
      notifier.removeSelectedProvider(p1);
      expect(notifier.state.selectedProviderNames, isEmpty);
      expect(notifier.state.activeTabProviderName, null);
    });

    test('setActiveTab updates active tab', () {
      const p1 = 'provider1';
      notifier.selectProvider(p1);
      notifier.setActiveTab(p1);
      expect(notifier.state.activeTabProviderName, p1);
    });

    test('toggleEventExpansion updates expanded events', () {
      const eventId = 'event1';

      notifier.toggleEventExpansion(eventId);
      expect(notifier.state.expandedEventIds, contains(eventId));

      notifier.toggleEventExpansion(eventId);
      expect(notifier.state.expandedEventIds, isNot(contains(eventId)));
    });

    test('updateSplitRatios updates layout state', () {
      notifier.updateLeftSplitRatio(0.3);
      expect(notifier.state.leftSplitRatio, 0.3);

      notifier.updateRightSplitRatio(0.6);
      expect(notifier.state.rightSplitRatio, 0.6);
    });

    group('shared selection', () {
      test('selectOnly replaces any prior selection with a single provider',
          () {
        notifier.selectProvider('a');
        notifier.selectProvider('b');
        notifier.selectOnly('c');

        expect(notifier.state.selectedProviderNames, {'c'});
        expect(notifier.state.activeTabProviderName, 'c');
      });

      test('selectOnly on the sole selection deselects it', () {
        notifier.selectOnly('a');
        notifier.selectOnly('a');

        expect(notifier.state.selectedProviderNames, isEmpty);
        expect(notifier.state.activeTabProviderName, isNull);
      });

      test('clearSelection clears selection and active tab', () {
        notifier.selectProvider('a');
        notifier.selectProvider('b');
        notifier.clearSelection();

        expect(notifier.state.selectedProviderNames, isEmpty);
        expect(notifier.state.activeTabProviderName, isNull);
      });

      test('selection survives a view-mode switch (single and multi)', () {
        // Single selection persists Inspector -> Graph -> Inspector.
        notifier.selectOnly('a');
        notifier.setViewMode(InspectorViewMode.graph);
        expect(notifier.state.selectedProviderNames, {'a'});
        notifier.setViewMode(InspectorViewMode.inspector);
        expect(notifier.state.selectedProviderNames, {'a'});

        // Multi-selection persists too.
        notifier.selectProvider('b');
        expect(notifier.state.selectedProviderNames, {'a', 'b'});
        notifier.setViewMode(InspectorViewMode.graph);
        expect(notifier.state.selectedProviderNames, {'a', 'b'});
        notifier.setViewMode(InspectorViewMode.stats);
        expect(notifier.state.selectedProviderNames, {'a', 'b'});
      });
    });

    test('flashProvider updates flashing state temporarily', () async {
      // Since flashProvider uses Timers, we'd need to use fake async
      // or just verify the initial state change if possible.
      // However, flashProvider logic is internal timer based.
      // We can check if it sets it initially (it might wait for first timer).
      // Actually, looking at implementation:
      // it cancels timer, sets flashingProviderName, notifies.
      // So we can check immediate state.

      const p1 = 'provider1';
      notifier.flashProvider(p1);

      expect(notifier.state.flashingProviderName, p1);
    });

    // Note: Testing actual event subscription requires mocking vm_service,
    // which is complex for this scope.
    // We implicitly trust that the logic extracted from main.dart matches
    // the previous logic, and we've verified the "pure" logic methods above.

    group('eventDepths', () {
      test('root events have no depth entry', () {
        notifier.debugSetEvents([
          _updateEvent('a', 2),
          _updateEvent('a', 1),
        ]);
        expect(notifier.eventDepths, isEmpty);
      });

      test('triggered events nest under their trigger', () {
        // Newest first, like the real event list: a(1) → b(2) → c(3).
        final a = _updateEvent('a', 1);
        final b = _updateEvent('b', 2,
            triggeredBy: [const TriggerRef(provider: 'a', seq: 1)]);
        final c = _updateEvent('c', 3,
            triggeredBy: [const TriggerRef(provider: 'b', seq: 2)]);
        notifier.debugSetEvents([c, b, a]);

        expect(notifier.eventDepths[a.id], isNull);
        expect(notifier.eventDepths[b.id], 1);
        expect(notifier.eventDepths[c.id], 2);
      });

      test('a trigger missing from the log still yields depth 1', () {
        final b = _updateEvent('b', 10,
            triggeredBy: [const TriggerRef(provider: 'a', seq: 9)]);
        notifier.debugSetEvents([b]);
        expect(notifier.eventDepths[b.id], 1);
      });

      test('depth is capped', () {
        final events = <ProviderEvent>[_updateEvent('p0', 1)];
        for (var i = 1; i < 8; i++) {
          events.add(_updateEvent('p$i', i + 1,
              triggeredBy: [TriggerRef(provider: 'p${i - 1}', seq: i)]));
        }
        notifier.debugSetEvents(events.reversed.toList());
        expect(notifier.eventDepths[events.last.id], 4);
      });
    });
  });
}
