import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riverpod_devtools/riverpod_devtools.dart';

void main() {
  setUp(() => RiverpodDevToolsRegistry.instance.clear());
  tearDown(() => RiverpodDevToolsRegistry.instance.clear());

  testWidgets('a throwing FutureProvider produces a provider_failed event',
      (tester) async {
    final observer = RiverpodDevToolsObserver();
    final container = ProviderContainer(observers: [observer]);
    addTearDown(container.dispose);

    final failingProvider = FutureProvider<int>(
      (ref) async => throw StateError('boom'),
      name: 'failingProvider',
    );

    container.listen(failingProvider, (_, __) {});
    await tester.pump(const Duration(milliseconds: 150));

    final failed = observer.bufferedEventsForTesting.firstWhere(
      (e) => e['type'] == 'provider_failed',
    );
    expect(failed['provider'], 'failingProvider');
    expect(failed['seq'], isA<int>());

    final error = failed['error'] as Map;
    expect(error['type'], 'StateError');
    expect(error['message'], contains('boom'));
    expect(error['stackTrace'], isA<String>());
    expect((error['stackTrace'] as String), isNotEmpty);
  });

  testWidgets('a synchronously throwing provider produces a failed event',
      (tester) async {
    final observer = RiverpodDevToolsObserver();
    final container = ProviderContainer(observers: [observer]);
    addTearDown(container.dispose);

    final syncFailingProvider = Provider<int>(
      (ref) => throw ArgumentError('bad'),
      name: 'syncFailingProvider',
    );

    // Riverpod 3.x wraps sync init errors in a ProviderException; either
    // way reading the failed provider throws.
    expect(() => container.read(syncFailingProvider), throwsA(anything));
    await tester.pump(const Duration(milliseconds: 150));

    final failed = observer.bufferedEventsForTesting.firstWhere(
      (e) => e['type'] == 'provider_failed',
    );
    expect(failed['provider'], 'syncFailingProvider');
    expect((failed['error'] as Map)['message'], contains('bad'));
  });
}
