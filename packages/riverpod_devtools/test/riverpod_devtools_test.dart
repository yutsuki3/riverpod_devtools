import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riverpod_devtools/riverpod_devtools.dart';

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

    // Should trigger didUpdateProvider (though value is same, it might not re-emit depending on provider logic,
    // so let's use a StateProvider for updates)
    final stateProvider = StateProvider<int>((ref) => 0);
    container.read(stateProvider);
    container.read(stateProvider.notifier).state = 1;

    // Should trigger didDisposeProvider
    container.dispose();
  });
}
