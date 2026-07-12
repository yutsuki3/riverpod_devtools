// Rewrites the flutter_riverpod (and riverpod, if present) version constraint
// in pubspec.yaml to the value given as the first CLI argument. Used only by
// CI (see .github/workflows/riverpod-compat.yml) to test both the 2.x and 3.x
// lines. Not used at runtime.
import 'dart:io';

void main(List<String> args) {
  if (args.isEmpty) {
    stderr.writeln('Usage: dart run tool/set_riverpod_version.dart <constraint>');
    exit(64);
  }
  final constraint = args.first;
  final file = File('pubspec.yaml');
  final lines = file.readAsLinesSync();

  // Match lines like:  "  flutter_riverpod: ^2.6.0"  (any leading indent).
  final pattern = RegExp(r'^(\s+)(flutter_riverpod|riverpod):\s*.*$');
  var changed = 0;
  for (var i = 0; i < lines.length; i++) {
    final m = pattern.firstMatch(lines[i]);
    if (m != null) {
      lines[i] = '${m.group(1)}${m.group(2)}: "$constraint"';
      changed++;
    }
  }
  if (changed == 0) {
    stderr.writeln('No riverpod dependency line found in pubspec.yaml.');
    exit(1);
  }
  file.writeAsStringSync('${lines.join('\n')}\n');
  stdout.writeln('Pinned $changed dependency line(s) to "$constraint".');
}
