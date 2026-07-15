import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riverpod_devtools/src/builder/provider_metadata.dart';
import 'package:riverpod_devtools/src/cli/analyzer.dart';

/// [ProviderVisitor] normally runs against a resolved AnalysisContextCollection
/// unit (via `RiverpodAnalyzer.analyze()`), which needs an SDK to resolve
/// against. It only does syntactic AST matching though (same as
/// [SimpleDependencyExtractor]), so an unresolved `parseString()` unit is
/// enough to exercise it directly.
List<ProviderMetadata> _providersFor(String source) {
  final parsed = parseString(content: source, throwIfDiagnostics: false);
  final visitor = ProviderVisitor('lib/test.dart');
  parsed.unit.visitChildren(visitor);
  return visitor.providers;
}

void main() {
  group('ProviderVisitor - @riverpod function-based providers', () {
    test('names a function-based provider per riverpod_generator convention', () {
      final providers = _providersFor('''
@riverpod
String greeting(GreetingRef ref) => 'hi';
''');

      expect(providers, hasLength(1));
      expect(providers.single.name, 'greetingProvider');
      expect(providers.single.providerType, 'Provider');
    });

    test('recognizes the @Riverpod(...) constructor form', () {
      final providers = _providersFor('''
@Riverpod(keepAlive: true)
String greeting(GreetingRef ref) => 'hi';
''');

      expect(providers, hasLength(1));
      expect(providers.single.name, 'greetingProvider');
    });

    test('infers FutureProvider/StreamProvider from the return type', () {
      final providers = _providersFor('''
@riverpod
Future<String> asyncGreeting(AsyncGreetingRef ref) async => 'hi';

@riverpod
Stream<int> tick(TickRef ref) async* {}
''');

      expect(providers, hasLength(2));
      expect(providers[0].providerType, 'FutureProvider');
      expect(providers[1].providerType, 'StreamProvider');
    });

    test('extracts ref.watch/read/listen calls from the function body', () {
      final providers = _providersFor('''
@riverpod
String greeting(GreetingRef ref) {
  final name = ref.watch(nameProvider);
  ref.listen(loggerProvider, (prev, next) {});
  return name;
}
''');

      expect(providers.single.dependencies.map((d) => d.providerName),
          containsAll(['nameProvider', 'loggerProvider']));
    });

    test('a plain (non-annotated) function is not treated as a provider', () {
      final providers = _providersFor('String greeting() => \'hi\';');
      expect(providers, isEmpty);
    });
  });

  group('ProviderVisitor - @riverpod class-based (notifier) providers', () {
    test('names a class-based provider from the lower-camel class name', () {
      final providers = _providersFor('''
@riverpod
class VersionManager extends _\$VersionManager {
  @override
  int build() => 0;
}
''');

      expect(providers, hasLength(1));
      expect(providers.single.name, 'versionManagerProvider');
      expect(providers.single.providerType, 'NotifierProvider');
    });

    test('infers AsyncNotifierProvider/StreamNotifierProvider from build()', () {
      final providers = _providersFor('''
@riverpod
class Facility extends _\$Facility {
  @override
  Future<int> build() async => 0;
}

@riverpod
class FacilityTicker extends _\$FacilityTicker {
  @override
  Stream<int> build() async* {}
}
''');

      expect(providers, hasLength(2));
      expect(providers[0].providerType, 'AsyncNotifierProvider');
      expect(providers[1].providerType, 'StreamNotifierProvider');
    });

    test('extracts ref.watch calls from anywhere in the class body', () {
      final providers = _providersFor('''
@riverpod
class VersionManager extends _\$VersionManager {
  @override
  int build() {
    return ref.watch(configProvider);
  }
}
''');

      expect(providers.single.dependencies.single.providerName, 'configProvider');
    });

    test('a plain (non-annotated) class is not treated as a provider', () {
      final providers = _providersFor('''
class VersionManager {
  int build() => 0;
}
''');
      expect(providers, isEmpty);
    });
  });
}
