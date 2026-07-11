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

    test('focus restricts to transitive deps and dependents', () {
      // d -> c -> b -> a, unrelated y -> x.
      final layout = computeGraphLayout(
        nodeNames: {'a', 'b', 'c', 'd', 'x', 'y'},
        edges: [
          _edge('b', 'a'),
          _edge('c', 'b'),
          _edge('d', 'c'),
          _edge('y', 'x'),
        ],
        focus: 'b',
      );

      expect(layout.nodes.map((n) => n.name), ['a', 'b', 'c', 'd']);
    });

    test('focus does not pull in siblings of a shared dependency', () {
      final layout = computeGraphLayout(
        nodeNames: {'a', 'b', 'z'},
        edges: [_edge('b', 'a'), _edge('z', 'a')],
        focus: 'b',
      );

      expect(layout.nodes.map((n) => n.name), ['a', 'b']);
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
}
