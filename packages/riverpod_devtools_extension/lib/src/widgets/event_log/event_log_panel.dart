import 'package:flutter/material.dart';
import '../../models/event_type.dart';
import '../../models/provider_event.dart';
import '../../providers/inspector_notifier.dart';
import '../../utils/color_utils.dart';
import '../../utils/time_utils.dart';
import '../common/json_tree_view.dart';
import '../common/panel_ui.dart';

class EventLogPanel extends StatelessWidget {
  final InspectorNotifier notifier;

  const EventLogPanel({
    super.key,
    required this.notifier,
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: notifier,
      builder: (context, child) {
        final state = notifier.state;
        final filteredEvents = notifier.filteredEvents;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            PanelHeader(
              icon: Icons.history,
              title: state.selectedProviderNames.isEmpty
                  ? 'Event Log'
                  : state.selectedProviderNames.length == 1
                      ? 'Event Log (${state.selectedProviderNames.first})'
                      : 'Event Log (${state.selectedProviderNames.length} providers)',
              count: filteredEvents.length,
              actions: [
                HeaderActionButton(
                  label: 'Clear',
                  icon: Icons.delete_outline,
                  onPressed: notifier.clearEvents,
                ),
              ],
            ),
            Expanded(
              child: state.events.isEmpty
                  ? const EmptyState(
                      icon: Icons.timeline,
                      message: 'No events yet',
                      hint: 'Provider events appear here in real time',
                    )
                  : filteredEvents.isEmpty
                      ? const EmptyState(
                          icon: Icons.filter_alt_off_outlined,
                          message: 'No events found',
                          hint: 'No events for the selected providers',
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.symmetric(vertical: 4),
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
                              cascadeDepth:
                                  notifier.eventDepths[event.id] ?? 0,
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

  /// 0 for root events; 1+ indents the tile under the update cascade that
  /// (transitively) triggered it.
  final int cascadeDepth;

  const _EventTile({
    super.key,
    required this.event,
    required this.notifier,
    this.timeDiffString,
    this.cascadeDepth = 0,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final state = notifier.state;

    final semanticColor = getEventColor(event.type, isDark);

    final icon = switch (event.type) {
      EventType.added => Icons.add_circle_outline,
      EventType.updated => Icons.change_circle_outlined,
      EventType.disposed => Icons.remove_circle_outline,
    };

    final typeLabel = switch (event.type) {
      EventType.added => 'ADDED',
      EventType.updated => 'UPDATED',
      EventType.disposed => 'DISPOSED',
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
      margin: EdgeInsets.only(
        left: 6.0 + cascadeDepth * 12.0,
        right: 6,
        top: 2,
        bottom: 2,
      ),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest
            .withValues(alpha: 0.25),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: theme.colorScheme.outline.withValues(alpha: 0.1),
        ),
      ),
      child: Stack(
        children: [
          // Left accent bar
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            child: Container(width: 3, color: semanticColor),
          ),
          InkWell(
            splashFactory: NoSplash.splashFactory,
            highlightColor: Colors.transparent,
            onTap: isLongText
                ? () => notifier.toggleEventExpansion(event.id)
                : null,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(11, 6, 8, 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(icon, color: semanticColor, size: 14),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          event.providerName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: theme.colorScheme.onSurface,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 5, vertical: 1),
                        decoration: BoxDecoration(
                          color: semanticColor.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          typeLabel,
                          style: TextStyle(
                            fontSize: 7.5,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.4,
                            color: semanticColor,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '${event.timestamp.hour.toString().padLeft(2, '0')}:'
                        '${event.timestamp.minute.toString().padLeft(2, '0')}:'
                        '${event.timestamp.second.toString().padLeft(2, '0')}',
                        style: TextStyle(
                          color: theme.colorScheme.onSurfaceVariant
                              .withValues(alpha: 0.8),
                          fontSize: 10,
                          fontFamily: 'monospace',
                        ),
                      ),
                      if (timeDiffString != null &&
                          timeDiffString!.isNotEmpty) ...[
                        const SizedBox(width: 4),
                        Text(
                          timeDiffString!,
                          style: TextStyle(
                            fontSize: 9,
                            color: theme.colorScheme.onSurfaceVariant
                                .withValues(alpha: 0.5),
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
                  if (event.triggeredBy.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(left: 20, top: 3),
                      child: Wrap(
                        spacing: 4,
                        runSpacing: 2,
                        children: [
                          for (final trigger in event.triggeredBy)
                            _TriggerChip(
                              providerName: trigger.provider,
                              onTap: () {
                                notifier.selectProvider(trigger.provider);
                                notifier.flashProvider(trigger.provider);
                              },
                            ),
                        ],
                      ),
                    ),
                  if (!isExpanded)
                    Padding(
                      padding: const EdgeInsets.only(left: 20, top: 4),
                      child: Text(
                        summarySubtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 10,
                          fontFamily: 'monospace',
                          color: theme.colorScheme.onSurface
                              .withValues(alpha: 0.75),
                        ),
                      ),
                    )
                  else
                    Padding(
                      padding:
                          const EdgeInsets.only(left: 20, top: 6, bottom: 4),
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
        Row(
          children: [
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                color: labelColor,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.3,
                color: labelColor,
              ),
            ),
          ],
        ),
        const SizedBox(height: 3),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface.withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: theme.colorScheme.outline.withValues(alpha: 0.1),
            ),
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

    // JsonTreeView unwraps the metadata keys ('type', 'value', 'items',
    // 'entries', 'string', 'asyncState') itself, so pass the data through.
    return JsonTreeView(data: data, initiallyExpanded: false);
  }
}

/// "caused by <provider>" chip shown on updates that were (likely)
/// triggered by a dependency change. Tapping selects and flashes the
/// triggering provider.
class _TriggerChip extends StatelessWidget {
  final String providerName;
  final VoidCallback onTap;

  const _TriggerChip({
    required this.providerName,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = theme.colorScheme.tertiary;

    return Tooltip(
      message: 'Likely triggered by $providerName\n'
          '(inferred from static dependencies + timing)',
      waitDuration: const Duration(milliseconds: 400),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: color.withValues(alpha: 0.25)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.bolt, size: 10, color: color),
              const SizedBox(width: 2),
              Text(
                'caused by $providerName',
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w600,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
