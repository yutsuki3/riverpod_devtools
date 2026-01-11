import 'package:flutter_test/flutter_test.dart';
import 'package:riverpod_devtools/src/static_dependencies.dart';

void main() {
  group('DependencyType', () {
    test('has correct enum values', () {
      expect(DependencyType.values.length, 3);
      expect(DependencyType.watch.name, 'watch');
      expect(DependencyType.read.name, 'read');
      expect(DependencyType.listen.name, 'listen');
    });
  });

  group('StaticDependency', () {
    test('creates instance correctly', () {
      const dep = StaticDependency(
        providerName: 'testProvider',
        type: DependencyType.watch,
        file: 'lib/test.dart',
        line: 42,
        column: 10,
      );

      expect(dep.providerName, 'testProvider');
      expect(dep.type, DependencyType.watch);
      expect(dep.file, 'lib/test.dart');
      expect(dep.line, 42);
      expect(dep.column, 10);
    });

    test('toJson returns correct format', () {
      const dep = StaticDependency(
        providerName: 'authProvider',
        type: DependencyType.read,
        file: 'lib/auth.dart',
        line: 100,
        column: 15,
      );

      final json = dep.toJson();
      expect(json['providerName'], 'authProvider');
      expect(json['type'], 'read');
      expect(json['file'], 'lib/auth.dart');
      expect(json['line'], 100);
      expect(json['column'], 15);
    });

    test('equality works correctly', () {
      const dep1 = StaticDependency(
        providerName: 'provider1',
        type: DependencyType.watch,
        file: 'lib/test.dart',
        line: 10,
        column: 5,
      );
      const dep2 = StaticDependency(
        providerName: 'provider1',
        type: DependencyType.watch,
        file: 'lib/test.dart',
        line: 10,
        column: 5,
      );
      const dep3 = StaticDependency(
        providerName: 'provider2',
        type: DependencyType.watch,
        file: 'lib/test.dart',
        line: 10,
        column: 5,
      );

      expect(dep1, equals(dep2));
      expect(dep1, isNot(equals(dep3)));
    });

    test('hashCode is consistent', () {
      const dep1 = StaticDependency(
        providerName: 'provider1',
        type: DependencyType.listen,
        file: 'lib/test.dart',
        line: 20,
        column: 8,
      );
      const dep2 = StaticDependency(
        providerName: 'provider1',
        type: DependencyType.listen,
        file: 'lib/test.dart',
        line: 20,
        column: 8,
      );

      expect(dep1.hashCode, equals(dep2.hashCode));
    });

    test('toString returns readable format', () {
      const dep = StaticDependency(
        providerName: 'myProvider',
        type: DependencyType.watch,
        file: 'lib/providers.dart',
        line: 50,
        column: 12,
      );

      expect(
        dep.toString(),
        'StaticDependency(myProvider, watch, lib/providers.dart:50:12)',
      );
    });
  });

  group('StaticProviderMetadata', () {
    test('creates instance correctly', () {
      const metadata = StaticProviderMetadata(
        name: 'userProvider',
        dependencies: [
          StaticDependency(
            providerName: 'authProvider',
            type: DependencyType.watch,
            file: 'lib/user.dart',
            line: 10,
            column: 5,
          ),
        ],
      );

      expect(metadata.name, 'userProvider');
      expect(metadata.dependencies.length, 1);
      expect(metadata.dependencies.first.providerName, 'authProvider');
    });

    test('equality works correctly', () {
      const metadata1 = StaticProviderMetadata(
        name: 'provider1',
        dependencies: [
          StaticDependency(
            providerName: 'dep1',
            type: DependencyType.watch,
            file: 'lib/test.dart',
            line: 1,
            column: 1,
          ),
        ],
      );
      const metadata2 = StaticProviderMetadata(
        name: 'provider1',
        dependencies: [
          StaticDependency(
            providerName: 'dep1',
            type: DependencyType.watch,
            file: 'lib/test.dart',
            line: 1,
            column: 1,
          ),
        ],
      );
      const metadata3 = StaticProviderMetadata(
        name: 'provider2',
        dependencies: [
          StaticDependency(
            providerName: 'dep1',
            type: DependencyType.watch,
            file: 'lib/test.dart',
            line: 1,
            column: 1,
          ),
        ],
      );

      expect(metadata1, equals(metadata2));
      expect(metadata1, isNot(equals(metadata3)));
    });

    test('toString returns readable format', () {
      const metadata = StaticProviderMetadata(
        name: 'myProvider',
        dependencies: [
          StaticDependency(
            providerName: 'dep1',
            type: DependencyType.watch,
            file: 'lib/test.dart',
            line: 1,
            column: 1,
          ),
          StaticDependency(
            providerName: 'dep2',
            type: DependencyType.read,
            file: 'lib/test.dart',
            line: 2,
            column: 2,
          ),
        ],
      );

      expect(
        metadata.toString(),
        'StaticProviderMetadata(myProvider, 2 dependencies)',
      );
    });
  });

  group('RiverpodDevToolsRegistry', () {
    setUp(() {
      // Clear registry before each test
      RiverpodDevToolsRegistry.instance.clear();
    });

    test('is a singleton', () {
      final instance1 = RiverpodDevToolsRegistry.instance;
      final instance2 = RiverpodDevToolsRegistry.instance;
      expect(identical(instance1, instance2), isTrue);
    });

    test('register and getMetadata work correctly', () {
      const metadata = StaticProviderMetadata(
        name: 'testProvider',
        dependencies: [
          StaticDependency(
            providerName: 'dep1',
            type: DependencyType.watch,
            file: 'lib/test.dart',
            line: 10,
            column: 5,
          ),
        ],
      );

      RiverpodDevToolsRegistry.instance.register(metadata);

      final retrieved = RiverpodDevToolsRegistry.instance.getMetadata('testProvider');
      expect(retrieved, equals(metadata));
    });

    test('getMetadata returns null for unregistered provider', () {
      final retrieved = RiverpodDevToolsRegistry.instance.getMetadata('nonexistent');
      expect(retrieved, isNull);
    });

    test('getDependencyNames returns correct list', () {
      const metadata = StaticProviderMetadata(
        name: 'userProvider',
        dependencies: [
          StaticDependency(
            providerName: 'authProvider',
            type: DependencyType.watch,
            file: 'lib/user.dart',
            line: 10,
            column: 5,
          ),
          StaticDependency(
            providerName: 'settingsProvider',
            type: DependencyType.read,
            file: 'lib/user.dart',
            line: 11,
            column: 5,
          ),
        ],
      );

      RiverpodDevToolsRegistry.instance.register(metadata);

      final names = RiverpodDevToolsRegistry.instance.getDependencyNames('userProvider');
      expect(names, ['authProvider', 'settingsProvider']);
    });

    test('getDependencyNames returns empty list for unregistered provider', () {
      final names = RiverpodDevToolsRegistry.instance.getDependencyNames('nonexistent');
      expect(names, isEmpty);
    });

    test('getDependenciesWithDetails returns correct JSON list', () {
      const metadata = StaticProviderMetadata(
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
            type: DependencyType.listen,
            file: 'lib/test.dart',
            line: 15,
            column: 8,
          ),
        ],
      );

      RiverpodDevToolsRegistry.instance.register(metadata);

      final details = RiverpodDevToolsRegistry.instance.getDependenciesWithDetails('testProvider');
      expect(details.length, 2);
      expect(details[0]['providerName'], 'dep1');
      expect(details[0]['type'], 'watch');
      expect(details[1]['providerName'], 'dep2');
      expect(details[1]['type'], 'listen');
    });

    test('hasMetadata works correctly', () {
      const metadata = StaticProviderMetadata(
        name: 'existingProvider',
        dependencies: [],
      );

      RiverpodDevToolsRegistry.instance.register(metadata);

      expect(RiverpodDevToolsRegistry.instance.hasMetadata('existingProvider'), isTrue);
      expect(RiverpodDevToolsRegistry.instance.hasMetadata('nonexistent'), isFalse);
    });

    test('allProviderNames returns all registered names', () {
      RiverpodDevToolsRegistry.instance.register(
        const StaticProviderMetadata(name: 'provider1', dependencies: []),
      );
      RiverpodDevToolsRegistry.instance.register(
        const StaticProviderMetadata(name: 'provider2', dependencies: []),
      );
      RiverpodDevToolsRegistry.instance.register(
        const StaticProviderMetadata(name: 'provider3', dependencies: []),
      );

      final names = RiverpodDevToolsRegistry.instance.allProviderNames;
      expect(names.length, 3);
      expect(names, containsAll(['provider1', 'provider2', 'provider3']));
    });

    test('count returns correct number', () {
      expect(RiverpodDevToolsRegistry.instance.count, 0);

      RiverpodDevToolsRegistry.instance.register(
        const StaticProviderMetadata(name: 'provider1', dependencies: []),
      );
      expect(RiverpodDevToolsRegistry.instance.count, 1);

      RiverpodDevToolsRegistry.instance.register(
        const StaticProviderMetadata(name: 'provider2', dependencies: []),
      );
      expect(RiverpodDevToolsRegistry.instance.count, 2);
    });

    test('clear removes all metadata', () {
      RiverpodDevToolsRegistry.instance.register(
        const StaticProviderMetadata(name: 'provider1', dependencies: []),
      );
      RiverpodDevToolsRegistry.instance.register(
        const StaticProviderMetadata(name: 'provider2', dependencies: []),
      );

      expect(RiverpodDevToolsRegistry.instance.count, 2);

      RiverpodDevToolsRegistry.instance.clear();

      expect(RiverpodDevToolsRegistry.instance.count, 0);
      expect(RiverpodDevToolsRegistry.instance.allProviderNames, isEmpty);
    });

    test('registering same provider name overwrites previous', () {
      const metadata1 = StaticProviderMetadata(
        name: 'provider',
        dependencies: [
          StaticDependency(
            providerName: 'dep1',
            type: DependencyType.watch,
            file: 'lib/test.dart',
            line: 1,
            column: 1,
          ),
        ],
      );
      const metadata2 = StaticProviderMetadata(
        name: 'provider',
        dependencies: [
          StaticDependency(
            providerName: 'dep2',
            type: DependencyType.read,
            file: 'lib/test.dart',
            line: 2,
            column: 2,
          ),
        ],
      );

      RiverpodDevToolsRegistry.instance.register(metadata1);
      expect(RiverpodDevToolsRegistry.instance.count, 1);

      RiverpodDevToolsRegistry.instance.register(metadata2);
      expect(RiverpodDevToolsRegistry.instance.count, 1);

      final retrieved = RiverpodDevToolsRegistry.instance.getMetadata('provider');
      expect(retrieved, equals(metadata2));
      expect(retrieved?.dependencies.first.providerName, 'dep2');
    });
  });
}
