import 'package:flutter_test/flutter_test.dart';
import 'package:riverpod_devtools_extension/src/utils/json_diff.dart';

/// Finds the first descendant (depth-first) whose key matches, for concise
/// assertions.
JsonDiffNode? _find(JsonDiffNode node, String key) {
  if (node.key == key) return node;
  for (final child in node.children) {
    final hit = _find(child, key);
    if (hit != null) return hit;
  }
  return null;
}

void main() {
  group('diffJson', () {
    test('identical scalars are unchanged', () {
      final root = diffJson({'value': 3}, {'value': 3});
      expect(root.kind, JsonDiffKind.unchanged);
      expect(_find(root, 'value')!.kind, JsonDiffKind.unchanged);
    });

    test('a changed scalar surfaces old and new values', () {
      final root = diffJson(
        {'type': 'int', 'value': 3},
        {'type': 'int', 'value': 4},
      );
      expect(root.kind, JsonDiffKind.changed);
      final value = _find(root, 'value')!;
      expect(value.kind, JsonDiffKind.changed);
      expect(value.oldValue, 3);
      expect(value.newValue, 4);
      // The unchanged sibling stays unchanged.
      expect(_find(root, 'type')!.kind, JsonDiffKind.unchanged);
    });

    test('an added key is marked added, a removed key removed', () {
      final root = diffJson(
        {'a': 1, 'gone': true},
        {'a': 1, 'added': 'x'},
      );
      expect(_find(root, 'gone')!.kind, JsonDiffKind.removed);
      expect(_find(root, 'gone')!.oldValue, true);
      expect(_find(root, 'added')!.kind, JsonDiffKind.added);
      expect(_find(root, 'added')!.newValue, 'x');
    });

    test('nested maps roll changes up to their parent', () {
      final root = diffJson(
        {'user': {'name': 'Alice', 'age': 30}},
        {'user': {'name': 'Alice', 'age': 31}},
      );
      final user = _find(root, 'user')!;
      expect(user.kind, JsonDiffKind.changed);
      expect(user.isLeaf, isFalse);
      expect(_find(root, 'name')!.kind, JsonDiffKind.unchanged);
      expect(_find(root, 'age')!.kind, JsonDiffKind.changed);
    });

    test('lists diff element-wise and flag length changes', () {
      final root = diffJson(
        {'items': [1, 2, 3]},
        {'items': [1, 9, 3, 4]},
      );
      final items = _find(root, 'items')!;
      expect(items.kind, JsonDiffKind.changed);
      expect(_find(root, '[1]')!.kind, JsonDiffKind.changed);
      expect(_find(root, '[3]')!.kind, JsonDiffKind.added);
      expect(_find(root, '[0]')!.kind, JsonDiffKind.unchanged);
    });

    test('a type change from scalar to map is a leaf change', () {
      final root = diffJson({'v': 5}, {'v': {'nested': true}});
      final v = _find(root, 'v')!;
      expect(v.kind, JsonDiffKind.changed);
      expect(v.isLeaf, isTrue);
      expect(v.oldValue, 5);
      expect(v.newValue, {'nested': true});
    });

    test('two fully equal trees report no change at the root', () {
      final root = diffJson(
        {'a': [1, 2], 'b': {'c': 'd'}},
        {'a': [1, 2], 'b': {'c': 'd'}},
      );
      expect(root.hasChange, isFalse);
    });
  });
}
