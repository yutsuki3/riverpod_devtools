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
/// (`from` depends on `to` — edges referencing nodes outside the set, or
/// self-edges, are ignored).
///
/// The layout always covers the full graph — "focusing" on a node is a
/// render-time concern (dim unrelated nodes, hide unrelated edges; see
/// [reachableFromFocus]), not a layout concern, so that node positions
/// stay stable as the focus changes instead of the whole graph
/// reshuffling on every click.
GraphLayout computeGraphLayout({
  required Set<String> nodeNames,
  required List<GraphEdgeInput> edges,
}) {
  final nodes = nodeNames;
  final validEdges = [
    for (final edge in edges)
      if (nodes.contains(edge.from) &&
          nodes.contains(edge.to) &&
          edge.from != edge.to)
        edge,
  ];

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

/// Whether [nodeName] should render dimmed, combining the two independent
/// reasons a node can be de-emphasized:
///
/// - It doesn't match [searchQuery] (always dims, regardless of focus).
/// - [focusedSet] is set (a node is focused) and [nodeName] isn't in it —
///   *unless* [searchQuery] is non-empty and matches, in which case the
///   search wins so the node the user is actively looking for stays
///   visible even outside the current focus.
bool isNodeDimmed({
  required String nodeName,
  required String searchQuery,
  required Set<String>? focusedSet,
}) {
  if (searchQuery.isEmpty) {
    return focusedSet != null && !focusedSet.contains(nodeName);
  }
  return !nodeName.toLowerCase().contains(searchQuery.toLowerCase());
}

/// Whether an edge between [from] and [to] should be drawn: always when
/// nothing is focused, or when focused, only when both endpoints are in
/// [focusedSet] — this is the single source of truth for edge visibility,
/// shared by the painter and [hasVisibleCycle] so they can't disagree.
bool isEdgeVisible({
  required String from,
  required String to,
  required Set<String>? focusedSet,
}) {
  return focusedSet == null ||
      (focusedSet.contains(from) && focusedSet.contains(to));
}

/// Whether any cycle edge is actually visible given [focusedSet] — an
/// edge outside the focused sub-graph is hidden by the view, so a cycle
/// entirely outside it should not trigger the "cycle detected" warning
/// (there would be nothing red on screen to point at).
bool hasVisibleCycle({
  required List<GraphEdgeLayout> edges,
  required Set<String>? focusedSet,
}) {
  return edges.any((edge) =>
      edge.isCycle &&
      isEdgeVisible(from: edge.from, to: edge.to, focusedSet: focusedSet));
}

/// The set of nodes "related" to [focus] for rendering purposes: itself
/// plus its transitive dependencies and dependents. Used by the view to
/// decide which nodes to dim and which edges to hide when a node is
/// focused — the layout itself (node positions) does not change.
Set<String> reachableFromFocus(String focus, List<GraphEdgeInput> edges) {
  final forward = <String, List<String>>{};
  final backward = <String, List<String>>{};
  for (final edge in edges) {
    forward.putIfAbsent(edge.from, () => []).add(edge.to);
    backward.putIfAbsent(edge.to, () => []).add(edge.from);
  }
  return {..._closure(focus, forward), ..._closure(focus, backward)};
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
