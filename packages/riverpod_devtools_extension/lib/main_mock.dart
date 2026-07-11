// Screenshot / development harness: runs the inspector UI with seeded mock
// data instead of a live vm_service connection, so the extension can be
// previewed (and screenshotted for PRs) with plain `flutter run -d chrome
// --target lib/main_mock.dart` or `flutter build web --target
// lib/main_mock.dart`.
//
// Query parameters:
//   ?theme=light|dark   (default dark, like DevTools)
//   ?select=<provider>  provider to pre-select in the detail panel
//   ?view=graph|stats   open the dependency graph or stats view
//   ?focus=<provider>   focus the graph on one provider's sub-graph
import 'package:flutter/material.dart';
import 'package:riverpod_devtools_extension/src/models/event_type.dart';
import 'package:riverpod_devtools_extension/src/models/provider_event.dart';
import 'package:riverpod_devtools_extension/src/models/provider_info.dart';
import 'package:riverpod_devtools_extension/src/providers/inspector_notifier.dart';
import 'package:riverpod_devtools_extension/src/widgets/event_log/event_log_panel.dart';
import 'package:riverpod_devtools_extension/src/widgets/inspector/inspector_view.dart';

void main() {
  runApp(const _MockApp());
}

class _MockApp extends StatefulWidget {
  const _MockApp();

  @override
  State<_MockApp> createState() => _MockAppState();
}

class _MockAppState extends State<_MockApp> {
  late final InspectorNotifier _notifier;

  /// When `?compare=open`, the value-diff pair to auto-open on first frame.
  (ProviderEvent, ProviderEvent)? _autoOpenDiff;

  @override
  void initState() {
    super.initState();
    _notifier = InspectorNotifier();
    _seed();
  }

  @override
  void dispose() {
    _notifier.dispose();
    super.dispose();
  }

  void _seed() {
    Map<String, dynamic> intValue(int v) => {'type': 'int', 'value': v};

    final now = DateTime.now();
    DateTime at(int secondsAgo) => now.subtract(Duration(seconds: secondsAgo));

    const error = {
      'type': 'HttpException',
      'message': 'Failed to fetch user profile: 401 Unauthorized',
      'stackTrace': '#0      UserRepository.fetchProfile '
          '(package:my_app/data/user_repository.dart:42:7)\n'
          '#1      userProfileProvider.<fn> '
          '(package:my_app/providers/user_providers.dart:18:31)\n'
          '#2      main (package:my_app/main.dart:12:3)',
    };

    // Two updates of a structured value, used to demo the event value diff
    // (#57): items 2->3, total changes, a coupon appears. Kept as locals so
    // `?compare` can pick this exact pair.
    final cartUpdateA = ProviderEvent(
      type: EventType.updated,
      providerId: '14',
      providerName: 'cartProvider',
      previousValue: const {'type': 'Cart', 'itemCount': 1, 'total': 19.0},
      value: const {
        'type': 'Cart',
        'itemCount': 2,
        'total': 42.5,
        'coupon': null,
      },
      timestamp: at(30),
      seq: 150,
    );
    final cartUpdateB = ProviderEvent(
      type: EventType.updated,
      providerId: '14',
      providerName: 'cartProvider',
      previousValue: const {
        'type': 'Cart',
        'itemCount': 2,
        'total': 42.5,
        'coupon': null,
      },
      value: const {
        'type': 'Cart',
        'itemCount': 3,
        'total': 63.0,
        'coupon': 'SAVE10',
      },
      timestamp: at(8),
      seq: 151,
    );

    final events = <ProviderEvent>[
      ProviderEvent(
        type: EventType.failed,
        providerId: '3',
        providerName: 'userProfileProvider',
        timestamp: at(2),
        seq: 9,
        error: error,
      ),
      ProviderEvent(
        type: EventType.updated,
        providerId: '2',
        providerName: 'doubledCounterProvider',
        previousValue: intValue(4),
        value: intValue(6),
        timestamp: at(5),
        seq: 8,
        triggeredBy: const [TriggerRef(provider: 'counterProvider', seq: 7)],
      ),
      ProviderEvent(
        type: EventType.updated,
        providerId: '1',
        providerName: 'counterProvider',
        previousValue: intValue(2),
        value: intValue(3),
        timestamp: at(5),
        seq: 7,
      ),
      ProviderEvent(
        type: EventType.updated,
        providerId: '2',
        providerName: 'doubledCounterProvider',
        previousValue: intValue(2),
        value: intValue(4),
        timestamp: at(21),
        seq: 6,
        triggeredBy: const [TriggerRef(provider: 'counterProvider', seq: 5)],
      ),
      ProviderEvent(
        type: EventType.updated,
        providerId: '1',
        providerName: 'counterProvider',
        previousValue: intValue(1),
        value: intValue(2),
        timestamp: at(21),
        seq: 5,
      ),
      ProviderEvent(
        type: EventType.disposed,
        providerId: '5',
        providerName: 'cartItemsProvider',
        timestamp: at(40),
        seq: 4,
      ),
      ProviderEvent(
        type: EventType.added,
        providerId: '3',
        providerName: 'userProfileProvider',
        value: {'type': 'AsyncLoading<UserProfile>', 'asyncState': 'loading'},
        // Close to the provider_failed event's at(2) below, so the
        // loading->failed pairing in the Stats tab shows a plausible ~1s
        // duration instead of the full time since the provider was added.
        timestamp: at(3),
        seq: 3,
      ),
      ProviderEvent(
        type: EventType.added,
        providerId: '2',
        providerName: 'doubledCounterProvider',
        value: intValue(2),
        timestamp: at(63),
        seq: 2,
      ),
      ProviderEvent(
        type: EventType.added,
        providerId: '1',
        providerName: 'counterProvider',
        value: intValue(1),
        timestamp: at(63),
        seq: 1,
      ),

      // --- Stats-tab scenarios (#56) ---
      // A provider updating well past the high-frequency threshold
      // (>10/sec sustained over the last 10s, i.e. >100 updates in 10s).
      for (var i = 0; i < 120; i++)
        ProviderEvent(
          type: EventType.updated,
          providerId: '8',
          providerName: 'searchResultsProvider',
          previousValue: intValue(i),
          value: intValue(i + 1),
          timestamp: now.subtract(Duration(milliseconds: i * 80)),
          seq: 1000 + i,
        ),
      // A slow async load (loading -> data over the 2s threshold).
      ProviderEvent(
        type: EventType.updated,
        providerId: '9',
        providerName: 'weatherProvider',
        previousValue: {
          'type': 'AsyncLoading<Weather>',
          'asyncState': 'loading'
        },
        value: {
          'type': 'AsyncData<Weather>',
          'asyncState': 'data',
          'string': 'Weather(sunny)'
        },
        timestamp: at(50),
        seq: 120,
      ),
      ProviderEvent(
        type: EventType.added,
        providerId: '9',
        providerName: 'weatherProvider',
        value: {'type': 'AsyncLoading<Weather>', 'asyncState': 'loading'},
        timestamp: at(54),
        seq: 119,
      ),
      // A provider disposed and re-created twice (churn).
      ProviderEvent(
        type: EventType.added,
        providerId: '10c',
        providerName: 'sessionProvider',
        value: const {'type': 'String', 'value': 'session-3'},
        timestamp: at(10),
        seq: 133,
      ),
      ProviderEvent(
        type: EventType.disposed,
        providerId: '10b',
        providerName: 'sessionProvider',
        timestamp: at(15),
        seq: 132,
      ),
      ProviderEvent(
        type: EventType.added,
        providerId: '10b',
        providerName: 'sessionProvider',
        value: const {'type': 'String', 'value': 'session-2'},
        timestamp: at(30),
        seq: 131,
      ),
      ProviderEvent(
        type: EventType.disposed,
        providerId: '10a',
        providerName: 'sessionProvider',
        timestamp: at(35),
        seq: 130,
      ),
      ProviderEvent(
        type: EventType.added,
        providerId: '10a',
        providerName: 'sessionProvider',
        value: const {'type': 'String', 'value': 'session-1'},
        timestamp: at(50),
        seq: 129,
      ),

      // --- Family instances (#57): one `.family` provider read with three
      // different arguments, so the provider list groups them under a
      // collapsible `userProvider` header.
      ProviderEvent(
        type: EventType.added,
        providerId: '11',
        providerName: 'userProvider(1)',
        value: const {'type': 'User', 'string': 'User(id: 1, Alice)'},
        timestamp: at(60),
        seq: 140,
      ),
      ProviderEvent(
        type: EventType.added,
        providerId: '12',
        providerName: 'userProvider(2)',
        value: const {'type': 'User', 'string': 'User(id: 2, Bob)'},
        timestamp: at(58),
        seq: 141,
      ),
      ProviderEvent(
        type: EventType.added,
        providerId: '13',
        providerName: 'userProvider(7)',
        value: const {'type': 'User', 'string': 'User(id: 7, Carol)'},
        timestamp: at(12),
        seq: 142,
      ),

      // Event value diff (#57) demo pair, plus the provider's birth event.
      cartUpdateB,
      cartUpdateA,
      ProviderEvent(
        type: EventType.added,
        providerId: '14',
        providerName: 'cartProvider',
        value: const {'type': 'Cart', 'itemCount': 1, 'total': 19.0},
        timestamp: at(70),
        seq: 149,
      ),
    ];

    DependencyDetail dep(String name, String type) => DependencyDetail(
          providerName: name,
          type: type,
          file: 'lib/providers.dart',
          line: 1,
        );

    final providers = <String, ProviderInfo>{
      'counterProvider': ProviderInfo(
        id: '1',
        name: 'counterProvider',
        value: intValue(3),
        status: ProviderStatus.active,
        dependenciesSource: DependencySource.static,
        dependenciesLoadedAt: at(63),
      ),
      'doubledCounterProvider': ProviderInfo(
        id: '2',
        name: 'doubledCounterProvider',
        value: intValue(6),
        status: ProviderStatus.active,
        dependencies: const ['counterProvider'],
        dependenciesSource: DependencySource.static,
        dependenciesLoadedAt: at(63),
        dependencyDetails: [dep('counterProvider', 'watch')],
      ),
      'userProfileProvider': ProviderInfo(
        id: '3',
        name: 'userProfileProvider',
        value: {
          'type': 'AsyncError<UserProfile>',
          'asyncState': 'error',
          'string': 'AsyncError(HttpException: Failed to fetch user profile)',
        },
        status: ProviderStatus.active,
        dependencies: const ['apiClientProvider', 'authTokenProvider'],
        dependenciesSource: DependencySource.static,
        dependenciesLoadedAt: at(63),
        lastError: error,
        dependencyDetails: [
          dep('apiClientProvider', 'watch'),
          dep('authTokenProvider', 'read'),
        ],
      ),
      'authTokenProvider': ProviderInfo(
        id: '4',
        name: 'authTokenProvider',
        value: const {'type': 'String', 'value': 'eyJhbGciOiJIUzI1NiJ9…'},
        status: ProviderStatus.active,
        dependenciesSource: DependencySource.static,
        dependenciesLoadedAt: at(63),
      ),
      'apiClientProvider': ProviderInfo(
        id: '6',
        name: 'apiClientProvider',
        value: const {'type': 'ApiClient', 'string': 'ApiClient(baseUrl: …)'},
        status: ProviderStatus.active,
        dependencies: const ['authTokenProvider'],
        dependenciesSource: DependencySource.static,
        dependenciesLoadedAt: at(63),
        dependencyDetails: [dep('authTokenProvider', 'watch')],
      ),
      'cartItemsProvider': ProviderInfo(
        id: '5',
        name: 'cartItemsProvider',
        value: const {'type': 'List<CartItem>', 'string': '[2 items]'},
        status: ProviderStatus.disposed,
        dependencies: const ['apiClientProvider'],
        dependenciesSource: DependencySource.static,
        dependenciesLoadedAt: at(63),
        dependencyDetails: [dep('apiClientProvider', 'watch')],
      ),
      'cartTotalProvider': ProviderInfo(
        id: '7',
        name: 'cartTotalProvider',
        value: const {'type': 'double', 'value': 42.5},
        status: ProviderStatus.active,
        dependencies: const ['cartItemsProvider', 'counterProvider'],
        dependenciesSource: DependencySource.static,
        dependenciesLoadedAt: at(63),
        dependencyDetails: [
          dep('cartItemsProvider', 'watch'),
          dep('counterProvider', 'listen'),
        ],
      ),
      'searchResultsProvider': ProviderInfo(
        id: '8',
        name: 'searchResultsProvider',
        value: intValue(120),
        status: ProviderStatus.active,
        dependenciesSource: DependencySource.static,
        dependenciesLoadedAt: at(63),
      ),
      'weatherProvider': ProviderInfo(
        id: '9',
        name: 'weatherProvider',
        value: const {
          'type': 'AsyncData<Weather>',
          'asyncState': 'data',
          'string': 'Weather(sunny)',
        },
        status: ProviderStatus.active,
        dependenciesSource: DependencySource.static,
        dependenciesLoadedAt: at(63),
      ),
      'sessionProvider': ProviderInfo(
        id: '10c',
        name: 'sessionProvider',
        value: const {'type': 'String', 'value': 'session-3'},
        status: ProviderStatus.active,
        dependenciesSource: DependencySource.static,
        dependenciesLoadedAt: at(63),
      ),
      'userProvider(1)': ProviderInfo(
        id: '11',
        name: 'userProvider(1)',
        value: const {'type': 'User', 'string': 'User(id: 1, Alice)'},
        status: ProviderStatus.active,
        family: 'userProvider',
        argument: '1',
        dependenciesSource: DependencySource.static,
        dependenciesLoadedAt: at(63),
      ),
      'userProvider(2)': ProviderInfo(
        id: '12',
        name: 'userProvider(2)',
        value: const {'type': 'User', 'string': 'User(id: 2, Bob)'},
        status: ProviderStatus.active,
        family: 'userProvider',
        argument: '2',
        dependenciesSource: DependencySource.static,
        dependenciesLoadedAt: at(63),
      ),
      'userProvider(7)': ProviderInfo(
        id: '13',
        name: 'userProvider(7)',
        value: const {'type': 'User', 'string': 'User(id: 7, Carol)'},
        status: ProviderStatus.active,
        family: 'userProvider',
        argument: '7',
        dependenciesSource: DependencySource.static,
        dependenciesLoadedAt: at(63),
      ),
      'cartProvider': ProviderInfo(
        id: '14',
        name: 'cartProvider',
        value: const {
          'type': 'Cart',
          'itemCount': 3,
          'total': 63.0,
          'coupon': 'SAVE10',
        },
        status: ProviderStatus.active,
        dependenciesSource: DependencySource.static,
        dependenciesLoadedAt: at(63),
      ),
    };

    // The mock harness is the one legitimate non-test consumer.
    // ignore: invalid_use_of_visible_for_testing_member
    _notifier.debugSeed(providers: providers, events: events);

    final select = Uri.base.queryParameters['select'];
    if (select != null && providers.containsKey(select)) {
      _notifier.selectProvider(select);
    }
    switch (Uri.base.queryParameters['view']) {
      case 'graph':
        _notifier.setViewMode(InspectorViewMode.graph);
      case 'stats':
        _notifier.setViewMode(InspectorViewMode.stats);
    }
    final focus = Uri.base.queryParameters['focus'];
    if (focus != null && providers.containsKey(focus)) {
      _notifier.setGraphFocus(focus);
    }

    // `?compare` selects cartProvider and picks its two updates for the
    // value diff; `?compare=open` also opens the diff dialog on first frame.
    final compare = Uri.base.queryParameters['compare'];
    if (compare != null) {
      _notifier.selectProvider('cartProvider');
      _notifier.toggleEventComparison(cartUpdateA.id);
      _notifier.toggleEventComparison(cartUpdateB.id);
      if (compare == 'open') {
        _autoOpenDiff = (cartUpdateA, cartUpdateB);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isLight = Uri.base.queryParameters['theme'] == 'light';
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: const Color(0xFF2196F3),
        brightness: isLight ? Brightness.light : Brightness.dark,
        // The bundled DevTools font — the plain web build ships no default
        // "Roboto", so text would render blank (especially headless).
        fontFamily: 'packages/devtools_app_shared/Roboto',
      ),
      home: Scaffold(
        body: Builder(
          builder: (context) {
            final pair = _autoOpenDiff;
            if (pair != null) {
              _autoOpenDiff = null;
              WidgetsBinding.instance.addPostFrameCallback((_) {
                showEventValueDiffDialog(context, pair.$1, pair.$2);
              });
            }
            return InspectorView(notifier: _notifier);
          },
        ),
      ),
    );
  }
}
