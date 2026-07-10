import 'package:flutter/material.dart';
import '../../providers/inspector_notifier.dart';
import '../common/panel_ui.dart';
import '../detail_panel/detail_panel.dart';
import '../event_log/event_log_panel.dart';
import '../provider_list/provider_list_panel.dart';

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
          color: theme.colorScheme.surfaceContainerLowest
              .withValues(alpha: 0.5),
          padding: const EdgeInsets.all(8),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final totalWidth = constraints.maxWidth;
              const dividerWidth = 8.0;

              final providerListWidth = totalWidth * state.leftSplitRatio;
              final remainingWidth =
                  totalWidth - providerListWidth - dividerWidth;
              final detailPanelWidth = remainingWidth * state.rightSplitRatio;
              final eventLogWidth =
                  remainingWidth - detailPanelWidth - dividerWidth;

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
                      final newRatio =
                          state.leftSplitRatio + delta / totalWidth;
                      widget.notifier
                          .updateLeftSplitRatio(newRatio.clamp(0.15, 0.5));
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
                      final newRatio =
                          state.rightSplitRatio + delta / remainingWidth;
                      widget.notifier
                          .updateRightSplitRatio(newRatio.clamp(0.3, 0.7));
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
          ),
        );
      },
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
