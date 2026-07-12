import 'package:flutter/material.dart';

import '../../models/provider_info.dart';
import '../../providers/inspector_notifier.dart';
import '../../utils/graph_layout.dart';
import '../common/panel_ui.dart';
import '../detail_panel/detail_panel.dart';

/// Interactive dependency-graph view: layered DAG (dependencies on the
/// left, dependents to the right), pan/zoom, and cycle highlighting.
/// Clicking a node selects it (details shown in the panel on the right)
/// and focuses the graph on its sub-graph in one gesture; "Show all"
/// returns to the full graph.
class GraphView extends StatelessWidget {
  final InspectorNotifier notifier;

  const GraphView({super.key, required this.notifier});

  static const _nodeWidth = 170.0;
  static const _nodeHeight = 46.0;
  static const _hGap = 90.0;
  static const _vGap = 26.0;
  static const _padding = 32.0;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: notifier,
      builder: (context, child) {
        final state = notifier.state;

        final nodeNames = <String>{...state.providers.keys};
        final edges = <GraphEdgeInput>[];
        for (final provider in state.providers.values) {
          if (provider.dependencyDetails.isNotEmpty) {
            for (final detail in provider.dependencyDetails) {
              nodeNames.add(detail.providerName);
              edges.add(GraphEdgeInput(
                from: provider.name,
                to: detail.providerName,
                type: detail.type,
              ));
            }
          } else {
            for (final dependency in provider.dependencies) {
              nodeNames.add(dependency);
              edges.add(GraphEdgeInput(from: provider.name, to: dependency));
            }
          }
        }

        final layout = computeGraphLayout(nodeNames: nodeNames, edges: edges);

        // Focusing is a render-time filter (dim unrelated nodes, hide
        // unrelated edges), not a layout change — node positions stay
        // fixed regardless of focus so the graph doesn't reshuffle on
        // every click. Null means "nothing focused, show everything".
        final focus = state.graphFocusProvider;
        final focusedSet = focus != null && nodeNames.contains(focus)
            ? reachableFromFocus(focus, edges)
            : null;

        // layout.hasCycle reflects the whole graph, but an edge outside
        // the focused sub-graph is hidden by _EdgePainter — computed once
        // here and shared by the toolbar badge and the legend so they
        // can't disagree about whether a cycle is actually on screen.
        final visibleCycle =
            hasVisibleCycle(edges: layout.edges, focusedSet: focusedSet);

        return Row(
          children: [
            Expanded(
              child: PanelCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _GraphToolbar(
                      notifier: notifier,
                      layout: layout,
                      hasVisibleCycle: visibleCycle,
                    ),
                    Expanded(
                      child: layout.nodes.isEmpty
                          ? const EmptyState(
                              icon: Icons.account_tree_outlined,
                              message: 'No providers yet',
                              hint: 'The graph appears once your app '
                                  'creates providers',
                            )
                          : _GraphCanvas(
                              notifier: notifier,
                              layout: layout,
                              focusedSet: focusedSet,
                              hasVisibleCycle: visibleCycle,
                            ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 340,
              child: PanelCard(
                child: DetailPanel(
                  notifier: notifier,
                  noSelectionHint: 'Click a node in the graph',
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _GraphToolbar extends StatelessWidget {
  final InspectorNotifier notifier;
  final GraphLayout layout;
  final bool hasVisibleCycle;

  const _GraphToolbar({
    required this.notifier,
    required this.layout,
    required this.hasVisibleCycle,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final state = notifier.state;
    final focus = state.graphFocusProvider;

    return Container(
      // Fixed height, matching PanelHeader: the "Show all" action (and the
      // cycle badge) come and go, and without a fixed height their
      // appearance would resize the toolbar and shift the canvas below.
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: theme.colorScheme.outline.withValues(alpha: 0.12),
          ),
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.account_tree_outlined,
              size: 14, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 6),
          // The title group owns exactly the space the action doesn't use,
          // keeping "Show all" flush right (see PanelHeader for the layout
          // rationale) while the title still ellipsizes when tight.
          Expanded(
            child: Row(
              children: [
                Flexible(
                  child: Text(
                    'Dependency Graph',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '${layout.nodes.length} providers',
                  style: TextStyle(
                    fontSize: 9.5,
                    color: theme.colorScheme.onSurfaceVariant
                        .withValues(alpha: 0.7),
                  ),
                ),
                if (hasVisibleCycle) ...[
                  const SizedBox(width: 8),
                  Tooltip(
                    message: 'Dependency cycle detected — highlighted in red',
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.error.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.sync_problem,
                              size: 11, color: theme.colorScheme.error),
                          const SizedBox(width: 3),
                          Text(
                            'cycle',
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w600,
                              color: theme.colorScheme.error,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (focus != null)
            HeaderActionButton(
              label: 'Show all',
              icon: Icons.zoom_out_map,
              onPressed: notifier.resetGraphSelection,
            ),
        ],
      ),
    );
  }
}

class _GraphCanvas extends StatelessWidget {
  final InspectorNotifier notifier;
  final GraphLayout layout;

  /// Nodes related to the focused provider (itself + transitive deps and
  /// dependents), or null when nothing is focused. Nodes outside this set
  /// are dimmed and edges not fully inside it are hidden, but they stay
  /// laid out in place — see [computeGraphLayout].
  final Set<String>? focusedSet;

  final bool hasVisibleCycle;

  const _GraphCanvas({
    required this.notifier,
    required this.layout,
    required this.focusedSet,
    required this.hasVisibleCycle,
  });

  Offset _nodeOrigin(GraphNodeLayout node) => Offset(
        GraphView._padding +
            node.layer * (GraphView._nodeWidth + GraphView._hGap),
        GraphView._padding +
            node.row * (GraphView._nodeHeight + GraphView._vGap),
      );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final state = notifier.state;

    final contentWidth = GraphView._padding * 2 +
        layout.layerCount * GraphView._nodeWidth +
        (layout.layerCount - 1).clamp(0, 1 << 30) * GraphView._hGap;
    final contentHeight = GraphView._padding * 2 +
        layout.maxRowCount * GraphView._nodeHeight +
        (layout.maxRowCount - 1).clamp(0, 1 << 30) * GraphView._vGap;

    final origins = <String, Offset>{
      for (final node in layout.nodes) node.name: _nodeOrigin(node),
    };

    return LayoutBuilder(
      builder: (context, constraints) {
        // The deselect-on-empty-tap area below must cover at least the
        // visible viewport, not just the (possibly much smaller) graph
        // content — otherwise clicking the panel's empty margin around a
        // small graph would hit nothing and silently do nothing.
        final width = contentWidth > constraints.maxWidth
            ? contentWidth
            : constraints.maxWidth;
        final height = contentHeight > constraints.maxHeight
            ? contentHeight
            : constraints.maxHeight;

        return Stack(
          children: [
            InteractiveViewer(
              constrained: false,
              minScale: 0.25,
              maxScale: 2.5,
              boundaryMargin: const EdgeInsets.all(200),
              child: GestureDetector(
                // Tapping empty canvas (not a node — those have their own
                // GestureDetector and are hit-tested first) clears the
                // selection and exits focus, mirroring the Inspector view's
                // "tap empty area to deselect" behavior. Without this there
                // was no way back to a fully neutral state once a node had
                // been clicked.
                behavior: HitTestBehavior.opaque,
                onTap: notifier.resetGraphSelection,
                child: SizedBox(
                  width: width,
                  height: height,
                  child: Stack(
                    children: [
                      CustomPaint(
                        size: Size(width, height),
                        painter: _EdgePainter(
                          layout: layout,
                          origins: origins,
                          selected: state.selectedProviderNames,
                          focusedSet: focusedSet,
                          theme: theme,
                        ),
                      ),
                      for (final node in layout.nodes)
                        Positioned(
                          left: origins[node.name]!.dx,
                          top: origins[node.name]!.dy,
                          width: GraphView._nodeWidth,
                          height: GraphView._nodeHeight,
                          child: _GraphNode(
                            name: node.name,
                            info: state.providers[node.name],
                            isSelected:
                                state.selectedProviderNames.contains(node.name),
                            isFlashing: state.flashingProviderName == node.name,
                            isDimmed: isNodeDimmed(
                              nodeName: node.name,
                              searchQuery: state.providerSearchQuery,
                              focusedSet: focusedSet,
                            ),
                            onTap: () =>
                                notifier.selectAndFocusInGraph(node.name),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            // Fixed overlay (unaffected by pan/zoom) explaining the visual
            // encoding and the mouse interactions.
            Positioned(
              left: 8,
              bottom: 8,
              child: _GraphLegend(hasCycle: hasVisibleCycle),
            ),
          ],
        );
      },
    );
  }
}

/// Always-visible legend: what the edge line styles, node states, and
/// mouse gestures mean.
class _GraphLegend extends StatelessWidget {
  final bool hasCycle;

  const _GraphLegend({required this.hasCycle});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final labelStyle = TextStyle(
      fontSize: 9,
      color: theme.colorScheme.onSurfaceVariant,
    );
    final lineColor = theme.colorScheme.onSurfaceVariant;

    Widget edgeRow(String label, List<double>? dashPattern, {Color? color}) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 1.5),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            CustomPaint(
              size: const Size(26, 8),
              painter: _LegendLinePainter(
                color: color ?? lineColor,
                dashPattern: dashPattern,
              ),
            ),
            const SizedBox(width: 6),
            Text(label, style: labelStyle),
          ],
        ),
      );
    }

    Widget statusRow(Widget marker, String label) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 1.5),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(width: 26, child: Center(child: marker)),
            const SizedBox(width: 6),
            Text(label, style: labelStyle),
          ],
        ),
      );
    }

    final errorColor = theme.brightness == Brightness.dark
        ? const Color(0xFFE57373)
        : const Color(0xFFD32F2F);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: theme.colorScheme.outline.withValues(alpha: 0.2),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          edgeRow('watch — rebuilds on change', null),
          edgeRow('read — one-time read', const [6, 4]),
          edgeRow('listen — side-effect listener', const [2, 3]),
          if (hasCycle)
            edgeRow('dependency cycle', null, color: theme.colorScheme.error),
          const SizedBox(height: 4),
          statusRow(const StatusDot(isActive: true, size: 7), 'active'),
          statusRow(const StatusDot(isActive: false, size: 7),
              'disposed / not seen yet'),
          statusRow(Icon(Icons.error, size: 10, color: errorColor), 'failed'),
          const SizedBox(height: 6),
          Text(
            'Arrows point from a provider to the providers\n'
            'that consume it (the direction data flows).',
            style: labelStyle.copyWith(
              fontSize: 8.5,
              color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.75),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Click a node: select & focus its sub-graph\n'
            'Click empty space: deselect\n'
            'Drag: pan\n'
            'Scroll / pinch: zoom',
            style:
                labelStyle.copyWith(fontWeight: FontWeight.w600, height: 1.5),
          ),
        ],
      ),
    );
  }
}

class _LegendLinePainter extends CustomPainter {
  final Color color;
  final List<double>? dashPattern;

  _LegendLinePainter({required this.color, this.dashPattern});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.4
      ..style = PaintingStyle.stroke;
    final y = size.height / 2;

    final pattern = dashPattern;
    if (pattern == null) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    } else {
      var x = 0.0;
      var draw = true;
      var index = 0;
      while (x < size.width) {
        final length = pattern[index % pattern.length];
        if (draw) {
          final end = (x + length).clamp(0.0, size.width);
          canvas.drawLine(Offset(x, y), Offset(end, y), paint);
        }
        x += length;
        draw = !draw;
        index++;
      }
    }
  }

  @override
  bool shouldRepaint(_LegendLinePainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.dashPattern != dashPattern;
}

class _GraphNode extends StatelessWidget {
  final String name;
  final ProviderInfo? info;
  final bool isSelected;
  final bool isFlashing;
  final bool isDimmed;
  final VoidCallback onTap;

  const _GraphNode({
    required this.name,
    required this.info,
    required this.isSelected,
    required this.isFlashing,
    required this.isDimmed,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final status = info?.status;
    final hasError = info?.lastError != null;
    final isActive = status == ProviderStatus.active;
    final errorColor =
        isDark ? const Color(0xFFE57373) : const Color(0xFFD32F2F);

    final borderColor = isSelected
        ? theme.colorScheme.primary
        : hasError
            ? errorColor.withValues(alpha: 0.7)
            : theme.colorScheme.outline.withValues(alpha: 0.3);

    return Opacity(
      opacity: isDimmed ? 0.25 : 1,
      child: Tooltip(
        message: '$name\nClick: select & focus its sub-graph',
        waitDuration: const Duration(milliseconds: 600),
        child: GestureDetector(
          onTap: onTap,
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: isFlashing
                    ? theme.colorScheme.primary.withValues(alpha: 0.3)
                    : isSelected
                        ? theme.colorScheme.primary.withValues(alpha: 0.12)
                        : theme.colorScheme.surfaceContainerHighest
                            .withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: borderColor,
                  width: isSelected ? 1.5 : 1,
                ),
              ),
              child: Row(
                children: [
                  // Unknown status (statically-known but never observed at
                  // runtime) renders as a hollow dot, like disposed.
                  StatusDot(isActive: isActive, size: 7),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight:
                            isSelected ? FontWeight.w600 : FontWeight.w500,
                        color: info == null
                            ? theme.colorScheme.onSurfaceVariant
                                .withValues(alpha: 0.7)
                            : theme.colorScheme.onSurface,
                      ),
                    ),
                  ),
                  if (hasError) Icon(Icons.error, size: 11, color: errorColor),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _EdgePainter extends CustomPainter {
  final GraphLayout layout;
  final Map<String, Offset> origins;
  final Set<String> selected;

  /// See [_GraphCanvas.focusedSet]. An edge is only drawn when both of
  /// its endpoints are in this set (or it is null, meaning no focus).
  final Set<String>? focusedSet;

  final ThemeData theme;

  _EdgePainter({
    required this.layout,
    required this.origins,
    required this.selected,
    required this.focusedSet,
    required this.theme,
  });

  @override
  void paint(Canvas canvas, Size size) {
    for (final edge in layout.edges) {
      final fromOrigin = origins[edge.from];
      final toOrigin = origins[edge.to];
      if (fromOrigin == null || toOrigin == null) continue;
      if (!isEdgeVisible(
          from: edge.from, to: edge.to, focusedSet: focusedSet)) {
        continue;
      }

      // Data flows dependency -> dependent: start at the dependency's
      // right edge, end at the dependent's left edge.
      final start = toOrigin +
          const Offset(GraphView._nodeWidth, GraphView._nodeHeight / 2);
      final end = fromOrigin + const Offset(0, GraphView._nodeHeight / 2);

      final isHighlighted =
          selected.contains(edge.from) || selected.contains(edge.to);
      final baseColor = edge.isCycle
          ? theme.colorScheme.error
          : isHighlighted
              ? theme.colorScheme.primary
              : theme.colorScheme.onSurfaceVariant;
      final paint = Paint()
        ..color = baseColor.withValues(
            alpha: isHighlighted || edge.isCycle ? 0.8 : 0.35)
        ..strokeWidth = isHighlighted ? 1.8 : 1.2
        ..style = PaintingStyle.stroke;

      final controlDx = (end.dx - start.dx).abs() / 2;
      final path = Path()
        ..moveTo(start.dx, start.dy)
        ..cubicTo(
          start.dx + controlDx,
          start.dy,
          end.dx - controlDx,
          end.dy,
          end.dx,
          end.dy,
        );

      switch (edge.type) {
        case 'read':
          canvas.drawPath(_dashPath(path, const [6, 4]), paint);
        case 'listen':
          canvas.drawPath(_dashPath(path, const [2, 3]), paint);
        default:
          canvas.drawPath(path, paint);
      }

      _drawArrowhead(canvas, end, paint..style = PaintingStyle.fill);
    }
  }

  Path _dashPath(Path source, List<double> pattern) {
    final dashed = Path();
    for (final metric in source.computeMetrics()) {
      var distance = 0.0;
      var draw = true;
      var index = 0;
      while (distance < metric.length) {
        final length = pattern[index % pattern.length];
        if (draw) {
          dashed.addPath(
            metric.extractPath(distance, distance + length),
            Offset.zero,
          );
        }
        distance += length;
        draw = !draw;
        index++;
      }
    }
    return dashed;
  }

  void _drawArrowhead(Canvas canvas, Offset tip, Paint paint) {
    const size = 5.0;
    final path = Path()
      ..moveTo(tip.dx, tip.dy)
      ..lineTo(tip.dx - size, tip.dy - size * 0.6)
      ..lineTo(tip.dx - size, tip.dy + size * 0.6)
      ..close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_EdgePainter oldDelegate) =>
      oldDelegate.layout != layout ||
      oldDelegate.origins != origins ||
      oldDelegate.selected != selected ||
      oldDelegate.focusedSet != focusedSet ||
      oldDelegate.theme != theme;
}
