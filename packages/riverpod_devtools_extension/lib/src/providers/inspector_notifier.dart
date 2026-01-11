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
    _state = _state.copyWith(providerSearchQuery: query);
    notifyListeners();
  }

  void toggleEventExpansion(String eventId) {
    final newExpanded = Set<String>.from(_state.expandedEventIds);
    if (newExpanded.contains(eventId)) {
      newExpanded.remove(eventId);
    } else {
      newExpanded.add(eventId);
    }
    _state = _state.copyWith(expandedEventIds: newExpanded);
    notifyListeners();
  }

  void selectProvider(String providerName) {
    final newSelected = Set<String>.from(_state.selectedProviderNames);
    newSelected.add(providerName);
    _state = _state.copyWith(
      selectedProviderNames: newSelected,
      activeTabProviderName: providerName,
    );
    notifyListeners();
  }

  void removeSelectedProvider(String providerName) {
    final newSelected = Set<String>.from(_state.selectedProviderNames);
    newSelected.remove(providerName);

    String? newActiveTab = _state.activeTabProviderName;
    if (newActiveTab == providerName) {
      newActiveTab = newSelected.isNotEmpty ? newSelected.first : null;
    }

    _state = _state.copyWith(
      selectedProviderNames: newSelected,
      activeTabProviderName: newActiveTab,
    );
    notifyListeners();
  }

  void setActiveTab(String providerName) {
    _state = _state.copyWith(activeTabProviderName: providerName);
    notifyListeners();
  }

  void updateLeftSplitRatio(double ratio) {
    _state = _state.copyWith(leftSplitRatio: ratio);
    notifyListeners();
  }

  void updateRightSplitRatio(double ratio) {
    _state = _state.copyWith(rightSplitRatio: ratio);
    notifyListeners();
  }

  void flashProvider(String providerName, {int flashCount = 2}) {
    _flashTimer?.cancel();
    _state = _state.copyWith(flashingProviderName: providerName);
    notifyListeners();

    if (flashCount == 1) {
      _flashTimer = Timer(const Duration(milliseconds: 300), () {
        _state = _state.copyWith(flashingProviderName: null);
        notifyListeners();
      });
    } else {
      _flashTimer = Timer(const Duration(milliseconds: 200), () {
        _state = _state.copyWith(flashingProviderName: null);
        notifyListeners();

        _flashTimer = Timer(const Duration(milliseconds: 100), () {
          _state = _state.copyWith(flashingProviderName: providerName);
          notifyListeners();

          _flashTimer = Timer(const Duration(milliseconds: 200), () {
            _state = _state.copyWith(flashingProviderName: null);
            notifyListeners();
          });
        });
      });
    }
  }

  List<ProviderInfo> get filteredProviders {
    final providers = _state.providers.values.toList();
    if (_state.providerSearchQuery.isEmpty) return providers;

    final query = _state.providerSearchQuery.toLowerCase();
    return providers
        .where((provider) => provider.name.toLowerCase().contains(query))
        .toList();
  }

  List<ProviderEvent> get filteredEvents {
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
      try {
        final rawDeps = data['dependencies'];
        if (rawDeps is List) {
          dependencies = rawDeps.map((e) => e.toString()).toList();
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
        newProviders[providerName] = ProviderInfo(
          id: providerId,
          name: providerName,
          value: value,
          status: ProviderStatus.active,
          dependencies: dependencies,
        );
        newEvent = ProviderEvent(
          type: EventType.added,
          providerId: providerId,
          providerName: providerName,
          value: value,
          timestamp: eventTimestamp,
        );
      } else if (kind == 'riverpod:provider_updated') {
        newProviders[providerName] = ProviderInfo(
          id: providerId,
          name: providerName,
          value: value,
          status: ProviderStatus.active,
          dependencies: dependencies,
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
        newProviders[providerName] = ProviderInfo(
          id: providerId,
          name: providerName,
          value: _state.providers[providerName]?.value ??
              {'type': 'null', 'value': null},
          status: ProviderStatus.disposed,
          dependencies: _state.providers[providerName]?.dependencies ?? [],
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

        _state = _state.copyWith(providers: newProviders, events: newEvents);
        _applyRingBuffer();
        _cleanupDisposedProviders();
        notifyListeners();
      }
    });
  }

  void _applyRingBuffer() {
    if (_state.events.length > _maxEventCount) {
      final newEvents = List<ProviderEvent>.from(_state.events);
      final removed = newEvents.removeAt(_maxEventCount);

      final providerEvents = _eventsByProvider[removed.providerName];
      if (providerEvents != null) {
        providerEvents.remove(removed);
        if (providerEvents.isEmpty) {
          _eventsByProvider.remove(removed.providerName);
        }
      }

      final newExpanded = Set<String>.from(_state.expandedEventIds)
        ..remove(removed.id);
      _state =
          _state.copyWith(events: newEvents, expandedEventIds: newExpanded);
    }
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

    _state = _state.copyWith(
      providers: newProviders,
      events: newEvents,
      expandedEventIds: newExpanded,
      selectedProviderNames: newSelected,
      activeTabProviderName: newActiveTab,
    );
  }
}
