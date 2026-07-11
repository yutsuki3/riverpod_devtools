import 'package:flutter/material.dart';

import '../../models/provider_info.dart';
import '../../providers/inspector_notifier.dart';
import '../../utils/provider_stats.dart';
import '../common/panel_ui.dart';

enum _SortColumn { name, recentUpdates, totalUpdates, maxLoad, churn }

/// "Is something wrong?" table: per-provider update frequency, async load
/// duration, and dispose/re-create churn, aggregated from the event log by
/// [computeProviderStats]. Sortable by clicking a column header; rows
/// exceeding a threshold get a warning badge, and clicking a row jumps to
/// that provider in the Inspector view.
class StatsView extends StatefulWidget {
  final InspectorNotifier notifier;

  const StatsView({super.key, required this.notifier});

  @override
  State<StatsView> createState() => _StatsViewState();
}

class _StatsViewState extends State<StatsView> {
  _SortColumn _sortColumn = _SortColumn.recentUpdates;
  bool _sortDescending = true;

  void _setSort(_SortColumn column) {
    setState(() {
      if (_sortColumn == column) {
        _sortDescending = !_sortDescending;
      } else {
        _sortColumn = column;
        _sortDescending = true;
      }
    });
  }

  List<ProviderStats> _sorted(List<ProviderStats> stats) {
    final sorted = stats.toList();
    int compare(ProviderStats a, ProviderStats b) {
      switch (_sortColumn) {
        case _SortColumn.name:
          return a.providerName.compareTo(b.providerName);
        case _SortColumn.recentUpdates:
          return a.recentUpdateCount.compareTo(b.recentUpdateCount);
        case _SortColumn.totalUpdates:
          return a.totalUpdateCount.compareTo(b.totalUpdateCount);
        case _SortColumn.maxLoad:
          final aMs = a.maxLoadDuration?.inMicroseconds ?? -1;
          final bMs = b.maxLoadDuration?.inMicroseconds ?? -1;
          return aMs.compareTo(bMs);
        case _SortColumn.churn:
          return a.churnCount.compareTo(b.churnCount);
      }
    }

    sorted.sort(_sortDescending ? (a, b) => compare(b, a) : compare);
    return sorted;
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.notifier,
      builder: (context, child) {
        final stats = widget.notifier.providerStats;

        return PanelCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              PanelHeader(
                icon: Icons.speed_outlined,
                title: 'Provider Stats',
                count: stats.length,
              ),
              if (stats.isEmpty)
                const Expanded(
                  child: EmptyState(
                    icon: Icons.speed_outlined,
                    message: 'No stats yet',
                    hint: 'Stats appear once your app updates a provider',
                  ),
                )
              else
                Expanded(
                    child: _StatsTable(
                  stats: _sorted(stats),
                  sortColumn: _sortColumn,
                  sortDescending: _sortDescending,
                  onSort: _setSort,
                  providers: widget.notifier.state.providers,
                  onRowTap: (name) {
                    widget.notifier.selectProvider(name);
                    widget.notifier.setViewMode(InspectorViewMode.inspector);
                  },
                )),
            ],
          ),
        );
      },
    );
  }
}

class _StatsTable extends StatelessWidget {
  final List<ProviderStats> stats;
  final _SortColumn sortColumn;
  final bool sortDescending;
  final void Function(_SortColumn) onSort;
  final Map<String, ProviderInfo> providers;
  final void Function(String providerName) onRowTap;

  const _StatsTable({
    required this.stats,
    required this.sortColumn,
    required this.sortDescending,
    required this.onSort,
    required this.providers,
    required this.onRowTap,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Table(
          columnWidths: const {
            0: FlexColumnWidth(2.2),
            1: FlexColumnWidth(1.2),
            2: FlexColumnWidth(1.2),
            3: FlexColumnWidth(1.6),
            4: FlexColumnWidth(1),
          },
          children: [
            TableRow(children: [
              _HeaderCell(
                  label: 'Provider',
                  column: _SortColumn.name,
                  current: sortColumn,
                  descending: sortDescending,
                  onSort: onSort),
              _HeaderCell(
                  label: 'Updates (10s)',
                  column: _SortColumn.recentUpdates,
                  current: sortColumn,
                  descending: sortDescending,
                  onSort: onSort,
                  alignEnd: true),
              _HeaderCell(
                  label: 'Updates (total)',
                  column: _SortColumn.totalUpdates,
                  current: sortColumn,
                  descending: sortDescending,
                  onSort: onSort,
                  alignEnd: true),
              _HeaderCell(
                  label: 'Load (min/avg/max)',
                  column: _SortColumn.maxLoad,
                  current: sortColumn,
                  descending: sortDescending,
                  onSort: onSort,
                  alignEnd: true),
              _HeaderCell(
                  label: 'Churn',
                  column: _SortColumn.churn,
                  current: sortColumn,
                  descending: sortDescending,
                  onSort: onSort,
                  alignEnd: true),
            ]),
            for (final stat in stats)
              _statRow(context, stat, providers[stat.providerName]),
          ],
        ),
      ),
    );
  }

  TableRow _statRow(
      BuildContext context, ProviderStats stat, ProviderInfo? info) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final warnColor =
        isDark ? const Color(0xFFFFB74D) : const Color(0xFFE65100);

    Widget cell(Widget child, {bool alignEnd = false}) => TableCell(
          verticalAlignment: TableCellVerticalAlignment.middle,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
            child: Align(
              alignment:
                  alignEnd ? Alignment.centerRight : Alignment.centerLeft,
              child: child,
            ),
          ),
        );

    Widget text(String value, {Color? color, FontWeight? weight}) => Text(
          value,
          style: TextStyle(
            fontSize: 10.5,
            fontFamily: 'monospace',
            color: color ?? theme.colorScheme.onSurface,
            fontWeight: weight,
          ),
        );

    return TableRow(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: theme.colorScheme.outline.withValues(alpha: 0.08),
          ),
        ),
      ),
      children: [
        cell(
          InkWell(
            onTap: () => onRowTap(stat.providerName),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                StatusDot(
                  isActive: info?.status == ProviderStatus.active,
                  size: 6,
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    stat.providerName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                ),
                if (stat.isHighFrequency) ...[
                  const SizedBox(width: 4),
                  Tooltip(
                    message: '${stat.updatesPerSecond.toStringAsFixed(1)} '
                        'updates/sec — over the ${kHighFrequencyThreshold.toInt()}/sec threshold',
                    child: Icon(Icons.bolt, size: 12, color: warnColor),
                  ),
                ],
                if (stat.isSlowLoading) ...[
                  const SizedBox(width: 4),
                  Tooltip(
                    message: 'Slowest load: '
                        '${_formatDuration(stat.maxLoadDuration!)} — over the '
                        '${_formatDuration(kSlowLoadThreshold)} threshold',
                    child: Icon(Icons.hourglass_bottom,
                        size: 12, color: warnColor),
                  ),
                ],
              ],
            ),
          ),
        ),
        cell(
          text(
            '${stat.recentUpdateCount}',
            color: stat.isHighFrequency ? warnColor : null,
            weight: stat.isHighFrequency ? FontWeight.w700 : null,
          ),
          alignEnd: true,
        ),
        cell(text('${stat.totalUpdateCount}'), alignEnd: true),
        cell(
          text(
            stat.loadSampleCount == 0
                ? '—'
                : '${_formatDuration(stat.minLoadDuration!)} / '
                    '${_formatDuration(stat.avgLoadDuration!)} / '
                    '${_formatDuration(stat.maxLoadDuration!)}',
            color: stat.isSlowLoading ? warnColor : null,
            weight: stat.isSlowLoading ? FontWeight.w700 : null,
          ),
          alignEnd: true,
        ),
        cell(text('${stat.churnCount}'), alignEnd: true),
      ],
    );
  }
}

String _formatDuration(Duration d) {
  if (d.inMilliseconds < 1000) return '${d.inMilliseconds}ms';
  return '${(d.inMilliseconds / 1000).toStringAsFixed(1)}s';
}

class _HeaderCell extends StatelessWidget {
  final String label;
  final _SortColumn column;
  final _SortColumn current;
  final bool descending;
  final void Function(_SortColumn) onSort;
  final bool alignEnd;

  const _HeaderCell({
    required this.label,
    required this.column,
    required this.current,
    required this.descending,
    required this.onSort,
    this.alignEnd = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isActive = current == column;

    return TableCell(
      child: InkWell(
        onTap: () => onSort(column),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment:
                alignEnd ? MainAxisAlignment.end : MainAxisAlignment.start,
            children: [
              if (alignEnd && isActive) ...[
                Icon(
                  descending ? Icons.arrow_downward : Icons.arrow_upward,
                  size: 10,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 2),
              ],
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 9.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.2,
                    color: isActive
                        ? theme.colorScheme.primary
                        : theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              if (!alignEnd && isActive) ...[
                const SizedBox(width: 2),
                Icon(
                  descending ? Icons.arrow_downward : Icons.arrow_upward,
                  size: 10,
                  color: theme.colorScheme.primary,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
