import 'package:flutter_test/flutter_test.dart';
import 'package:riverpod_devtools/src/utils/stack_trace_utils.dart';

void main() {
  group('formatStackTrace', () {
    test('keeps user frames and drops riverpod-internal frames', () {
      final trace = StackTrace.fromString('''
#0      MyNotifier.build (package:my_app/notifier.dart:10:5)
#1      ProviderElement.rebuild (package:riverpod/src/framework.dart:100:9)
#2      Notifier.state= (package:flutter_riverpod/src/notifier.dart:20:3)
#3      main (package:my_app/main.dart:5:3)
''');
      final formatted = formatStackTrace(trace);
      expect(formatted, contains('package:my_app/notifier.dart'));
      expect(formatted, contains('package:my_app/main.dart'));
      expect(formatted, isNot(contains('package:riverpod/')));
      expect(formatted, isNot(contains('package:flutter_riverpod/')));
    });

    test('caps the number of frames', () {
      final lines = List.generate(
          40, (i) => '#$i      fn$i (package:my_app/a.dart:$i:1)');
      final formatted = formatStackTrace(
        StackTrace.fromString(lines.join('\n')),
        maxFrames: 20,
      );
      expect(formatted.split('\n'), hasLength(20));
    });

    test('falls back to unfiltered frames when everything is internal', () {
      final trace = StackTrace.fromString('''
#0      a (package:riverpod/src/a.dart:1:1)
#1      b (package:riverpod/src/b.dart:2:2)
''');
      final formatted = formatStackTrace(trace);
      expect(formatted, contains('package:riverpod/src/a.dart'));
    });
  });

  group('truncateErrorMessage', () {
    test('returns short messages unchanged', () {
      expect(truncateErrorMessage('boom'), 'boom');
    });

    test('caps long messages', () {
      final truncated = truncateErrorMessage('x' * 5000, maxLength: 2000);
      expect(truncated.length, lessThan(2100));
      expect(truncated, endsWith('… (truncated)'));
    });
  });
}
