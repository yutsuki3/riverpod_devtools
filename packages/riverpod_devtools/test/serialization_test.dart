import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:riverpod_devtools/src/utils/serialization.dart';

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
