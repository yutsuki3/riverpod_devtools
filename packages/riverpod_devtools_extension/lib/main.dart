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

  /// The currently active tab (provider name) when multiple providers are selected
  String? _activeTabProviderName;

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

  /// Provider name currently being flashed in the list
  String? _flashingProviderName;

  /// Timer for controlling flash animation
  Timer? _flashTimer;

  @override
  void initState() {
    super.initState();
    _subscribeToEvents();
  }

  @override
  void dispose() {
    _extensionSubscription?.cancel();
    _flashTimer?.cancel();
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

  /// Flash a provider in the list to highlight it
  void _flashProvider(String providerName) {
    _flashTimer?.cancel();

    setState(() {
      _flashingProviderName = providerName;
    });

    // Flash twice (on-off-on-off) over 600ms
    int flashCount = 0;
    _flashTimer = Timer.periodic(const Duration(milliseconds: 150), (timer) {
      flashCount++;
      if (flashCount >= 4) {
        timer.cancel();
        setState(() {
          _flashingProviderName = null;
        });
      } else {
        setState(() {
          // Toggle flash state
          _flashingProviderName = flashCount.isEven ? null : providerName;
        });
      }
    });
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
          _providers[providerName] = ProviderInfo(
            id: providerId,
            name: providerName,
            value: value,
            status: ProviderStatus.active,
            dependencies: dependencies,
          );
          _addEvent(ProviderEvent(
            type: EventType.updated,
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
                    _activeTabProviderName = null;
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
                          _activeTabProviderName = null;
                        });
                      },
                      child: ListView.builder(
                        itemCount: filteredProviders.length,
                        itemBuilder: (context, index) {
                          final provider = filteredProviders[index];
                          final isSelected =
                              _selectedProviderNames.contains(provider.name);
                          final isFlashing =
                              _flashingProviderName == provider.name;
                          return Theme(
                            data: Theme.of(context).copyWith(
                              splashFactory: NoSplash.splashFactory,
                              highlightColor: Colors.transparent,
                            ),
                            child: Listener(
                              onPointerDown: (event) {
                                setState(() {
                                  final isCtrlOrCmd =
                                      event.kind == PointerDeviceKind.mouse &&
                                          (HardwareKeyboard
                                                  .instance.isMetaPressed ||
                                              HardwareKeyboard
                                                  .instance.isControlPressed);

                                  if (isCtrlOrCmd) {
                                    // Multi-selection mode: toggle
                                    if (isSelected) {
                                      _selectedProviderNames
                                          .remove(provider.name);
                                      // If removed the active tab, update it
                                      if (_activeTabProviderName ==
                                          provider.name) {
                                        _activeTabProviderName =
                                            _selectedProviderNames.isNotEmpty
                                                ? _selectedProviderNames.first
                                                : null;
                                      }
                                    } else {
                                      _selectedProviderNames.add(provider.name);
                                      // If this is the first selection or active tab is not set, set it
                                      if (_activeTabProviderName == null ||
                                          !_selectedProviderNames.contains(
                                              _activeTabProviderName)) {
                                        _activeTabProviderName = provider.name;
                                      }
                                    }
                                  } else {
                                    // Single selection mode
                                    if (isSelected &&
                                        _selectedProviderNames.length == 1) {
                                      // If clicking the only selected provider, deselect it
                                      _selectedProviderNames.clear();
                                      _activeTabProviderName = null;
                                    } else {
                                      // Otherwise, select only this one
                                      _selectedProviderNames.clear();
                                      _selectedProviderNames.add(provider.name);
                                      _activeTabProviderName = provider.name;
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
                                  color: isFlashing
                                      ? theme.colorScheme.primary
                                          .withValues(alpha: 0.3)
                                      : isSelected
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
                                            : theme
                                                .colorScheme.onSurfaceVariant,
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

        // Tabs (only show when multiple providers selected)
        if (_selectedProviderNames.length > 1)
          Container(
            height: 28,
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: theme.colorScheme.outline.withValues(alpha: 0.2),
                ),
              ),
            ),
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: _selectedProviderNames.map((providerName) {
                final isActive = _activeTabProviderName == providerName;
                return InkWell(
                  onTap: () {
                    setState(() {
                      _activeTabProviderName = providerName;
                    });
                  },
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: isActive
                          ? theme.colorScheme.primary.withValues(alpha: 0.1)
                          : null,
                      border: isActive
                          ? Border(
                              bottom: BorderSide(
                                color: theme.colorScheme.primary,
                                width: 2,
                              ),
                            )
                          : null,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          providerName.length > 20
                              ? '${providerName.substring(0, 20)}...'
                              : providerName,
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight:
                                isActive ? FontWeight.bold : FontWeight.normal,
                            color: isActive
                                ? theme.colorScheme.primary
                                : theme.colorScheme.onSurface,
                          ),
                        ),
                        const SizedBox(width: 4),
                        InkWell(
                          onTap: () {
                            setState(() {
                              _selectedProviderNames.remove(providerName);
                              if (_activeTabProviderName == providerName) {
                                _activeTabProviderName =
                                    _selectedProviderNames.isNotEmpty
                                        ? _selectedProviderNames.first
                                        : null;
                              }
                            });
                          },
                          child: Icon(
                            Icons.close,
                            size: 12,
                            color: theme.colorScheme.onSurfaceVariant
                                .withValues(alpha: 0.6),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
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
                    // Determine which provider to display
                    String displayProviderName;
                    if (_selectedProviderNames.length == 1) {
                      displayProviderName = _selectedProviderNames.first;
                    } else {
                      // Multiple selection: use active tab or first selected
                      if (_activeTabProviderName != null &&
                          _selectedProviderNames
                              .contains(_activeTabProviderName)) {
                        displayProviderName = _activeTabProviderName!;
                      } else {
                        displayProviderName = _selectedProviderNames.first;
                        _activeTabProviderName = displayProviderName;
                      }
                    }

                    final provider = _providers[displayProviderName];
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
                final isSelected = _selectedProviderNames.contains(name);
                final isActive = _activeTabProviderName == name;

                return Tooltip(
                  message: isActive
                      ? 'Currently viewing $name'
                      : isSelected
                          ? 'Jump to $name'
                          : 'Add $name to selection',
                  child: InkWell(
                    onTap: () {
                      setState(() {
                        if (!isSelected) {
                          _selectedProviderNames.add(name);
                        } else {
                          _activeTabProviderName = name;
                        }
                      });
                      // Flash the provider in the list to highlight it
                      _flashProvider(name);
                    },
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 6),
                      margin: const EdgeInsets.only(bottom: 2),
                      decoration: BoxDecoration(
                        color: isActive
                            ? theme.colorScheme.primary
                            : isSelected
                                ? theme.colorScheme.primary
                                    .withValues(alpha: 0.08)
                                : theme.colorScheme.surfaceContainerHighest
                                    .withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                          color: isActive
                              ? theme.colorScheme.primary
                              : isSelected
                                  ? theme.colorScheme.primary
                                      .withValues(alpha: 0.5)
                                  : theme.colorScheme.outline
                                      .withValues(alpha: 0.1),
                          width: 1,
                          style: isSelected && !isActive
                              ? BorderStyle.solid
                              : BorderStyle.solid,
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            isActive
                                ? Icons.visibility
                                : isSelected
                                    ? Icons.open_in_new
                                    : Icons.add,
                            size: 12,
                            color: isActive
                                ? theme.colorScheme.onPrimary
                                : theme.colorScheme.primary,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              name,
                              style: TextStyle(
                                fontSize: 10,
                                fontFamily: 'monospace',
                                color: isActive
                                    ? theme.colorScheme.onPrimary
                                    : isSelected
                                        ? theme.colorScheme.primary
                                        : theme.colorScheme.onSurfaceVariant,
                                fontWeight: isActive || isSelected
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
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
    };

    final backgroundColor = diffBackgroundColor(event.type, isDark);

    final icon = switch (event.type) {
      EventType.added => Icons.add_circle_outline,
      EventType.updated => Icons.change_circle_outlined,
      EventType.disposed => Icons.remove_circle_outline,
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
    if (event.type == EventType.disposed) {
      summarySubtitle = 'disposed';
    } else if (event.type == EventType.updated) {
      summarySubtitle =
          '${event.getPreviousValueString()} → ${event.getValueString()}';
    } else {
      summarySubtitle = event.getValueString();
    }

    // Check if we should treat this as "long text" for the expand/collapse arrow visibility
    // For updated events, we almost always want to allow expansion to see the diff clearly if it's not trivial
    // Disposed events should not be expandable
    final isLongText = event.type == EventType.disposed
        ? false
        : (summarySubtitle.length > 50 || event.type == EventType.updated);

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
      };
    } else {
      return switch (type) {
        EventType.added => const Color(0xFFE8F5E9), // Light Green
        EventType.updated => const Color(0xFFE3F2FD), // Light Blue
        EventType.disposed => const Color(0xFFFFF3E0), // Light Orange
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

  /// Number of items to show by default for large collections
  static const int _loadLimit = 50;

  /// Keys that are currently showing more items
  final Set<String> _showingMoreKeys = {};

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
    final allEntries = widget.data.entries.toList();
    final bool isLarge = allEntries.length > _loadLimit;
    final bool showingMore = _showingMoreKeys.contains('__root__');

    final entries = (isLarge && !showingMore)
        ? allEntries.take(_loadLimit).toList()
        : allEntries;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ...entries.map((entry) {
          final key = entry.key;
          final value = entry.value;
          final isExpanded = _expandedKeys.contains(key);

          // Determine if the value is expandable (Map or List)
          final isExpandable = value is Map || value is List;

          return Padding(
            padding: EdgeInsets.only(left: widget.indent * 8.0),
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
                    padding: const EdgeInsets.only(left: 8.0, top: 2),
                    child: _buildExpandedValue(value, key),
                  ),
              ],
            ),
          );
        }),
        if (isLarge && !showingMore)
          Padding(
            padding: EdgeInsets.only(left: (widget.indent * 8.0) + 16),
            child: TextButton(
              onPressed: () => setState(() => _showingMoreKeys.add('__root__')),
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text(
                'Show ${allEntries.length - _loadLimit} more items...',
                style: const TextStyle(fontSize: 10),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildExpandedValue(dynamic value, String parentKey) {
    if (value is Map) {
      return _JsonTreeView(
        data: Map<String, dynamic>.from(value),
        indent: widget.indent + 1,
      );
    } else if (value is List) {
      return _buildListView(value, parentKey);
    }
    return const SizedBox.shrink();
  }

  Widget _buildListView(List list, String parentKey) {
    final theme = Theme.of(context);
    final bool isLarge = list.length > _loadLimit;
    final bool showingMore = _showingMoreKeys.contains(parentKey);

    final displayList =
        (isLarge && !showingMore) ? list.take(_loadLimit).toList() : list;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ...List.generate(displayList.length, (index) {
          final item = displayList[index];
          final isExpandable = item is Map || item is List;
          final itemKey = '$parentKey[$index]';
          final isExpanded = _expandedKeys.contains(itemKey);

          return Padding(
            padding: EdgeInsets.only(left: (widget.indent + 1) * 8.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                InkWell(
                  onTap: isExpandable
                      ? () {
                          setState(() {
                            if (isExpanded) {
                              _expandedKeys.remove(itemKey);
                            } else {
                              _expandedKeys.add(itemKey);
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
                    child: _buildExpandedValue(item, itemKey),
                  ),
              ],
            ),
          );
        }),
        if (isLarge && !showingMore)
          Padding(
            padding: EdgeInsets.only(left: ((widget.indent + 1) * 8.0) + 16),
            child: TextButton(
              onPressed: () => setState(() => _showingMoreKeys.add(parentKey)),
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text(
                'Show ${list.length - _loadLimit} more items...',
                style: const TextStyle(fontSize: 10),
              ),
            ),
          ),
      ],
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

enum EventType { added, updated, disposed }

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

  String? _valueStringCache;

  /// Get string representation of value for display
  String getValueString() {
    if (_valueStringCache != null) return _valueStringCache!;

    // If it has 'string', use that
    if (value.containsKey('string')) {
      return _valueStringCache = value['string'] as String;
    }

    // Otherwise, try to convert value to string
    if (value.containsKey('value')) {
      final rawValue = value['value'];
      return _valueStringCache = _safeToString(rawValue);
    }

    return _valueStringCache = _safeToString(value);
  }

  String _safeToString(dynamic value) {
    if (value == null) return 'null';
    if (value is String) return value;
    if (value is num || value is bool) return value.toString();

    if (value is List) {
      if (value.length > 10) {
        return '[${value.take(10).map((e) => _safeToString(e)).join(', ')}, ...]';
      }
      return value.toString();
    }
    if (value is Map) {
      if (value.length > 5) {
        final entries = value.entries
            .take(5)
            .map((e) => '${e.key}: ${_safeToString(e.value)}')
            .join(', ');
        return '{$entries, ...}';
      }
      return value.toString();
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

  String? _valueStringCache;
  String? _previousValueStringCache;

  /// Get string representation for display
  String getValueString() {
    if (value == null) return 'null';
    return _valueStringCache ??= _formatValueForDisplay(value!);
  }

  String getPreviousValueString() {
    if (previousValue == null) return 'null';
    return _previousValueStringCache ??= _formatValueForDisplay(previousValue!);
  }

  String _formatValueForDisplay(Map<String, dynamic> data) {
    // If it has 'string', use that
    if (data.containsKey('string')) {
      return data['string'] as String;
    }
    // Otherwise, try to convert value to string
    if (data.containsKey('value')) {
      return _safeToString(data['value']);
    }
    return _safeToString(data);
  }

  String _safeToString(dynamic value) {
    if (value == null) return 'null';
    if (value is String) return value;
    if (value is num || value is bool) return value.toString();

    if (value is List) {
      if (value.length > 10) {
        return '[${value.take(10).map((e) => _safeToString(e)).join(', ')}, ...]';
      }
      return value.toString();
    }
    if (value is Map) {
      if (value.length > 5) {
        final entries = value.entries
            .take(5)
            .map((e) => '${e.key}: ${_safeToString(e.value)}')
            .join(', ');
        return '{$entries, ...}';
      }
      return value.toString();
    }
    return value.toString();
  }
}
