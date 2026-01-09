// Stack trace configuration for Riverpod DevTools
//
// Concept inspired by riverpod_devtools_tracker by weitsai
// https://github.com/weitsai/riverpod_devtools_tracker (MIT License)
//
// This implementation is independently developed and adapted
// to integrate with our dependency tracking system.

/// Configuration for stack trace tracking in Riverpod DevTools.
///
/// Controls how stack traces are captured, filtered, and displayed
/// when providers are updated.
class StackTraceConfig {
  /// Whether stack trace tracking is enabled.
  final bool enabled;

  /// Maximum depth of call chain to capture (default: 10).
  final int maxCallChainDepth;

  /// Package prefixes to include in stack traces.
  /// Only frames matching these prefixes will be shown.
  /// Example: ['package:my_app/', 'package:my_feature/']
  final List<String> packagePrefixes;

  /// Package prefixes to ignore in stack traces.
  /// Frames matching these prefixes will be filtered out.
  /// Default includes Flutter and Riverpod framework code.
  final List<String> ignoredPackagePrefixes;

  /// File name patterns to ignore (e.g., '*.g.dart' for generated files).
  final List<String> ignoredFilePatterns;

  /// Maximum time (in seconds) to cache stack traces for async providers.
  /// Default: 60 seconds.
  final int stackCacheExpirationSeconds;

  /// Maximum number of cached stack traces to keep in memory.
  /// Default: 100 entries.
  final int maxStackCacheSize;

  const StackTraceConfig({
    this.enabled = true,
    this.maxCallChainDepth = 10,
    this.packagePrefixes = const [],
    this.ignoredPackagePrefixes = const [
      'dart:',
      'package:flutter/',
      'package:flutter_riverpod/',
      'package:riverpod/',
      'package:riverpod_devtools/',
    ],
    this.ignoredFilePatterns = const [
      '.g.dart',
      '.freezed.dart',
    ],
    this.stackCacheExpirationSeconds = 60,
    this.maxStackCacheSize = 100,
  });

  /// Creates a configuration for a specific package.
  ///
  /// This is the recommended way to set up stack trace tracking.
  /// Example:
  /// ```dart
  /// RiverpodDevToolsObserver(
  ///   stackTraceConfig: StackTraceConfig.forPackage('my_app'),
  /// )
  /// ```
  factory StackTraceConfig.forPackage(
    String packageName, {
    bool enabled = true,
    int maxCallChainDepth = 10,
    List<String> additionalIgnoredPrefixes = const [],
    List<String> additionalIgnoredPatterns = const [],
    int stackCacheExpirationSeconds = 60,
    int maxStackCacheSize = 100,
  }) {
    return StackTraceConfig(
      enabled: enabled,
      maxCallChainDepth: maxCallChainDepth,
      packagePrefixes: ['package:$packageName/'],
      ignoredPackagePrefixes: [
        'dart:',
        'package:flutter/',
        'package:flutter_riverpod/',
        'package:riverpod/',
        'package:riverpod_devtools/',
        ...additionalIgnoredPrefixes,
      ],
      ignoredFilePatterns: [
        '.g.dart',
        '.freezed.dart',
        ...additionalIgnoredPatterns,
      ],
      stackCacheExpirationSeconds: stackCacheExpirationSeconds,
      maxStackCacheSize: maxStackCacheSize,
    );
  }

  /// Creates a copy of this config with some fields replaced.
  StackTraceConfig copyWith({
    bool? enabled,
    int? maxCallChainDepth,
    List<String>? packagePrefixes,
    List<String>? ignoredPackagePrefixes,
    List<String>? ignoredFilePatterns,
    int? stackCacheExpirationSeconds,
    int? maxStackCacheSize,
  }) {
    return StackTraceConfig(
      enabled: enabled ?? this.enabled,
      maxCallChainDepth: maxCallChainDepth ?? this.maxCallChainDepth,
      packagePrefixes: packagePrefixes ?? this.packagePrefixes,
      ignoredPackagePrefixes:
          ignoredPackagePrefixes ?? this.ignoredPackagePrefixes,
      ignoredFilePatterns: ignoredFilePatterns ?? this.ignoredFilePatterns,
      stackCacheExpirationSeconds:
          stackCacheExpirationSeconds ?? this.stackCacheExpirationSeconds,
      maxStackCacheSize: maxStackCacheSize ?? this.maxStackCacheSize,
    );
  }
}
