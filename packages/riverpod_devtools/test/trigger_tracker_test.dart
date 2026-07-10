import 'package:flutter_test/flutter_test.dart';
import 'package:riverpod_devtools/src/trigger_tracker.dart';

void main() {
  group('UpdateTriggerTracker', () {
    test('returns no triggers when nothing was recorded', () {
      final tracker = UpdateTriggerTracker();
      expect(tracker.triggersFor('b', ['a'], 1000), isEmpty);
    });

    test('returns no triggers for a provider with no dependencies', () {
      final tracker = UpdateTriggerTracker();
      tracker.recordUpdate('a', 1, 1000);
      expect(tracker.triggersFor('b', [], 1000), isEmpty);
    });

    test('links an update to a recent dependency update', () {
      final tracker = UpdateTriggerTracker();
      tracker.recordUpdate('a', 1, 1000);
      expect(tracker.triggersFor('b', ['a'], 1010), [
        {'provider': 'a', 'seq': 1},
      ]);
    });

    test('ignores recent updates of non-dependencies', () {
      final tracker = UpdateTriggerTracker();
      tracker.recordUpdate('unrelated', 1, 1000);
      expect(tracker.triggersFor('b', ['a'], 1010), isEmpty);
    });

    test('ignores updates older than the window', () {
      final tracker = UpdateTriggerTracker(windowMs: 50);
      tracker.recordUpdate('a', 1, 1000);
      expect(tracker.triggersFor('b', ['a'], 1051), isEmpty);
    });

    test('includes an update exactly at the window boundary', () {
      final tracker = UpdateTriggerTracker(windowMs: 50);
      tracker.recordUpdate('a', 1, 1000);
      expect(tracker.triggersFor('b', ['a'], 1050), isNotEmpty);
    });

    test('does not report a provider as its own trigger', () {
      final tracker = UpdateTriggerTracker();
      tracker.recordUpdate('b', 1, 1000);
      // Self-watching cannot happen in Riverpod, but a provider whose static
      // dependency list erroneously contains itself must not self-trigger.
      expect(tracker.triggersFor('b', ['b', 'a'], 1010), isEmpty);
    });

    test('reports only the most recent update per trigger provider', () {
      final tracker = UpdateTriggerTracker();
      tracker.recordUpdate('a', 1, 1000);
      tracker.recordUpdate('a', 2, 1005);
      expect(tracker.triggersFor('b', ['a'], 1010), [
        {'provider': 'a', 'seq': 2},
      ]);
    });

    test('reports multiple distinct triggers, newest first', () {
      final tracker = UpdateTriggerTracker();
      tracker.recordUpdate('a', 1, 1000);
      tracker.recordUpdate('c', 2, 1005);
      expect(tracker.triggersFor('b', ['a', 'c'], 1010), [
        {'provider': 'c', 'seq': 2},
        {'provider': 'a', 'seq': 1},
      ]);
    });

    test('evicts entries beyond capacity, oldest first', () {
      final tracker = UpdateTriggerTracker(capacity: 2, windowMs: 10000);
      tracker.recordUpdate('a', 1, 1000);
      tracker.recordUpdate('b', 2, 1001);
      tracker.recordUpdate('c', 3, 1002);
      expect(tracker.triggersFor('x', ['a'], 1003), isEmpty);
      expect(tracker.triggersFor('x', ['b', 'c'], 1003), hasLength(2));
    });
  });
}
