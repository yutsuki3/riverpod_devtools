import 'package:flutter_test/flutter_test.dart';
import 'package:riverpod_devtools_extension/src/utils/graph_layout.dart';

GraphEdgeInput _edge(String from, String to, [String? type]) =>
    GraphEdgeInput(from: from, to: to, type: type);

void main() {
  group('computeGraphLayout', () {
    test('empty input produces an empty layout', () {
      final layout = computeGraphLayout(nodeNames: {}, edges: []);
      expect(layout.nodes, isEmpty);
      expect(layout.edges, isEmpty);
      expect(layout.layerCount, 0);
      expect(layout.hasCycle, isFalse);
    });

    test('chain layers dependencies left of their dependents', () {
      // c -> b -> a  (c depends on b, b depends on a)
      final layout = computeGraphLayout(
        nodeNames: {'a', 'b', 'c'},
        edges: [_edge('b', 'a'), _edge('c', 'b')],
      );

      expect(layout['a']!.layer, 0);
      expect(layout['b']!.layer, 1);
      expect(layout['c']!.layer, 2);
      expect(layout.layerCount, 3);
      expect(layout.hasCycle, isFalse);
    });

    test('diamond uses longest path for layering', () {
      // d -> b -> a, d -> c -> a, and d -> a directly:
      // a=0, b=c=1, d=2 (not 1, despite the direct edge).
      final layout = computeGraphLayout(
        nodeNames: {'a', 'b', 'c', 'd'},
        edges: [
          _edge('b', 'a'),
          _edge('c', 'a'),
          _edge('d', 'b'),
          _edge('d', 'c'),
          _edge('d', 'a'),
        ],
      );

      expect(layout['a']!.layer, 0);
      expect(layout['b']!.layer, 1);
      expect(layout['c']!.layer, 1);
      expect(layout['d']!.layer, 2);
    });

    test('nodes in the same layer get distinct rows', () {
      final layout = computeGraphLayout(
        nodeNames: {'a', 'b', 'c'},
        edges: [_edge('b', 'a'), _edge('c', 'a')],
      );

      expect(layout['b']!.layer, 1);
      expect(layout['c']!.layer, 1);
      expect(layout['b']!.row, isNot(layout['c']!.row));
      expect(layout.maxRowCount, 2);
    });

    test('cycles are broken and flagged instead of hanging', () {
      final layout = computeGraphLayout(
        nodeNames: {'a', 'b'},
        edges: [_edge('a', 'b'), _edge('b', 'a')],
      );

      expect(layout.hasCycle, isTrue);
      expect(layout.edges.where((e) => e.isCycle), hasLength(1));
      expect(layout.nodes, hasLength(2));
    });

    test('layout includes all nodes regardless of any later focus', () {
      // d -> c -> b -> a, unrelated y -> x: layout is not filtered by
      // focus — see reachableFromFocus for that.
      final layout = computeGraphLayout(
        nodeNames: {'a', 'b', 'c', 'd', 'x', 'y'},
        edges: [
          _edge('b', 'a'),
          _edge('c', 'b'),
          _edge('d', 'c'),
          _edge('y', 'x'),
        ],
      );

      expect(layout.nodes.map((n) => n.name), ['a', 'b', 'c', 'd', 'x', 'y']);
    });

    test('self- and dangling edges are ignored', () {
      final layout = computeGraphLayout(
        nodeNames: {'a'},
        edges: [_edge('a', 'a'), _edge('a', 'ghost')],
      );

      expect(layout.edges, isEmpty);
      expect(layout.hasCycle, isFalse);
    });

    test('duplicate dependencies produce one edge per input but stable layers',
        () {
      // watch + read of the same provider: two edges, same layering.
      final layout = computeGraphLayout(
        nodeNames: {'a', 'b'},
        edges: [_edge('b', 'a', 'watch'), _edge('b', 'a', 'read')],
      );

      expect(layout.edges, hasLength(2));
      expect(layout['b']!.layer, 1);
    });
  });

  group('reachableFromFocus', () {
    test('includes transitive dependencies and dependents', () {
      // d -> c -> b -> a, unrelated y -> x.
      final related = reachableFromFocus('b', [
        _edge('b', 'a'),
        _edge('c', 'b'),
        _edge('d', 'c'),
        _edge('y', 'x'),
      ]);

      expect(related, {'a', 'b', 'c', 'd'});
    });

    test('does not pull in siblings of a shared dependency', () {
      final related =
          reachableFromFocus('b', [_edge('b', 'a'), _edge('z', 'a')]);

      expect(related, {'a', 'b'});
    });

    test('a node with no edges is related only to itself', () {
      expect(reachableFromFocus('a', []), {'a'});
    });

    test('handles cycles without hanging', () {
      final related =
          reachableFromFocus('a', [_edge('a', 'b'), _edge('b', 'a')]);
      expect(related, {'a', 'b'});
    });
  });

  group('reachableFromSelection', () {
    final edges = [_edge('b', 'a'), _edge('y', 'x')];

    test('is null when the selection is empty', () {
      expect(reachableFromSelection(const [], edges), isNull);
    });

    test('equals the single sub-graph for a one-item selection', () {
      expect(reachableFromSelection(['b'], edges), {'a', 'b'});
    });

    test('is the union of each selected sub-graph', () {
      expect(reachableFromSelection(['b', 'y'], edges), {'a', 'b', 'x', 'y'});
    });
  });

  group('isEdgeVisible', () {
    test('every edge is visible when nothing is focused', () {
      expect(isEdgeVisible(from: 'a', to: 'b', focusedSet: null), isTrue);
    });

    test('visible when both endpoints are in the focused set', () {
      expect(
        isEdgeVisible(from: 'a', to: 'b', focusedSet: {'a', 'b', 'c'}),
        isTrue,
      );
    });

    test('hidden when either endpoint is outside the focused set', () {
      expect(
        isEdgeVisible(from: 'a', to: 'x', focusedSet: {'a', 'b'}),
        isFalse,
      );
      expect(
        isEdgeVisible(from: 'x', to: 'a', focusedSet: {'a', 'b'}),
        isFalse,
      );
    });
  });

  group('hasVisibleCycle', () {
    GraphEdgeLayout cycleEdge(String from, String to) => GraphEdgeLayout(
          from: from,
          to: to,
          isCycle: true,
        );

    test('false when there are no cycle edges', () {
      expect(
        hasVisibleCycle(
          edges: [const GraphEdgeLayout(from: 'a', to: 'b')],
          focusedSet: null,
        ),
        isFalse,
      );
    });

    test('true when a cycle edge is visible (nothing focused)', () {
      expect(
        hasVisibleCycle(edges: [cycleEdge('a', 'b')], focusedSet: null),
        isTrue,
      );
    });

    test('false when the only cycle is entirely outside the focused set', () {
      expect(
        hasVisibleCycle(
          edges: [cycleEdge('x', 'y')],
          focusedSet: {'a', 'b'},
        ),
        isFalse,
      );
    });

    test('true when the cycle is inside the focused set', () {
      expect(
        hasVisibleCycle(
          edges: [cycleEdge('a', 'b')],
          focusedSet: {'a', 'b', 'c'},
        ),
        isTrue,
      );
    });
  });

  group('isNodeDimmed', () {
    test('not dimmed with no search and no focus', () {
      expect(
        isNodeDimmed(nodeName: 'a', searchQuery: '', focusedSet: null),
        isFalse,
      );
    });

    test('dimmed when outside the focused set and not searching', () {
      expect(
        isNodeDimmed(
          nodeName: 'a',
          searchQuery: '',
          focusedSet: {'b', 'c'},
        ),
        isTrue,
      );
    });

    test('not dimmed when inside the focused set', () {
      expect(
        isNodeDimmed(
          nodeName: 'a',
          searchQuery: '',
          focusedSet: {'a', 'b'},
        ),
        isFalse,
      );
    });

    test('dimmed when it does not match an active search, focus or not', () {
      expect(
        isNodeDimmed(
          nodeName: 'apiClientProvider',
          searchQuery: 'counter',
          focusedSet: null,
        ),
        isTrue,
      );
    });

    test('a search match stays lit even outside the focused set', () {
      expect(
        isNodeDimmed(
          nodeName: 'counterProvider',
          searchQuery: 'counter',
          focusedSet: {'apiClientProvider'},
        ),
        isFalse,
      );
    });

    test('search is case-insensitive', () {
      expect(
        isNodeDimmed(
          nodeName: 'counterProvider',
          searchQuery: 'COUNTER',
          focusedSet: null,
        ),
        isFalse,
      );
    });
  });
}
