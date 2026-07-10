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

  testWidgets('invalidate rebuilds a listened provider and resets its state',
      (tester) async {
    final observer = RiverpodDevToolsObserver();
    final container = ProviderContainer(observers: [observer]);
    addTearDown(container.dispose);

    final counterProvider = NotifierProvider<CounterNotifier, int>(
      CounterNotifier.new,
      name: 'counterProvider',
    );

    container.listen(counterProvider, (_, __) {});
    container.read(counterProvider.notifier).increment();
    expect(container.read(counterProvider), 1);

    final result = observer.executeCommand('invalidate', 'counterProvider');
    await tester.pump(const Duration(milliseconds: 150));

    expect(result['status'], 'ok');
    expect(container.read(counterProvider), 0);
  });

  testWidgets('refresh rebuilds immediately even without listeners',
      (tester) async {
    final observer = RiverpodDevToolsObserver();
    final container = ProviderContainer(observers: [observer]);
    addTearDown(container.dispose);

    var buildCount = 0;
    final countingProvider = Provider<int>(
      (ref) => ++buildCount,
      name: 'countingProvider',
    );

    container.read(countingProvider);
    expect(buildCount, 1);

    final result = observer.executeCommand('refresh', 'countingProvider');
    await tester.pump(const Duration(milliseconds: 150));

    expect(result['status'], 'ok');
    expect(buildCount, 2);
  });

  testWidgets('the resulting rebuild is visible in the event log',
      (tester) async {
    final observer = RiverpodDevToolsObserver();
    final container = ProviderContainer(observers: [observer]);
    addTearDown(container.dispose);

    final counterProvider = NotifierProvider<CounterNotifier, int>(
      CounterNotifier.new,
      name: 'counterProvider',
    );
    container.listen(counterProvider, (_, __) {});
    await tester.pump(const Duration(milliseconds: 150));

    final eventsBefore = observer.bufferedEventsForTesting.length;
    observer.executeCommand('refresh', 'counterProvider');
    await tester.pump(const Duration(milliseconds: 150));

    expect(
      observer.bufferedEventsForTesting.length,
      greaterThan(eventsBefore),
    );
  });

  testWidgets('unknown provider returns an error result', (tester) async {
    final observer = RiverpodDevToolsObserver();
    final container = ProviderContainer(observers: [observer]);
    addTearDown(container.dispose);

    final result = observer.executeCommand('invalidate', 'nopeProvider');
    expect(result['status'], 'error');
    expect(result['message'], contains('nopeProvider'));
  });

  testWidgets('unknown action returns an error result', (tester) async {
    final observer = RiverpodDevToolsObserver();
    final container = ProviderContainer(observers: [observer]);
    addTearDown(container.dispose);

    final result = observer.executeCommand('explode', 'counterProvider');
    expect(result['status'], 'error');
    expect(result['message'], contains('explode'));
  });

  testWidgets('a disposed provider can no longer be targeted',
      (tester) async {
    final observer = RiverpodDevToolsObserver();
    final container = ProviderContainer(observers: [observer]);
    addTearDown(container.dispose);

    final autoProvider = Provider.autoDispose<int>(
      (ref) => 1,
      name: 'autoProvider',
    );

    final subscription = container.listen(autoProvider, (_, __) {});
    expect(observer.executeCommand('invalidate', 'autoProvider')['status'],
        'ok');

    subscription.close();
    // Let the autoDispose cleanup run.
    await tester.pump(const Duration(milliseconds: 150));

    expect(
      observer.executeCommand('invalidate', 'autoProvider')['status'],
      'error',
    );
  });
}
