import 'dart:convert';
import 'package:flutter/material.dart';
import '../../providers/inspector_notifier.dart';
import '../../utils/session_file_io.dart';
import '../../utils/session_io.dart';
import '../common/panel_ui.dart';
import '../detail_panel/detail_panel.dart';
import '../event_log/event_log_panel.dart';
import '../graph/graph_view.dart';
import '../provider_list/provider_list_panel.dart';
import '../stats/stats_view.dart';

class InspectorView extends StatefulWidget {
  final InspectorNotifier notifier;

  const InspectorView({
    super.key,
    required this.notifier,
  });

  @override
  State<InspectorView> createState() => _InspectorViewState();
}

class _InspectorViewState extends State<InspectorView> {
  final ScrollController _providerListScrollController = ScrollController();

  @override
  void dispose() {
    _providerListScrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ListenableBuilder(
      listenable: widget.notifier,
      builder: (context, child) {
        final state = widget.notifier.state;

        return Container(
          color:
              theme.colorScheme.surfaceContainerLowest.withValues(alpha: 0.5),
          padding: const EdgeInsets.all(8),
          child: Column(
            children: [
              Row(
                children: [
                  _ViewSwitcher(notifier: widget.notifier),
                  const Spacer(),
                  _SessionActions(notifier: widget.notifier),
                ],
              ),
              const SizedBox(height: 8),
              Expanded(
                child: switch (state.viewMode) {
                  InspectorViewMode.graph =>
                    GraphView(notifier: widget.notifier),
                  InspectorViewMode.stats =>
                    StatsView(notifier: widget.notifier),
                  InspectorViewMode.inspector => _buildInspectorPanels(state),
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildInspectorPanels(InspectorState state) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final totalWidth = constraints.maxWidth;
        const dividerWidth = 8.0;

        final providerListWidth = totalWidth * state.leftSplitRatio;
        final remainingWidth = totalWidth - providerListWidth - dividerWidth;
        final detailPanelWidth = remainingWidth * state.rightSplitRatio;
        final eventLogWidth = remainingWidth - detailPanelWidth - dividerWidth;

        return Row(
          children: [
            SizedBox(
              width: providerListWidth,
              child: PanelCard(
                child: ProviderListPanel(
                  notifier: widget.notifier,
                  scrollController: _providerListScrollController,
                ),
              ),
            ),
            _PanelDivider(
              width: dividerWidth,
              onDrag: (delta) {
                final newRatio = state.leftSplitRatio + delta / totalWidth;
                widget.notifier.updateLeftSplitRatio(newRatio.clamp(0.15, 0.5));
              },
            ),
            SizedBox(
              width: detailPanelWidth,
              child: PanelCard(
                child: DetailPanel(
                  notifier: widget.notifier,
                  onProviderJump: () {
                    // Handle jump logic if needed
                  },
                ),
              ),
            ),
            _PanelDivider(
              width: dividerWidth,
              onDrag: (delta) {
                final newRatio = state.rightSplitRatio + delta / remainingWidth;
                widget.notifier.updateRightSplitRatio(newRatio.clamp(0.3, 0.7));
              },
            ),
            SizedBox(
              width: eventLogWidth,
              child: PanelCard(
                child: EventLogPanel(
                  notifier: widget.notifier,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Segmented control switching between the Inspector (3-panel) and
/// Dependency Graph views.
class _ViewSwitcher extends StatelessWidget {
  final InspectorNotifier notifier;

  const _ViewSwitcher({required this.notifier});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mode = notifier.state.viewMode;

    Widget buildTab(InspectorViewMode value, IconData icon, String label) {
      final isActive = mode == value;
      return InkWell(
        onTap: () => notifier.setViewMode(value),
        borderRadius: BorderRadius.circular(6),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: isActive
                ? theme.colorScheme.primary.withValues(alpha: 0.12)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 12,
                color: isActive
                    ? theme.colorScheme.primary
                    : theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
                  color: isActive
                      ? theme.colorScheme.primary
                      : theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          color:
              theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: theme.colorScheme.outline.withValues(alpha: 0.12),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            buildTab(InspectorViewMode.inspector, Icons.view_column_outlined,
                'Inspector'),
            const SizedBox(width: 2),
            buildTab(
                InspectorViewMode.graph, Icons.account_tree_outlined, 'Graph'),
            const SizedBox(width: 2),
            buildTab(InspectorViewMode.stats, Icons.speed_outlined, 'Stats'),
          ],
        ),
      ),
    );
  }
}

/// Export / import buttons for the current session. Export downloads the
/// full session (providers + event log) as a JSON file; import replaces the
/// live view with a previously exported one for offline inspection.
class _SessionActions extends StatelessWidget {
  final InspectorNotifier notifier;

  const _SessionActions({required this.notifier});

  void _export() {
    final json = const JsonEncoder.withIndent('  ').convert(
      notifier.exportSession(),
    );
    final stamp = DateTime.now()
        .toIso8601String()
        .replaceAll(':', '-')
        .split('.')
        .first;
    downloadTextFile('riverpod-session-$stamp.json', json);
  }

  Future<void> _import(BuildContext context) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final text = await pickTextFile();
    if (text == null) return;
    try {
      final decoded = decodeSession(
        jsonDecode(text) as Map<String, dynamic>,
      );
      notifier.loadSession(decoded);
      messenger?.showSnackBar(
        SnackBar(
          content: Text(
            'Imported ${decoded.providers.length} providers, '
            '${decoded.events.length} events',
          ),
          duration: const Duration(seconds: 2),
        ),
      );
    } catch (e) {
      final message = e is SessionDecodeException
          ? e.message
          : 'Could not read session file: not valid JSON.';
      messenger?.showSnackBar(
        SnackBar(content: Text(message), duration: const Duration(seconds: 4)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasData = notifier.state.providers.isNotEmpty ||
        notifier.state.events.isNotEmpty;

    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: theme.colorScheme.outline.withValues(alpha: 0.12),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _SessionActionButton(
            icon: Icons.download_outlined,
            label: 'Export',
            tooltip: hasData
                ? 'Download the session (providers + events) as JSON'
                : 'Nothing to export yet',
            onTap: hasData ? _export : null,
          ),
          const SizedBox(width: 2),
          _SessionActionButton(
            icon: Icons.upload_outlined,
            label: 'Import',
            tooltip: 'Load a previously exported session file',
            onTap: () => _import(context),
          ),
        ],
      ),
    );
  }
}

class _SessionActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final String tooltip;
  final VoidCallback? onTap;

  const _SessionActionButton({
    required this.icon,
    required this.label,
    required this.tooltip,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final enabled = onTap != null;
    final color = enabled
        ? theme.colorScheme.onSurfaceVariant
        : theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.4);

    return Tooltip(
      message: tooltip,
      waitDuration: const Duration(milliseconds: 400),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 12, color: color),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.normal,
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

/// A draggable gutter between panels. Mostly invisible, with a grab handle
/// that highlights on hover.
class _PanelDivider extends StatefulWidget {
  final double width;
  final void Function(double delta) onDrag;

  const _PanelDivider({
    required this.width,
    required this.onDrag,
  });

  @override
  State<_PanelDivider> createState() => _PanelDividerState();
}

class _PanelDividerState extends State<_PanelDivider> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onHorizontalDragUpdate: (details) => widget.onDrag(details.delta.dx),
      child: MouseRegion(
        cursor: SystemMouseCursors.resizeColumn,
        onEnter: (_) => setState(() => _hovering = true),
        onExit: (_) => setState(() => _hovering = false),
        child: SizedBox(
          width: widget.width,
          child: Center(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: 3,
              height: _hovering ? 48 : 28,
              decoration: BoxDecoration(
                color: _hovering
                    ? theme.colorScheme.primary.withValues(alpha: 0.7)
                    : theme.colorScheme.outline.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
