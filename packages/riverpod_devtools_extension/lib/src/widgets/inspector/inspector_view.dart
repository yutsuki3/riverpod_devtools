import 'package:flutter/material.dart';
import '../../providers/inspector_notifier.dart';
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

        return LayoutBuilder(
          builder: (context, constraints) {
            final totalWidth = constraints.maxWidth;
            const dividerWidth = 4.0;

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
                  child: ProviderListPanel(
                    notifier: widget.notifier,
                    scrollController: _providerListScrollController,
                  ),
                ),
                _buildDivider(
                  theme: theme,
                  onDrag: (delta) {
                    final newRatio = state.leftSplitRatio + delta / totalWidth;
                    widget.notifier
                        .updateLeftSplitRatio(newRatio.clamp(0.15, 0.5));
                  },
                ),
                SizedBox(
                  width: detailPanelWidth,
                  child: DetailPanel(
                    notifier: widget.notifier,
                    onProviderJump: () {
                      // Handle jump logic if needed
                    },
                  ),
                ),
                _buildDivider(
                  theme: theme,
                  onDrag: (delta) {
                    final newRatio =
                        state.rightSplitRatio + delta / remainingWidth;
                    widget.notifier
                        .updateRightSplitRatio(newRatio.clamp(0.3, 0.7));
                  },
                ),
                SizedBox(
                  width: eventLogWidth,
                  child: EventLogPanel(
                    notifier: widget.notifier,
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildDivider({
    required ThemeData theme,
    required void Function(double delta) onDrag,
  }) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onHorizontalDragUpdate: (details) => onDrag(details.delta.dx),
      child: MouseRegion(
        cursor: SystemMouseCursors.resizeColumn,
        child: Container(
          width: 4.0,
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
    );
  }
}
