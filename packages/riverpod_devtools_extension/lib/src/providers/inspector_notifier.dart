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

/// Which top-level view the extension shows.
enum InspectorViewMode { inspector, graph }

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
  final InspectorViewMode viewMode;

  /// When set, the graph view shows only this provider plus its
  /// transitive dependencies and dependents.
  final String? graphFocusProvider;

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
    this.viewMode = InspectorViewMode.inspector,
    this.graphFocusProvider,
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
    InspectorViewMode? viewMode,
    Object? graphFocusProvider = const _Unset(),
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
      viewMode: viewMode ?? this.viewMode,
      graphFocusProvider: graphFocusProvider is _Unset
          ? this.graphFocusProvider
          : graphFocusProvider as String?,
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
  Map<String, List<String>>? _usedByIndex;
  Map<String, int>? _eventDepthsCache;

  void _setState(InspectorState newState) {
    final old = _state;
    _state = newState;
    if (!identical(old.providers, newState.providers)) {
      _filteredProvidersCache = null;
      _usedByIndex = null;
    } else if (old.providerSearchQuery != newState.providerSearchQuery) {
      _filteredProvidersCache = null;
    }
    if (!identical(old.events, newState.events) ||
        !identical(
            old.selectedProviderNames, newState.selectedProviderNames)) {
      _filteredEventsCache = null;
    }
    if (!identical(old.events, newState.events)) {
      _eventDepthsCache = null;
    }
  }

  static const int _maxEventCount = 1000;
  static const int _maxDisposedProviders = 100;
  static const int _dedupWindowMs = 100;
  static const int _dedupPruneThreshold = 64;

  final Map<String, DateTime> _disposedProviderTimestamps = {};
  final Map<String, List<ProviderEvent>> _eventsByProvider = {};

  /// Recently seen event keys mapped to their dedup-window expiry, in
  /// milliseconds since epoch. Expired entries are pruned in bulk once the
  /// map grows past [_dedupPruneThreshold] — cheaper than the previous
  /// approach of scheduling a 100ms Timer per event.
  final Map<String, int> _processedEventKeys = {};
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

  void setViewMode(InspectorViewMode mode) {
    _setState(_state.copyWith(viewMode: mode));
    notifyListeners();
  }

  void setGraphFocus(String? providerName) {
    _setState(_state.copyWith(graphFocusProvider: providerName));
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

  /// Providers that depend on [providerName], from a reverse-dependency
  /// index that is rebuilt only when the provider map changes (the naive
  /// scan was O(providers × dependencies) on every detail-panel rebuild).
  List<String> getUsedBy(String providerName) =>
      (_usedByIndex ??= _computeUsedByIndex())[providerName] ?? const [];

  Map<String, List<String>> _computeUsedByIndex() {
    final index = <String, List<String>>{};
    for (final entry in _state.providers.entries) {
      for (final dependency in entry.value.dependencies) {
        final dependents = index[dependency] ??= [];
        // A provider may list the same dependency several times (e.g. watch
        // + read of the same provider); additions for one provider are
        // contiguous, so checking the last element is enough to dedupe.
        if (dependents.isEmpty || dependents.last != entry.key) {
          dependents.add(entry.key);
        }
      }
    }
    return index;
  }

  /// Replaces the event list directly, bypassing the vm_service
  /// subscription. Only for tests (the subscription needs a live service
  /// connection, which unit tests don't have).
  @visibleForTesting
  void debugSetEvents(List<ProviderEvent> events) {
    _setState(_state.copyWith(events: events));
    notifyListeners();
  }

  /// Seeds the whole inspector state — providers, events (newest first),
  /// and the per-provider event index — bypassing the vm_service
  /// subscription. Only for tests and the screenshot harness
  /// (`main_mock.dart`).
  @visibleForTesting
  void debugSeed({
    required Map<String, ProviderInfo> providers,
    required List<ProviderEvent> events,
  }) {
    _eventsByProvider.clear();
    for (final event in events) {
      _eventsByProvider.putIfAbsent(event.providerName, () => []).add(event);
    }
    _setState(_state.copyWith(providers: providers, events: events));
    notifyListeners();
  }

  /// Cascade depth per event ID: 0 for root updates, 1+ for updates that
  /// were (transitively) triggered by another update in the log. Used by
  /// the event log to indent cascades. Rebuilt only when the event list
  /// changes.
  Map<String, int> get eventDepths =>
      _eventDepthsCache ??= _computeEventDepths();

  static const int _maxCascadeDepth = 4;

  Map<String, int> _computeEventDepths() {
    final depthBySeq = <int, int>{};
    final depthById = <String, int>{};
    // Oldest first, so an event's triggers are processed before it.
    for (var i = _state.events.length - 1; i >= 0; i--) {
      final event = _state.events[i];
      var depth = 0;
      for (final trigger in event.triggeredBy) {
        final triggerDepth =
            trigger.seq != null ? depthBySeq[trigger.seq] : null;
        // A trigger that is no longer in the log (evicted) still means
        // this event was caused by something: treat it as depth 1.
        final candidate = (triggerDepth ?? 0) + 1;
        if (candidate > depth) depth = candidate;
      }
      if (depth > _maxCascadeDepth) depth = _maxCascadeDepth;
      if (event.seq != null) depthBySeq[event.seq!] = depth;
      if (depth > 0) depthById[event.id] = depth;
    }
    return depthById;
  }

  /// The most recent event for [providerName], if any (O(1) lookup).
  ProviderEvent? latestEventFor(String providerName) {
    final events = _eventsByProvider[providerName];
    return events == null || events.isEmpty ? null : events.first;
  }

  Map<String, dynamic> _normalizeValue(dynamic rawValue) {
    if (rawValue == null) {
      return {'type': 'null', 'value': null};
    }
    if (rawValue is Map<String, dynamic>) {
      // Already the right type (the common case for decoded event JSON):
      // it is treated as read-only downstream, so skip the copy.
      return rawValue;
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
      final seq = data['seq'] is int ? data['seq'] as int : null;

      var dependencyDetails = const <DependencyDetail>[];
      final rawDetails = data['dependencyDetails'];
      if (rawDetails is List) {
        dependencyDetails = [
          for (final detail in rawDetails)
            if (detail is Map && detail['providerName'] != null)
              DependencyDetail(
                providerName: detail['providerName'].toString(),
                type: detail['type']?.toString(),
                file: detail['file']?.toString(),
                line: detail['line'] is int ? detail['line'] as int : null,
              ),
        ];
      }

      var triggeredBy = const <TriggerRef>[];
      final rawTriggers = data['triggeredBy'];
      if (rawTriggers is List) {
        triggeredBy = [
          for (final trigger in rawTriggers)
            if (trigger is Map && trigger['provider'] != null)
              TriggerRef(
                provider: trigger['provider'].toString(),
                seq: trigger['seq'] is int ? trigger['seq'] as int : null,
              ),
        ];
      }

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

      // seq uniquely identifies an event, so when present it makes the
      // dedup exact (only true re-deliveries collide). The value-based key
      // remains as a fallback for payloads from older observers.
      final String eventKey;
      if (seq != null) {
        eventKey = '$kind:$providerId:$seq';
      } else {
        final valueString = value.containsKey('string')
            ? value['string']
            : (value.containsKey('value')
                ? value['value'].toString()
                : value.toString());
        eventKey = '$kind:$providerId:$valueString';
      }

      final nowMs = DateTime.now().millisecondsSinceEpoch;
      final dedupExpiry = _processedEventKeys[eventKey];
      if (dedupExpiry != null && nowMs < dedupExpiry) return;
      if (_processedEventKeys.length >= _dedupPruneThreshold) {
        _processedEventKeys.removeWhere((_, expiry) => expiry <= nowMs);
      }
      _processedEventKeys[eventKey] = nowMs + _dedupWindowMs;

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
          dependencyDetails: dependencyDetails,
        );
        newEvent = ProviderEvent(
          type: EventType.added,
          providerId: providerId,
          providerName: providerName,
          value: value,
          timestamp: eventTimestamp,
          seq: seq,
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
          // Updates don't carry details; keep what the added event gave us.
          dependencyDetails:
              _state.providers[providerName]?.dependencyDetails ?? const [],
        );
        newEvent = ProviderEvent(
          type: EventType.updated,
          providerId: providerId,
          providerName: providerName,
          previousValue: previousValue,
          value: value,
          timestamp: eventTimestamp,
          seq: seq,
          triggeredBy: triggeredBy,
        );
      } else if (kind == 'riverpod:provider_failed') {
        Map<String, dynamic>? errorMap;
        final rawError = data['error'];
        if (rawError is Map) {
          errorMap = Map<String, dynamic>.from(rawError);
        }

        // The provider element still exists (it holds the error state), so
        // keep its current value/status and just record the failure.
        final existing = _state.providers[providerName];
        newProviders[providerName] = ProviderInfo(
          id: providerId,
          name: providerName,
          value: existing?.value ?? {'type': 'null', 'value': null},
          status: existing?.status ?? ProviderStatus.active,
          dependencies: existing?.dependencies ?? dependencies,
          dependenciesSource:
              existing?.dependenciesSource ?? dependenciesSource,
          dependenciesLoadedAt:
              existing?.dependenciesLoadedAt ?? dependenciesLoadedAt,
          dependenciesGeneratedAt:
              existing?.dependenciesGeneratedAt ?? dependenciesGeneratedAt,
          lastError: errorMap ?? {'message': 'Unknown error'},
          dependencyDetails: existing?.dependencyDetails ?? const [],
        );
        newEvent = ProviderEvent(
          type: EventType.failed,
          providerId: providerId,
          providerName: providerName,
          timestamp: eventTimestamp,
          seq: seq,
          error: errorMap,
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
          dependencyDetails: existing?.dependencyDetails ?? const [],
        );
        newEvent = ProviderEvent(
          type: EventType.disposed,
          providerId: providerId,
          providerName: providerName,
          timestamp: eventTimestamp,
          seq: seq,
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
