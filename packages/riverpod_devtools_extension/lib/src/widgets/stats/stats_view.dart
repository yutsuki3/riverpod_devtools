import 'package:flutter/material.dart';

import '../../models/provider_info.dart';
import '../../providers/inspector_notifier.dart';
import '../../utils/provider_stats.dart';
import '../common/panel_ui.dart';

enum _SortColumn { name, updateRate, totalUpdates, maxLoad, churn }

/// Warning accent, adapted per brightness (used for both high-frequency
/// and slow-load signals).
Color _warnColor(ThemeData theme) => theme.brightness == Brightness.dark
    ? const Color(0xFFFFB74D)
    : const Color(0xFFE65100);

/// "Is something wrong?" dashboard: per-provider update frequency (with a
/// sparkline of the recent update rate), async load duration, and
/// dispose/re-create churn, aggregated from the event log by
/// [computeProviderStats].
///
/// Rows are sorted with warnings first by default (click a column header to
/// re-sort); flagged rows are tinted and carry an explicit chip so problems
/// are obvious at a glance. Clicking a row jumps to that provider in the
/// Inspector view.
class StatsView extends StatefulWidget {
  final InspectorNotifier notifier;

  const StatsView({super.key, required this.notifier});

  @override
  State<StatsView> createState() => _StatsViewState();
}

class _StatsViewState extends State<StatsView> {
  // Null = the default "problems first, then busiest" ordering. Clicking a
  // header switches to an explicit column sort.
  _SortColumn? _sortColumn;
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
    final column = _sortColumn;

    if (column == null) {
      // Default: warnings first, then by recent update rate, then name —
      // so "what's wrong?" is answered by looking at the top rows.
      sorted.sort((a, b) {
        if (a.hasWarning != b.hasWarning) return a.hasWarning ? -1 : 1;
        final byRate = b.updatesPerSecond.compareTo(a.updatesPerSecond);
        if (byRate != 0) return byRate;
        return a.providerName.compareTo(b.providerName);
      });
      return sorted;
    }

    int compare(ProviderStats a, ProviderStats b) {
      switch (column) {
        case _SortColumn.name:
          return a.providerName.compareTo(b.providerName);
        case _SortColumn.updateRate:
          return a.updatesPerSecond.compareTo(b.updatesPerSecond);
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
        final warningCount = stats.where((s) => s.hasWarning).length;

        return PanelCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              PanelHeader(
                icon: Icons.speed_outlined,
                title: 'Provider Stats',
                count: stats.length,
                actions: [
                  if (warningCount > 0) _AttentionBadge(count: warningCount),
                ],
              ),
              if (stats.isEmpty)
                const Expanded(
                  child: EmptyState(
                    icon: Icons.speed_outlined,
                    message: 'No stats yet',
                    hint: 'Stats appear once your app updates a provider',
                  ),
                )
              else ...[
                Expanded(
                  child: _StatsTable(
                    stats: _sorted(stats),
                    sortColumn: _sortColumn,
                    sortDescending: _sortDescending,
                    onSort: _setSort,
                    providers: widget.notifier.state.providers,
                    onRowTap: (name) {
                      // Jump to the Inspector focused on just this provider,
                      // replacing any prior (possibly multi-) selection.
                      widget.notifier.selectOnly(name);
                      widget.notifier.setViewMode(InspectorViewMode.inspector);
                    },
                  ),
                ),
                const _StatsLegend(),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _AttentionBadge extends StatelessWidget {
  final int count;

  const _AttentionBadge({required this.count});

  @override
  Widget build(BuildContext context) {
    final color = _warnColor(Theme.of(context));
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.warning_amber_rounded, size: 12, color: color),
          const SizedBox(width: 4),
          Text(
            '$count need${count == 1 ? 's' : ''} attention',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

/// Column layout shared by the header and every row, so they stay aligned.
class _Cols {
  static const provider = 3.0;
  static const rate = 2.4;
  static const total = 1.6;
  static const load = 2.2;
  static const churn = 1.0;
}

class _StatsTable extends StatelessWidget {
  final List<ProviderStats> stats;
  final _SortColumn? sortColumn;
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
    // Shared maxima so the total-updates bar and the sparkline heights are
    // comparable across rows (a tall spike instantly reads as "hot").
    final maxTotal = stats.fold<int>(
        1, (m, s) => s.totalUpdateCount > m ? s.totalUpdateCount : m);
    var maxBucket = 1;
    for (final s in stats) {
      for (final b in s.updateBuckets) {
        if (b > maxBucket) maxBucket = b;
      }
    }

    return Column(
      children: [
        _HeaderRow(
          sortColumn: sortColumn,
          sortDescending: sortDescending,
          onSort: onSort,
        ),
        Expanded(
          child: ListView.builder(
            itemCount: stats.length,
            itemBuilder: (context, index) => _StatRow(
              stat: stats[index],
              info: providers[stats[index].providerName],
              maxTotal: maxTotal,
              maxBucket: maxBucket,
              onTap: () => onRowTap(stats[index].providerName),
            ),
          ),
        ),
      ],
    );
  }
}

class _HeaderRow extends StatelessWidget {
  final _SortColumn? sortColumn;
  final bool sortDescending;
  final void Function(_SortColumn) onSort;

  const _HeaderRow({
    required this.sortColumn,
    required this.sortDescending,
    required this.onSort,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      // Left inset = row padding (12) + the 2px left status border every
      // row reserves, so header labels line up with row content exactly.
      padding: const EdgeInsets.only(left: 14, right: 12, top: 6, bottom: 6),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: theme.colorScheme.outline.withValues(alpha: 0.12),
          ),
        ),
      ),
      child: Row(
        children: [
          _HeaderCell(
            label: 'Provider',
            column: _SortColumn.name,
            flex: _Cols.provider,
            sortColumn: sortColumn,
            descending: sortDescending,
            onSort: onSort,
          ),
          _HeaderCell(
            label: 'Update rate',
            column: _SortColumn.updateRate,
            flex: _Cols.rate,
            sortColumn: sortColumn,
            descending: sortDescending,
            onSort: onSort,
          ),
          _HeaderCell(
            label: 'Updates',
            column: _SortColumn.totalUpdates,
            flex: _Cols.total,
            sortColumn: sortColumn,
            descending: sortDescending,
            onSort: onSort,
            alignEnd: true,
          ),
          _HeaderCell(
            label: 'Load time',
            column: _SortColumn.maxLoad,
            flex: _Cols.load,
            sortColumn: sortColumn,
            descending: sortDescending,
            onSort: onSort,
            alignEnd: true,
          ),
          _HeaderCell(
            label: 'Churn',
            column: _SortColumn.churn,
            flex: _Cols.churn,
            sortColumn: sortColumn,
            descending: sortDescending,
            onSort: onSort,
            alignEnd: true,
          ),
        ],
      ),
    );
  }
}

class _HeaderCell extends StatelessWidget {
  final String label;
  final _SortColumn column;
  final double flex;
  final _SortColumn? sortColumn;
  final bool descending;
  final void Function(_SortColumn) onSort;
  final bool alignEnd;

  const _HeaderCell({
    required this.label,
    required this.column,
    required this.flex,
    required this.sortColumn,
    required this.descending,
    required this.onSort,
    this.alignEnd = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isActive = sortColumn == column;
    final arrow = Icon(
      descending ? Icons.arrow_downward : Icons.arrow_upward,
      size: 10,
      color: theme.colorScheme.primary,
    );

    return Expanded(
      flex: (flex * 10).round(),
      child: InkWell(
        onTap: () => onSort(column),
        borderRadius: BorderRadius.circular(4),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(
            mainAxisAlignment:
                alignEnd ? MainAxisAlignment.end : MainAxisAlignment.start,
            children: [
              if (alignEnd && isActive) ...[arrow, const SizedBox(width: 2)],
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 9.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.3,
                    color: isActive
                        ? theme.colorScheme.primary
                        : theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              if (!alignEnd && isActive) ...[const SizedBox(width: 2), arrow],
            ],
          ),
        ),
      ),
    );
  }
}

class _StatRow extends StatelessWidget {
  final ProviderStats stat;
  final ProviderInfo? info;
  final int maxTotal;
  final int maxBucket;
  final VoidCallback onTap;

  const _StatRow({
    required this.stat,
    required this.info,
    required this.maxTotal,
    required this.maxBucket,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final warn = _warnColor(theme);
    final hasWarning = stat.hasWarning;

    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: hasWarning ? warn.withValues(alpha: 0.06) : null,
          border: Border(
            left: BorderSide(
              width: 2,
              color: hasWarning ? warn : Colors.transparent,
            ),
            bottom: BorderSide(
              color: theme.colorScheme.outline.withValues(alpha: 0.07),
            ),
          ),
        ),
        child: Row(
          children: [
            Expanded(
                flex: (_Cols.provider * 10).round(), child: _provider(theme)),
            Expanded(
                flex: (_Cols.rate * 10).round(),
                child: _updateRate(theme, warn)),
            Expanded(
                flex: (_Cols.total * 10).round(), child: _totalUpdates(theme)),
            Expanded(
                flex: (_Cols.load * 10).round(), child: _loadTime(theme, warn)),
            Expanded(flex: (_Cols.churn * 10).round(), child: _churn(theme)),
          ],
        ),
      ),
    );
  }

  Widget _provider(ThemeData theme) {
    return Row(
      children: [
        StatusDot(isActive: info?.status == ProviderStatus.active, size: 7),
        const SizedBox(width: 7),
        Flexible(
          child: Text(
            stat.providerName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: theme.colorScheme.onSurface,
            ),
          ),
        ),
      ],
    );
  }

  Widget _updateRate(ThemeData theme, Color warn) {
    final active = stat.updatesPerSecond > 0;
    final rateColor = stat.isHighFrequency
        ? warn
        : active
            ? theme.colorScheme.onSurface
            : theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5);

    return Padding(
      padding: const EdgeInsets.only(right: 12),
      child: Row(
        children: [
          SizedBox(
            width: 72,
            height: 22,
            child: CustomPaint(
              painter: _SparklinePainter(
                buckets: stat.updateBuckets,
                maxBucket: maxBucket,
                color: stat.isHighFrequency ? warn : theme.colorScheme.primary,
                baseline: theme.colorScheme.outline.withValues(alpha: 0.25),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              active ? '${_formatRate(stat.updatesPerSecond)}/s' : '—',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                fontFamily: 'monospace',
                fontWeight:
                    stat.isHighFrequency ? FontWeight.w700 : FontWeight.w500,
                color: rateColor,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _totalUpdates(ThemeData theme) {
    final fraction = (stat.totalUpdateCount / maxTotal).clamp(0.0, 1.0);
    return Padding(
      padding: const EdgeInsets.only(right: 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            '${stat.totalUpdateCount}',
            style: TextStyle(
              fontSize: 11,
              fontFamily: 'monospace',
              color: theme.colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 3),
          ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: LinearProgressIndicator(
              value: fraction,
              minHeight: 3,
              backgroundColor:
                  theme.colorScheme.outline.withValues(alpha: 0.15),
              valueColor: AlwaysStoppedAnimation(
                theme.colorScheme.primary.withValues(alpha: 0.55),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _loadTime(ThemeData theme, Color warn) {
    if (stat.loadSampleCount == 0) {
      return Padding(
        padding: const EdgeInsets.only(right: 12),
        child: Align(
          alignment: Alignment.centerRight,
          child: Text(
            'no async loads',
            style: TextStyle(
              fontSize: 9.5,
              fontStyle: FontStyle.italic,
              color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
            ),
          ),
        ),
      );
    }

    final color = stat.isSlowLoading ? warn : theme.colorScheme.onSurface;
    // Subtitle: for one sample there's no range to show; for several, show
    // the min–max span the avg came from.
    final subtitle = stat.loadSampleCount == 1
        ? '1 sample'
        : '${_formatDuration(stat.minLoadDuration!)}–'
            '${_formatDuration(stat.maxLoadDuration!)}'
            ' · ${stat.loadSampleCount} samples';

    return Padding(
      padding: const EdgeInsets.only(right: 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (stat.isSlowLoading) ...[
                Icon(Icons.hourglass_bottom, size: 11, color: warn),
                const SizedBox(width: 3),
              ],
              Text(
                'avg ${_formatDuration(stat.avgLoadDuration!)}',
                style: TextStyle(
                  fontSize: 11,
                  fontFamily: 'monospace',
                  fontWeight:
                      stat.isSlowLoading ? FontWeight.w700 : FontWeight.w500,
                  color: color,
                ),
              ),
            ],
          ),
          const SizedBox(height: 1),
          Text(
            subtitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 8.5,
              color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
            ),
          ),
        ],
      ),
    );
  }

  Widget _churn(ThemeData theme) {
    if (stat.churnCount == 0) {
      return Align(
        alignment: Alignment.centerRight,
        child: Text(
          '0',
          style: TextStyle(
            fontSize: 11,
            fontFamily: 'monospace',
            color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
          ),
        ),
      );
    }
    final color = theme.brightness == Brightness.dark
        ? const Color(0xFFCE93D8)
        : const Color(0xFF8E24AA);
    return Align(
      alignment: Alignment.centerRight,
      child: Tooltip(
        message: 'Disposed and re-created ${stat.churnCount}× — '
            'check for a provider being recreated unnecessarily',
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            '${stat.churnCount}×',
            style: TextStyle(
              fontSize: 10,
              fontFamily: 'monospace',
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ),
      ),
    );
  }
}

/// Footer explaining what the columns and thresholds mean — the Stats tab
/// otherwise assumes the reader knows what "churn" or the warning tint is.
class _StatsLegend extends StatelessWidget {
  const _StatsLegend();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final warn = _warnColor(theme);
    final muted = theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.7);

    Widget item(Widget leading, String text) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            leading,
            const SizedBox(width: 4),
            Text(text, style: TextStyle(fontSize: 9, color: muted)),
          ],
        );

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
        border: Border(
          top: BorderSide(
            color: theme.colorScheme.outline.withValues(alpha: 0.1),
          ),
        ),
      ),
      child: Wrap(
        spacing: 16,
        runSpacing: 4,
        children: [
          item(
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: warn.withValues(alpha: 0.25),
                border: Border(left: BorderSide(width: 2, color: warn)),
              ),
            ),
            'Highlighted = needs attention',
          ),
          item(Icon(Icons.bolt, size: 12, color: warn),
              'Update rate > ${kHighFrequencyThreshold.toInt()}/s'),
          item(Icon(Icons.hourglass_bottom, size: 12, color: warn),
              'Load > ${_formatDuration(kSlowLoadThreshold)}'),
          item(
            Icon(Icons.autorenew, size: 12, color: muted),
            'Churn = times disposed & re-created',
          ),
        ],
      ),
    );
  }
}

String _formatRate(double rate) {
  if (rate >= 10) return rate.toStringAsFixed(0);
  return rate.toStringAsFixed(1);
}

String _formatDuration(Duration d) {
  if (d.inMilliseconds < 1000) return '${d.inMilliseconds}ms';
  return '${(d.inMilliseconds / 1000).toStringAsFixed(1)}s';
}

/// Mini bar-chart sparkline of recent update counts. Bar heights are
/// normalized to [maxBucket] (shared across rows) so a tall spike reads as
/// "busy" relative to the whole table, not just this row.
class _SparklinePainter extends CustomPainter {
  final List<int> buckets;
  final int maxBucket;
  final Color color;
  final Color baseline;

  _SparklinePainter({
    required this.buckets,
    required this.maxBucket,
    required this.color,
    required this.baseline,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // A baseline so an idle provider still shows a clear "flat" line
    // rather than empty space.
    final basePaint = Paint()
      ..color = baseline
      ..strokeWidth = 1;
    canvas.drawLine(
      Offset(0, size.height - 0.5),
      Offset(size.width, size.height - 0.5),
      basePaint,
    );

    if (buckets.isEmpty || maxBucket <= 0) return;

    final barPaint = Paint()..color = color;
    final slot = size.width / buckets.length;
    final barWidth = slot * 0.7;
    for (var i = 0; i < buckets.length; i++) {
      if (buckets[i] <= 0) continue;
      final h = (buckets[i] / maxBucket).clamp(0.0, 1.0) * (size.height - 1);
      final x = i * slot + (slot - barWidth) / 2;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, size.height - h, barWidth, h),
          const Radius.circular(0.5),
        ),
        barPaint,
      );
    }
  }

  @override
  bool shouldRepaint(_SparklinePainter old) =>
      old.maxBucket != maxBucket ||
      old.color != color ||
      !_listEq(old.buckets, buckets);

  static bool _listEq(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
