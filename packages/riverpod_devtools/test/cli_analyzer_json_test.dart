import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:riverpod_devtools/src/builder/provider_metadata.dart';
import 'package:riverpod_devtools/src/static_dependencies.dart';

/// Builds the JSON envelope that the CLI analyzer writes to
/// `lib/riverpod_dependencies.json`, so we can assert the contract between
/// the analyzer's output format and [RiverpodDevToolsRegistry.loadFromJson]
/// without invoking the analyzer binary (which needs a resolved analysis
/// context and a Flutter SDK).
String _analyzerJson(List<ProviderMetadata> providers) {
  final map = {
    'providers': providers.map((p) => p.toJson()).toList(),
    'generatedAt': '2026-07-14T00:00:00.000',
    'version': '1.0.0',
  };
  return const JsonEncoder.withIndent('  ').convert(map);
}

ProviderMetadata _provider(
  String name,
  String type,
  List<DependencyInfo> dependencies,
) {
  return ProviderMetadata(
    name: name,
    providerType: type,
    dependencies: dependencies,
    location: const SourceLocation(file: 'lib/main.dart', line: 1, column: 1),
  );
}

DependencyInfo _dep(String name, DependencyType type) {
  return DependencyInfo(
    providerName: name,
    type: type,
    location: const SourceLocation(file: 'lib/main.dart', line: 2, column: 3),
  );
}

void main() {
  final registry = RiverpodDevToolsRegistry.instance;

  setUp(registry.clear);
  tearDown(registry.clear);

  group('analyzer JSON -> registry round-trip', () {
    test('loads providers and their dependency names', () {
      final json = _analyzerJson([
        _provider('b', 'Provider', [_dep('a', DependencyType.watch)]),
        _provider('a', 'StateProvider', []),
      ]);

      registry.loadFromJson(json);

      expect(registry.count, 2);
      expect(registry.allProviderNames, containsAll(['a', 'b']));
      expect(registry.hasMetadata('b'), isTrue);
      expect(registry.getDependencyNames('b'), ['a']);
      expect(registry.getDependencyNames('a'), isEmpty);
    });

    test('preserves dependency type and source location details', () {
      final json = _analyzerJson([
        _provider('consumer', 'Provider', [
          _dep('watched', DependencyType.watch),
          _dep('read', DependencyType.read),
          _dep('listened', DependencyType.listen),
        ]),
      ]);

      registry.loadFromJson(json);

      final details = registry.getDependenciesWithDetails('consumer');
      expect(details, hasLength(3));
      expect(
        details.map((d) => '${d['providerName']}:${d['type']}').toList(),
        ['watched:watch', 'read:read', 'listened:listen'],
      );
      expect(details.first['line'], 2);
      expect(details.first['column'], 3);
    });

    test('a provider with no dependencies loads cleanly', () {
      registry.loadFromJson(
        _analyzerJson([_provider('lonely', 'Provider', [])]),
      );

      expect(registry.hasMetadata('lonely'), isTrue);
      expect(registry.getDependencyNames('lonely'), isEmpty);
    });
  });

  group('analyzer JSON -> registry resilience', () {
    test('an empty providers list yields an empty registry', () {
      registry.loadFromJson(_analyzerJson([]));

      expect(registry.count, 0);
      expect(registry.hasAnyData, isFalse);
    });

    test('malformed JSON does not throw and leaves the registry empty', () {
      expect(() => registry.loadFromJson('{not valid json'), returnsNormally);
      expect(registry.count, 0);
    });

    test('JSON missing the providers key does not throw', () {
      expect(
        () => registry.loadFromJson('{"generatedAt":"x","version":"1.0.0"}'),
        returnsNormally,
      );
      expect(registry.count, 0);
    });
  });
}
