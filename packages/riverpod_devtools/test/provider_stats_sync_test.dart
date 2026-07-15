import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Drift guard for the deliberately duplicated stats logic.
///
/// The stats aggregation is implemented twice on purpose — this package
/// aggregates raw event JSON for `/stats` + MCP, while the DevTools extension
/// aggregates its typed `ProviderEvent` model for the UI (the two packages
/// don't share code; see CLAUDE.md). The *rules* must stay identical, or the
/// UI and MCP will disagree about the same app.
///
/// This test machine-checks the parts that are textually shared between the
/// two files — the threshold/window constants and the sparkline bucketing
/// function — without introducing a dependency between the packages. If it
/// fails, someone changed one side only: apply the same change to the other
/// file (or update this test if the shapes legitimately diverged).
void main() {
  const packageFile = 'lib/src/provider_stats.dart';
  const extensionFile =
      '../riverpod_devtools_extension/lib/src/utils/provider_stats.dart';

  group('provider_stats duplication drift guard', () {
    test('the extension copy exists where this guard expects it', () {
      expect(
        File(extensionFile).existsSync(),
        isTrue,
        reason:
            'The extension-side stats implementation moved. Update the paths '
            'in this drift guard so it keeps comparing the two copies.',
      );
    });

    test('shared constants are identical in both copies', () {
      final packageConsts = _constants(File(packageFile).readAsStringSync());
      final extensionConsts =
          _constants(File(extensionFile).readAsStringSync());

      // Every constant defined on either side must exist on both sides with
      // the same value (thresholds/windows drive the flags users see).
      expect(packageConsts.keys.toSet(), extensionConsts.keys.toSet());
      expect(packageConsts, extensionConsts);
      expect(packageConsts, isNotEmpty);
    });

    test('the sparkline bucketing function is identical in both copies', () {
      final packageFn =
          _function(File(packageFile).readAsStringSync(), '_addToBucket');
      final extensionFn =
          _function(File(extensionFile).readAsStringSync(), '_addToBucket');

      expect(packageFn, isNotNull);
      expect(extensionFn, isNotNull);
      expect(packageFn, extensionFn);
    });
  });
}

/// Extracts top-level `const kName = value;` declarations as a name → value
/// map, with the value normalized (comments/whitespace stripped) so only a
/// semantic change trips the guard.
Map<String, String> _constants(String source) {
  final pattern = RegExp(r'^const\s+(k\w+)\s*=\s*([^;]+);', multiLine: true);
  return {
    for (final match in pattern.allMatches(_stripComments(source)))
      match.group(1)!: _normalize(match.group(2)!),
  };
}

/// Extracts the body of top-level function [name] (from its `void name`
/// declaration to the first unindented closing brace), normalized for
/// comparison. Returns null when not found.
String? _function(String source, String name) {
  final start = source.indexOf('void $name');
  if (start == -1) return null;
  final end = source.indexOf('\n}', start);
  if (end == -1) return null;
  return _normalize(_stripComments(source.substring(start, end + 2)));
}

String _stripComments(String source) =>
    source.replaceAll(RegExp(r'//[^\n]*'), '');

String _normalize(String source) => source.replaceAll(RegExp(r'\s+'), ' ').trim();
