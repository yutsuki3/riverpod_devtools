import 'dart:async';
import 'package:devtools_extensions/devtools_extensions.dart';
import 'package:flutter/material.dart';
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

  /// The set of provider names that are currently selected for filtering.
  /// If empty, no filtering is applied (all events are shown).
  final Set<String> _selectedProviderNames = {};
  StreamSubscription? _extensionSubscription;
  final Set<String> _processedEventKeys = {};

  /// ID-based expansion state (instead of index-based)
  final Set<String> _expandedEventIds = {};

  /// Split ratio for the resizable divider (0.0 to 1.0)
  /// Represents the fraction of width allocated to the provider list
  double _splitRatio = 0.33;

  @override
  void initState() {
    super.initState();
    _subscribeToEvents();
  }

  @override
  void dispose() {
    _extensionSubscription?.cancel();
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

  /// Get filtered events using index structure for performance
  List<ProviderEvent> get _filteredEvents {
    if (_selectedProviderNames.isEmpty) return _events;

    final result = <ProviderEvent>[];
    for (final name in _selectedProviderNames) {
      final providerEvents = _eventsByProvider[name];
      if (providerEvents != null) {
        result.addAll(providerEvents);
      }
    }
    // Sort by timestamp (newest first)
    result.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final totalWidth = constraints.maxWidth;
        final providerListWidth = totalWidth * _splitRatio;
        const dividerWidth = 4.0;
        final eventLogWidth = totalWidth - providerListWidth - dividerWidth;

        return Row(
          children: [
            SizedBox(
              width: providerListWidth,
              child: _buildProviderList(),
            ),
            GestureDetector(
              behavior: HitTestBehavior.translucent,
              onHorizontalDragUpdate: (details) {
                setState(() {
                  final newRatio = _splitRatio + details.delta.dx / totalWidth;
                  // Constrain ratio between 0.2 and 0.8 to prevent panels from becoming too small
                  _splitRatio = newRatio.clamp(0.2, 0.8);
                });
              },
              child: MouseRegion(
                cursor: SystemMouseCursors.resizeColumn,
                child: Container(
                  width: dividerWidth,
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
            ),
            SizedBox(
              width: eventLogWidth,
              child: _buildEventLog(),
            ),
          ],
        );
      },
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
              Text(
                _selectedProviderNames.isEmpty
                    ? 'Providers'
                    : 'Providers (${_selectedProviderNames.length})',
                style: const TextStyle(
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
                  child: const Text('Show All', style: TextStyle(fontSize: 10)),
                ),
            ],
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
              : ListView.builder(
                  itemCount: _providers.length,
                  itemBuilder: (context, index) {
                    final provider = _providers.values.elementAt(index);
                    final isSelected =
                        _selectedProviderNames.contains(provider.name);
                    return Theme(
                      data: Theme.of(context).copyWith(
                        splashFactory: NoSplash.splashFactory,
                        highlightColor: Colors.transparent,
                      ),
                      child: InkWell(
                        onTap: () {
                          setState(() {
                            if (isSelected) {
                              _selectedProviderNames.remove(provider.name);
                            } else {
                              _selectedProviderNames.add(provider.name);
                            }
                          });
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          color: isSelected
                              ? theme.colorScheme.primary.withValues(alpha: 0.1)
                              : null,
                          child: Row(
                            children: [
                              Icon(
                                provider.status == ProviderStatus.active
                                    ? Icons.circle
                                    : Icons.circle_outlined,
                                size: 8,
                                color: provider.status == ProviderStatus.active
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
                    );
                  },
                ),
        ),
      ],
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
                    : 'Event Log (Filtered)',
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

    // Construct the summary subtitle (collapsed view)
    String summarySubtitle;
    if (event.type == EventType.updated) {
      summarySubtitle =
          '${event.getPreviousValueString()} → ${event.getValueString()}';
    } else {
      summarySubtitle = event.getValueString();
    }

    // Check if we should treat this as "long text" for the expand/collapse arrow visibility
    // For updated events, we almost always want to allow expansion to see the diff clearly if it's not trivial
    final isLongText =
        summarySubtitle.length > 50 || event.type == EventType.updated;

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
                      Text(
                        '${event.timestamp.hour.toString().padLeft(2, '0')}:'
                        '${event.timestamp.minute.toString().padLeft(2, '0')}:'
                        '${event.timestamp.second.toString().padLeft(2, '0')}',
                        style: TextStyle(
                            color: theme.colorScheme.onSurfaceVariant,
                            fontSize: 10),
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
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (isExpandable)
                      Icon(
                        isExpanded ? Icons.arrow_drop_down : Icons.arrow_right,
                        size: 16,
                        color: theme.colorScheme.onSurfaceVariant,
                      )
                    else
                      const SizedBox(width: 16),
                    Expanded(
                      child: RichText(
                        text: TextSpan(
                          style: TextStyle(
                            fontSize: 10,
                            fontFamily: 'monospace',
                            color: theme.colorScheme.onSurface,
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
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (isExpandable)
                      Icon(
                        isExpanded ? Icons.arrow_drop_down : Icons.arrow_right,
                        size: 16,
                        color: theme.colorScheme.onSurfaceVariant,
                      )
                    else
                      const SizedBox(width: 16),
                    Expanded(
                      child: RichText(
                        text: TextSpan(
                          style: TextStyle(
                            fontSize: 10,
                            fontFamily: 'monospace',
                            color: theme.colorScheme.onSurface,
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

enum EventType { added, updated, disposed }

class ProviderInfo {
  final String id;
  final String name;
  final Map<String, dynamic> value;
  final ProviderStatus status;

  ProviderInfo({
    required this.id,
    required this.name,
    required this.value,
    required this.status,
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
