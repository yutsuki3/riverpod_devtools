/// Pure layered-DAG layout for the dependency graph view.
///
/// Nodes are assigned a column ([GraphNodeLayout.layer], dependencies to
/// the left of their dependents) and a row within that column. Cycles are
/// detected and broken for layering purposes; the offending edges are
/// flagged so the view can highlight them.
library;

class GraphEdgeInput {
  final String from;

  /// The provider [from] depends on.
  final String to;

  /// `watch` / `read` / `listen`, when known.
  final String? type;

  const GraphEdgeInput({required this.from, required this.to, this.type});
}

class GraphNodeLayout {
  final String name;
  final int layer;
  final int row;

  const GraphNodeLayout({
    required this.name,
    required this.layer,
    required this.row,
  });
}

class GraphEdgeLayout {
  final String from;
  final String to;
  final String? type;

  /// True when this edge closes a dependency cycle (broken for layering).
  final bool isCycle;

  const GraphEdgeLayout({
    required this.from,
    required this.to,
    this.type,
    this.isCycle = false,
  });
}

class GraphLayout {
  final List<GraphNodeLayout> nodes;
  final List<GraphEdgeLayout> edges;
  final int layerCount;

  /// Number of rows in the tallest layer.
  final int maxRowCount;

  final bool hasCycle;

  const GraphLayout({
    required this.nodes,
    required this.edges,
    required this.layerCount,
    required this.maxRowCount,
    required this.hasCycle,
  });

  GraphNodeLayout? operator [](String name) {
    for (final node in nodes) {
      if (node.name == name) return node;
    }
    return null;
  }
}

/// Computes the layout.
///
/// [nodeNames] is the full node set; [edges] the dependency edges
/// (`from` depends on `to` — edges referencing nodes outside the set are
/// ignored). When [focus] is set, the graph is restricted to the focus
/// node plus its transitive dependencies and dependents.
GraphLayout computeGraphLayout({
  required Set<String> nodeNames,
  required List<GraphEdgeInput> edges,
  String? focus,
}) {
  var nodes = Set<String>.of(nodeNames);
  var validEdges = [
    for (final edge in edges)
      if (nodes.contains(edge.from) &&
          nodes.contains(edge.to) &&
          edge.from != edge.to)
        edge,
  ];

  if (focus != null && nodes.contains(focus)) {
    final reachable = _reachableFrom(focus, validEdges);
    nodes = nodes.intersection(reachable);
    validEdges = [
      for (final edge in validEdges)
        if (nodes.contains(edge.from) && nodes.contains(edge.to)) edge,
    ];
  }

  // dependencies of each node, deduplicated (a provider may watch + read
  // the same dependency).
  final dependencies = <String, List<String>>{};
  for (final edge in validEdges) {
    final deps = dependencies.putIfAbsent(edge.from, () => []);
    if (!deps.contains(edge.to)) deps.add(edge.to);
  }

  // Longest-path layering via iterative DFS with cycle breaking:
  // layer(n) = 0 for nodes without dependencies, else 1 + max(dep layers).
  // Gray nodes on the DFS stack mark back edges (cycles), which are
  // skipped for layering and flagged in the output.
  final layers = <String, int>{};
  final onStack = <String>{};
  final cycleEdges = <String>{}; // 'from->to'

  int layerOf(String node) {
    final cached = layers[node];
    if (cached != null) return cached;
    onStack.add(node);
    var layer = 0;
    for (final dep in dependencies[node] ?? const <String>[]) {
      if (onStack.contains(dep)) {
        cycleEdges.add('$node->$dep');
        continue;
      }
      final depLayer = layerOf(dep) + 1;
      if (depLayer > layer) layer = depLayer;
    }
    onStack.remove(node);
    return layers[node] = layer;
  }

  final sortedNames = nodes.toList()..sort();
  for (final name in sortedNames) {
    layerOf(name);
  }

  // Row assignment per layer: order by the average row of already-placed
  // dependencies (one barycenter pass, left to right) to reduce edge
  // crossings; ties fall back to name order from the sorted iteration.
  final byLayer = <int, List<String>>{};
  for (final name in sortedNames) {
    byLayer.putIfAbsent(layers[name]!, () => []).add(name);
  }
  final layerCount = byLayer.isEmpty ? 0 : byLayer.keys.reduce(_max) + 1;

  final rows = <String, int>{};
  var maxRowCount = 0;
  for (var layer = 0; layer < layerCount; layer++) {
    final names = byLayer[layer] ?? const <String>[];
    final keyed = <(double, String)>[];
    for (final name in names) {
      final placedDeps = [
        for (final dep in dependencies[name] ?? const <String>[])
          if (rows.containsKey(dep)) rows[dep]!,
      ];
      final barycenter = placedDeps.isEmpty
          ? double.maxFinite // dependency-less nodes sink to the bottom
          : placedDeps.reduce((a, b) => a + b) / placedDeps.length;
      keyed.add((barycenter, name));
    }
    keyed.sort((a, b) {
      final byCenter = a.$1.compareTo(b.$1);
      return byCenter != 0 ? byCenter : a.$2.compareTo(b.$2);
    });
    for (var row = 0; row < keyed.length; row++) {
      rows[keyed[row].$2] = row;
    }
    if (keyed.length > maxRowCount) maxRowCount = keyed.length;
  }

  return GraphLayout(
    nodes: [
      for (final name in sortedNames)
        GraphNodeLayout(name: name, layer: layers[name]!, row: rows[name]!),
    ],
    edges: [
      for (final edge in validEdges)
        GraphEdgeLayout(
          from: edge.from,
          to: edge.to,
          type: edge.type,
          isCycle: cycleEdges.contains('${edge.from}->${edge.to}'),
        ),
    ],
    layerCount: layerCount,
    maxRowCount: maxRowCount,
    hasCycle: cycleEdges.isNotEmpty,
  );
}

int _max(int a, int b) => a > b ? a : b;

/// Focus node plus its transitive dependencies and dependents.
Set<String> _reachableFrom(String start, List<GraphEdgeInput> edges) {
  final forward = <String, List<String>>{};
  final backward = <String, List<String>>{};
  for (final edge in edges) {
    forward.putIfAbsent(edge.from, () => []).add(edge.to);
    backward.putIfAbsent(edge.to, () => []).add(edge.from);
  }
  return {..._closure(start, forward), ..._closure(start, backward)};
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
