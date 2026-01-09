// Stack trace parsing for Riverpod DevTools
//
// Concept inspired by riverpod_devtools_tracker by weitsai
// https://github.com/weitsai/riverpod_devtools_tracker (MIT License)
//
// This implementation is independently developed and adapted
// to integrate with our dependency tracking system.

import 'stack_trace_config.dart';

/// Represents a single location in the call stack.
class LocationInfo {
  /// File path (e.g., 'package:my_app/pages/todo_page.dart')
  final String file;

  /// Line number in the file
  final int line;

  /// Column number in the file (optional)
  final int? column;

  /// Function or method name (e.g., '_incrementCounter')
  final String function;

  const LocationInfo({
    required this.file,
    required this.line,
    this.column,
    required this.function,
  });

  /// Converts to JSON format for DevTools.
  Map<String, dynamic> toJson() => {
        'file': file,
        'line': line,
        if (column != null) 'column': column,
        'function': function,
      };

  @override
  String toString() => '$function ($file:$line${column != null ? ':$column' : ''})';
}

/// Parser for Dart stack traces.
///
/// Extracts location information from stack traces and filters
/// framework code to show only user code.
class StackTraceParser {
  final StackTraceConfig config;

  /// Regular expression to parse stack trace lines.
  ///
  /// Matches patterns like:
  /// #0  _incrementCounter (package:my_app/pages/todo_page.dart:45:12)
  /// #1  TodoPage.build.<anonymous closure> (package:my_app/pages/todo_page.dart:30:7)
  static final _stackTracePattern = RegExp(
    r'#(\d+)\s+(.+?)\s+\((.+?):(\d+)(?::(\d+))?\)',
  );

  const StackTraceParser(this.config);

  /// Parses a stack trace and returns the complete call chain.
  ///
  /// Returns a list of [LocationInfo] objects, filtered according to
  /// the configuration, up to [maxCallChainDepth] entries.
  List<LocationInfo> parseCallChain(StackTrace stackTrace) {
    final lines = stackTrace.toString().split('\n');
    final locations = <LocationInfo>[];

    for (final line in lines) {
      if (locations.length >= config.maxCallChainDepth) break;

      final match = _stackTracePattern.firstMatch(line);
      if (match == null) continue;

      final function = match.group(2)?.trim() ?? '';
      final file = match.group(3) ?? '';
      final lineStr = match.group(4) ?? '0';
      final columnStr = match.group(5);

      final lineNum = int.tryParse(lineStr) ?? 0;
      final columnNum = columnStr != null ? int.tryParse(columnStr) : null;

      final location = LocationInfo(
        file: file,
        line: lineNum,
        column: columnNum,
        function: function,
      );

      // Apply filtering
      if (!_shouldIgnore(location)) {
        locations.add(location);
      }
    }

    return locations;
  }

  /// Finds the trigger location (where user code called the provider).
  ///
  /// Returns the first location that is not in a provider file,
  /// or null if no valid user code is found.
  LocationInfo? findTriggerLocation(StackTrace stackTrace) {
    final callChain = parseCallChain(stackTrace);

    // Find the first non-provider file
    for (final location in callChain) {
      if (!_isProviderFile(location.file)) {
        return location;
      }
    }

    // If all locations are provider files, return the first one
    return callChain.isNotEmpty ? callChain.first : null;
  }

  /// Checks if a location should be ignored based on configuration.
  bool _shouldIgnore(LocationInfo location) {
    final file = location.file;

    // Check ignored package prefixes
    for (final prefix in config.ignoredPackagePrefixes) {
      if (file.startsWith(prefix)) {
        return true;
      }
    }

    // Check ignored file patterns
    for (final pattern in config.ignoredFilePatterns) {
      if (file.contains(pattern)) {
        return true;
      }
    }

    // If package prefixes are specified, only include matching files
    if (config.packagePrefixes.isNotEmpty) {
      bool matches = false;
      for (final prefix in config.packagePrefixes) {
        if (file.startsWith(prefix)) {
          matches = true;
          break;
        }
      }
      if (!matches) {
        return true;
      }
    }

    return false;
  }

  /// Checks if a file is likely a provider definition file.
  ///
  /// This is used to prioritize non-provider files when finding
  /// the trigger location.
  bool _isProviderFile(String file) {
    return file.contains('_provider.dart') ||
        file.contains('/providers/') ||
        file.contains('.g.dart');
  }
}
