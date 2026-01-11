import 'package:flutter_test/flutter_test.dart';
import 'package:riverpod_devtools/src/utils/serialization.dart';

class TestObject {
  final String id;
  TestObject? child;

  TestObject(this.id);

  @override
  String toString() => 'TestObject(id: $id)';
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
    });
  });
}
