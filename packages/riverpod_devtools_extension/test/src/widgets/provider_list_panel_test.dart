import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riverpod_devtools_extension/src/models/provider_info.dart';
import 'package:riverpod_devtools_extension/src/providers/inspector_notifier.dart';
import 'package:riverpod_devtools_extension/src/widgets/provider_list/provider_list_panel.dart';

ProviderInfo _provider(String name, {String? family, String? argument}) =>
    ProviderInfo(
      id: name.hashCode.toString(),
      name: name,
      value: const {'type': 'int', 'value': 1},
      status: ProviderStatus.active,
      family: family,
      argument: argument,
    );

void main() {
  late InspectorNotifier notifier;
  late ScrollController scrollController;

  setUp(() {
    notifier = InspectorNotifier();
    scrollController = ScrollController();
  });

  tearDown(() {
    notifier.dispose();
    scrollController.dispose();
  });

  Future<void> pumpPanel(WidgetTester tester,
      {List<ProviderInfo>? providers}) async {
    notifier.debugSeed(
      providers: {
        for (final p in providers ??
            [_provider('counterProvider'), _provider('userProvider')])
          p.name: p,
      },
      events: const [],
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ProviderListPanel(
            notifier: notifier,
            scrollController: scrollController,
          ),
        ),
      ),
    );
  }

  group('ProviderListPanel selection', () {
    testWidgets('tapping a tile selects the provider', (tester) async {
      await pumpPanel(tester);

      await tester.tap(find.text('counterProvider'));
      await tester.pump();

      expect(notifier.state.selectedProviderNames, {'counterProvider'});
      expect(notifier.state.activeTabProviderName, 'counterProvider');
    });

    testWidgets(
        'selection survives a rebuild between pointer down and up '
        '(regression: parent deselect-all used to win the gesture arena)',
        (tester) async {
      await pumpPanel(tester);

      // Press, let the UI rebuild while the pointer is still down (as
      // happens with any non-instant click, or when a provider event
      // triggers a rebuild mid-click), then release.
      final gesture =
          await tester.startGesture(tester.getCenter(find.text('counterProvider')));
      await tester.pump(const Duration(milliseconds: 300));
      await gesture.up();
      await tester.pump();

      expect(notifier.state.selectedProviderNames, {'counterProvider'});
    });

    testWidgets('tapping the selected provider again deselects it',
        (tester) async {
      await pumpPanel(tester);

      await tester.tap(find.text('counterProvider'));
      await tester.pump();
      await tester.tap(find.text('counterProvider'));
      await tester.pump();

      expect(notifier.state.selectedProviderNames, isEmpty);
      expect(notifier.state.activeTabProviderName, isNull);
    });

    testWidgets('plain click on another provider replaces the selection',
        (tester) async {
      await pumpPanel(tester);

      await tester.tap(find.text('counterProvider'));
      await tester.pump();
      await tester.tap(find.text('userProvider'));
      await tester.pump();

      expect(notifier.state.selectedProviderNames, {'userProvider'});
      expect(notifier.state.activeTabProviderName, 'userProvider');
    });

    testWidgets('Ctrl+click adds to and removes from the selection',
        (tester) async {
      await pumpPanel(tester);

      await tester.tap(find.text('counterProvider'));
      await tester.pump();

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.tap(find.text('userProvider'));
      await tester.pump();
      expect(notifier.state.selectedProviderNames,
          {'counterProvider', 'userProvider'});

      await tester.tap(find.text('userProvider'));
      await tester.pump();
      expect(notifier.state.selectedProviderNames, {'counterProvider'});
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    });

    testWidgets('tapping empty area below the list clears the selection',
        (tester) async {
      await pumpPanel(tester);

      await tester.tap(find.text('counterProvider'));
      await tester.pump();
      expect(notifier.state.selectedProviderNames, isNotEmpty);

      // The list has two short rows; tap well below them, inside the
      // opaque deselect area.
      final listBottomCenter = tester.getBottomLeft(
            find.byType(ListView),
          ) +
          const Offset(100, -20);
      await tester.tapAt(listBottomCenter);
      await tester.pump();

      expect(notifier.state.selectedProviderNames, isEmpty);
    });

    testWidgets('Clear header button clears a multi-selection in one step',
        (tester) async {
      await pumpPanel(tester);

      await tester.tap(find.text('counterProvider'));
      await tester.pump();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.tap(find.text('userProvider'));
      await tester.pump();
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);

      var notifications = 0;
      notifier.addListener(() => notifications++);
      await tester.tap(find.text('Clear'));
      await tester.pump();

      expect(notifier.state.selectedProviderNames, isEmpty);
      expect(notifications, 1,
          reason: 'clearing must be one atomic state change');
    });

    testWidgets('family header toggle collapses instances without '
        'changing the selection', (tester) async {
      await pumpPanel(tester, providers: [
        _provider('plainProvider'),
        _provider('userProvider(1)', family: 'userProvider', argument: '1'),
        _provider('userProvider(2)', family: 'userProvider', argument: '2'),
      ]);

      await tester.tap(find.text('plainProvider'));
      await tester.pump();

      // Instances are visible under the header, labeled by argument.
      expect(find.text('(1)'), findsOneWidget);

      await tester.tap(find.text('userProvider'));
      await tester.pump();

      expect(find.text('(1)'), findsNothing,
          reason: 'header tap collapses the family');
      expect(notifier.state.selectedProviderNames, {'plainProvider'},
          reason: 'header tap must not touch the selection');
    });
  });
}
