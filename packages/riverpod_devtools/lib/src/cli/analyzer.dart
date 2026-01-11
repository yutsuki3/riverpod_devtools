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
          final visitor = _ProviderVisitor(file.path);
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

class _ProviderVisitor extends RecursiveAstVisitor<void> {
  final String filePath;
  final List<ProviderMetadata> providers = [];

  _ProviderVisitor(this.filePath);

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

  String? _getProviderType(Expression expression) {
    final type = expression.toString();
    // Extract provider type from expression - check for Provider anywhere
    if (type.contains('StateProvider')) return 'StateProvider';
    if (type.contains('FutureProvider')) return 'FutureProvider';
    if (type.contains('StreamProvider')) return 'StreamProvider';
    if (type.contains('NotifierProvider') && !type.contains('StateNotifierProvider')) {
      return 'NotifierProvider';
    }
    if (type.contains('StateNotifierProvider')) return 'StateNotifierProvider';
    if (type.contains('AsyncNotifierProvider')) return 'AsyncNotifierProvider';
    if (type.contains('ChangeNotifierProvider')) return 'ChangeNotifierProvider';
    if (type.contains('Provider')) return 'Provider';
    return null;
  }
}
