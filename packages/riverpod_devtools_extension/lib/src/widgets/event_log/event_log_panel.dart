import 'package:flutter/material.dart';
import '../../models/event_type.dart';
import '../../models/provider_event.dart';
import '../../providers/inspector_notifier.dart';
import '../../utils/color_utils.dart';
import '../../utils/json_diff.dart';
import '../../utils/time_utils.dart';
import '../common/error_details.dart';
import '../common/json_diff_view.dart';
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
            if (state.comparedEventIds.isNotEmpty)
              _CompareBar(notifier: notifier),
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
                              isComparing: state.comparedEventIds
                                  .contains(event.id),
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

  /// True when this event is one of the (up to two) picked for the value
  /// diff — the tile gets an accent border and a filled compare toggle.
  final bool isComparing;

  const _EventTile({
    super.key,
    required this.event,
    required this.notifier,
    this.timeDiffString,
    this.cascadeDepth = 0,
    this.isComparing = false,
  });

  /// Only events that carry a value are worth diffing (added / updated);
  /// disposed and failed events have no value tree to compare.
  bool get _canCompare =>
      event.type == EventType.added || event.type == EventType.updated;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final state = notifier.state;

    final semanticColor = getEventColor(event.type, isDark);

    final icon = switch (event.type) {
      EventType.added => Icons.add_circle_outline,
      EventType.updated => Icons.change_circle_outlined,
      EventType.failed => Icons.error_outline,
      EventType.disposed => Icons.remove_circle_outline,
    };

    final typeLabel = switch (event.type) {
      EventType.added => 'ADDED',
      EventType.updated => 'UPDATED',
      EventType.failed => 'FAILED',
      EventType.disposed => 'DISPOSED',
    };

    final isExpanded = state.expandedEventIds.contains(event.id);

    String summarySubtitle;
    if (event.type == EventType.disposed) {
      summarySubtitle = 'disposed';
    } else if (event.type == EventType.updated) {
      summarySubtitle =
          '${event.getPreviousValueString()} → ${event.getValueString()}';
    } else if (event.type == EventType.failed) {
      summarySubtitle =
          (event.error?['message'] as String?)?.split('\n').first ?? 'Error';
    } else {
      summarySubtitle = event.getValueString();
    }

    final isLongText = event.type == EventType.disposed
        ? false
        : (summarySubtitle.length > 50 ||
            event.type == EventType.updated ||
            event.type == EventType.failed);

    return Container(
      margin: EdgeInsets.only(
        left: 6.0 + cascadeDepth * 12.0,
        right: 6,
        top: 2,
        bottom: 2,
      ),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: isComparing
            ? theme.colorScheme.primary.withValues(alpha: 0.08)
            : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.25),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isComparing
              ? theme.colorScheme.primary.withValues(alpha: 0.6)
              : theme.colorScheme.outline.withValues(alpha: 0.1),
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
                      if (_canCompare) ...[
                        const SizedBox(width: 2),
                        _CompareToggle(
                          active: isComparing,
                          onTap: () =>
                              notifier.toggleEventComparison(event.id),
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
    if (event.type == EventType.failed) {
      return ErrorDetails(error: event.error);
    }
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

/// A small toggle placed on each value-carrying event tile that adds/removes
/// the event from the two-event diff selection.
class _CompareToggle extends StatelessWidget {
  final bool active;
  final VoidCallback onTap;

  const _CompareToggle({required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Tooltip(
      message: active ? 'Remove from diff' : 'Pick for value diff',
      waitDuration: const Duration(milliseconds: 400),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        child: Padding(
          padding: const EdgeInsets.all(2),
          child: Icon(
            active ? Icons.difference : Icons.difference_outlined,
            size: 14,
            color: active
                ? theme.colorScheme.primary
                : theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
          ),
        ),
      ),
    );
  }
}

/// Bar shown above the event list while events are picked for diffing.
/// Explains progress (1 of 2) and, once a pair is ready, offers to open the
/// diff dialog.
class _CompareBar extends StatelessWidget {
  final InspectorNotifier notifier;

  const _CompareBar({required this.notifier});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pair = notifier.comparedEventPair;
    final count = notifier.state.comparedEventIds.length;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: theme.colorScheme.primary.withValues(alpha: 0.08),
        border: Border(
          bottom: BorderSide(
            color: theme.colorScheme.primary.withValues(alpha: 0.2),
          ),
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.difference, size: 13, color: theme.colorScheme.primary),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              pair != null
                  ? 'Comparing two ${pair.$1.providerName} events'
                  : 'Pick one more event to compare ($count of 2)',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w500,
                color: theme.colorScheme.onSurface,
              ),
            ),
          ),
          if (pair != null)
            HeaderActionButton(
              label: 'View diff',
              icon: Icons.compare_arrows,
              onPressed: () => showEventValueDiffDialog(context, pair.$1, pair.$2),
            ),
          HeaderActionButton(
            label: 'Clear',
            icon: Icons.close,
            onPressed: notifier.clearEventComparison,
          ),
        ],
      ),
    );
  }
}

/// Opens the structural value-diff of two events (A = older, B = newer).
void showEventValueDiffDialog(
    BuildContext context, ProviderEvent older, ProviderEvent newer) {
  showDialog<void>(
    context: context,
    builder: (context) => _DiffDialog(older: older, newer: newer),
  );
}

class _DiffDialog extends StatefulWidget {
  final ProviderEvent older;
  final ProviderEvent newer;

  const _DiffDialog({required this.older, required this.newer});

  @override
  State<_DiffDialog> createState() => _DiffDialogState();
}

class _DiffDialogState extends State<_DiffDialog> {
  bool _changesOnly = true;

  String _time(ProviderEvent e) =>
      '${e.timestamp.hour.toString().padLeft(2, '0')}:'
      '${e.timestamp.minute.toString().padLeft(2, '0')}:'
      '${e.timestamp.second.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final root = diffJson(widget.older.value, widget.newer.value);

    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560, maxHeight: 560),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 8, 8),
              child: Row(
                children: [
                  Icon(Icons.difference,
                      size: 16, color: theme.colorScheme.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Value diff · ${widget.older.providerName}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                '${_time(widget.older)}  →  ${_time(widget.newer)}',
                style: TextStyle(
                  fontSize: 11,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 6, 16, 2),
              child: Row(
                children: [
                  Checkbox(
                    value: _changesOnly,
                    visualDensity: VisualDensity.compact,
                    materialTapTargetSize:
                        MaterialTapTargetSize.shrinkWrap,
                    onChanged: (v) =>
                        setState(() => _changesOnly = v ?? true),
                  ),
                  const SizedBox(width: 2),
                  Text(
                    'Show changes only',
                    style: TextStyle(
                      fontSize: 11,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                  const Spacer(),
                  if (!root.hasChange)
                    Text(
                      'Values are identical',
                      style: TextStyle(
                        fontSize: 11,
                        fontStyle: FontStyle.italic,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ),
            const Divider(height: 1),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(14),
                child: JsonDiffView(root: root, changesOnly: _changesOnly),
              ),
            ),
          ],
        ),
      ),
    );
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
