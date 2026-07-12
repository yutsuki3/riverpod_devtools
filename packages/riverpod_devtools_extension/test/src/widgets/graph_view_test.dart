import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riverpod_devtools_extension/src/models/provider_info.dart';
import 'package:riverpod_devtools_extension/src/providers/inspector_notifier.dart';
import 'package:riverpod_devtools_extension/src/widgets/graph/graph_view.dart';

ProviderInfo _provider(String name, {List<String> dependencies = const []}) =>
    ProviderInfo(
      id: name.hashCode.toString(),
      name: name,
      value: const {'type': 'int', 'value': 1},
      status: ProviderStatus.active,
      dependencies: dependencies,
      dependenciesSource: DependencySource.static,
    );

void main() {
  late InspectorNotifier notifier;

  setUp(() {
    notifier = InspectorNotifier();
    notifier.debugSeed(
      providers: {
        'aProvider': _provider('aProvider', dependencies: ['bProvider']),
        'bProvider': _provider('bProvider'),
      },
      events: const [],
    );
  });

  tearDown(() => notifier.dispose());

  Future<void> pumpGraph(WidgetTester tester) => tester.pumpWidget(
        MaterialApp(home: Scaffold(body: GraphView(notifier: notifier))),
      );

  /// The toolbar is the nearest container holding the 'Dependency Graph'
  /// title (ancestors are reported innermost-first).
  double toolbarHeight(WidgetTester tester) => tester
      .getSize(
        find
            .ancestor(
              of: find.text('Dependency Graph'),
              matching: find.byType(Container),
            )
            .first,
      )
      .height;

  testWidgets(
      'toolbar height does not change when the Show all button appears '
      '(regression: focusing a node used to grow the toolbar and shift '
      'the canvas)', (tester) async {
    await pumpGraph(tester);

    expect(find.text('Show all'), findsNothing);
    final heightWithoutButton = toolbarHeight(tester);

    notifier.selectAndFocusInGraph('aProvider');
    await tester.pump();

    expect(find.text('Show all'), findsOneWidget);
    expect(toolbarHeight(tester), heightWithoutButton);
  });

  testWidgets(
      'Show all sits flush right in the toolbar at any width '
      '(regression: a Flexible title next to a Spacer used to leave a '
      'dead gap after the button)', (tester) async {
    tester.view.physicalSize = const Size(3000, 1900);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);
    await pumpGraph(tester);

    notifier.selectAndFocusInGraph('aProvider');
    await tester.pump();

    final toolbar = find
        .ancestor(
          of: find.text('Dependency Graph'),
          matching: find.byType(Container),
        )
        .first;
    final gap = tester.getRect(toolbar).right -
        tester.getRect(find.text('Show all')).right;
    // Toolbar padding (10) + button inner padding (8) + rounding.
    expect(gap, lessThan(25),
        reason: 'Show all must hug the toolbar right edge (gap: $gap)');
  });

  testWidgets('Show all exits focus and clears the selection',
      (tester) async {
    await pumpGraph(tester);

    notifier.selectAndFocusInGraph('aProvider');
    await tester.pump();
    expect(notifier.state.graphFocusProvider, 'aProvider');

    await tester.tap(find.text('Show all'));
    await tester.pump();

    expect(notifier.state.graphFocusProvider, isNull);
    expect(notifier.state.selectedProviderNames, isEmpty);
    expect(find.text('Show all'), findsNothing);
  });

  testWidgets(
      'clicking a node selects it, clicking the same node again deselects '
      '(consistency with the provider list)', (tester) async {
    await pumpGraph(tester);

    // Node positions are fixed regardless of focus, so the same on-screen
    // point addresses the node before and after selection (the detail
    // panel also renders the name once selected, so tap by coordinate).
    final nodeCenter = tester.getCenter(find.text('aProvider'));

    await tester.tapAt(nodeCenter);
    await tester.pump();
    expect(notifier.state.selectedProviderNames, {'aProvider'});
    expect(notifier.state.graphFocusProvider, 'aProvider');

    await tester.tapAt(nodeCenter);
    await tester.pump();
    expect(notifier.state.selectedProviderNames, isEmpty);
    expect(notifier.state.graphFocusProvider, isNull);
  });

  testWidgets(
      'clicking a different node switches selection instead of deselecting',
      (tester) async {
    await pumpGraph(tester);

    // Capture the node's on-screen point before selecting anything — once
    // aProvider is focused its detail panel also lists bProvider (a
    // dependency), so the text is no longer unique. Node positions are
    // fixed, so the coordinate stays valid.
    final bNodeCenter = tester.getCenter(find.text('bProvider'));

    notifier.selectAndFocusInGraph('aProvider');
    await tester.pump();

    await tester.tapAt(bNodeCenter);
    await tester.pump();

    expect(notifier.state.selectedProviderNames, {'bProvider'});
    expect(notifier.state.graphFocusProvider, 'bProvider');
  });

  group('toggleFocusInGraph', () {
    test('selects when nothing is focused', () {
      notifier.toggleFocusInGraph('aProvider');
      expect(notifier.state.graphFocusProvider, 'aProvider');
      expect(notifier.state.selectedProviderNames, {'aProvider'});
    });

    test('deselects when the same node is already focused', () {
      notifier.toggleFocusInGraph('aProvider');
      notifier.toggleFocusInGraph('aProvider');
      expect(notifier.state.graphFocusProvider, isNull);
      expect(notifier.state.selectedProviderNames, isEmpty);
    });

    test('switches focus when a different node is clicked', () {
      notifier.toggleFocusInGraph('aProvider');
      notifier.toggleFocusInGraph('bProvider');
      expect(notifier.state.graphFocusProvider, 'bProvider');
      expect(notifier.state.selectedProviderNames, {'bProvider'});
    });
  });
}
