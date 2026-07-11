import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riverpod_devtools/riverpod_devtools.dart';

void main() {
  setUp(() => RiverpodDevToolsRegistry.instance.clear());
  tearDown(() => RiverpodDevToolsRegistry.instance.clear());

  testWidgets(
      'family instances get distinct names plus a shared family + argument',
      (tester) async {
    final observer = RiverpodDevToolsObserver();
    final container = ProviderContainer(observers: [observer]);
    addTearDown(container.dispose);

    final itemProvider = Provider.family<int, int>(
      (ref, id) => id * 10,
      name: 'itemProvider',
    );

    container.read(itemProvider(1));
    container.read(itemProvider(2));
    await tester.pump(const Duration(milliseconds: 150));

    final added = observer.bufferedEventsForTesting
        .where((e) => e['type'] == 'provider_added')
        .toList();

    // Two distinct entries, not one collapsed one.
    final names = added.map((e) => e['provider']).toSet();
    expect(names, {'itemProvider(1)', 'itemProvider(2)'});

    for (final event in added) {
      expect(event['family'], 'itemProvider');
      expect(event['argument'], anyOf('1', '2'));
    }
  });

  testWidgets('a non-family provider carries no family/argument fields',
      (tester) async {
    final observer = RiverpodDevToolsObserver();
    final container = ProviderContainer(observers: [observer]);
    addTearDown(container.dispose);

    final plainProvider = Provider<int>((ref) => 1, name: 'plainProvider');
    container.read(plainProvider);
    await tester.pump(const Duration(milliseconds: 150));

    final added = observer.bufferedEventsForTesting.firstWhere(
      (e) => e['type'] == 'provider_added' && e['provider'] == 'plainProvider',
    );
    expect(added.containsKey('family'), isFalse);
    expect(added.containsKey('argument'), isFalse);
  });
}
