// A structural diff between two JSON-ish values (the decoded `value` maps
// carried on provider events). Produces a tree that mirrors the data so it
// can be rendered side-by-side with change highlighting.

/// How a node in the diff tree changed between the two values.
enum JsonDiffKind { added, removed, changed, unchanged }

/// One node in the diff tree. Leaves carry [oldValue]/[newValue]; interior
/// nodes (maps/lists) carry [children] and roll their kind up from them.
class JsonDiffNode {
  /// Map key or `[index]` label for this node; empty for the root.
  final String key;
  final JsonDiffKind kind;
  final bool isLeaf;
  final Object? oldValue;
  final Object? newValue;
  final List<JsonDiffNode> children;

  const JsonDiffNode({
    required this.key,
    required this.kind,
    required this.isLeaf,
    this.oldValue,
    this.newValue,
    this.children = const [],
  });

  /// True when this node (or any descendant) represents a real change.
  bool get hasChange => kind != JsonDiffKind.unchanged;
}

/// Diffs [oldValue] against [newValue], returning the root of the diff tree.
JsonDiffNode diffJson(Object? oldValue, Object? newValue) =>
    _diff('', oldValue, newValue, present: _Presence.both);

enum _Presence { both, onlyOld, onlyNew }

JsonDiffNode _diff(
  String key,
  Object? oldValue,
  Object? newValue, {
  required _Presence present,
}) {
  // A whole subtree that exists on only one side is added/removed wholesale.
  if (present == _Presence.onlyNew) {
    return _wholeSubtree(key, newValue, JsonDiffKind.added, isNew: true);
  }
  if (present == _Presence.onlyOld) {
    return _wholeSubtree(key, oldValue, JsonDiffKind.removed, isNew: false);
  }

  if (oldValue is Map && newValue is Map) {
    final children = <JsonDiffNode>[];
    // Preserve old-side key order first, then any new-only keys.
    final keys = <String>[
      for (final k in oldValue.keys) k.toString(),
      for (final k in newValue.keys)
        if (!oldValue.containsKey(k)) k.toString(),
    ];
    for (final k in keys) {
      final inOld = oldValue.containsKey(k);
      final inNew = newValue.containsKey(k);
      children.add(_diff(
        k,
        inOld ? oldValue[k] : null,
        inNew ? newValue[k] : null,
        present: inOld && inNew
            ? _Presence.both
            : inOld
                ? _Presence.onlyOld
                : _Presence.onlyNew,
      ));
    }
    return _interior(key, children);
  }

  if (oldValue is List && newValue is List) {
    final children = <JsonDiffNode>[];
    final maxLen =
        oldValue.length > newValue.length ? oldValue.length : newValue.length;
    for (var i = 0; i < maxLen; i++) {
      final inOld = i < oldValue.length;
      final inNew = i < newValue.length;
      children.add(_diff(
        '[$i]',
        inOld ? oldValue[i] : null,
        inNew ? newValue[i] : null,
        present: inOld && inNew
            ? _Presence.both
            : inOld
                ? _Presence.onlyOld
                : _Presence.onlyNew,
      ));
    }
    return _interior(key, children);
  }

  // Scalars, or a type change (e.g. int -> Map): treat as a leaf.
  final changed = !_deepEquals(oldValue, newValue);
  return JsonDiffNode(
    key: key,
    kind: changed ? JsonDiffKind.changed : JsonDiffKind.unchanged,
    isLeaf: true,
    oldValue: oldValue,
    newValue: newValue,
  );
}

JsonDiffNode _interior(String key, List<JsonDiffNode> children) {
  final anyChange = children.any((c) => c.hasChange);
  return JsonDiffNode(
    key: key,
    kind: anyChange ? JsonDiffKind.changed : JsonDiffKind.unchanged,
    isLeaf: false,
    children: children,
  );
}

JsonDiffNode _wholeSubtree(
  String key,
  Object? value,
  JsonDiffKind kind, {
  required bool isNew,
}) {
  if (value is Map) {
    return JsonDiffNode(
      key: key,
      kind: kind,
      isLeaf: false,
      children: [
        for (final entry in value.entries)
          _wholeSubtree(entry.key.toString(), entry.value, kind, isNew: isNew),
      ],
    );
  }
  if (value is List) {
    return JsonDiffNode(
      key: key,
      kind: kind,
      isLeaf: false,
      children: [
        for (var i = 0; i < value.length; i++)
          _wholeSubtree('[$i]', value[i], kind, isNew: isNew),
      ],
    );
  }
  return JsonDiffNode(
    key: key,
    kind: kind,
    isLeaf: true,
    oldValue: isNew ? null : value,
    newValue: isNew ? value : null,
  );
}

bool _deepEquals(Object? a, Object? b) {
  if (identical(a, b)) return true;
  if (a is Map && b is Map) {
    if (a.length != b.length) return false;
    for (final key in a.keys) {
      if (!b.containsKey(key) || !_deepEquals(a[key], b[key])) return false;
    }
    return true;
  }
  if (a is List && b is List) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!_deepEquals(a[i], b[i])) return false;
    }
    return true;
  }
  return a == b;
}
