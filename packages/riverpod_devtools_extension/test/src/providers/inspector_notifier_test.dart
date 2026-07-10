import 'package:flutter_test/flutter_test.dart';
import 'package:riverpod_devtools_extension/src/models/event_type.dart';
import 'package:riverpod_devtools_extension/src/models/provider_event.dart';
import 'package:riverpod_devtools_extension/src/providers/inspector_notifier.dart';

ProviderEvent _event(
  String providerName,
  EventType type, {
  String? value,
  int timestampMicros = 0,
}) {
  return ProviderEvent(
    type: type,
    providerId: providerName,
    providerName: providerName,
    value: value != null ? {'type': 'String', 'value': value} : null,
    timestamp: DateTime.fromMicrosecondsSinceEpoch(timestampMicros),
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

    test('initial state enables all event types', () {
      expect(
        notifier.state.enabledEventTypes,
        containsAll(EventType.values),
      );
      expect(notifier.state.eventSearchQuery, isEmpty);
    });

    test('toggleEventTypeFilter toggles a type on and off', () {
      notifier.toggleEventTypeFilter(EventType.updated);
      expect(
        notifier.state.enabledEventTypes,
        isNot(contains(EventType.updated)),
      );
      expect(notifier.state.enabledEventTypes, contains(EventType.added));

      notifier.toggleEventTypeFilter(EventType.updated);
      expect(notifier.state.enabledEventTypes, contains(EventType.updated));
    });

    test('updateEventSearchQuery updates state', () {
      notifier.updateEventSearchQuery('todo');
      expect(notifier.state.eventSearchQuery, 'todo');
    });

    test('filteredEvents filters by event type', () {
      notifier.addEventForTest(_event('counterProvider', EventType.added,
          value: '0', timestampMicros: 1));
      notifier.addEventForTest(_event('counterProvider', EventType.updated,
          value: '1', timestampMicros: 2));
      notifier.addEventForTest(
          _event('counterProvider', EventType.disposed, timestampMicros: 3));

      expect(notifier.filteredEvents.length, 3);

      notifier.toggleEventTypeFilter(EventType.disposed);
      expect(notifier.filteredEvents.length, 2);
      expect(
        notifier.filteredEvents.every((e) => e.type != EventType.disposed),
        isTrue,
      );

      notifier.toggleEventTypeFilter(EventType.added);
      notifier.toggleEventTypeFilter(EventType.updated);
      expect(notifier.filteredEvents, isEmpty);
    });

    test('filteredEvents filters by search query on name and value', () {
      notifier.addEventForTest(_event('counterProvider', EventType.updated,
          value: '42', timestampMicros: 1));
      notifier.addEventForTest(_event('todoProvider', EventType.updated,
          value: 'buy milk', timestampMicros: 2));

      notifier.updateEventSearchQuery('todo');
      expect(notifier.filteredEvents.length, 1);
      expect(notifier.filteredEvents.first.providerName, 'todoProvider');

      // Matches value content, case-insensitively
      notifier.updateEventSearchQuery('MILK');
      expect(notifier.filteredEvents.length, 1);
      expect(notifier.filteredEvents.first.providerName, 'todoProvider');

      notifier.updateEventSearchQuery('42');
      expect(notifier.filteredEvents.length, 1);
      expect(notifier.filteredEvents.first.providerName, 'counterProvider');

      notifier.updateEventSearchQuery('nomatch');
      expect(notifier.filteredEvents, isEmpty);

      notifier.updateEventSearchQuery('');
      expect(notifier.filteredEvents.length, 2);
    });

    test('filteredEvents combines provider selection with filters', () {
      notifier.addEventForTest(_event('counterProvider', EventType.added,
          value: '0', timestampMicros: 1));
      notifier.addEventForTest(_event('todoProvider', EventType.added,
          value: 'buy milk', timestampMicros: 2));
      notifier.addEventForTest(_event('todoProvider', EventType.updated,
          value: 'buy bread', timestampMicros: 3));

      notifier.selectProvider('todoProvider');
      expect(notifier.filteredEvents.length, 2);

      notifier.toggleEventTypeFilter(EventType.added);
      expect(notifier.filteredEvents.length, 1);
      expect(notifier.filteredEvents.first.type, EventType.updated);
    });

    test('clearEvents removes all events and expansion state', () {
      notifier.addEventForTest(_event('counterProvider', EventType.added,
          value: '0', timestampMicros: 1));
      notifier.toggleEventExpansion(notifier.state.events.first.id);

      notifier.clearEvents();
      expect(notifier.state.events, isEmpty);
      expect(notifier.filteredEvents, isEmpty);
      expect(notifier.state.expandedEventIds, isEmpty);
    });

    // Note: Testing actual event subscription requires mocking vm_service,
    // which is complex for this scope.
    // We implicitly trust that the logic extracted from main.dart matches
    // the previous logic, and we've verified the "pure" logic methods above.
  });
}
