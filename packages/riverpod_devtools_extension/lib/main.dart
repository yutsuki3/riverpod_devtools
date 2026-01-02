import 'dart:async';
import 'package:devtools_extensions/devtools_extensions.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/gestures.dart';
import 'package:vm_service/vm_service.dart';

void main() {
  runApp(const RiverpodDevToolsExtension());
}

class RiverpodDevToolsExtension extends StatelessWidget {
  const RiverpodDevToolsExtension({super.key});

  @override
  Widget build(BuildContext context) {
    return const DevToolsExtension(
      child: RiverpodInspector(),
    );
  }
}

class RiverpodInspector extends StatefulWidget {
  const RiverpodInspector({super.key});

  @override
  State<RiverpodInspector> createState() => _RiverpodInspectorState();
}

class _RiverpodInspectorState extends State<RiverpodInspector> {
  /// Maximum number of events to keep in memory (ring buffer)
  static const int _maxEventCount = 1000;

  final List<ProviderEvent> _events = [];
  final Map<String, ProviderInfo> _providers = {};

  /// Index structure for fast filtering: provider name -> list of events
  final Map<String, List<ProviderEvent>> _eventsByProvider = {};

  /// The currently selected provider names for detail view.
  /// Empty set means no provider is selected.
  final Set<String> _selectedProviderNames = {};
  StreamSubscription? _extensionSubscription;
  final Set<String> _processedEventKeys = {};

  /// Search query for filtering providers
  String _providerSearchQuery = '';
  final TextEditingController _searchController = TextEditingController();

  /// ID-based expansion state (instead of index-based)
  final Set<String> _expandedEventIds = {};

  /// Split ratio for the left divider (0.0 to 1.0)
  /// Represents the fraction of width allocated to the provider list
  double _leftSplitRatio = 0.2;

  /// Split ratio for the right divider (0.0 to 1.0)
  /// Represents the fraction of remaining width allocated to the detail panel
  double _rightSplitRatio = 0.375;

  @override
  void initState() {
    super.initState();
    _subscribeToEvents();
  }

  @override
  void dispose() {
    _extensionSubscription?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  /// Normalize a value to Map<String, dynamic> format
  Map<String, dynamic> _normalizeValue(dynamic rawValue) {
    if (rawValue == null) {
      return {'type': 'null', 'value': null};
    }
    if (rawValue is Map) {
      return Map<String, dynamic>.from(rawValue);
    }
    // For primitive types, wrap in a simple structure
    return {
      'type': rawValue.runtimeType.toString(),
      'string': rawValue.toString(),
    };
  }

  /// Get providers that depend on (use) the given provider
  List<String> _getUsedBy(String providerName) {
    final usedBy = <String>[];
    for (final entry in _providers.entries) {
      if (entry.value.dependencies.contains(providerName)) {
        usedBy.add(entry.key);
      }
    }
    return usedBy;
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

      // Safely extract dependencies list
      List<String> dependencies = [];
      try {
        final rawDeps = data['dependencies'];
        if (rawDeps is List) {
          dependencies = rawDeps.map((e) => e.toString()).toList();
        }
      } catch (e) {
        // Keep empty list on error
      }

      // Convert values to Map<String, dynamic> if they're already Maps,
      // or wrap primitive types in a simple structure
      final value = _normalizeValue(rawValue);
      final previousValue = _normalizeValue(rawPreviousValue);

      // Create a unique key for this event to deduplicate
      // Format: kind:providerId:value
      // We don't use timestamp in the key because we WANT to deduplicate
      // identically valued updates that happen inside the same logical "tick"
      final valueString = value.containsKey('string')
          ? value['string']
          : (value.containsKey('value')
              ? value['value'].toString()
              : value.toString());
      final eventKey = '$kind:$providerId:$valueString';

      if (_processedEventKeys.contains(eventKey)) {
        return;
      }

      _processedEventKeys.add(eventKey);
      // Clear the key after a short period to allow future identical updates
      Timer(const Duration(milliseconds: 100), () {
        _processedEventKeys.remove(eventKey);
      });

      setState(() {
        final eventTimestamp = timestamp != null
            ? DateTime.fromMillisecondsSinceEpoch(timestamp)
            : DateTime.now();

        if (kind == 'riverpod:provider_added') {
          _providers[providerName] = ProviderInfo(
            id: providerId,
            name: providerName,
            value: value,
            status: ProviderStatus.active,
            dependencies: dependencies,
          );
          _addEvent(ProviderEvent(
            type: EventType.added,
            providerId: providerId,
            providerName: providerName,
            value: value,
            timestamp: eventTimestamp,
          ));
        } else if (kind == 'riverpod:provider_updated') {
          // Categorize the event type based on the update characteristics
          final eventType = _categorizeEventType(
            previousValue: previousValue,
            value: value,
            currentDependencies: dependencies,
            providerName: providerName,
          );

          _providers[providerName] = ProviderInfo(
            id: providerId,
            name: providerName,
            value: value,
            status: ProviderStatus.active,
            dependencies: dependencies,
          );
          _addEvent(ProviderEvent(
            type: eventType,
            providerId: providerId,
            providerName: providerName,
            previousValue: previousValue,
            value: value,
            timestamp: eventTimestamp,
          ));
        } else if (kind == 'riverpod:provider_disposed') {
          _providers[providerName] = ProviderInfo(
            id: providerId,
            name: providerName,
            value: _providers[providerName]?.value ??
                {'type': 'null', 'value': null},
            status: ProviderStatus.disposed,
            dependencies: _providers[providerName]?.dependencies ?? [],
          );
          _addEvent(ProviderEvent(
            type: EventType.disposed,
            providerId: providerId,
            providerName: providerName,
            timestamp: eventTimestamp,
          ));
        }
      });
    });
  }

  /// Determine the specific event type based on event characteristics
  EventType _categorizeEventType({
    required Map<String, dynamic>? previousValue,
    required Map<String, dynamic>? value,
    required List<String> currentDependencies,
    required String providerName,
  }) {
    // Check for dependency changes
    final previousProvider = _providers[providerName];
    if (previousProvider != null) {
      final prevDeps = previousProvider.dependencies;
      if (!_listsEqual(prevDeps, currentDependencies)) {
        return EventType.dependencyChange;
      }
    }

    // Check for AsyncValue state transitions
    if (value != null && value.containsKey('type')) {
      final valueType = value['type'] as String?;
      final prevType = previousValue?.containsKey('type') == true
          ? previousValue!['type'] as String?
          : null;

      // AsyncComplete: transition from loading to data
      if (prevType == 'AsyncLoading' && valueType == 'AsyncData') {
        return EventType.asyncComplete;
      }

      // Invalidate: transition to loading or null
      if (valueType == 'AsyncLoading' || valueType == 'null') {
        return EventType.invalidate;
      }
    }

    // Check for rebuild (same value)
    if (previousValue != null &&
        value != null &&
        _mapsEqual(previousValue, value)) {
      return EventType.rebuild;
    }

    // Check for refresh (explicit re-fetch with different value)
    // This is detected when an AsyncData changes to another AsyncData with different value
    if (previousValue != null && value != null) {
      final prevType = previousValue.containsKey('type')
          ? previousValue['type'] as String?
          : null;
      final currType = value.containsKey('type') ? value['type'] as String? : null;

      if (prevType == 'AsyncData' && currType == 'AsyncData') {
        final prevData = previousValue.containsKey('value')
            ? previousValue['value']
            : null;
        final currData = value.containsKey('value') ? value['value'] : null;

        if (prevData != currData) {
          return EventType.refresh;
        }
      }
    }

    // Default to updated
    return EventType.updated;
  }

  /// Helper to compare two lists for equality
  bool _listsEqual(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  /// Helper to compare two maps for equality
  bool _mapsEqual(Map<String, dynamic> a, Map<String, dynamic> b) {
    if (a.length != b.length) return false;
    for (final key in a.keys) {
      if (!b.containsKey(key)) return false;
      final aVal = a[key];
      final bVal = b[key];
      if (aVal is Map && bVal is Map) {
        if (!_mapsEqual(
            aVal as Map<String, dynamic>, bVal as Map<String, dynamic>)) {
          return false;
        }
      } else if (aVal is List && bVal is List) {
        if (aVal.length != bVal.length) return false;
        for (var i = 0; i < aVal.length; i++) {
          if (aVal[i] != bVal[i]) return false;
        }
      } else if (aVal != bVal) {
        return false;
      }
    }
    return true;
  }

  /// Add an event with ring buffer logic and index updates
  void _addEvent(ProviderEvent event) {
    _events.insert(0, event);

    // Update provider index
    _eventsByProvider.putIfAbsent(event.providerName, () => []);
    _eventsByProvider[event.providerName]!.insert(0, event);

    // Ring buffer: remove oldest events if exceeding max count
    if (_events.length > _maxEventCount) {
      final removed = _events.removeAt(_maxEventCount);
      _eventsByProvider[removed.providerName]?.remove(removed);
      // Clean up expansion state for removed event
      _expandedEventIds.remove(removed.id);
    }
  }

  /// Get filtered providers based on search query
  List<ProviderInfo> get _filteredProviders {
    if (_providerSearchQuery.isEmpty) {
      return _providers.values.toList();
    }

    final query = _providerSearchQuery.toLowerCase();
    return _providers.values
        .where((provider) => provider.name.toLowerCase().contains(query))
        .toList();
  }

  /// Get filtered events using index structure for performance
  List<ProviderEvent> get _filteredEvents {
    if (_selectedProviderNames.isEmpty) return _events;

    // Combine events from all selected providers
    final allEvents = <ProviderEvent>[];
    for (final providerName in _selectedProviderNames) {
      final providerEvents = _eventsByProvider[providerName];
      if (providerEvents != null) {
        allEvents.addAll(providerEvents);
      }
    }
    // Sort by timestamp (newest first)
    allEvents.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return allEvents;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final totalWidth = constraints.maxWidth;
        const dividerWidth = 4.0;

        // Calculate widths for 3 columns
        final providerListWidth = totalWidth * _leftSplitRatio;
        final remainingWidth = totalWidth - providerListWidth - dividerWidth;
        final detailPanelWidth = remainingWidth * _rightSplitRatio;
        final eventLogWidth = remainingWidth - detailPanelWidth - dividerWidth;

        return Row(
          children: [
            // Left: Provider List
            SizedBox(
              width: providerListWidth,
              child: _buildProviderList(),
            ),

            // Left Divider
            _buildDivider(
              theme: theme,
              onDrag: (delta) {
                setState(() {
                  final newRatio = _leftSplitRatio + delta / totalWidth;
                  _leftSplitRatio = newRatio.clamp(0.15, 0.5);
                });
              },
            ),

            // Center: Detail Panel
            SizedBox(
              width: detailPanelWidth,
              child: _buildDetailPanel(),
            ),

            // Right Divider
            _buildDivider(
              theme: theme,
              onDrag: (delta) {
                setState(() {
                  final newRatio = _rightSplitRatio + delta / remainingWidth;
                  _rightSplitRatio = newRatio.clamp(0.3, 0.7);
                });
              },
            ),

            // Right: Event Log
            SizedBox(
              width: eventLogWidth,
              child: _buildEventLog(),
            ),
          ],
        );
      },
    );
  }

  Widget _buildDivider({
    required ThemeData theme,
    required void Function(double delta) onDrag,
  }) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onHorizontalDragUpdate: (details) => onDrag(details.delta.dx),
      child: MouseRegion(
        cursor: SystemMouseCursors.resizeColumn,
        child: Container(
          width: 4.0,
          color: theme.colorScheme.outline.withValues(alpha: 0.2),
          child: Center(
            child: Container(
              width: 1.5,
              height: 32,
              decoration: BoxDecoration(
                color: theme.colorScheme.outline.withValues(alpha: 0.8),
                borderRadius: BorderRadius.circular(0.75),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildProviderList() {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          color: theme.colorScheme.surfaceContainerHighest,
          width: double.infinity,
          height: 32,
          alignment: Alignment.centerLeft,
          child: Row(
            children: [
              const Text(
                'Providers',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
              const Spacer(),
              if (_selectedProviderNames.isNotEmpty)
                TextButton(
                  onPressed: () => setState(() {
                    _selectedProviderNames.clear();
                  }),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    minimumSize: const Size(0, 24),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: const Text('Clear', style: TextStyle(fontSize: 10)),
                ),
            ],
          ),
        ),
        // Search field
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          child: TextField(
            controller: _searchController,
            onChanged: (value) {
              setState(() {
                _providerSearchQuery = value;
              });
            },
            style: const TextStyle(fontSize: 10),
            decoration: InputDecoration(
              hintText: 'Search providers...',
              hintStyle: TextStyle(
                fontSize: 10,
                color:
                    theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
              ),
              prefixIcon: Padding(
                padding: const EdgeInsets.only(left: 6),
                child: Icon(
                  Icons.search,
                  size: 14,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              prefixIconConstraints: const BoxConstraints(
                minWidth: 20,
                minHeight: 20,
              ),
              suffixIcon: SizedBox(
                width: 20,
                height: 20,
                child: _providerSearchQuery.isNotEmpty
                    ? IconButton(
                        icon: Icon(
                          Icons.clear,
                          size: 14,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        onPressed: () {
                          setState(() {
                            _searchController.clear();
                            _providerSearchQuery = '';
                          });
                        },
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      )
                    : null,
              ),
              isDense: true,
              constraints: const BoxConstraints(
                maxHeight: 32,
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 6,
                vertical: 6,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(4),
                borderSide: BorderSide(
                  color: theme.colorScheme.outline.withValues(alpha: 0.3),
                ),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(4),
                borderSide: BorderSide(
                  color: theme.colorScheme.outline.withValues(alpha: 0.3),
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(4),
                borderSide: BorderSide(
                  color: theme.colorScheme.primary,
                  width: 1.5,
                ),
              ),
            ),
          ),
        ),
        Expanded(
          child: _providers.isEmpty
              ? Center(
                  child: Text(
                    'No providers yet',
                    style: TextStyle(
                        fontSize: 12,
                        color: theme.colorScheme.onSurfaceVariant),
                  ),
                )
              : Builder(
                  builder: (context) {
                    final filteredProviders = _filteredProviders;

                    if (filteredProviders.isEmpty) {
                      return Center(
                        child: Text(
                          'No providers found',
                          style: TextStyle(
                            fontSize: 12,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      );
                    }

                    return GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () {
                        // Tapping empty area deselects all
                        setState(() {
                          _selectedProviderNames.clear();
                        });
                      },
                      child: ListView.builder(
                        itemCount: filteredProviders.length,
                        itemBuilder: (context, index) {
                        final provider = filteredProviders[index];
                        final isSelected =
                            _selectedProviderNames.contains(provider.name);
                        return Theme(
                          data: Theme.of(context).copyWith(
                            splashFactory: NoSplash.splashFactory,
                            highlightColor: Colors.transparent,
                          ),
                          child: Listener(
                            onPointerDown: (event) {
                              setState(() {
                                final isCtrlOrCmd = event.kind ==
                                        PointerDeviceKind.mouse &&
                                    (HardwareKeyboard.instance.isMetaPressed ||
                                        HardwareKeyboard
                                            .instance.isControlPressed);

                                if (isCtrlOrCmd) {
                                  // Multi-selection mode: toggle
                                  if (isSelected) {
                                    _selectedProviderNames
                                        .remove(provider.name);
                                  } else {
                                    _selectedProviderNames.add(provider.name);
                                  }
                                } else {
                                  // Single selection mode
                                  if (isSelected && _selectedProviderNames.length == 1) {
                                    // If clicking the only selected provider, deselect it
                                    _selectedProviderNames.clear();
                                  } else {
                                    // Otherwise, select only this one
                                    _selectedProviderNames.clear();
                                    _selectedProviderNames.add(provider.name);
                                  }
                                }
                              });
                            },
                            child: InkWell(
                              onTap: () {
                                // Handled by Listener above
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                color: isSelected
                                    ? theme.colorScheme.primary
                                        .withValues(alpha: 0.1)
                                    : null,
                                child: Row(
                                  children: [
                                    Icon(
                                      provider.status == ProviderStatus.active
                                          ? Icons.circle
                                          : Icons.circle_outlined,
                                      size: 8,
                                      color: provider.status ==
                                              ProviderStatus.active
                                          ? Colors.greenAccent
                                          : theme.colorScheme.onSurfaceVariant,
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        provider.name,
                                        style: const TextStyle(fontSize: 10),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                    );
                  },
                ),
        ),
        // Operation hint
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          color:
              theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
          child: Text(
            'Tip: Ctrl/Cmd+Click for multi-selection',
            style: TextStyle(
              fontSize: 8,
              color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
              fontStyle: FontStyle.italic,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDetailPanel() {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          color: theme.colorScheme.surfaceContainerHighest,
          width: double.infinity,
          height: 32,
          alignment: Alignment.centerLeft,
          child: const Text(
            'Provider Details',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 12,
            ),
          ),
        ),

        // Content
        Expanded(
          child: _selectedProviderNames.isEmpty
              ? Center(
                  child: Text(
                    'Select a provider to view details',
                    style: TextStyle(
                      fontSize: 12,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                )
              : Builder(
                  builder: (context) {
                    final provider = _providers[_selectedProviderNames.first];
                    if (provider == null) {
                      return Center(
                        child: Text(
                          'Provider not found',
                          style: TextStyle(
                            fontSize: 12,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      );
                    }

                    return SingleChildScrollView(
                      padding: const EdgeInsets.all(8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Provider Name (Large Display)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  provider.name,
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: theme.colorScheme.onSurface,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Row(
                                  children: [
                                    Icon(
                                      provider.status == ProviderStatus.active
                                          ? Icons.circle
                                          : Icons.circle_outlined,
                                      size: 12,
                                      color: provider.status ==
                                              ProviderStatus.active
                                          ? Colors.greenAccent
                                          : theme.colorScheme.onSurfaceVariant,
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      provider.status == ProviderStatus.active
                                          ? 'Active'
                                          : 'Disposed',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color:
                                            theme.colorScheme.onSurfaceVariant,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),

                          // State Section
                          _buildDetailSection(
                            title: 'Current State',
                            child: Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: theme.colorScheme.surfaceContainerHighest
                                    .withValues(alpha: 0.5),
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(
                                  color: theme.colorScheme.outline
                                      .withValues(alpha: 0.2),
                                ),
                              ),
                              child: _buildJsonTreeView(provider.value),
                            ),
                          ),

                          const SizedBox(height: 16),

                          // Dependencies Section (with Beta badge)
                          _buildDetailSection(
                            title: 'Dependencies',
                            betaBadge: true,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Note UI
                                Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 6,
                                  ),
                                  margin: const EdgeInsets.only(bottom: 12),
                                  decoration: BoxDecoration(
                                    color: Colors.blue.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(4),
                                    border: Border.all(
                                      color: Colors.blue.withValues(alpha: 0.3),
                                    ),
                                  ),
                                  child: Text(
                                    'Dependencies are detected by observing update patterns. '
                                    'May include false positives.',
                                    style: TextStyle(
                                      fontSize: 9,
                                      color: theme.colorScheme.onSurfaceVariant,
                                      fontStyle: FontStyle.italic,
                                    ),
                                  ),
                                ),

                                // Depends On subsection
                                _buildDependencySubsection(
                                  title: 'Depends On',
                                  dependencies: provider.dependencies,
                                  emptyMessage: 'No dependencies detected yet',
                                  theme: theme,
                                ),

                                const SizedBox(height: 12),

                                // Used By subsection
                                _buildDependencySubsection(
                                  title: 'Used By',
                                  dependencies: _getUsedBy(provider.name),
                                  emptyMessage: 'Not used by any providers',
                                  theme: theme,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildDetailSection({
    required String title,
    required Widget child,
    bool betaBadge = false,
  }) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              title,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: theme.colorScheme.primary,
              ),
            ),
            if (betaBadge) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.fromLTRB(3, 2, 3, 1),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest
                      .withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(2),
                  border: Border.all(
                    color: theme.colorScheme.outline.withValues(alpha: 0.3),
                    width: 0.5,
                  ),
                ),
                child: Text(
                  'BETA',
                  style: TextStyle(
                    fontSize: 7,
                    fontWeight: FontWeight.w500,
                    color: theme.colorScheme.onSurfaceVariant
                        .withValues(alpha: 0.6),
                  ),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 4),
        child,
      ],
    );
  }

  Widget _buildDependencySubsection({
    required String title,
    required List<String> dependencies,
    required String emptyMessage,
    required ThemeData theme,
  }) {
    return Padding(
      padding: const EdgeInsets.only(left: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Subsection title
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(
              title,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          // Dependency list
          if (dependencies.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
              child: Text(
                emptyMessage,
                style: TextStyle(
                  fontSize: 10,
                  color: theme.colorScheme.onSurfaceVariant,
                  fontStyle: FontStyle.italic,
                ),
              ),
            )
          else
            Column(
              children: dependencies.map((name) {
                return InkWell(
                  onTap: () {
                    setState(() {
                      _selectedProviderNames.clear();
                      _selectedProviderNames.add(name);
                    });
                  },
                  child: Container(
                    width: double.infinity,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    margin: const EdgeInsets.only(bottom: 2),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(
                        color: theme.colorScheme.outline.withValues(alpha: 0.2),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.arrow_forward_ios,
                          size: 10,
                          color: theme.colorScheme.primary,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            name,
                            style: TextStyle(
                              fontSize: 10,
                              color: theme.colorScheme.primary,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
        ],
      ),
    );
  }

  Widget _buildEventLog() {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          color: theme.colorScheme.surfaceContainerHighest,
          width: double.infinity,
          height: 32,
          alignment: Alignment.centerLeft,
          child: Row(
            children: [
              Text(
                _selectedProviderNames.isEmpty
                    ? 'Event Log'
                    : _selectedProviderNames.length == 1
                        ? 'Event Log (${_selectedProviderNames.first})'
                        : 'Event Log (${_selectedProviderNames.length} providers)',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.delete_outline, size: 16),
                onPressed: () => setState(() {
                  _events.clear();
                  _eventsByProvider.clear();
                  _expandedEventIds.clear();
                }),
                tooltip: 'Clear All',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                iconSize: 16,
              ),
            ],
          ),
        ),
        Expanded(
          child: _events.isEmpty
              ? Center(
                  child: Text(
                    'No events yet',
                    style: TextStyle(
                        fontSize: 12,
                        color: theme.colorScheme.onSurfaceVariant),
                  ),
                )
              : Builder(
                  builder: (context) {
                    final filteredEvents = _filteredEvents;

                    if (filteredEvents.isEmpty) {
                      return Center(
                        child: Text(
                          'No events found for selected providers',
                          style: TextStyle(
                              fontSize: 12,
                              color: theme.colorScheme.onSurfaceVariant),
                        ),
                      );
                    }

                    return ListView.builder(
                      itemCount: filteredEvents.length,
                      itemBuilder: (context, index) {
                        final event = filteredEvents[index];
                        return _buildEventTile(event, key: ValueKey(event.id));
                      },
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildEventTile(ProviderEvent event, {Key? key}) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final color = switch (event.type) {
      EventType.added =>
        isDark ? const Color(0xFF4CAF50) : const Color(0xFF2E7D32), // Green
      EventType.updated =>
        isDark ? const Color(0xFF2196F3) : const Color(0xFF1565C0), // Blue
      EventType.disposed =>
        isDark ? const Color(0xFFFF9800) : const Color(0xFFEF6C00), // Orange
      EventType.invalidate =>
        isDark ? const Color(0xFFEF5350) : const Color(0xFFC62828), // Red
      EventType.refresh =>
        isDark ? const Color(0xFF26C6DA) : const Color(0xFF00838F), // Cyan
      EventType.rebuild =>
        isDark ? const Color(0xFFAB47BC) : const Color(0xFF6A1B9A), // Purple
      EventType.dependencyChange =>
        isDark ? const Color(0xFFFFCA28) : const Color(0xFFF57F17), // Amber
      EventType.asyncComplete =>
        isDark ? const Color(0xFF9CCC65) : const Color(0xFF558B2F), // Lime
    };

    final backgroundColor = diffBackgroundColor(event.type, isDark);

    final icon = switch (event.type) {
      EventType.added => Icons.add_circle_outline,
      EventType.updated => Icons.change_circle_outlined,
      EventType.disposed => Icons.remove_circle_outline,
      EventType.invalidate => Icons.refresh_outlined,
      EventType.refresh => Icons.sync_outlined,
      EventType.rebuild => Icons.autorenew_outlined,
      EventType.dependencyChange => Icons.link_outlined,
      EventType.asyncComplete => Icons.check_circle_outline,
    };

    final isExpanded = _expandedEventIds.contains(event.id);

    // Calculate relative time from previous event for the same provider
    // The newest event shows the time difference from the previous (older) event
    String? relativeTime;
    final providerEvents = _eventsByProvider[event.providerName];
    if (providerEvents != null && providerEvents.length > 1) {
      final currentIndex = providerEvents.indexOf(event);
      // Events are sorted newest first, so index 0 is the newest
      // We want to show the time diff on newer events (smaller index)
      // comparing with older events (larger index)
      if (currentIndex >= 0 && currentIndex < providerEvents.length - 1) {
        // Get the next older event (at index currentIndex + 1)
        final olderEvent = providerEvents[currentIndex + 1];
        final timeDiff = event.timestamp.difference(olderEvent.timestamp);
        relativeTime = _formatRelativeTime(timeDiff);
      }
    }

    // Construct the summary subtitle (collapsed view)
    String summarySubtitle;
    switch (event.type) {
      case EventType.disposed:
        summarySubtitle = 'disposed';
        break;
      case EventType.invalidate:
        summarySubtitle = 'invalidated → ${event.getValueString()}';
        break;
      case EventType.refresh:
        summarySubtitle =
            'refreshed: ${event.getPreviousValueString()} → ${event.getValueString()}';
        break;
      case EventType.rebuild:
        summarySubtitle = 'rebuilt (same value)';
        break;
      case EventType.dependencyChange:
        summarySubtitle = 'dependencies changed';
        break;
      case EventType.asyncComplete:
        summarySubtitle = 'completed → ${event.getValueString()}';
        break;
      case EventType.updated:
        summarySubtitle =
            '${event.getPreviousValueString()} → ${event.getValueString()}';
        break;
      case EventType.added:
        summarySubtitle = event.getValueString();
        break;
    }

    // Check if we should treat this as "long text" for the expand/collapse arrow visibility
    // For updated events, we almost always want to allow expansion to see the diff clearly if it's not trivial
    // Disposed events should not be expandable
    final isLongText = event.type == EventType.disposed
        ? false
        : (summarySubtitle.length > 50 ||
            event.type == EventType.updated ||
            event.type == EventType.refresh ||
            event.type == EventType.invalidate ||
            event.type == EventType.asyncComplete);

    return Container(
      key: key,
      margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(4),
        border: Border(
          left: BorderSide(color: color, width: 2),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            splashFactory: NoSplash.splashFactory,
            highlightColor: Colors.transparent,
            onTap: isLongText
                ? () {
                    setState(() {
                      if (isExpanded) {
                        _expandedEventIds.remove(event.id);
                      } else {
                        _expandedEventIds.add(event.id);
                      }
                    });
                  }
                : null,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(6, 2, 6, 2),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header Row: Icon, ProviderName, Timestamp, Expand Arrow
                  Row(
                    children: [
                      Icon(icon, color: color, size: 14),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          event.providerName,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                            color: color,
                          ),
                        ),
                      ),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '${event.timestamp.hour.toString().padLeft(2, '0')}:'
                            '${event.timestamp.minute.toString().padLeft(2, '0')}:'
                            '${event.timestamp.second.toString().padLeft(2, '0')}',
                            style: TextStyle(
                                color: theme.colorScheme.onSurfaceVariant,
                                fontSize: 10),
                          ),
                          if (relativeTime != null) ...[
                            const SizedBox(width: 4),
                            Text(
                              relativeTime,
                              style: TextStyle(
                                color: theme.colorScheme.onSurfaceVariant
                                    .withValues(alpha: 0.7),
                                fontSize: 9,
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                          ],
                        ],
                      ),
                      if (isLongText) ...[
                        const SizedBox(width: 4),
                        Icon(
                          isExpanded ? Icons.expand_less : Icons.expand_more,
                          size: 16,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ],
                    ],
                  ),

                  // Content View
                  if (!isExpanded)
                    // Collapsed: Show summary (truncated)
                    Padding(
                      padding: const EdgeInsets.only(left: 20, top: 2),
                      child: Text(
                        summarySubtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 10,
                          fontFamily: 'monospace',
                          color: theme.colorScheme.onSurface,
                        ),
                      ),
                    )
                  else
                    // Expanded: Show detailed view
                    Padding(
                      padding:
                          const EdgeInsets.only(left: 20, top: 4, bottom: 4),
                      child: _buildExpandedContent(event),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildExpandedContent(ProviderEvent event) {
    if (event.type == EventType.updated) {
      // For updated events, show both previous and current as tree views
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildValueSection('Previous', event.previousValue, isPrevious: true),
          const SizedBox(height: 8),
          _buildValueSection('Current', event.value, isPrevious: false),
        ],
      );
    }

    // For Added / Disposed, show JSON tree view
    return _buildJsonTreeView(event.value);
  }

  Widget _buildValueSection(String label, Map<String, dynamic>? data,
      {required bool isPrevious}) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final labelColor = isPrevious
        ? (isDark ? const Color(0xFFFFB4AB) : const Color(0xFFD32F2F))
        : (isDark ? const Color(0xFF86EFAC) : const Color(0xFF2E7D32));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 9,
            fontWeight: FontWeight.bold,
            color: labelColor,
          ),
        ),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest
                .withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(2),
          ),
          child: _buildJsonTreeView(data),
        ),
      ],
    );
  }

  /// Format relative time difference for display
  String _formatRelativeTime(Duration duration) {
    final totalSeconds = duration.inSeconds;

    if (totalSeconds < 1) {
      final ms = duration.inMilliseconds;
      return '(+${ms}ms)';
    } else if (totalSeconds < 60) {
      return '(+${totalSeconds}s)';
    } else if (totalSeconds < 3600) {
      final minutes = totalSeconds ~/ 60;
      final seconds = totalSeconds % 60;
      return seconds > 0 ? '(+${minutes}m${seconds}s)' : '(+${minutes}m)';
    } else {
      final hours = totalSeconds ~/ 3600;
      final minutes = (totalSeconds % 3600) ~/ 60;
      return minutes > 0 ? '(+${hours}h${minutes}m)' : '(+${hours}h)';
    }
  }

  Color diffBackgroundColor(EventType type, bool isDark) {
    if (isDark) {
      return switch (type) {
        EventType.added => const Color(0xFF1B5E20).withValues(alpha: 0.2),
        EventType.updated => const Color(0xFF0D47A1).withValues(alpha: 0.2),
        EventType.disposed => const Color(0xFFE65100).withValues(alpha: 0.2),
        EventType.invalidate => const Color(0xFFB71C1C).withValues(alpha: 0.2),
        EventType.refresh => const Color(0xFF006064).withValues(alpha: 0.2),
        EventType.rebuild => const Color(0xFF4A148C).withValues(alpha: 0.2),
        EventType.dependencyChange =>
          const Color(0xFFF57F17).withValues(alpha: 0.2),
        EventType.asyncComplete => const Color(0xFF33691E).withValues(alpha: 0.2),
      };
    } else {
      return switch (type) {
        EventType.added => const Color(0xFFE8F5E9), // Light Green
        EventType.updated => const Color(0xFFE3F2FD), // Light Blue
        EventType.disposed => const Color(0xFFFFF3E0), // Light Orange
        EventType.invalidate => const Color(0xFFFFEBEE), // Light Red
        EventType.refresh => const Color(0xFFE0F7FA), // Light Cyan
        EventType.rebuild => const Color(0xFFF3E5F5), // Light Purple
        EventType.dependencyChange => const Color(0xFFFFF9C4), // Light Amber
        EventType.asyncComplete => const Color(0xFFF1F8E9), // Light Lime
      };
    }
  }

  /// Build JSON tree view with expand/collapse functionality
  Widget _buildJsonTreeView(Map<String, dynamic>? data) {
    if (data == null) {
      return const Text('null',
          style: TextStyle(fontSize: 10, fontFamily: 'monospace'));
    }

    // Always show as tree view - let users expand to see structure
    return _JsonTreeView(data: data, initiallyExpanded: true);
  }
}

/// A widget that displays JSON data in a tree structure with expand/collapse
class _JsonTreeView extends StatefulWidget {
  final Map<String, dynamic> data;
  final int indent;
  final bool initiallyExpanded;

  const _JsonTreeView({
    required this.data,
    this.indent = 0,
    this.initiallyExpanded = false,
  });

  @override
  State<_JsonTreeView> createState() => _JsonTreeViewState();
}

class _JsonTreeViewState extends State<_JsonTreeView> {
  final Set<String> _expandedKeys = {};

  @override
  void initState() {
    super.initState();
    // If initiallyExpanded is true, expand all top-level keys
    if (widget.initiallyExpanded) {
      for (final entry in widget.data.entries) {
        if (entry.value is Map || entry.value is List) {
          _expandedKeys.add(entry.key);
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final entries = widget.data.entries.toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: entries.map((entry) {
        final key = entry.key;
        final value = entry.value;
        final isExpanded = _expandedKeys.contains(key);

        // Determine if the value is expandable (Map or List)
        final isExpandable = value is Map || value is List;

        return Padding(
          padding: EdgeInsets.only(left: widget.indent * 16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              InkWell(
                onTap: isExpandable
                    ? () {
                        setState(() {
                          if (isExpanded) {
                            _expandedKeys.remove(key);
                          } else {
                            _expandedKeys.add(key);
                          }
                        });
                      }
                    : null,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    if (isExpandable)
                      SizedBox(
                        width: 14,
                        height: 14,
                        child: Icon(
                          isExpanded
                              ? Icons.arrow_drop_down
                              : Icons.arrow_right,
                          size: 14,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      )
                    else
                      const SizedBox(width: 14),
                    const SizedBox(width: 2),
                    Expanded(
                      child: RichText(
                        text: TextSpan(
                          style: TextStyle(
                            fontSize: 10,
                            fontFamily: 'monospace',
                            color: theme.colorScheme.onSurface,
                            height: 1.4,
                          ),
                          children: [
                            TextSpan(
                              text: '$key: ',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: theme.colorScheme.primary,
                              ),
                            ),
                            if (!isExpandable || !isExpanded)
                              TextSpan(
                                text: _formatValue(value),
                                style: TextStyle(
                                  color: _getValueColor(value, theme),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (isExpandable && isExpanded)
                Padding(
                  padding: const EdgeInsets.only(left: 16.0, top: 2),
                  child: _buildExpandedValue(value),
                ),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildExpandedValue(dynamic value) {
    if (value is Map) {
      return _JsonTreeView(
        data: Map<String, dynamic>.from(value),
        indent: widget.indent + 1,
      );
    } else if (value is List) {
      return _buildListView(value);
    }
    return const SizedBox.shrink();
  }

  Widget _buildListView(List list) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: List.generate(list.length, (index) {
        final item = list[index];
        final isExpandable = item is Map || item is List;
        final isExpanded = _expandedKeys.contains('[$index]');

        return Padding(
          padding: EdgeInsets.only(left: (widget.indent + 1) * 16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              InkWell(
                onTap: isExpandable
                    ? () {
                        setState(() {
                          final key = '[$index]';
                          if (isExpanded) {
                            _expandedKeys.remove(key);
                          } else {
                            _expandedKeys.add(key);
                          }
                        });
                      }
                    : null,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    if (isExpandable)
                      SizedBox(
                        width: 14,
                        height: 14,
                        child: Icon(
                          isExpanded
                              ? Icons.arrow_drop_down
                              : Icons.arrow_right,
                          size: 14,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      )
                    else
                      const SizedBox(width: 14),
                    const SizedBox(width: 2),
                    Expanded(
                      child: RichText(
                        text: TextSpan(
                          style: TextStyle(
                            fontSize: 10,
                            fontFamily: 'monospace',
                            color: theme.colorScheme.onSurface,
                            height: 1.4,
                          ),
                          children: [
                            TextSpan(
                              text: '[$index]: ',
                              style: TextStyle(
                                color: theme.colorScheme.primary
                                    .withValues(alpha: 0.7),
                              ),
                            ),
                            if (!isExpandable || !isExpanded)
                              TextSpan(
                                text: _formatValue(item),
                                style: TextStyle(
                                  color: _getValueColor(item, theme),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (isExpandable && isExpanded)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: _buildExpandedValue(item),
                ),
            ],
          ),
        );
      }),
    );
  }

  String _formatValue(dynamic value) {
    if (value == null) return 'null';
    if (value is String) return '"$value"';
    if (value is num || value is bool) return value.toString();
    if (value is List) return '[${value.length} items]';
    if (value is Map) return '{${value.length} keys}';
    return value.toString();
  }

  Color _getValueColor(dynamic value, ThemeData theme) {
    if (value == null) return theme.colorScheme.onSurfaceVariant;
    if (value is String) return const Color(0xFF4CAF50); // Green for strings
    if (value is num) return const Color(0xFF2196F3); // Blue for numbers
    if (value is bool) return const Color(0xFFFF9800); // Orange for booleans
    return theme.colorScheme.onSurface;
  }
}

enum ProviderStatus { active, disposed }

enum EventType {
  added,
  updated,
  disposed,
  invalidate,
  refresh,
  rebuild,
  dependencyChange,
  asyncComplete,
}

class ProviderInfo {
  final String id;
  final String name;
  final Map<String, dynamic> value;
  final ProviderStatus status;
  final List<String> dependencies;

  ProviderInfo({
    required this.id,
    required this.name,
    required this.value,
    required this.status,
    this.dependencies = const [],
  });

  /// Get string representation of value for display
  String getValueString() {
    // If it has 'string', use that
    if (value.containsKey('string')) {
      return value['string'] as String;
    }
    // Otherwise, try to convert value to string
    if (value.containsKey('value')) {
      return value['value']?.toString() ?? 'null';
    }
    return value.toString();
  }
}

class ProviderEvent {
  final EventType type;
  final String providerId;
  final String providerName;
  final Map<String, dynamic>? previousValue;
  final Map<String, dynamic>? value;
  final DateTime timestamp;

  /// Unique ID for this event (used for expansion state tracking)
  late final String id;

  ProviderEvent({
    required this.type,
    required this.providerId,
    required this.providerName,
    this.previousValue,
    this.value,
    required this.timestamp,
  }) {
    // Generate unique ID based on timestamp and provider ID
    id = '${timestamp.microsecondsSinceEpoch}_$providerId';
  }

  /// Get string representation for display
  String getValueString() {
    if (value == null) return 'null';
    return _formatValueForDisplay(value!);
  }

  String getPreviousValueString() {
    if (previousValue == null) return 'null';
    return _formatValueForDisplay(previousValue!);
  }

  String _formatValueForDisplay(Map<String, dynamic> data) {
    // If it has 'string', use that
    if (data.containsKey('string')) {
      return data['string'] as String;
    }
    // Otherwise, try to convert value to string
    if (data.containsKey('value')) {
      return data['value']?.toString() ?? 'null';
    }
    return data.toString();
  }
}
