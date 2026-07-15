import 'package:flutter_test/flutter_test.dart';
import 'package:riverpod_devtools/src/utils/coerce_int.dart';

void main() {
  group('coerceInt', () {
    test('passes an int through', () {
      expect(coerceInt(50), 50);
      expect(coerceInt(0), 0);
      expect(coerceInt(-3), -3);
    });

    test('coerces a whole-numbered double (client quirk)', () {
      expect(coerceInt(50.0), 50);
    });

    test('truncates a fractional double (matches num.toInt())', () {
      // Pre-existing behavior of both call sites; fractional values are
      // normally rejected upstream (MCP schema validation) before reaching
      // this helper.
      expect(coerceInt(50.7), 50);
    });

    test('parses integer and double strings (query parameters)', () {
      expect(coerceInt('50'), 50);
      expect(coerceInt('50.0'), 50);
      expect(coerceInt('-3'), -3);
    });

    test('returns null for non-numeric input', () {
      expect(coerceInt(null), isNull);
      expect(coerceInt('abc'), isNull);
      expect(coerceInt(''), isNull);
      expect(coerceInt(true), isNull);
      expect(coerceInt([50]), isNull);
    });
  });
}
