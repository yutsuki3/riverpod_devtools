import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:riverpod_devtools/src/utils/serialization.dart';

/// An object whose toString() is a class-like string longer than the
/// serializer's string cap, used to verify truncated strings are not parsed.
class _LongToString {
  @override
  String toString() => 'Huge(field: ${'y' * 10000})';
}

class TestObject {
  final String id;
  TestObject? child;

  TestObject(this.id);

  @override
  String toString() => 'TestObject(id: $id)';
}

/// Mimics Riverpod's AsyncData.toString() without depending on Riverpod
class FakeAsyncData {
  @override
  String toString() => 'AsyncData<int>(value: 5)';
}

class FakeAsyncLoading {
  @override
  String toString() => 'AsyncLoading<int>()';
}

class FakeAsyncError {
  @override
  String toString() =>
      'AsyncError<int>(error: Exception: boom, stackTrace: #0 main)';
}

/// A model whose toJson() contains values json.encode can't handle directly.
class ModelWithUnsafeToJson {
  Map<String, Object?> toJson() => {
        'name': 'test',
        'createdAt': DateTime.utc(2026, 1, 1),
        'nested': [
          DateTime.utc(2026, 1, 2),
          {'inner': DateTime.utc(2026, 1, 3)},
        ],
      };
}

/// A model whose toJson() contains non-finite doubles, which json.encode
/// cannot handle (and developer.postEvent has no toEncodable fallback).
class ModelWithNonFiniteToJson {
  Map<String, Object?> toJson() => {
        'ratio': double.infinity,
        'delta': double.negativeInfinity,
        'score': double.nan,
        'finite': 3.5,
        'nested': [
          double.infinity,
          {'inner': double.nan},
        ],
      };
}

/// A model whose toString() carries a non-finite number in the
/// "ClassName(prop: val)" shape the serializer parses into structure.
class StatsWithInfinity {
  @override
  String toString() => 'Stats(ratio: Infinity, count: 3)';
}

void main() {
  group('serializeValue', () {
    test('handles null', () {
      final result = serializeValue(null);
      expect(result['type'], 'null');
      expect(result['value'], null);
    });

    test('handles primitives', () {
      expect(serializeValue(123)['string'], '123');
      expect(serializeValue(true)['string'], 'true');
      expect(serializeValue('hello')['string'], 'hello');
    });

    test('handles lists', () {
      final list = [1, 'two'];
      final result = serializeValue(list);
      expect(result['items'], isNotNull);
      expect((result['items'] as List).length, 2);
    });

    test('handles maps', () {
      final map = {'one': 1, 'two': 2};
      final result = serializeValue(map);
      expect(result['entries'], isNotNull);
      expect((result['entries'] as List).length, 2);
    });

    test('handles recursion depth limit', () {
      // Create a deeply nested list: [[[[[[...]]]]]]
      dynamic deepList = [];
      for (var i = 0; i < 15; i++) {
        deepList = [deepList];
      }

      final result = serializeValue(deepList);

      // We expect at some level to find <Max Depth Exceeded>
      bool foundMaxDepthMsg = false;
      dynamic current = result;
      while (current is Map) {
        if (current['value'] == '<Max Depth Exceeded>') {
          foundMaxDepthMsg = true;
          break;
        }
        if (current['items'] != null && (current['items'] as List).isNotEmpty) {
          current = (current['items'] as List)[0];
        } else {
          break;
        }
      }
      expect(foundMaxDepthMsg, isTrue, reason: 'Should hit max depth');
    });

    test('detects AsyncValue states from toString()', () {
      final data = serializeValue(FakeAsyncData());
      expect(data['asyncState'], 'data');
      expect(data['value'], {'value': 5});

      final loading = serializeValue(FakeAsyncLoading());
      expect(loading['asyncState'], 'loading');

      final error = serializeValue(FakeAsyncError());
      expect(error['asyncState'], 'error');
    });

    test('sanitizes non-JSON-encodable leaves in toJson() output', () {
      final result = serializeValue(ModelWithUnsafeToJson());
      final value = result['value'] as Map;

      expect(value['name'], 'test');
      expect(value['createdAt'], isA<String>());
      final nested = value['nested'] as List;
      expect(nested[0], isA<String>());
      expect((nested[1] as Map)['inner'], isA<String>());
      // The whole event must survive json.encode without a toEncodable
      // fallback, as developer.postEvent has none.
      expect(() => jsonEncode(result), returnsNormally);
    });

    group('non-finite numbers (Infinity/-Infinity/NaN)', () {
      test('a top-level non-finite double is encodable', () {
        for (final value in [
          double.infinity,
          double.negativeInfinity,
          double.nan,
        ]) {
          final result = serializeValue(value);
          // The number itself is only carried as its `string` form, which is
          // json-safe; the event must survive json.encode regardless.
          expect(() => jsonEncode(result), returnsNormally,
              reason: 'failed for $value');
        }
      });

      test('sanitizes non-finite doubles in toJson() output', () {
        final result = serializeValue(ModelWithNonFiniteToJson());
        final value = result['value'] as Map;

        expect(value['ratio'], 'Infinity');
        expect(value['delta'], '-Infinity');
        expect(value['score'], 'NaN');
        // Finite numbers are left as-is.
        expect(value['finite'], 3.5);

        final nested = value['nested'] as List;
        expect(nested[0], 'Infinity');
        expect((nested[1] as Map)['inner'], 'NaN');

        // The whole event must survive json.encode without a toEncodable
        // fallback, as developer.postEvent has none.
        expect(() => jsonEncode(result), returnsNormally);
      });

      test('does not parse a non-finite toString() number into a live double',
          () {
        final result = serializeValue(StatsWithInfinity());
        final value = result['value'] as Map;

        // The non-finite field stays a string; the finite one still parses.
        expect(value['ratio'], 'Infinity');
        expect(value['count'], 3);
        expect(() => jsonEncode(result), returnsNormally);
      });
    });

    test('handles circular references', () {
      final obj1 = TestObject('1');
      final obj2 = TestObject('2');
      obj1.child = obj2;
      obj2.child = obj1; // Cycle

      // Serialize circular structure (manual map construction simulation)
      // Since our custom object is not a Map/List, serializeValue relies on toString/reflection fallback
      // or we can test with Maps which are easier to cycle in Dart without mirrors if we use dynamic?
      // Actually, serializeValue uses recursion for Maps/Lists.

      final map1 = <String, dynamic>{'name': 'map1'};
      final map2 = <String, dynamic>{'name': 'map2'};
      map1['next'] = map2;
      map2['prev'] = map1;

      final result = serializeValue(map1);
      final entries = result['entries'] as List;
      final nextEntry = entries.firstWhere((e) => e['key'] == 'next')['value'];
      final nextEntries = nextEntry['entries'] as List;
      final prevEntry =
          nextEntries.firstWhere((e) => e['key'] == 'prev')['value'];

      expect(prevEntry['value'], '<Cyclic Reference>');
      expect(prevEntry['lossy'], true);
    });

    test('marks a max-depth-exceeded value as lossy', () {
      dynamic deepList = [];
      for (var i = 0; i < 15; i++) {
        deepList = [deepList];
      }

      final result = serializeValue(deepList);

      dynamic current = result;
      var foundLossy = false;
      while (current is Map) {
        if (current['value'] == '<Max Depth Exceeded>') {
          foundLossy = current['lossy'] == true;
          break;
        }
        if (current['items'] != null && (current['items'] as List).isNotEmpty) {
          current = (current['items'] as List)[0];
        } else {
          break;
        }
      }
      expect(foundLossy, isTrue);
    });

    test('a normal value is not marked lossy', () {
      expect(serializeValue(5).containsKey('lossy'), isFalse);
      expect(serializeValue('hi').containsKey('lossy'), isFalse);
    });

    group('breadth/size caps', () {
      test('caps a large List and reports the true size', () {
        final result = serializeValue(List<int>.generate(5000, (i) => i));

        expect((result['items'] as List).length, 100);
        expect(result['truncated'], true);
        expect(result['totalItems'], 5000);
        expect(result['lossy'], true);
        // The capped payload is still encodable.
        expect(() => jsonEncode(result), returnsNormally);
      });

      test('caps a large Map and reports the true size', () {
        final big = {for (var i = 0; i < 5000; i++) 'k$i': i};
        final result = serializeValue(big);

        expect((result['entries'] as List).length, 100);
        expect(result['truncated'], true);
        expect(result['totalItems'], 5000);
        expect(result['lossy'], true);
      });

      test('caps a large Set and reports the true size', () {
        final result = serializeValue(List<int>.generate(5000, (i) => i).toSet());

        expect((result['items'] as List).length, 100);
        expect(result['totalItems'], 5000);
        expect(result['lossy'], true);
      });

      test('a collection at the cap is not marked truncated', () {
        final result = serializeValue(List<int>.generate(100, (i) => i));

        expect((result['items'] as List).length, 100);
        expect(result.containsKey('truncated'), isFalse);
        expect(result.containsKey('lossy'), isFalse);
      });

      test('caps a very long string value and flags it lossy', () {
        final result = serializeValue('x' * 10000);

        final string = result['string'] as String;
        expect(string.length, lessThan(10000));
        expect(string.endsWith('…'), isTrue);
        expect(result['lossy'], true);
      });

      test('does not parse a truncated ClassName(...) string into structure', () {
        // A giant "class-like" string must not be parsed (which would produce
        // misleading fields from a cut-off representation).
        final result = serializeValue(_LongToString());

        expect(result.containsKey('value'), isFalse);
        expect(result['string'], isA<String>());
        expect(result['lossy'], true);
      });
    });

    test('a shared object beyond the depth limit is not later mislabeled '
        'as a cyclic reference', () {
      // `shared` sits at depth 11 down one path (past the limit) and depth
      // 1 down another. The deep path is serialized first; it must not leave
      // `shared` marked as "seen", which would make the shallow, genuinely
      // non-cyclic occurrence report a false cycle.
      final shared = <String, dynamic>{'leaf': 1};
      Map<String, dynamic> deep = shared;
      for (var i = 0; i < 10; i++) {
        deep = {'n': deep};
      }
      final root = <String, dynamic>{'deep': deep, 'shallow': shared};

      final entries = serializeValue(root)['entries'] as List;
      final shallow =
          entries.firstWhere((e) => e['key'] == 'shallow')['value'] as Map;

      expect(shallow['value'], isNot('<Cyclic Reference>'));
      final leafEntries = shallow['entries'] as List;
      expect(leafEntries.single['key'], 'leaf');
    });
  });
}
