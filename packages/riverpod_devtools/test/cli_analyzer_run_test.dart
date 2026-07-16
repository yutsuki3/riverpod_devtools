import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:riverpod_devtools/src/cli/analyzer.dart';

/// End-to-end coverage for `RiverpodAnalyzer.analyze()` against a real
/// on-disk project layout. This became testable when the analyzer switched
/// from `AnalysisContextCollection` + `getResolvedUnit` (which needs a
/// resolvable SDK, unavailable in some test environments) to a plain
/// syntax-only `parseFile` — the very change that also makes the CLI fast on
/// provider-heavy projects. These tests pin that contract: the parse-only
/// pipeline must keep producing the same metadata the resolved pipeline did.
void main() {
  late Directory tempDir;
  late Directory previousCwd;

  setUp(() async {
    previousCwd = Directory.current;
    tempDir = await Directory.systemTemp.createTemp('riverpod_analyze_test');
    // analyze() reads the project from the current directory, like the CLI.
    Directory.current = tempDir;
  });

  tearDown(() async {
    Directory.current = previousCwd;
    await tempDir.delete(recursive: true);
  });

  File libFile(String name, String contents) {
    final file = File('${tempDir.path}/lib/$name')
      ..createSync(recursive: true)
      ..writeAsStringSync(contents);
    return file;
  }

  test('fails cleanly when lib/ does not exist', () async {
    final result = await RiverpodAnalyzer().analyze();

    expect(result.success, isFalse);
    expect(result.error, contains('lib/ directory not found'));
  });

  test('analyzes hand-written and @riverpod providers end-to-end', () async {
    libFile('providers.dart', '''
final counterProvider = StateProvider<int>((ref) => 0);

final doubledProvider = Provider<int>((ref) {
  return ref.watch(counterProvider) * 2;
});
''');
    libFile('version_manager.dart', '''
@riverpod
class VersionManager extends _\$VersionManager {
  @override
  int build() => ref.watch(counterProvider);
}
''');

    final result = await RiverpodAnalyzer().analyze();

    expect(result.success, isTrue, reason: result.error ?? '');
    expect(result.providerCount, 3);
    // doubledProvider -> counterProvider, VersionManager -> counterProvider
    expect(result.dependencyCount, 2);

    final json = jsonDecode(File(result.outputPath).readAsStringSync())
        as Map<String, dynamic>;
    final providers = (json['providers'] as List).cast<Map<String, dynamic>>();
    expect(
      providers.map((p) => p['name']).toSet(),
      {'counterProvider', 'doubledProvider', 'versionManagerProvider'},
    );
    expect(json['version'], '1.0.0'); // dependency-JSON FORMAT version
  });

  test('skips generated files and survives a file with syntax errors',
      () async {
    libFile('good.dart', 'final aProvider = Provider<int>((ref) => 1);');
    // Generated files are excluded from analysis entirely.
    libFile('good.g.dart',
        'final generatedProvider = Provider<int>((ref) => 2);');
    libFile('good.freezed.dart',
        'final frozenProvider = Provider<int>((ref) => 3);');
    // A broken file must skip only itself, not abort the run.
    libFile('broken.dart', 'final = ;;; class {');

    final result = await RiverpodAnalyzer().analyze();

    expect(result.success, isTrue, reason: result.error ?? '');
    expect(result.providerCount, 1);

    final json = jsonDecode(File(result.outputPath).readAsStringSync())
        as Map<String, dynamic>;
    final names =
        (json['providers'] as List).map((p) => p['name'] as String).toList();
    expect(names, ['aProvider']);
  });
}
