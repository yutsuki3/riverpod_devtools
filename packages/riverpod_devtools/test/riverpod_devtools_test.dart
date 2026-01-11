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
  testWidgets('RiverpodDevToolsObserver posts events', (tester) async {
    // We can't easily intercept developer.postEvent in a unit test without
    // a custom zone specification or using a mock.
    // However, for a basic sanity check, we can ensure the observer
    // doesn't crash the app and runs its logic.

    final container = ProviderContainer(
      observers: [
        RiverpodDevToolsObserver(),
      ],
    );

    final provider = Provider<int>((ref) => 0);

    // Should trigger didAddProvider
    container.read(provider);

    // Should trigger didUpdateProvider
    final counterProvider = NotifierProvider<CounterNotifier, int>(
      CounterNotifier.new,
    );
    container.read(counterProvider);
    container.read(counterProvider.notifier).increment();

    // Wait for any pending timers (dependency tracker flush timer)
    await tester.pump(const Duration(milliseconds: 150));

    // Should trigger didDisposeProvider
    container.dispose();
  });
}
