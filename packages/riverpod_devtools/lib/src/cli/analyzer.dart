import 'dart:convert';
import 'dart:io';
import 'package:analyzer/dart/analysis/analysis_context_collection.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:path/path.dart' as path;

import '../builder/provider_metadata.dart';
import 'simple_dependency_extractor.dart';

class AnalysisResult {
  final bool success;
  final int providerCount;
  final int dependencyCount;
  final String outputPath;
  final String? error;

  AnalysisResult({
    required this.success,
    required this.providerCount,
    required this.dependencyCount,
    required this.outputPath,
    this.error,
  });
}

class RiverpodAnalyzer {
  static const String _outputFileName = 'riverpod_dependencies.json';

  Future<AnalysisResult> analyze() async {
    try {
      final currentDir = Directory.current;
      final libDir = Directory(path.join(currentDir.path, 'lib'));

      if (!await libDir.exists()) {
        return AnalysisResult(
          success: false,
          providerCount: 0,
          dependencyCount: 0,
          outputPath: '',
          error: 'lib/ directory not found. Run this command from your project root.',
        );
      }

      // Collect all .dart files in lib/
      final dartFiles = <File>[];
      await for (final entity in libDir.list(recursive: true)) {
        if (entity is File && entity.path.endsWith('.dart')) {
          // Skip generated files
          if (!entity.path.endsWith('.g.dart') &&
              !entity.path.endsWith('.freezed.dart')) {
            dartFiles.add(entity);
          }
        }
      }

      // Analyze all files
      final allMetadata = <ProviderMetadata>[];
      final collection = AnalysisContextCollection(
        includedPaths: [libDir.path],
      );

      for (final file in dartFiles) {
        final metadata = await _analyzeFile(file, collection);
        allMetadata.addAll(metadata);
      }

      // Generate JSON
      final outputPath = path.join(libDir.path, _outputFileName);
      final jsonData = _generateJson(allMetadata);
      await File(outputPath).writeAsString(jsonData);

      final dependencyCount = allMetadata.fold<int>(
        0,
        (sum, metadata) => sum + metadata.dependencies.length,
      );

      return AnalysisResult(
        success: true,
        providerCount: allMetadata.length,
        dependencyCount: dependencyCount,
        outputPath: outputPath,
      );
    } catch (e) {
      return AnalysisResult(
        success: false,
        providerCount: 0,
        dependencyCount: 0,
        outputPath: '',
        error: e.toString(),
      );
    }
  }

  Future<List<ProviderMetadata>> _analyzeFile(
    File file,
    AnalysisContextCollection collection,
  ) async {
    final metadata = <ProviderMetadata>[];

    for (final context in collection.contexts) {
      if (context.contextRoot.isAnalyzed(file.path)) {
        final result = await context.currentSession.getResolvedUnit(file.path);
        if (result is ResolvedUnitResult) {
          final visitor = ProviderVisitor(file.path);
          result.unit.visitChildren(visitor);
          metadata.addAll(visitor.providers);
        }
        break;
      }
    }

    return metadata;
  }

  String _generateJson(List<ProviderMetadata> allMetadata) {
    final jsonMap = {
      'providers': allMetadata.map((m) => m.toJson()).toList(),
      'generatedAt': DateTime.now().toIso8601String(),
      'version': '1.0.0',
    };

    return const JsonEncoder.withIndent('  ').convert(jsonMap);
  }

  Future<void> watch() async {
    // Initial analysis
    await analyze();

    final currentDir = Directory.current;
    final libDir = Directory(path.join(currentDir.path, 'lib'));

    if (!await libDir.exists()) {
      // ignore: avoid_print
      print('lib/ directory not found');
      return;
    }

    // Watch for changes
    await for (final event in libDir.watch(recursive: true)) {
      if (event.path.endsWith('.dart') &&
          !event.path.endsWith('.g.dart') &&
          !event.path.endsWith('.freezed.dart')) {
        // ignore: avoid_print
        print('\n🔄 File changed: ${path.basename(event.path)}');
        final result = await analyze();
        if (result.success) {
          // ignore: avoid_print
          print('✅ Re-analysis complete (${result.providerCount} providers)');
        }
      }
    }
  }
}

/// Walks a compilation unit collecting [ProviderMetadata] for every provider
/// declaration it recognizes. Public (rather than the usual analyzer-private
/// helper) so tests can drive it directly off an unresolved `parseString()`
/// unit, the same way [SimpleDependencyExtractor] is tested — a full
/// [AnalysisContextCollection] needs a resolvable SDK, which test
/// environments don't always have.
class ProviderVisitor extends RecursiveAstVisitor<void> {
  final String filePath;
  final List<ProviderMetadata> providers = [];

  ProviderVisitor(this.filePath);

  @override
  void visitTopLevelVariableDeclaration(TopLevelVariableDeclaration node) {
    for (final variable in node.variables.variables) {
      final initializer = variable.initializer;
      if (initializer == null) continue;

      // Check if this is a provider
      final providerType = _getProviderType(initializer);
      if (providerType != null) {
        final providerName = variable.name.lexeme;
        // Get lineInfo from the compilation unit
        final compilationUnit = node.thisOrAncestorOfType<CompilationUnit>();
        if (compilationUnit == null) continue;

        final lineInfo = compilationUnit.lineInfo;

        final dependencies = SimpleDependencyExtractor.extractDependencies(
          initializer,
          filePath,
          lineInfo,
        );

        final location = lineInfo.getLocation(variable.offset);
        providers.add(ProviderMetadata(
          name: providerName,
          providerType: providerType,
          dependencies: dependencies,
          location: SourceLocation(
            file: filePath,
            line: location.lineNumber,
            column: location.columnNumber,
          ),
        ));
      }
    }

    super.visitTopLevelVariableDeclaration(node);
  }

  // `@riverpod` code generation (riverpod_generator) never declares a
  // top-level `final xProvider = ...` in the *source* file — the generated
  // variable lives in the `.g.dart` file, which is intentionally excluded
  // from analysis (it's derived, not authored). Without these two visitors,
  // every annotated provider/notifier is invisible to the analyzer, so its
  // generated name (`<lowerCamelCase(name)>Provider`, per riverpod_generator's
  // own convention) never appears in riverpod_dependencies.json — the runtime
  // provider then reports 'name_mismatch' even though nothing is misconfigured.
  @override
  void visitFunctionDeclaration(FunctionDeclaration node) {
    if (_hasRiverpodAnnotation(node.metadata)) {
      _addAnnotatedProvider(
        offsetNode: node,
        name: _generatedProviderName(node.name.lexeme),
        providerType: _inferFunctionProviderType(node),
        dependencySource: node.functionExpression.body,
      );
    }
    super.visitFunctionDeclaration(node);
  }

  @override
  void visitClassDeclaration(ClassDeclaration node) {
    if (_hasRiverpodAnnotation(node.metadata)) {
      _addAnnotatedProvider(
        offsetNode: node,
        name: _generatedProviderName(node.name.lexeme),
        providerType: _inferClassProviderType(node),
        dependencySource: node,
      );
    }
    super.visitClassDeclaration(node);
  }

  void _addAnnotatedProvider({
    required AstNode offsetNode,
    required String name,
    required String providerType,
    required AstNode dependencySource,
  }) {
    final compilationUnit = offsetNode.thisOrAncestorOfType<CompilationUnit>();
    if (compilationUnit == null) return;

    final lineInfo = compilationUnit.lineInfo;
    final dependencies = SimpleDependencyExtractor.extractDependencies(
      dependencySource,
      filePath,
      lineInfo,
    );

    final location = lineInfo.getLocation(offsetNode.offset);
    providers.add(ProviderMetadata(
      name: name,
      providerType: providerType,
      dependencies: dependencies,
      location: SourceLocation(
        file: filePath,
        line: location.lineNumber,
        column: location.columnNumber,
      ),
    ));
  }

  /// `@riverpod`/`@Riverpod(...)` — matched by name only (not the resolved
  /// element), same lightweight approach as the rest of this AST-only
  /// analyzer (no resolved imports, no build_runner dependency).
  bool _hasRiverpodAnnotation(NodeList<Annotation> metadata) {
    for (final annotation in metadata) {
      final name = annotation.name.name;
      if (name == 'riverpod' || name == 'Riverpod') return true;
    }
    return false;
  }

  /// riverpod_generator's naming convention: the function/class name with
  /// its first letter lower-cased, plus a `Provider` suffix.
  String _generatedProviderName(String sourceName) {
    if (sourceName.isEmpty) return 'Provider';
    return '${sourceName[0].toLowerCase()}${sourceName.substring(1)}Provider';
  }

  String _inferFunctionProviderType(FunctionDeclaration node) {
    final returnType = node.returnType?.toString() ?? '';
    if (returnType.startsWith('Stream')) return 'StreamProvider';
    if (returnType.startsWith('Future')) return 'FutureProvider';
    return 'Provider';
  }

  String _inferClassProviderType(ClassDeclaration node) {
    for (final member in node.members) {
      if (member is MethodDeclaration && member.name.lexeme == 'build') {
        final returnType = member.returnType?.toString() ?? '';
        if (returnType.startsWith('Stream')) return 'StreamNotifierProvider';
        if (returnType.startsWith('Future')) return 'AsyncNotifierProvider';
      }
    }
    return 'NotifierProvider';
  }

  String? _getProviderType(Expression expression) {
    final type = expression.toString();
    
    // Map of provider type patterns (order matters for specificity)
    const providerPatterns = [
      'StateNotifierProvider',
      'AsyncNotifierProvider',
      'ChangeNotifierProvider',
      'StateProvider',
      'FutureProvider',
      'StreamProvider',
      'NotifierProvider',
      'Provider',
    ];
    
    for (final pattern in providerPatterns) {
      if (type.contains(pattern)) {
        return pattern;
      }
    }
    return null;
  }
}
