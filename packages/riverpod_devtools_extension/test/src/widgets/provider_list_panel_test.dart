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
      final gesture = await tester
          .startGesture(tester.getCenter(find.text('counterProvider')));
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

    testWidgets(
        'family header toggle collapses instances without '
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

  group('ProviderListPanel keyboard', () {
    Future<void> press(WidgetTester tester, LogicalKeyboardKey key) async {
      await tester.sendKeyEvent(key);
      await tester.pump();
    }

    testWidgets('arrow keys move the selection and clamp at the ends',
        (tester) async {
      await pumpPanel(tester, providers: [
        _provider('a'),
        _provider('b'),
        _provider('c'),
      ]);
      await tester.tap(find.text('a')); // gives the panel focus
      await tester.pump();

      await press(tester, LogicalKeyboardKey.arrowDown);
      expect(notifier.state.selectedProviderNames, {'b'});
      await press(tester, LogicalKeyboardKey.arrowDown);
      await press(tester, LogicalKeyboardKey.arrowDown);
      expect(notifier.state.selectedProviderNames, {'c'}, reason: 'clamped');
      await press(tester, LogicalKeyboardKey.arrowUp);
      expect(notifier.state.selectedProviderNames, {'b'});
    });

    testWidgets('Down from no selection picks the first, Up the last',
        (tester) async {
      await pumpPanel(tester, providers: [_provider('a'), _provider('b')]);
      await tester.tap(find.text('a'));
      await tester.pump();
      await tester.tap(find.text('a')); // deselect, focus stays
      await tester.pump();
      expect(notifier.state.selectedProviderNames, isEmpty);

      await press(tester, LogicalKeyboardKey.arrowDown);
      expect(notifier.state.selectedProviderNames, {'a'});

      notifier.clearSelection();
      await tester.pump();
      await press(tester, LogicalKeyboardKey.arrowUp);
      expect(notifier.state.selectedProviderNames, {'b'});
    });

    testWidgets('arrows skip family headers and collapsed instances',
        (tester) async {
      await pumpPanel(tester, providers: [
        _provider('first'),
        _provider('user(1)', family: 'user', argument: '1'),
        _provider('user(2)', family: 'user', argument: '2'),
        _provider('last'),
      ]);
      await tester.tap(find.text('first'));
      await tester.pump();

      await press(tester, LogicalKeyboardKey.arrowDown);
      expect(notifier.state.selectedProviderNames, {'user(1)'});
      await press(tester, LogicalKeyboardKey.arrowDown);
      await press(tester, LogicalKeyboardKey.arrowDown);
      expect(notifier.state.selectedProviderNames, {'last'});

      await tester.tap(find.text('user')); // collapse the family
      await tester.pump();
      await tester.tap(find.text('first'));
      await tester.pump();
      await press(tester, LogicalKeyboardKey.arrowDown);
      expect(notifier.state.selectedProviderNames, {'last'});
    });

    testWidgets('arrows work from inside the search field on filtered rows',
        (tester) async {
      await pumpPanel(tester, providers: [
        _provider('apple'),
        _provider('banana'),
        _provider('blueberry'),
      ]);
      await tester.enterText(find.byType(TextField), 'b');
      await tester.pump();

      await press(tester, LogicalKeyboardKey.arrowDown);
      expect(notifier.state.selectedProviderNames, {'banana'});
      await press(tester, LogicalKeyboardKey.arrowDown);
      expect(notifier.state.selectedProviderNames, {'blueberry'});
    });

    testWidgets('Esc clears the search first, then the selection',
        (tester) async {
      await pumpPanel(tester, providers: [_provider('apple')]);
      await tester.tap(find.text('apple'));
      await tester.pump();
      await tester.enterText(find.byType(TextField), 'app');
      await tester.pump();

      await press(tester, LogicalKeyboardKey.escape);
      expect(notifier.state.providerSearchQuery, isEmpty);
      expect(notifier.state.selectedProviderNames, {'apple'});

      await press(tester, LogicalKeyboardKey.escape);
      expect(notifier.state.selectedProviderNames, isEmpty);
    });

    testWidgets('"/" focuses the search field, and is typeable inside it',
        (tester) async {
      await pumpPanel(tester, providers: [_provider('a')]);
      await tester.tap(find.text('a'));
      await tester.pump();

      await press(tester, LogicalKeyboardKey.slash);
      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.focusNode!.hasFocus, isTrue);

      await tester.enterText(find.byType(TextField), 'a/b');
      await tester.pump();
      expect(notifier.state.providerSearchQuery, 'a/b');
    });

    testWidgets('a long list scrolls the keyboard-selected row into view',
        (tester) async {
      await pumpPanel(tester, providers: [
        for (var i = 0; i < 60; i++)
          _provider('p${i.toString().padLeft(2, '0')}'),
      ]);
      await tester.tap(find.text('p00'));
      await tester.pump();

      await press(tester, LogicalKeyboardKey.arrowUp); // clamp stays p00
      for (var i = 0; i < 40; i++) {
        await press(tester, LogicalKeyboardKey.arrowDown);
      }
      await tester.pumpAndSettle();

      expect(notifier.state.selectedProviderNames, {'p40'});
      expect(find.text('p40'), findsOneWidget, reason: 'built = on screen');
      final rect = tester.getRect(find.text('p40'));
      expect(rect.top, greaterThanOrEqualTo(0));
      expect(
          rect.bottom,
          lessThanOrEqualTo(
              tester.view.physicalSize.height / tester.view.devicePixelRatio));
    });
  });
}
