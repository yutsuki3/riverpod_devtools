import 'dart:async';
import 'package:devtools_extensions/devtools_extensions.dart';
import 'package:flutter/foundation.dart';
import 'package:vm_service/vm_service.dart';
import '../models/event_type.dart';
import '../models/provider_event.dart';
import '../models/provider_info.dart';

class _Unset {
  const _Unset();
}

class InspectorState {
  final Map<String, ProviderInfo> providers;
  final List<ProviderEvent> events;
  final Set<String> selectedProviderNames;
  final String? activeTabProviderName;
  final String providerSearchQuery;
  final Set<String> expandedEventIds;
  final String? flashingProviderName;
  final double leftSplitRatio;
  final double rightSplitRatio;

  InspectorState({
    this.providers = const {},
    this.events = const [],
    this.selectedProviderNames = const {},
    this.activeTabProviderName,
    this.providerSearchQuery = '',
    this.expandedEventIds = const {},
    this.flashingProviderName,
    this.leftSplitRatio = 0.2,
    this.rightSplitRatio = 0.375,
  });

  InspectorState copyWith({
    Map<String, ProviderInfo>? providers,
    List<ProviderEvent>? events,
    Set<String>? selectedProviderNames,
    Object? activeTabProviderName = const _Unset(),
    String? providerSearchQuery,
    Set<String>? expandedEventIds,
    Object? flashingProviderName = const _Unset(),
    double? leftSplitRatio,
    double? rightSplitRatio,
  }) {
    return InspectorState(
      providers: providers ?? this.providers,
      events: events ?? this.events,
      selectedProviderNames:
          selectedProviderNames ?? this.selectedProviderNames,
      activeTabProviderName: activeTabProviderName is _Unset
          ? this.activeTabProviderName
          : activeTabProviderName as String?,
      providerSearchQuery: providerSearchQuery ?? this.providerSearchQuery,
      expandedEventIds: expandedEventIds ?? this.expandedEventIds,
      flashingProviderName: flashingProviderName is _Unset
          ? this.flashingProviderName
          : flashingProviderName as String?,
      leftSplitRatio: leftSplitRatio ?? this.leftSplitRatio,
      rightSplitRatio: rightSplitRatio ?? this.rightSplitRatio,
    );
  }
}

class InspectorNotifier extends ChangeNotifier {
  InspectorState _state = InspectorState();

  InspectorState get state => _state;

  // Memoized derived lists. Panels read [filteredProviders]/[filteredEvents]
  // on every rebuild (which happens on every provider event), so recomputing
  // the filter + merge/sort each time is wasted work. All state mutations go
  // through [_setState], which invalidates exactly the caches whose inputs
  // changed — e.g. flash-animation ticks touch neither cache.
  List<ProviderInfo>? _filteredProvidersCache;
  List<ProviderEvent>? _filteredEventsCache;

  void _setState(InspectorState newState) {
    final old = _state;
    _state = newState;
    if (!identical(old.providers, newState.providers) ||
        old.providerSearchQuery != newState.providerSearchQuery) {
      _filteredProvidersCache = null;
    }
    if (!identical(old.events, newState.events) ||
        !identical(
            old.selectedProviderNames, newState.selectedProviderNames)) {
      _filteredEventsCache = null;
    }
  }

  static const int _maxEventCount = 1000;
  static const int _maxDisposedProviders = 100;

  final Map<String, DateTime> _disposedProviderTimestamps = {};
  final Map<String, List<ProviderEvent>> _eventsByProvider = {};
  final Set<String> _processedEventKeys = {};
  StreamSubscription? _extensionSubscription;
  Timer? _flashTimer;

  InspectorNotifier();

  void initialize() {
    _subscribeToEvents();
  }

  @override
  void dispose() {
    _extensionSubscription?.cancel();
    _flashTimer?.cancel();
    super.dispose();
  }

  void updateSearchQuery(String query) {
    _setState(_state.copyWith(providerSearchQuery: query));
    notifyListeners();
  }

  void clearEvents() {
    _eventsByProvider.clear();
    _processedEventKeys.clear();
    _setState(_state.copyWith(
      events: const [],
      expandedEventIds: const {},
    ));
    notifyListeners();
  }

  void toggleEventExpansion(String eventId) {
    final newExpanded = Set<String>.from(_state.expandedEventIds);
    if (newExpanded.contains(eventId)) {
      newExpanded.remove(eventId);
    } else {
      newExpanded.add(eventId);
    }
    _setState(_state.copyWith(expandedEventIds: newExpanded));
    notifyListeners();
  }

  void selectProvider(String providerName) {
    final newSelected = Set<String>.from(_state.selectedProviderNames);
    newSelected.add(providerName);
    _setState(_state.copyWith(
      selectedProviderNames: newSelected,
      activeTabProviderName: providerName,
    ));
    notifyListeners();
  }

  void removeSelectedProvider(String providerName) {
    final newSelected = Set<String>.from(_state.selectedProviderNames);
    newSelected.remove(providerName);

    String? newActiveTab = _state.activeTabProviderName;
    if (newActiveTab == providerName) {
      newActiveTab = newSelected.isNotEmpty ? newSelected.first : null;
    }

    _setState(_state.copyWith(
      selectedProviderNames: newSelected,
      activeTabProviderName: newActiveTab,
    ));
    notifyListeners();
  }

  void setActiveTab(String providerName) {
    _setState(_state.copyWith(activeTabProviderName: providerName));
    notifyListeners();
  }

  void updateLeftSplitRatio(double ratio) {
    _setState(_state.copyWith(leftSplitRatio: ratio));
    notifyListeners();
  }

  void updateRightSplitRatio(double ratio) {
    _setState(_state.copyWith(rightSplitRatio: ratio));
    notifyListeners();
  }

  void flashProvider(String providerName, {int flashCount = 2}) {
    _flashTimer?.cancel();
    _setState(_state.copyWith(flashingProviderName: providerName));
    notifyListeners();

    if (flashCount == 1) {
      _flashTimer = Timer(const Duration(milliseconds: 300), () {
        _setState(_state.copyWith(flashingProviderName: null));
        notifyListeners();
      });
    } else {
      _flashTimer = Timer(const Duration(milliseconds: 200), () {
        _setState(_state.copyWith(flashingProviderName: null));
        notifyListeners();

        _flashTimer = Timer(const Duration(milliseconds: 100), () {
          _setState(_state.copyWith(flashingProviderName: providerName));
          notifyListeners();

          _flashTimer = Timer(const Duration(milliseconds: 200), () {
            _setState(_state.copyWith(flashingProviderName: null));
            notifyListeners();
          });
        });
      });
    }
  }

  List<ProviderInfo> get filteredProviders =>
      _filteredProvidersCache ??= _computeFilteredProviders();

  List<ProviderInfo> _computeFilteredProviders() {
    final providers = _state.providers.values.toList();
    if (_state.providerSearchQuery.isEmpty) return providers;

    final query = _state.providerSearchQuery.toLowerCase();
    return providers
        .where((provider) => provider.name.toLowerCase().contains(query))
        .toList();
  }

  List<ProviderEvent> get filteredEvents =>
      _filteredEventsCache ??= _computeFilteredEvents();

  List<ProviderEvent> _computeFilteredEvents() {
    if (_state.selectedProviderNames.isEmpty) return _state.events;

    final allEvents = <ProviderEvent>[];
    for (final providerName in _state.selectedProviderNames) {
      final providerEvents = _eventsByProvider[providerName];
      if (providerEvents != null) {
        allEvents.addAll(providerEvents);
      }
    }
    allEvents.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return allEvents;
  }

  List<String> getUsedBy(String providerName) {
    final usedBy = <String>[];
    for (final entry in _state.providers.entries) {
      if (entry.value.dependencies.contains(providerName)) {
        usedBy.add(entry.key);
      }
    }
    return usedBy;
  }

  Map<String, dynamic> _normalizeValue(dynamic rawValue) {
    if (rawValue == null) {
      return {'type': 'null', 'value': null};
    }
    if (rawValue is Map) {
      return Map<String, dynamic>.from(rawValue);
    }
    return {
      'type': rawValue.runtimeType.toString(),
      'string': rawValue.toString(),
    };
  }

  Future<void> _subscribeToEvents() async {
    await serviceManager.onServiceAvailable;
    final service = serviceManager.service!;
    const streamId = 'Extension';
    await service.streamListen(streamId);

    _extensionSubscription = service.onExtensionEvent.listen((Event event) {
      final kind = event.extensionKind;
      if (kind == null || !kind.startsWith('riverpod:')) return;

      final data = event.extensionData?.data ?? {};
      final providerName = data['provider'] as String? ?? 'Unknown';
      final providerId = data['providerId'] as String? ?? 'Unknown';
      final rawValue = data['newValue'] ?? data['value'];
      final rawPreviousValue = data['previousValue'];
      final timestamp = data['timestamp'] as int?;

      List<String> dependencies = [];
      DependencySource dependenciesSource = DependencySource.none;
      DateTime? dependenciesLoadedAt;
      DateTime? dependenciesGeneratedAt;
      try {
        final rawDeps = data['dependencies'];
        if (rawDeps is List) {
          dependencies = rawDeps.map((e) => e.toString()).toList();
        }

        final rawSource = data['dependenciesSource'];
        if (rawSource is String) {
          if (rawSource == 'static') {
            dependenciesSource = DependencySource.static;
          } else if (rawSource == 'name_mismatch') {
            dependenciesSource = DependencySource.nameMismatch;
          } else if (rawSource == 'none') {
            dependenciesSource = DependencySource.none;
          }
        }

        final rawLoadedAt = data['dependenciesLoadedAt'];
        if (rawLoadedAt is int) {
          dependenciesLoadedAt = DateTime.fromMillisecondsSinceEpoch(rawLoadedAt);
        }

        final rawGeneratedAt = data['dependenciesGeneratedAt'];
        if (rawGeneratedAt is int) {
          dependenciesGeneratedAt = DateTime.fromMillisecondsSinceEpoch(rawGeneratedAt);
        }
      } catch (e) {
        // Fallback or ignore if dependencies parsing fails
      }

      final value = _normalizeValue(rawValue);
      final previousValue = _normalizeValue(rawPreviousValue);

      final valueString = value.containsKey('string')
          ? value['string']
          : (value.containsKey('value')
              ? value['value'].toString()
              : value.toString());
      final eventKey = '$kind:$providerId:$valueString';

      if (_processedEventKeys.contains(eventKey)) return;
      _processedEventKeys.add(eventKey);
      Timer(const Duration(milliseconds: 100),
          () => _processedEventKeys.remove(eventKey));

      final eventTimestamp = timestamp != null
          ? DateTime.fromMillisecondsSinceEpoch(timestamp)
          : DateTime.now();

      final newProviders = Map<String, ProviderInfo>.from(_state.providers);
      ProviderEvent? newEvent;

      if (kind == 'riverpod:provider_added') {
        // The provider is alive again; drop it from the disposed list so
        // _cleanupDisposedProviders never evicts an active provider.
        _disposedProviderTimestamps.remove(providerName);
        newProviders[providerName] = ProviderInfo(
          id: providerId,
          name: providerName,
          value: value,
          status: ProviderStatus.active,
          dependencies: dependencies,
          dependenciesSource: dependenciesSource,
          dependenciesLoadedAt: dependenciesLoadedAt,
          dependenciesGeneratedAt: dependenciesGeneratedAt,
        );
        newEvent = ProviderEvent(
          type: EventType.added,
          providerId: providerId,
          providerName: providerName,
          value: value,
          timestamp: eventTimestamp,
        );
      } else if (kind == 'riverpod:provider_updated') {
        _disposedProviderTimestamps.remove(providerName);
        newProviders[providerName] = ProviderInfo(
          id: providerId,
          name: providerName,
          value: value,
          status: ProviderStatus.active,
          dependencies: dependencies,
          dependenciesSource: dependenciesSource,
          dependenciesLoadedAt: dependenciesLoadedAt,
          dependenciesGeneratedAt: dependenciesGeneratedAt,
        );
        newEvent = ProviderEvent(
          type: EventType.updated,
          providerId: providerId,
          providerName: providerName,
          previousValue: previousValue,
          value: value,
          timestamp: eventTimestamp,
        );
      } else if (kind == 'riverpod:provider_disposed') {
        final existing = _state.providers[providerName];
        newProviders[providerName] = ProviderInfo(
          id: providerId,
          name: providerName,
          value: existing?.value ?? {'type': 'null', 'value': null},
          status: ProviderStatus.disposed,
          dependencies: existing?.dependencies ?? [],
          dependenciesSource:
              existing?.dependenciesSource ?? DependencySource.none,
          dependenciesLoadedAt: existing?.dependenciesLoadedAt,
          dependenciesGeneratedAt: existing?.dependenciesGeneratedAt,
        );
        newEvent = ProviderEvent(
          type: EventType.disposed,
          providerId: providerId,
          providerName: providerName,
          timestamp: eventTimestamp,
        );
        _disposedProviderTimestamps[providerName] = eventTimestamp;
      }

      if (newEvent != null) {
        final newEvents = List<ProviderEvent>.from(_state.events)
          ..insert(0, newEvent);
        _eventsByProvider.putIfAbsent(newEvent.providerName, () => []);
        _eventsByProvider[newEvent.providerName]!.insert(0, newEvent);

        // Ring buffer: exactly one event was inserted, so at most one needs
        // evicting. Evict in place on the copy we just made instead of
        // copying the whole list a second time.
        Set<String>? newExpanded;
        if (newEvents.length > _maxEventCount) {
          final removed = newEvents.removeLast();

          final providerEvents = _eventsByProvider[removed.providerName];
          if (providerEvents != null) {
            providerEvents.remove(removed);
            if (providerEvents.isEmpty) {
              _eventsByProvider.remove(removed.providerName);
            }
          }

          if (_state.expandedEventIds.contains(removed.id)) {
            // Passing null to copyWith below means "keep the current set".
            newExpanded = Set<String>.from(_state.expandedEventIds)
              ..remove(removed.id);
          }
        }

        _setState(_state.copyWith(
          providers: newProviders,
          events: newEvents,
          expandedEventIds: newExpanded,
        ));
        _cleanupDisposedProviders();
        notifyListeners();
      }
    });
  }

  void _cleanupDisposedProviders() {
    if (_disposedProviderTimestamps.length <= _maxDisposedProviders) return;

    final sortedDisposed = _disposedProviderTimestamps.entries.toList()
      ..sort((a, b) => a.value.compareTo(b.value));

    final toRemoveCount = sortedDisposed.length - _maxDisposedProviders;
    final newProviders = Map<String, ProviderInfo>.from(_state.providers);
    final newEvents = List<ProviderEvent>.from(_state.events);
    final newExpanded = Set<String>.from(_state.expandedEventIds);
    final newSelected = Set<String>.from(_state.selectedProviderNames);
    String? newActiveTab = _state.activeTabProviderName;

    for (var i = 0; i < toRemoveCount; i++) {
      final providerName = sortedDisposed[i].key;
      newProviders.remove(providerName);
      _disposedProviderTimestamps.remove(providerName);

      final events = _eventsByProvider.remove(providerName);
      if (events != null) {
        for (final event in events) {
          newEvents.remove(event);
          newExpanded.remove(event.id);
        }
      }

      newSelected.remove(providerName);
      if (newActiveTab == providerName) {
        newActiveTab = newSelected.isNotEmpty ? newSelected.first : null;
      }
    }

    _setState(_state.copyWith(
      providers: newProviders,
      events: newEvents,
      expandedEventIds: newExpanded,
      selectedProviderNames: newSelected,
      activeTabProviderName: newActiveTab,
    ));
  }
}
