import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_devtools/riverpod_devtools.dart';

void main() {
  group('Observer Integration with Static Dependencies', () {
    setUp(() {
      // Clear registry before each test
      RiverpodDevToolsRegistry.instance.clear();
    });

    test('uses static dependencies when available', () {
      // Register static metadata
      RiverpodDevToolsRegistry.instance.register(
        const StaticProviderMetadata(
          name: 'testProvider',
          dependencies: [
            StaticDependency(
              providerName: 'dep1',
              type: DependencyType.watch,
              file: 'lib/test.dart',
              line: 10,
              column: 5,
            ),
            StaticDependency(
              providerName: 'dep2',
              type: DependencyType.read,
              file: 'lib/test.dart',
              line: 11,
              column: 5,
            ),
          ],
        ),
      );

      // Verify registry has the metadata
      expect(RiverpodDevToolsRegistry.instance.hasMetadata('testProvider'), isTrue);
      expect(
        RiverpodDevToolsRegistry.instance.getDependencyNames('testProvider'),
        ['dep1', 'dep2'],
      );
    });

    test('getDependenciesWithDetails returns full metadata', () {
      RiverpodDevToolsRegistry.instance.register(
        const StaticProviderMetadata(
          name: 'userProvider',
          dependencies: [
            StaticDependency(
              providerName: 'authProvider',
              type: DependencyType.watch,
              file: 'lib/user.dart',
              line: 42,
              column: 17,
            ),
          ],
        ),
      );

      final details = RiverpodDevToolsRegistry.instance
          .getDependenciesWithDetails('userProvider');

      expect(details.length, 1);
      expect(details[0]['providerName'], 'authProvider');
      expect(details[0]['type'], 'watch');
      expect(details[0]['file'], 'lib/user.dart');
      expect(details[0]['line'], 42);
      expect(details[0]['column'], 17);
    });

    test('returns empty list for unregistered provider', () {
      expect(
        RiverpodDevToolsRegistry.instance.getDependencyNames('nonexistent'),
        isEmpty,
      );
      expect(
        RiverpodDevToolsRegistry.instance.hasMetadata('nonexistent'),
        isFalse,
      );
    });

    test('can register multiple providers', () {
      RiverpodDevToolsRegistry.instance.register(
        const StaticProviderMetadata(name: 'provider1', dependencies: []),
      );
      RiverpodDevToolsRegistry.instance.register(
        const StaticProviderMetadata(name: 'provider2', dependencies: []),
      );
      RiverpodDevToolsRegistry.instance.register(
        const StaticProviderMetadata(name: 'provider3', dependencies: []),
      );

      expect(RiverpodDevToolsRegistry.instance.count, 3);
      expect(
        RiverpodDevToolsRegistry.instance.allProviderNames,
        containsAll(['provider1', 'provider2', 'provider3']),
      );
    });

    test('observer can be created without errors', () {
      expect(() => RiverpodDevToolsObserver(), returnsNormally);
    });

    test('provider scope can use observer', () {
      final container = ProviderContainer(
        observers: [RiverpodDevToolsObserver()],
      );

      // Create a simple provider
      final testProvider = Provider<int>((ref) => 42);

      // Read the provider (this will trigger observer callbacks)
      final value = container.read(testProvider);

      expect(value, 42);

      container.dispose();
    });
  });
}
