#!/usr/bin/env dart

import 'dart:io';
import 'package:riverpod_devtools/src/cli/analyzer.dart';

void main(List<String> arguments) async {
  final watch = arguments.contains('--watch') || arguments.contains('-w');

  // ignore: avoid_print
  print('🔍 Riverpod DevTools - Static Dependency Analyzer');
  // ignore: avoid_print
  print('');

  final analyzer = RiverpodAnalyzer();

  if (watch) {
    // ignore: avoid_print
    print('👀 Watch mode enabled - analyzing on file changes...');
    await analyzer.watch();
  } else {
    // ignore: avoid_print
    print('📊 Analyzing providers...');
    final result = await analyzer.analyze();

    if (result.success) {
      // ignore: avoid_print
      print('✅ Analysis complete!');
      // ignore: avoid_print
      print('   Found ${result.providerCount} providers');
      // ignore: avoid_print
      print('   Detected ${result.dependencyCount} dependencies');
      // ignore: avoid_print
      print('   Output: ${result.outputPath}');
    } else {
      // ignore: avoid_print
      print('❌ Analysis failed: ${result.error}');
      exit(1);
    }
  }
}
