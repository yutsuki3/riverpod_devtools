import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riverpod_devtools/riverpod_devtools.dart';

class Counter extends Notifier<int> {
  @override
  int build() => 0;
}

final namedProvider =
    NotifierProvider<Counter, int>(Counter.new, name: 'namedProvider');

// Two UNNAMED providers of the same type: both report the display name
// "Provider<int>" — the collision the instanceId is meant to disambiguate.
final unnamedA = Provider<int>((ref) => 1);
final unnamedB = Provider<int>((ref) => 2);

// Two providers deliberately sharing an explicit name.
final dupeA = Provider<int>((ref) => 1, name: 'dupe');
final dupeB = Provider<int>((ref) => 2, name: 'dupe');

extension _Events on RiverpodDevToolsObserver {
  List<Map<String, Object?>> get added => bufferedEventsForTesting
      .where((e) => e['type'] == 'provider_added')
      .toList();
}

void main() {
  setUp(() => RiverpodDevToolsRegistry.instance.clear());
  tearDown(() => RiverpodDevToolsRegistry.instance.clear());

  testWidgets('every event carries an instanceId', (tester) async {
    final observer = RiverpodDevToolsObserver();
    final container = ProviderContainer(observers: [observer]);
    addTearDown(container.dispose);

    container.read(namedProvider);
    await tester.pump(const Duration(milliseconds: 50));

    final event = observer.added.single;
    expect(event['instanceId'], isA<String>());
    expect(event['provider'], 'namedProvider');
    expect(event['nameIsUnique'], isTrue);
  });

  testWidgets('the same provider keeps one instanceId across its events',
      (tester) async {
    final observer = RiverpodDevToolsObserver();
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: ProviderContainer(observers: [observer]),
        child: MaterialApp(
          home: Consumer(
            builder: (context, ref, _) => Text('${ref.watch(namedProvider)}',
                textDirection: TextDirection.ltr),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 50));

    final firstId = observer.added.first['instanceId'];
    expect(firstId, isA<String>());

    // Invalidate/refresh churns the element; the id must not change.
    observer.executeCommand('refresh', 'namedProvider');
    await tester.pump(const Duration(milliseconds: 50));

    final ids = observer.bufferedEventsForTesting
        .where((e) => e['provider'] == 'namedProvider')
        .map((e) => e['instanceId'])
        .toSet();
    expect(ids, {firstId}, reason: 'instanceId is stable across churn');
  });

  testWidgets(
      'two providers sharing a display name get distinct instanceIds and are '
      'flagged non-unique', (tester) async {
    final observer = RiverpodDevToolsObserver();
    final container = ProviderContainer(observers: [observer]);
    addTearDown(container.dispose);

    container.read(unnamedA);
    container.read(unnamedB);
    await tester.pump(const Duration(milliseconds: 50));

    final collisions = observer.added
        .where((e) => e['provider'] == 'Provider<int>')
        .toList();
    expect(collisions, hasLength(2));

    final ids = collisions.map((e) => e['instanceId']).toSet();
    expect(ids, hasLength(2), reason: 'distinct instanceIds, no collapse');

    // The later event, emitted once both are registered, is flagged
    // non-unique.
    expect(collisions.last['nameIsUnique'], isFalse);
  });

  group('executeCommand target resolution', () {
    testWidgets('a unique name resolves and the result echoes name + id',
        (tester) async {
      final observer = RiverpodDevToolsObserver();
      final container = ProviderContainer(observers: [observer]);
      addTearDown(container.dispose);

      container.listen(namedProvider, (_, __) {});
      await tester.pump(const Duration(milliseconds: 50));
      final id = observer.added.single['instanceId'];

      final result = observer.executeCommand('invalidate', 'namedProvider');
      await tester.pump(const Duration(milliseconds: 50));
      expect(result['status'], 'ok');
      expect(result['provider'], 'namedProvider');
      expect(result['instanceId'], id);
    });

    testWidgets('an ambiguous name is rejected with the candidate ids',
        (tester) async {
      final observer = RiverpodDevToolsObserver();
      final container = ProviderContainer(observers: [observer]);
      addTearDown(container.dispose);

      container.read(dupeA);
      container.read(dupeB);
      await tester.pump(const Duration(milliseconds: 50));

      final result = observer.executeCommand('invalidate', 'dupe');
      expect(result['status'], 'error');
      expect(result['ambiguous'], isTrue);
      final candidates = (result['candidates'] as List).cast<String>();
      expect(candidates, hasLength(2));
      expect(result['message'], contains('ambiguous'));
    });

    testWidgets('targeting by instanceId works even when the name is shared',
        (tester) async {
      final observer = RiverpodDevToolsObserver();
      final container = ProviderContainer(observers: [observer]);
      addTearDown(container.dispose);

      container.read(dupeA);
      container.read(dupeB);
      await tester.pump(const Duration(milliseconds: 50));

      final candidates = (observer.executeCommand('invalidate', 'dupe')
          ['candidates'] as List).cast<String>();

      // Each id resolves to exactly one provider — no ambiguity.
      for (final id in candidates) {
        final result = observer.executeCommand('invalidate', id);
        expect(result['status'], 'ok', reason: 'id $id should resolve');
        expect(result['instanceId'], id);
      }
      await tester.pump(const Duration(milliseconds: 50));
    });

    testWidgets('an unknown name/id is reported as unknown', (tester) async {
      final observer = RiverpodDevToolsObserver();
      final container = ProviderContainer(observers: [observer]);
      addTearDown(container.dispose);

      final result = observer.executeCommand('invalidate', 'ghostProvider');
      expect(result['status'], 'error');
      expect(result['message'], contains('unknown'));
      expect(result.containsKey('ambiguous'), isFalse);
    });
  });
}
