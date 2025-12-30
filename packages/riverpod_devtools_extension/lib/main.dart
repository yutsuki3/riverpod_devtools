import 'dart:async';
import 'package:devtools_extensions/devtools_extensions.dart';
import 'package:diff_match_patch/diff_match_patch.dart';
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
  final List<ProviderEvent> _events = [];
  final Map<String, ProviderInfo> _providers = {};

  /// The set of provider names that are currently selected for filtering.
  /// If empty, no filtering is applied (all events are shown).
  final Set<String> _selectedProviderNames = {};
  StreamSubscription? _extensionSubscription;
  final Set<String> _processedEventKeys = {};
  final Set<int> _expandedEventIndices = {};

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
      final value = (data['newValue'] ?? data['value'])?.toString() ?? 'null';
      final timestamp = data['timestamp'] as int?;

      // Create a unique key for this event to deduplicate
      // Format: kind:providerId:value
      // We don't use timestamp in the key because we WANT to deduplicate
      // identically valued updates that happen inside the same logical "tick"
      final eventKey = '$kind:$providerId:$value';

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
          _events.insert(
              0,
              ProviderEvent(
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
          _events.insert(
              0,
              ProviderEvent(
                type: EventType.updated,
                providerId: providerId,
                providerName: providerName,
                previousValue: data['previousValue']?.toString(),
                value: value,
                timestamp: eventTimestamp,
              ));
        } else if (kind == 'riverpod:provider_disposed') {
          _providers[providerName] = ProviderInfo(
            id: providerId,
            name: providerName,
            value: _providers[providerName]?.value ?? 'null',
            status: ProviderStatus.disposed,
          );
          _events.insert(
              0,
              ProviderEvent(
                type: EventType.disposed,
                providerId: providerId,
                providerName: providerName,
                timestamp: eventTimestamp,
              ));
        }
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          flex: 1,
          child: _buildProviderList(),
        ),
        const VerticalDivider(width: 1),
        Expanded(
          flex: 2,
          child: _buildEventLog(),
        ),
      ],
    );
  }

  Widget _buildProviderList() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          color: Colors.grey[900],
          width: double.infinity,
          height: 32,
          alignment: Alignment.centerLeft,
          child: Row(
            children: [
              Text(
                'Providers (${_providers.length})',
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
                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
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
                      child: ListTile(
                        dense: true,
                        selected: isSelected,
                        selectedTileColor: Colors.blue.withOpacity(0.1),
                        onTap: () {
                          setState(() {
                            if (isSelected) {
                              _selectedProviderNames.remove(provider.name);
                            } else {
                              _selectedProviderNames.add(provider.name);
                            }
                          });
                        },
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 0,
                        ),
                        minVerticalPadding: 2,
                        visualDensity: const VisualDensity(
                          horizontal: -4,
                          vertical: -4,
                        ),
                        leading: Icon(
                          provider.status == ProviderStatus.active
                              ? Icons.circle
                              : Icons.circle_outlined,
                          size: 10,
                          color: provider.status == ProviderStatus.active
                              ? Colors.greenAccent
                              : Colors.grey[600],
                        ),
                        title: Text(
                          provider.name,
                          style: const TextStyle(fontSize: 11),
                        ),
                        subtitle: Text(
                          provider.value,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 10,
                            color: Colors.grey[500],
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          color: Colors.grey[900],
          width: double.infinity,
          height: 32,
          alignment: Alignment.centerLeft,
          child: Row(
            children: [
              const Text(
                'Event Log',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.delete_outline, size: 16),
                onPressed: () => setState(() {
                  _events.clear();
                  _expandedEventIndices.clear();
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
                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  ),
                )
              : Builder(
                  builder: (context) {
                    final filteredEvents = _selectedProviderNames.isEmpty
                        ? _events
                        : _events
                            .where((e) =>
                                _selectedProviderNames.contains(e.providerName))
                            .toList();

                    if (filteredEvents.isEmpty) {
                      return Center(
                        child: Text(
                          'No events found for selected providers',
                          style:
                              TextStyle(fontSize: 12, color: Colors.grey[600]),
                        ),
                      );
                    }

                    return ListView.builder(
                      itemCount: filteredEvents.length,
                      itemBuilder: (context, index) {
                        final event = filteredEvents[index];
                        // We need to pass the original index or handle expansion state correctly if it depends on index.
                        // However, _expandedEventIndices tracks by index.
                        // If we filter, indices shift.
                        // A better way for expansion is to track by event instance or some ID.
                        // But for now, let's see if we can just disable unique expansion tracking or map it.
                        // The current _buildEventTile uses 'index' for expansion state: _expandedEventIndices.contains(index).
                        // If we filter, 'index' 0 is different.
                        // The simplest fix for now without large refactor is to find the original index.
                        final originalIndex = _events.indexOf(event);
                        return _buildEventTile(event, originalIndex);
                      },
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildEventTile(ProviderEvent event, int index) {
    final color = switch (event.type) {
      EventType.added => const Color(0xFF4CAF50), // Green
      EventType.updated => const Color(0xFF2196F3), // Blue
      EventType.disposed => const Color(0xFFFF9800), // Orange
    };

    final backgroundColor = switch (event.type) {
      EventType.added => const Color(0xFF1B5E20).withOpacity(0.2),
      EventType.updated => const Color(0xFF0D47A1).withOpacity(0.2),
      EventType.disposed => const Color(0xFFE65100).withOpacity(0.2),
    };

    final icon = switch (event.type) {
      EventType.added => Icons.add_circle_outline,
      EventType.updated => Icons.change_circle_outlined,
      EventType.disposed => Icons.remove_circle_outline,
    };

    final isExpanded = _expandedEventIndices.contains(index);

    // Construct the summary subtitle (collapsed view)
    String summarySubtitle;
    if (event.type == EventType.updated) {
      summarySubtitle = '${event.previousValue} → ${event.value}';
    } else {
      summarySubtitle = event.value ??
          (event.type == EventType.disposed ? 'disposed' : 'null');
    }

    // Check if we should treat this as "long text" for the expand/collapse arrow visibility
    // For updated events, we almost always want to allow expansion to see the diff clearly if it's not trivial
    final isLongText =
        summarySubtitle.length > 50 || event.type == EventType.updated;

    return Container(
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
                        _expandedEventIndices.remove(index);
                      } else {
                        _expandedEventIndices.add(index);
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
                        style: TextStyle(color: Colors.grey[600], fontSize: 10),
                      ),
                      if (isLongText) ...[
                        const SizedBox(width: 4),
                        Icon(
                          isExpanded ? Icons.expand_less : Icons.expand_more,
                          size: 16,
                          color: Colors.grey[600],
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
                        style: const TextStyle(
                          fontSize: 10,
                          fontFamily: 'monospace',
                          color: Colors.grey,
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
      final oldText = event.previousValue ?? '';
      final newText = event.value ?? '';
      final diffs = diff(oldText, newText);

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildDiffBlock('Previous', diffs, isPrevious: true),
          const SizedBox(height: 4),
          _buildDiffBlock('Current', diffs, isPrevious: false),
        ],
      );
    }

    // For Added / Disposed, just show the value full
    return SelectableText(
      event.value ?? 'null',
      style: const TextStyle(
        fontSize: 10,
        fontFamily: 'monospace',
      ),
    );
  }

  Widget _buildDiffBlock(String label, List<Diff> diffs,
      {required bool isPrevious}) {
    final labelColor = isPrevious
        ? const Color(0xFFFFB4AB) // Soft Red/Pink for Previous label
        : const Color(0xFF86EFAC); // Soft Green for Current label

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
            color: Colors.black12,
            borderRadius: BorderRadius.circular(2),
          ),
          child: SelectableText.rich(
            TextSpan(
              children: diffs.map((d) {
                final text = d.text;
                if (isPrevious) {
                  // In "Previous", we show EQUAL and DELETE.
                  // DELETE is highlighted. INSERT is skipped.
                  if (d.operation == DIFF_INSERT) {
                    return const TextSpan();
                  }
                  final isDelete = d.operation == DIFF_DELETE;
                  return TextSpan(
                    text: text,
                    style: TextStyle(
                      fontSize: 10,
                      fontFamily: 'monospace',
                      backgroundColor: isDelete
                          ? const Color(0xFF442D2D) // Muted Dark Red bg
                          : null,
                      color: isDelete
                          ? const Color(0xFFFFB4AB) // Soft Red/Pink fg
                          : null,
                    ),
                  );
                } else {
                  // In "Current", we show EQUAL and INSERT.
                  // INSERT is highlighted. DELETE is skipped.
                  if (d.operation == DIFF_DELETE) {
                    return const TextSpan();
                  }
                  final isInsert = d.operation == DIFF_INSERT;
                  return TextSpan(
                    text: text,
                    style: TextStyle(
                      fontSize: 10,
                      fontFamily: 'monospace',
                      backgroundColor: isInsert
                          ? const Color(0xFF2D4431) // Muted Dark Green bg
                          : null,
                      color: isInsert
                          ? const Color(0xFF86EFAC) // Soft Green fg
                          : null,
                    ),
                  );
                }
              }).toList(),
            ),
          ),
        ),
      ],
    );
  }
}

enum ProviderStatus { active, disposed }

enum EventType { added, updated, disposed }

class ProviderInfo {
  final String id;
  final String name;
  final String value;
  final ProviderStatus status;

  ProviderInfo({
    required this.id,
    required this.name,
    required this.value,
    required this.status,
  });
}

class ProviderEvent {
  final EventType type;
  final String providerId;
  final String providerName;
  final String? previousValue;
  final String? value;
  final DateTime timestamp;

  ProviderEvent({
    required this.type,
    required this.providerId,
    required this.providerName,
    this.previousValue,
    this.value,
    required this.timestamp,
  });
}
