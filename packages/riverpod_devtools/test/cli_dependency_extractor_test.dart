import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/source/line_info.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riverpod_devtools/src/builder/provider_metadata.dart';
import 'package:riverpod_devtools/src/cli/simple_dependency_extractor.dart';
import 'package:riverpod_devtools/src/static_dependencies.dart';

/// Parses [source] and returns the initializer expression of the first
/// top-level variable, plus the unit's [LineInfo]. This mirrors what the
/// CLI analyzer feeds into [SimpleDependencyExtractor] for each provider.
({Expression initializer, LineInfo lineInfo}) _firstInitializer(String source) {
  final parsed = parseString(content: source, throwIfDiagnostics: false);
  final unit = parsed.unit;
  for (final declaration in unit.declarations) {
    if (declaration is TopLevelVariableDeclaration) {
      final initializer = declaration.variables.variables.first.initializer;
      if (initializer != null) {
        return (initializer: initializer, lineInfo: unit.lineInfo);
      }
    }
  }
  fail('No top-level variable with an initializer found in source');
}

List<DependencyInfo> _extract(String source) {
  final parsed = _firstInitializer(source);
  return SimpleDependencyExtractor.extractDependencies(
    parsed.initializer,
    'lib/test.dart',
    parsed.lineInfo,
  );
}

void main() {
  group('SimpleDependencyExtractor - dependency kinds', () {
    test('extracts ref.watch as a watch dependency', () {
      final deps = _extract('''
final b = Provider((ref) {
  return ref.watch(a);
});
''');

      expect(deps, hasLength(1));
      expect(deps.single.providerName, 'a');
      expect(deps.single.type, DependencyType.watch);
    });

    test('extracts ref.read as a read dependency', () {
      final deps = _extract('''
final b = Provider((ref) {
  return ref.read(a);
});
''');

      expect(deps, hasLength(1));
      expect(deps.single.providerName, 'a');
      expect(deps.single.type, DependencyType.read);
    });

    test('extracts ref.listen as a listen dependency', () {
      final deps = _extract('''
final b = Provider((ref) {
  ref.listen(a, (prev, next) {});
  return 0;
});
''');

      expect(deps, hasLength(1));
      expect(deps.single.providerName, 'a');
      expect(deps.single.type, DependencyType.listen);
    });

    test('extracts multiple mixed dependencies in declaration order', () {
      final deps = _extract('''
final d = Provider((ref) {
  final x = ref.watch(a);
  final y = ref.read(b);
  ref.listen(c, (prev, next) {});
  return x + y;
});
''');

      expect(
        deps.map((d) => '${d.providerName}:${d.type.name}').toList(),
        ['a:watch', 'b:read', 'c:listen'],
      );
    });
  });

  group('SimpleDependencyExtractor - provider name shapes', () {
    test('resolves .select() to the underlying provider', () {
      final deps = _extract('''
final b = Provider((ref) {
  return ref.watch(a.select((v) => v.field));
});
''');

      expect(deps.single.providerName, 'a');
      expect(deps.single.type, DependencyType.watch);
    });

    test('resolves prefixed/property access to the property name', () {
      final deps = _extract('''
final b = Provider((ref) {
  return ref.watch(providers.counterProvider);
});
''');

      expect(deps.single.providerName, 'counterProvider');
    });
  });

  group('SimpleDependencyExtractor - edge cases', () {
    test('returns empty for a provider with no ref calls', () {
      final deps = _extract('final a = Provider((ref) => 0);');
      expect(deps, isEmpty);
    });

    test('ignores calls on non-ref targets', () {
      final deps = _extract('''
final b = Provider((ref) {
  return other.watch(a);
});
''');

      expect(deps, isEmpty);
    });

    test('ignores ref methods that are not watch/read/listen', () {
      final deps = _extract('''
final b = Provider((ref) {
  ref.invalidate(a);
  ref.refresh(c);
  return 0;
});
''');

      expect(deps, isEmpty);
    });

    test('ignores ref calls with no arguments', () {
      final deps = _extract('''
final b = Provider((ref) {
  ref.watch();
  return 0;
});
''');

      expect(deps, isEmpty);
    });

    test('records a source location for each dependency', () {
      final deps = _extract('''
final b = Provider((ref) {
  return ref.watch(a);
});
''');

      final location = deps.single.location;
      expect(location.file, 'lib/test.dart');
      expect(location.line, greaterThan(0));
      expect(location.column, greaterThan(0));
    });
  });
}
