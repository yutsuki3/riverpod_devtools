import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
        // A standalone node unrelated to a/b, so multi-select of a and c
        // widens the focused set in a way a single selection can't.
        'cProvider': _provider('cProvider'),
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

    notifier.selectOnly('aProvider');
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

    notifier.selectOnly('aProvider');
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

  testWidgets('Show all clears the selection', (tester) async {
    await pumpGraph(tester);

    notifier.selectOnly('aProvider');
    await tester.pump();
    expect(notifier.state.selectedProviderNames, {'aProvider'});

    await tester.tap(find.text('Show all'));
    await tester.pump();

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
    expect(notifier.state.activeTabProviderName, 'aProvider');

    await tester.tapAt(nodeCenter);
    await tester.pump();
    expect(notifier.state.selectedProviderNames, isEmpty);
    expect(notifier.state.activeTabProviderName, isNull);
  });

  testWidgets(
      'plain-clicking a different node switches selection instead of adding',
      (tester) async {
    await pumpGraph(tester);

    // Capture node points before selecting anything — once a node is
    // selected the detail panel also renders related names, so text is no
    // longer unique. Node positions are fixed, so coordinates stay valid.
    final bNodeCenter = tester.getCenter(find.text('bProvider'));

    notifier.selectOnly('aProvider');
    await tester.pump();

    await tester.tapAt(bNodeCenter);
    await tester.pump();

    expect(notifier.state.selectedProviderNames, {'bProvider'});
    expect(notifier.state.activeTabProviderName, 'bProvider');
  });

  testWidgets(
      'Ctrl+click adds a node to the selection (multi-select, matching '
      'the provider list)', (tester) async {
    await pumpGraph(tester);

    final cNodeCenter = tester.getCenter(find.text('cProvider'));

    notifier.selectOnly('aProvider');
    await tester.pump();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.tapAt(cNodeCenter);
    await tester.pump();
    expect(notifier.state.selectedProviderNames, {'aProvider', 'cProvider'});

    // Ctrl+clicking it again removes it.
    await tester.tapAt(cNodeCenter);
    await tester.pump();
    expect(notifier.state.selectedProviderNames, {'aProvider'});
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  });

  testWidgets('empty-canvas tap clears the whole selection', (tester) async {
    tester.view.physicalSize = const Size(2400, 1600);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);
    await pumpGraph(tester);

    notifier.selectProvider('aProvider');
    notifier.selectProvider('cProvider');
    await tester.pump();
    expect(notifier.state.selectedProviderNames, hasLength(2));

    // Tap inside the canvas but away from any node: the nodes are laid out
    // from the top-left, so a point low on the left is empty canvas (the
    // legend sits bottom-right, so stay left of it).
    final canvas = tester.getRect(find.byType(InteractiveViewer));
    await tester.tapAt(Offset(canvas.left + 40, canvas.bottom - 40));
    await tester.pump();

    expect(notifier.state.selectedProviderNames, isEmpty);
  });

  testWidgets(
      'the legend is anchored bottom-right so it does not overlap the '
      'left-anchored nodes', (tester) async {
    tester.view.physicalSize = const Size(2400, 1600);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);
    await pumpGraph(tester);

    // The legend contains this gesture hint line.
    final legend = find.textContaining('Ctrl/Cmd+Click: multi-select');
    expect(legend, findsOneWidget);

    final legendRect = tester.getRect(legend);
    final graphRect = tester.getRect(find.byType(GraphView));
    // Right-anchored: the legend's right edge is near the graph's right
    // edge, not the left.
    expect(graphRect.right - legendRect.right, lessThan(graphRect.width / 2),
        reason: 'legend should sit on the right half of the canvas');
  });
}
