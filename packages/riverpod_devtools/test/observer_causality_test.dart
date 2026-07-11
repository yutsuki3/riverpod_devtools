import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riverpod_devtools/riverpod_devtools.dart';

class CounterNotifier extends Notifier<int> {
  @override
  int build() => 0;

  void increment() {
    state++;
  }
}

void main() {
  setUp(() => RiverpodDevToolsRegistry.instance.clear());
  tearDown(() => RiverpodDevToolsRegistry.instance.clear());

  testWidgets('events carry monotonically increasing seq', (tester) async {
    final observer = RiverpodDevToolsObserver();
    final container = ProviderContainer(observers: [observer]);
    addTearDown(container.dispose);

    final counterProvider = NotifierProvider<CounterNotifier, int>(
      CounterNotifier.new,
      name: 'counterProvider',
    );

    container.read(counterProvider);
    container.read(counterProvider.notifier).increment();
    container.read(counterProvider.notifier).increment();
    await tester.pump(const Duration(milliseconds: 150));

    final events = observer.bufferedEventsForTesting;
    expect(events.length, greaterThanOrEqualTo(3));
    final seqs = events.map((e) => e['seq'] as int).toList();
    for (var i = 1; i < seqs.length; i++) {
      expect(seqs[i], greaterThan(seqs[i - 1]));
    }
  });

  testWidgets(
      'a dependent update is attributed to the dependency that triggered it',
      (tester) async {
    RiverpodDevToolsRegistry.instance.register(
      const StaticProviderMetadata(
        name: 'doubledProvider',
        dependencies: [
          StaticDependency(
            providerName: 'counterProvider',
            type: DependencyType.watch,
            file: 'lib/test.dart',
            line: 1,
            column: 1,
          ),
        ],
      ),
    );

    final observer = RiverpodDevToolsObserver();
    final container = ProviderContainer(observers: [observer]);
    addTearDown(container.dispose);

    final counterProvider = NotifierProvider<CounterNotifier, int>(
      CounterNotifier.new,
      name: 'counterProvider',
    );
    final doubledProvider = Provider<int>(
      (ref) => ref.watch(counterProvider) * 2,
      name: 'doubledProvider',
    );

    // An active subscription is required for the dependent to rebuild
    // eagerly when its dependency changes (a bare read() creates the
    // element but does not keep it live on Riverpod 3.x).
    container.listen(doubledProvider, (_, __) {});
    container.read(counterProvider.notifier).increment();
    await tester.pump(const Duration(milliseconds: 150));

    final events = observer.bufferedEventsForTesting;

    final counterUpdate = events.firstWhere((e) =>
        e['type'] == 'provider_updated' && e['provider'] == 'counterProvider');
    final doubledUpdate = events.firstWhere((e) =>
        e['type'] == 'provider_updated' && e['provider'] == 'doubledProvider');

    // The counter update itself has no dependencies, so no trigger.
    expect(counterUpdate['triggeredBy'], isNull);

    // The added event carries full dependency details from the registry.
    final doubledAdded = events.firstWhere((e) =>
        e['type'] == 'provider_added' && e['provider'] == 'doubledProvider');
    final details = doubledAdded['dependencyDetails'] as List;
    expect(details, hasLength(1));
    final detail = details.single as Map;
    expect(detail['providerName'], 'counterProvider');
    expect(detail['type'], 'watch');

    // The doubled update was caused by the counter update.
    expect(doubledUpdate['triggerConfidence'], 'inferred');
    final triggers = doubledUpdate['triggeredBy'] as List;
    expect(triggers, hasLength(1));
    final trigger = triggers.single as Map;
    expect(trigger['provider'], 'counterProvider');
    expect(trigger['seq'], counterUpdate['seq']);
  });

  testWidgets('updates of unrelated providers are not linked',
      (tester) async {
    RiverpodDevToolsRegistry.instance.register(
      const StaticProviderMetadata(name: 'otherProvider', dependencies: []),
    );

    final observer = RiverpodDevToolsObserver();
    final container = ProviderContainer(observers: [observer]);
    addTearDown(container.dispose);

    final counterProvider = NotifierProvider<CounterNotifier, int>(
      CounterNotifier.new,
      name: 'counterProvider',
    );
    final otherProvider = NotifierProvider<CounterNotifier, int>(
      CounterNotifier.new,
      name: 'otherProvider',
    );

    container.read(counterProvider);
    container.read(otherProvider);
    container.read(counterProvider.notifier).increment();
    container.read(otherProvider.notifier).increment();
    await tester.pump(const Duration(milliseconds: 150));

    final otherUpdate = observer.bufferedEventsForTesting.firstWhere((e) =>
        e['type'] == 'provider_updated' && e['provider'] == 'otherProvider');
    expect(otherUpdate['triggeredBy'], isNull);
    expect(otherUpdate['triggerConfidence'], isNull);
  });
}
