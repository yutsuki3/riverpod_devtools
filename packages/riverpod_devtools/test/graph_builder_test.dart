import 'package:flutter_test/flutter_test.dart';
import 'package:riverpod_devtools/riverpod_devtools.dart';
import 'package:riverpod_devtools/src/graph_builder.dart';

StaticDependency _dep(String name, {DependencyType type = DependencyType.watch}) {
  return StaticDependency(
    providerName: name,
    type: type,
    file: 'lib/test.dart',
    line: 1,
    column: 1,
  );
}

void main() {
  final registry = RiverpodDevToolsRegistry.instance;

  setUp(registry.clear);
  tearDown(registry.clear);

  group('buildDependencyGraph', () {
    test('returns an empty graph when nothing is registered', () {
      final graph = buildDependencyGraph();
      expect(graph['nodes'], isEmpty);
      expect(graph['edges'], isEmpty);
    });

    test('builds nodes and edges from the registry', () {
      registry.register(StaticProviderMetadata(
        name: 'b',
        dependencies: [_dep('a'), _dep('c', type: DependencyType.read)],
      ));

      final graph = buildDependencyGraph();
      final nodes = graph['nodes'] as List;
      final edges = graph['edges'] as List;

      // Nodes are sorted by name; 'a' and 'c' appear even though only 'b'
      // has metadata.
      expect(nodes.map((n) => (n as Map)['name']), ['a', 'b', 'c']);
      expect(edges, [
        {
          'from': 'b',
          'to': 'a',
          'type': 'watch',
          'file': 'lib/test.dart',
          'line': 1,
          'column': 1,
        },
        {
          'from': 'b',
          'to': 'c',
          'type': 'read',
          'file': 'lib/test.dart',
          'line': 1,
          'column': 1,
        },
      ]);
    });

    test('merges runtime status and includes runtime-only providers', () {
      registry.register(
        StaticProviderMetadata(name: 'b', dependencies: [_dep('a')]),
      );

      final graph = buildDependencyGraph(
        runtimeStatus: {'b': 'failed', 'runtimeOnly': 'active'},
      );
      final byName = {
        for (final node in graph['nodes'] as List)
          (node as Map)['name']: node,
      };

      expect(byName['b']!['status'], 'failed');
      expect(byName['a']!['status'], 'unknown');
      expect(byName['runtimeOnly']!['status'], 'active');
      expect(byName['b']!['hasStaticMetadata'], true);
      expect(byName['runtimeOnly']!['hasStaticMetadata'], false);
    });

    test('focus provider restricts to transitive deps and dependents', () {
      // Chain: d -> c -> b -> a, plus unrelated: y -> x.
      registry.register(
          StaticProviderMetadata(name: 'b', dependencies: [_dep('a')]));
      registry.register(
          StaticProviderMetadata(name: 'c', dependencies: [_dep('b')]));
      registry.register(
          StaticProviderMetadata(name: 'd', dependencies: [_dep('c')]));
      registry.register(
          StaticProviderMetadata(name: 'y', dependencies: [_dep('x')]));

      final graph = buildDependencyGraph(focusProvider: 'b');
      final names =
          (graph['nodes'] as List).map((n) => (n as Map)['name']).toList();

      expect(names, ['a', 'b', 'c', 'd']);
      expect(
        (graph['edges'] as List).map((e) => '${(e as Map)['from']}->${e['to']}'),
        ['b->a', 'c->b', 'd->c'],
      );
    });

    test('focus does not pull in siblings of a shared dependency', () {
      // b -> a and z -> a: focusing on b must include a but not z.
      registry.register(
          StaticProviderMetadata(name: 'b', dependencies: [_dep('a')]));
      registry.register(
          StaticProviderMetadata(name: 'z', dependencies: [_dep('a')]));

      final graph = buildDependencyGraph(focusProvider: 'b');
      final names =
          (graph['nodes'] as List).map((n) => (n as Map)['name']).toList();

      expect(names, ['a', 'b']);
    });

    test('handles dependency cycles without hanging', () {
      registry.register(
          StaticProviderMetadata(name: 'a', dependencies: [_dep('b')]));
      registry.register(
          StaticProviderMetadata(name: 'b', dependencies: [_dep('a')]));

      final graph = buildDependencyGraph(focusProvider: 'a');
      final names =
          (graph['nodes'] as List).map((n) => (n as Map)['name']).toList();
      expect(names, ['a', 'b']);
    });

    test('adds an edgesNote when no static data is loaded', () {
      final graph = buildDependencyGraph(runtimeStatus: {'a': 'active'});
      expect(graph['edges'], isEmpty);
      expect(graph['edgesNote'], contains('riverpod_devtools:analyze'));
    });

    test('adds a name-mismatch edgesNote when data matches no live provider',
        () {
      registry.register(
          const StaticProviderMetadata(name: 'other', dependencies: []));
      final graph = buildDependencyGraph(runtimeStatus: {'a': 'active'});
      expect(graph['edgesNote'], contains('match'));
    });

    test('no edgesNote when a running provider has static metadata', () {
      registry.register(
          const StaticProviderMetadata(name: 'a', dependencies: []));
      final graph = buildDependencyGraph(runtimeStatus: {'a': 'active'});
      expect(graph.containsKey('edgesNote'), isFalse);
    });

    test('reports a load failure in the edgesNote, with the reason', () {
      // A malformed JSON load records an error but does not throw.
      registry.loadFromJson('{ this is not valid json');
      expect(registry.loadError, isNotNull);

      final graph = buildDependencyGraph(runtimeStatus: {'a': 'active'});
      expect(graph['edges'], isEmpty);
      final note = graph['edgesNote'] as String;
      expect(note, contains('FAILED'));
      expect(note, contains('riverpod_devtools:analyze'));
    });
  });
}
