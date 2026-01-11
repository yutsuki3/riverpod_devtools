import 'package:flutter_test/flutter_test.dart';
import 'package:riverpod_devtools_extension/src/providers/inspector_notifier.dart';

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
  });
}
