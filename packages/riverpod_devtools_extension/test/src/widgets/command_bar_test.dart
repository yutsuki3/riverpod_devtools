import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riverpod_devtools_extension/src/models/provider_info.dart';
import 'package:riverpod_devtools_extension/src/providers/inspector_notifier.dart';
import 'package:riverpod_devtools_extension/src/widgets/detail_panel/detail_panel.dart';

ProviderInfo _provider(String name, {ProviderStatus? status}) => ProviderInfo(
      id: name.hashCode.toString(),
      name: name,
      value: const {'type': 'int', 'value': 1},
      status: status ?? ProviderStatus.active,
    );

void main() {
  late InspectorNotifier notifier;

  setUp(() {
    notifier = InspectorNotifier();
  });

  tearDown(() {
    notifier.dispose();
    DetailPanel.debugCommandSender = null;
  });

  Future<void> pump(WidgetTester tester,
      {List<ProviderInfo>? providers, String? select}) async {
    notifier.debugSeed(
      providers: {
        for (final p in providers ?? [_provider('counterProvider')]) p.name: p,
      },
      events: const [],
    );
    if (select != null) notifier.selectOnly(select);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 360,
            child: DetailPanel(notifier: notifier),
          ),
        ),
      ),
    );
  }

  group('Invalidate/Refresh command bar', () {
    testWidgets('a successful invalidate shows a short confirmation',
        (tester) async {
      DetailPanel.debugCommandSender =
          (action, provider) async => (ok: true, message: null);
      await pump(tester, select: 'counterProvider');

      await tester.tap(find.text('Invalidate'));
      await tester.pump(); // start _send
      await tester.pump(); // resolve future + feedback

      expect(find.text('Invalidated'), findsOneWidget);
    });

    testWidgets(
        'a long error message is shown in full (up to two lines), not '
        'clipped to a sliver', (tester) async {
      const longError =
          'Provider "counterProvider" is not alive (unknown name or '
          'already disposed).';
      DetailPanel.debugCommandSender =
          (action, provider) async => (ok: false, message: longError);
      await pump(tester, select: 'counterProvider');

      await tester.tap(find.text('Refresh'));
      await tester.pump();
      await tester.pump();

      final text = tester.widget<Text>(find.text(longError));
      expect(text.maxLines, 2, reason: 'error should get two lines to breathe');
      // The full message is still available on hover.
      expect(find.byType(Tooltip), findsWidgets);
      expect(find.text(longError), findsOneWidget);
    });

    testWidgets(
        'two rapid clicks in the same frame send only one command '
        '(re-entrancy guard, before the disabled state has rebuilt)',
        (tester) async {
      var calls = 0;
      final gate = Completer<CommandResult>();
      DetailPanel.debugCommandSender = (action, provider) {
        calls++;
        return gate.future;
      };
      await pump(tester, select: 'counterProvider');

      // No pump between the taps: the second lands before the first's
      // setState has rebuilt the buttons into their disabled state, so only
      // the in-flight `_busy` guard can stop the double send.
      await tester.tap(find.text('Invalidate'));
      await tester.tap(find.text('Invalidate'), warnIfMissed: false);
      await tester.pump();

      expect(calls, 1, reason: 'the in-flight command must block a second');

      gate.complete((ok: true, message: null));
      await tester.pump();
      await tester.pump();
      expect(find.text('Invalidated'), findsOneWidget);
    });

    testWidgets('the buttons re-enable after the command completes',
        (tester) async {
      var calls = 0;
      DetailPanel.debugCommandSender = (action, provider) async {
        calls++;
        return (ok: true, message: null);
      };
      await pump(tester, select: 'counterProvider');

      await tester.tap(find.text('Invalidate'));
      await tester.pump();
      await tester.pump();
      // A deliberate second action after completion is allowed.
      await tester.tap(find.text('Refresh'));
      await tester.pump();
      await tester.pump();

      expect(calls, 2);
      expect(find.text('Refreshed'), findsOneWidget);
    });

    testWidgets('switching to another provider clears the stale result label',
        (tester) async {
      DetailPanel.debugCommandSender =
          (action, provider) async => (ok: false, message: 'boom failure');
      await pump(
        tester,
        providers: [_provider('counterProvider'), _provider('userProvider')],
        select: 'counterProvider',
      );

      await tester.tap(find.text('Invalidate'));
      await tester.pump();
      await tester.pump();
      expect(find.text('boom failure'), findsOneWidget);

      // Select a different provider: the previous provider's error must go.
      notifier.selectOnly('userProvider');
      await tester.pump();

      expect(find.text('boom failure'), findsNothing);
    });

    testWidgets('the command bar is disabled for a disposed provider',
        (tester) async {
      var calls = 0;
      DetailPanel.debugCommandSender = (action, provider) async {
        calls++;
        return (ok: true, message: null);
      };
      await pump(
        tester,
        providers: [_provider('goneProvider', status: ProviderStatus.disposed)],
        select: 'goneProvider',
      );

      await tester.tap(find.text('Invalidate'), warnIfMissed: false);
      await tester.pump();

      expect(calls, 0, reason: 'disposed providers cannot be invalidated');
    });
  });
}
