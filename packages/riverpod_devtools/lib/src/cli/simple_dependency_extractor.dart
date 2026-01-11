import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/source/line_info.dart';

import '../builder/provider_metadata.dart';
import '../static_dependencies.dart';

/// Simplified dependency extractor for CLI use (no build_runner dependency)
class SimpleDependencyExtractor {
  /// Extract dependencies from a provider initializer expression
  static List<DependencyInfo> extractDependencies(
    Expression initializer,
    String filePath,
    LineInfo lineInfo,
  ) {
    final dependencies = <DependencyInfo>[];
    final visitor = _RefCallVisitor(dependencies, filePath, lineInfo);
    initializer.visitChildren(visitor);
    return dependencies;
  }
}

/// AST visitor that finds ref.watch/read/listen calls
class _RefCallVisitor extends RecursiveAstVisitor<void> {
  final List<DependencyInfo> dependencies;
  final String filePath;
  final LineInfo lineInfo;

  _RefCallVisitor(this.dependencies, this.filePath, this.lineInfo);

  @override
  void visitMethodInvocation(MethodInvocation node) {
    // Check if this is a ref.watch/read/listen call
    final target = node.target;
    final methodName = node.methodName.name;

    // Check for ref.watch/read/listen
    if (_isRefTarget(target) && _isRefMethod(methodName)) {
      final providerName = _extractProviderName(node.argumentList.arguments);
      if (providerName != null) {
        final dependencyType = _getDependencyType(methodName);
        if (dependencyType != null) {
          dependencies.add(DependencyInfo(
            providerName: providerName,
            type: dependencyType,
            location: _getLocation(node),
          ));
        }
      }
    }

    super.visitMethodInvocation(node);
  }

  /// Check if the target is 'ref'
  bool _isRefTarget(Expression? target) {
    if (target == null) return false;
    if (target is SimpleIdentifier && target.name == 'ref') return true;
    return false;
  }

  /// Check if the method name is watch, read, or listen
  bool _isRefMethod(String methodName) {
    return methodName == 'watch' ||
        methodName == 'read' ||
        methodName == 'listen';
  }

  /// Extract provider name from method arguments
  String? _extractProviderName(NodeList<Expression> arguments) {
    if (arguments.isEmpty) return null;

    final firstArg = arguments.first;
    return _getProviderNameFromExpression(firstArg);
  }

  /// Get provider name from an expression
  String? _getProviderNameFromExpression(Expression expr) {
    // Handle simple identifier: ref.watch(counterProvider)
    if (expr is SimpleIdentifier) {
      return expr.name;
    }

    // Handle property access: ref.watch(myProviders.counterProvider)
    if (expr is PropertyAccess) {
      return expr.propertyName.name;
    }

    // Handle prefixed identifier: ref.watch(providers.counterProvider)
    if (expr is PrefixedIdentifier) {
      return expr.identifier.name;
    }

    // Handle method calls (e.g., ref.watch(counterProvider.select(...)))
    if (expr is MethodInvocation) {
      final target = expr.target;
      if (target != null) {
        return _getProviderNameFromExpression(target);
      }
    }

    // Handle function calls (e.g., ref.watch(counterProvider(id)))
    if (expr is FunctionExpressionInvocation) {
      final function = expr.function;
      return _getProviderNameFromExpression(function);
    }

    return null;
  }

  /// Get DependencyType from method name
  DependencyType? _getDependencyType(String methodName) {
    switch (methodName) {
      case 'watch':
        return DependencyType.watch;
      case 'read':
        return DependencyType.read;
      case 'listen':
        return DependencyType.listen;
      default:
        return null;
    }
  }

  /// Get source location for an AST node
  SourceLocation _getLocation(AstNode node) {
    final location = lineInfo.getLocation(node.offset);
    return SourceLocation(
      file: filePath,
      line: location.lineNumber,
      column: location.columnNumber,
    );
  }
}
