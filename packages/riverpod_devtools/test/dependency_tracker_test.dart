import 'package:flutter_test/flutter_test.dart';
import 'package:riverpod_devtools/src/dependency_tracker.dart';
import 'package:fake_async/fake_async.dart';

void main() {
  group('DependencyTracker', () {
    late DependencyTracker tracker;

    setUp(() {
      tracker = DependencyTracker();
    });

    test('detects dependency when updates happen in sequence', () {
      fakeAsync((async) {
        // providerA updates
        tracker.recordUpdate('idA', 'providerA', isUpdate: true);

        // short delay (within batch window)
        async.elapse(const Duration(milliseconds: 10));

        // providerB updates (should depend on A)
        tracker.recordUpdate('idB', 'providerB', isUpdate: true);

        // Wait for batch window to close and flush
        async.elapse(const Duration(milliseconds: 150));

        final depsB = tracker.getDependencies('idB');
        expect(depsB, contains('providerA'));

        final depsA = tracker.getDependencies('idA');
        expect(depsA, isEmpty);
      });
    });

    test('ignores dependencies across large time gaps (separate waves)', () {
      fakeAsync((async) {
        // providerA updates
        tracker.recordUpdate('idA', 'providerA', isUpdate: true);

        // Large delay (new wave)
        async.elapse(const Duration(milliseconds: 200));

        // providerB updates
        tracker.recordUpdate('idB', 'providerB', isUpdate: true);

        async.elapse(const Duration(milliseconds: 150));

        final depsB = tracker.getDependencies('idB');
        expect(depsB, isEmpty);
      });
    });

    test('detects dependencies during initial loads (isUpdate: false)', () {
      fakeAsync((async) {
        tracker.recordUpdate('idA', 'providerA', isUpdate: false); // Add
        async.elapse(const Duration(milliseconds: 10));
        tracker.recordUpdate('idB', 'providerB', isUpdate: false); // Add (depends on A)

        async.elapse(const Duration(milliseconds: 150));

        final depsB = tracker.getDependencies('idB');
        expect(depsB, contains('providerA'));
      });
    });

    test('detects mixed add and update dependencies', () {
      fakeAsync((async) {
        tracker.recordUpdate('idA', 'providerA', isUpdate: false); // Add
        async.elapse(const Duration(milliseconds: 10));
        tracker.recordUpdate('idB', 'providerB', isUpdate: true); // Update (depends on A)

        async.elapse(const Duration(milliseconds: 150));

        final depsB = tracker.getDependencies('idB');
        expect(depsB, contains('providerA'));
      });
    });

    test('detects dependency chain during initial load', () {
      fakeAsync((async) {
        // Simulate a dependency chain: A -> B -> C
        tracker.recordUpdate('idA', 'providerA', isUpdate: false);
        async.elapse(const Duration(milliseconds: 10));
        tracker.recordUpdate('idB', 'providerB', isUpdate: false);
        async.elapse(const Duration(milliseconds: 10));
        tracker.recordUpdate('idC', 'providerC', isUpdate: false);

        async.elapse(const Duration(milliseconds: 150));

        final depsA = tracker.getDependencies('idA');
        expect(depsA, isEmpty, reason: 'A has no dependencies');

        final depsB = tracker.getDependencies('idB');
        expect(depsB, contains('providerA'),
            reason: 'B depends on A (immediate predecessor)');

        final depsC = tracker.getDependencies('idC');
        expect(depsC, contains('providerB'),
            reason: 'C depends on B (immediate predecessor)');
      });
    });

    test('clears dependencies', () {
      fakeAsync((async) {
        tracker.recordUpdate('idA', 'providerA', isUpdate: true);
        async.elapse(const Duration(milliseconds: 10));
        tracker.recordUpdate('idB', 'providerB', isUpdate: true);
        async.elapse(const Duration(milliseconds: 150));

        expect(tracker.getDependencies('idB'), isNotEmpty);

        tracker.clear();
        expect(tracker.getDependencies('idB'), isEmpty);
      });
    });
  });
}
