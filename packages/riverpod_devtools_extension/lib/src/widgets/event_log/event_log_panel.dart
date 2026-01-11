import 'package:flutter/material.dart';
import '../../models/event_type.dart';
import '../../models/provider_event.dart';
import '../../providers/inspector_notifier.dart';
import '../../utils/color_utils.dart';
import '../../utils/time_utils.dart';
import '../common/json_tree_view.dart';

class EventLogPanel extends StatelessWidget {
  final InspectorNotifier notifier;

  const EventLogPanel({
    super.key,
    required this.notifier,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ListenableBuilder(
      listenable: notifier,
      builder: (context, child) {
        final state = notifier.state;
        final filteredEvents = notifier.filteredEvents;

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
                    state.selectedProviderNames.isEmpty
                        ? 'Event Log'
                        : state.selectedProviderNames.length == 1
                            ? 'Event Log (${state.selectedProviderNames.first})'
                            : 'Event Log (${state.selectedProviderNames.length} providers)',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.delete_outline, size: 16),
                    onPressed: () {
                      // Logic to clear events is not implemented yet in notifier, so we leave it no-op or implement it if requested.
                    },
                    tooltip: 'Clear All',
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    iconSize: 16,
                  ),
                ],
              ),
            ),
            Expanded(
              child: state.events.isEmpty
                  ? Center(
                      child: Text(
                        'No events yet',
                        style: TextStyle(
                          fontSize: 12,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    )
                  : filteredEvents.isEmpty
                      ? Center(
                          child: Text(
                            'No events found for selected providers',
                            style: TextStyle(
                              fontSize: 12,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        )
                      : ListView.builder(
                          itemCount: filteredEvents.length,
                          itemBuilder: (context, index) {
                            final event = filteredEvents[index];
                            final prevEvent = index + 1 < filteredEvents.length
                                ? filteredEvents[index + 1]
                                : null;
                            final timeDiff = prevEvent != null
                                ? event.timestamp
                                    .difference(prevEvent.timestamp)
                                : null;

                            return _EventTile(
                              event: event,
                              notifier: notifier,
                              timeDiffString: timeDiff != null
                                  ? formatTimeDiff(timeDiff)
                                  : null,
                              key: ValueKey(event.id),
                            );
                          },
                        ),
            ),
          ],
        );
      },
    );
  }
}

class _EventTile extends StatelessWidget {
  final ProviderEvent event;
  final InspectorNotifier notifier;
  final String? timeDiffString;

  const _EventTile({
    super.key,
    required this.event,
    required this.notifier,
    this.timeDiffString,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final state = notifier.state;

    final semanticColor = getEventColor(event.type, isDark);

    final backgroundColor = isDark
        ? Colors.white.withValues(alpha: 0.03)
        : Colors.black.withValues(alpha: 0.02);

    final icon = switch (event.type) {
      EventType.added => Icons.add_circle_outline,
      EventType.updated => Icons.change_circle_outlined,
      EventType.disposed => Icons.remove_circle_outline,
    };

    final isExpanded = state.expandedEventIds.contains(event.id);

    String summarySubtitle;
    if (event.type == EventType.disposed) {
      summarySubtitle = 'disposed';
    } else if (event.type == EventType.updated) {
      summarySubtitle =
          '${event.getPreviousValueString()} → ${event.getValueString()}';
    } else {
      summarySubtitle = event.getValueString();
    }

    final isLongText = event.type == EventType.disposed
        ? false
        : (summarySubtitle.length > 50 || event.type == EventType.updated);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(4),
        border: Border(
          left: BorderSide(color: semanticColor, width: 3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            splashFactory: NoSplash.splashFactory,
            highlightColor: Colors.transparent,
            onTap: isLongText
                ? () => notifier.toggleEventExpansion(event.id)
                : null,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 6, 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(icon, color: semanticColor, size: 14),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          event.providerName,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                            color: semanticColor,
                          ),
                        ),
                      ),
                      Text(
                        '${event.timestamp.hour.toString().padLeft(2, '0')}:'
                        '${event.timestamp.minute.toString().padLeft(2, '0')}:'
                        '${event.timestamp.second.toString().padLeft(2, '0')}',
                        style: TextStyle(
                            color: theme.colorScheme.onSurfaceVariant
                                .withValues(alpha: 0.8),
                            fontSize: 10),
                      ),
                      if (timeDiffString != null &&
                          timeDiffString!.isNotEmpty) ...[
                        const SizedBox(width: 4),
                        Text(
                          timeDiffString!,
                          style: TextStyle(
                            fontSize: 10,
                            color: theme.colorScheme.onSurfaceVariant
                                .withValues(alpha: 0.5),
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ],
                      if (isLongText) ...[
                        const SizedBox(width: 4),
                        Icon(
                          isExpanded ? Icons.expand_less : Icons.expand_more,
                          size: 16,
                          color: theme.colorScheme.onSurfaceVariant
                              .withValues(alpha: 0.5),
                        ),
                      ],
                    ],
                  ),
                  if (!isExpanded)
                    Padding(
                      padding: const EdgeInsets.only(left: 22, top: 4),
                      child: Text(
                        summarySubtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 10,
                          fontFamily: 'monospace',
                          color: theme.colorScheme.onSurface
                              .withValues(alpha: 0.8),
                        ),
                      ),
                    )
                  else
                    Padding(
                      padding:
                          const EdgeInsets.only(left: 22, top: 6, bottom: 4),
                      child: _buildExpandedContent(theme, event),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildExpandedContent(ThemeData theme, ProviderEvent event) {
    if (event.type == EventType.updated) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildValueSection(theme, 'Previous', event.previousValue,
              isPrevious: true),
          const SizedBox(height: 8),
          _buildValueSection(theme, 'Current', event.value, isPrevious: false),
        ],
      );
    }
    return _buildJsonTreeView(event.value);
  }

  Widget _buildValueSection(
      ThemeData theme, String label, Map<String, dynamic>? data,
      {required bool isPrevious}) {
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

  Widget _buildJsonTreeView(Map<String, dynamic>? data) {
    if (data == null) {
      return const Text('null',
          style: TextStyle(fontSize: 10, fontFamily: 'monospace'));
    }

    // Unwrapping logic is handled by JsonTreeView itself, but we might want to do pre-processing if needed.
    // For now, passing data directly as previous implementation did.
    // However, the previous implementation in this file (step 62) had unwrapping logic DUPLICATED here.
    // Since JsonTreeView handles unwrapping (as seen in step 113), we can simplify this!
    // BUT, let's look closely at step 62 _buildJsonTreeView logic.
    // It unwraps 'value', 'items', 'entries', 'string'.
    // JsonTreeView (step 113) ALSO explicitly unwraps 'value', 'items', 'entries', 'string'.
    // So we can just pass the data! Simpler!

    // Wait, step 62 _buildJsonTreeView also unwrapped `type` and `asyncState` by removing them.
    // JsonTreeView step 113 DOES handle that too inside `build` and `_buildExpandedValue`.
    // So yes, we can simplify!

    return JsonTreeView(data: data, initiallyExpanded: false);
  }
}
