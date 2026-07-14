import 'static_dependencies.dart';

/// Builds the dependency-graph JSON served by `GET /graph` and the
/// `get_dependency_graph` MCP tool.
///
/// Edges come from static analysis ([RiverpodDevToolsRegistry]); nodes are
/// the union of statically-known providers and providers observed at
/// runtime, annotated with their runtime status ([runtimeStatus], e.g.
/// `active` / `failed`) or `unknown` when the observer has not seen them.
///
/// When [focusProvider] is set, the result is restricted to the sub-graph
/// reachable from it: its transitive dependencies plus its transitive
/// dependents.
Map<String, Object?> buildDependencyGraph({
  RiverpodDevToolsRegistry? registry,
  Map<String, String> runtimeStatus = const {},
  String? focusProvider,
}) {
  registry ??= RiverpodDevToolsRegistry.instance;

  final edges = <Map<String, Object?>>[];
  final nodeNames = <String>{...runtimeStatus.keys};
  for (final name in registry.allProviderNames) {
    nodeNames.add(name);
    final metadata = registry.getMetadata(name);
    if (metadata == null) continue;
    for (final dep in metadata.dependencies) {
      nodeNames.add(dep.providerName);
      edges.add({
        'from': name,
        'to': dep.providerName,
        'type': dep.type.name,
        'file': dep.file,
        'line': dep.line,
        'column': dep.column,
      });
    }
  }

  Set<String>? reachable;
  if (focusProvider != null && focusProvider.isNotEmpty) {
    reachable = _reachableFrom(focusProvider, edges);
  }

  final names = nodeNames
      .where((name) => reachable == null || reachable.contains(name))
      .toList()
    ..sort();
  final nodes = [
    for (final name in names)
      {
        'name': name,
        'status': runtimeStatus[name] ?? 'unknown',
        'hasStaticMetadata': registry.hasMetadata(name),
      },
  ];

  final filteredEdges = reachable == null
      ? edges
      : [
          for (final edge in edges)
            if (reachable.contains(edge['from']) &&
                reachable.contains(edge['to']))
              edge,
        ];

  // In-band setup hint: an empty `edges` is ambiguous — it can mean "no
  // dependencies" or "static analysis was never loaded". Tell the consumer
  // (typically an AI) which one it is, and how to fix it.
  String? edgesNote;
  if (registry.loadError != null) {
    edgesNote =
        'Loading static dependency data FAILED, so "edges" is empty. The JSON '
        'was found but could not be parsed: ${registry.loadError}. Re-run '
        '`dart run riverpod_devtools:analyze` to regenerate '
        'lib/riverpod_dependencies.json, then hot-restart.';
  } else if (!registry.hasAnyData) {
    edgesNote =
        'No static dependency data is loaded, so "edges" is empty even if '
        'dependencies exist in the code. In the Flutter app: run '
        '`dart run riverpod_devtools:analyze`, load '
        'lib/riverpod_dependencies.json in main() '
        '(RiverpodDevToolsRegistry.instance.loadFromJson), add it to the '
        'pubspec assets, then hot-restart.';
  } else if (runtimeStatus.isNotEmpty &&
      runtimeStatus.keys.every((name) => !registry!.hasMetadata(name))) {
    edgesNote =
        'Static dependency data is loaded, but none of the running providers '
        'match it by name — edges may be missing or stale. Re-run '
        '`dart run riverpod_devtools:analyze` and hot-restart.';
  }

  final generatedAt = registry.jsonGeneratedTimestamp;
  return {
    'nodes': nodes,
    'edges': filteredEdges,
    if (edgesNote != null) 'edgesNote': edgesNote,
    if (generatedAt != null) 'generatedAt': generatedAt.toIso8601String(),
  };
}

/// The focus provider itself, its transitive dependencies (downstream along
/// `from -> to` edges), and its transitive dependents (upstream).
Set<String> _reachableFrom(String start, List<Map<String, Object?>> edges) {
  final dependencies = <String, List<String>>{};
  final dependents = <String, List<String>>{};
  for (final edge in edges) {
    final from = edge['from'] as String;
    final to = edge['to'] as String;
    dependencies.putIfAbsent(from, () => []).add(to);
    dependents.putIfAbsent(to, () => []).add(from);
  }
  return {
    ..._closure(start, dependencies),
    ..._closure(start, dependents),
  };
}

Set<String> _closure(String start, Map<String, List<String>> adjacency) {
  final visited = <String>{start};
  final queue = [start];
  while (queue.isNotEmpty) {
    final node = queue.removeLast();
    for (final next in adjacency[node] ?? const <String>[]) {
      if (visited.add(next)) queue.add(next);
    }
  }
  return visited;
}
