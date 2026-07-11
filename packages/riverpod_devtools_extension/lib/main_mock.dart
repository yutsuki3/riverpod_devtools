// Screenshot / development harness: runs the inspector UI with seeded mock
// data instead of a live vm_service connection, so the extension can be
// previewed (and screenshotted for PRs) with plain `flutter run -d chrome
// --target lib/main_mock.dart` or `flutter build web --target
// lib/main_mock.dart`.
//
// Query parameters:
//   ?theme=light|dark   (default dark, like DevTools)
//   ?select=<provider>  provider to pre-select in the detail panel
//   ?view=graph         open the dependency graph view
//   ?focus=<provider>   focus the graph on one provider's sub-graph
import 'package:flutter/material.dart';
import 'package:riverpod_devtools_extension/src/models/event_type.dart';
import 'package:riverpod_devtools_extension/src/models/provider_event.dart';
import 'package:riverpod_devtools_extension/src/models/provider_info.dart';
import 'package:riverpod_devtools_extension/src/providers/inspector_notifier.dart';
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
        timestamp: at(62),
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
    };

    // The mock harness is the one legitimate non-test consumer.
    // ignore: invalid_use_of_visible_for_testing_member
    _notifier.debugSeed(providers: providers, events: events);

    final select = Uri.base.queryParameters['select'];
    if (select != null && providers.containsKey(select)) {
      _notifier.selectProvider(select);
    }
    if (Uri.base.queryParameters['view'] == 'graph') {
      _notifier.setViewMode(InspectorViewMode.graph);
    }
    final focus = Uri.base.queryParameters['focus'];
    if (focus != null && providers.containsKey(focus)) {
      _notifier.setGraphFocus(focus);
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
        body: InspectorView(notifier: _notifier),
      ),
    );
  }
}
