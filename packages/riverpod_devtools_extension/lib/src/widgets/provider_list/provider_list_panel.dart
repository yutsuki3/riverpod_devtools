import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../models/provider_info.dart';
import '../../providers/inspector_notifier.dart';
import '../../utils/provider_stats.dart';
import '../common/panel_ui.dart';

class ProviderListPanel extends StatefulWidget {
  final InspectorNotifier notifier;
  final ScrollController scrollController;

  const ProviderListPanel({
    super.key,
    required this.notifier,
    required this.scrollController,
  });

  @override
  State<ProviderListPanel> createState() => _ProviderListPanelState();
}

class _ProviderListPanelState extends State<ProviderListPanel> {
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _searchController.text = widget.notifier.state.providerSearchQuery;
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ListenableBuilder(
      listenable: widget.notifier,
      builder: (context, child) {
        final state = widget.notifier.state;
        final filteredProviders = widget.notifier.filteredProviders;
        final statsByProvider = <String, ProviderStats>{
          for (final stat in widget.notifier.providerStats)
            stat.providerName: stat,
        };

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            PanelHeader(
              icon: Icons.account_tree_outlined,
              title: 'Providers',
              count: state.providers.length,
              actions: [
                if (state.selectedProviderNames.isNotEmpty)
                  HeaderActionButton(
                    label: 'Clear',
                    icon: Icons.close,
                    onPressed: () {
                      for (final name in state.selectedProviderNames.toList()) {
                        widget.notifier.removeSelectedProvider(name);
                      }
                    },
                  ),
              ],
            ),
            // Search field
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
              child: TextField(
                controller: _searchController,
                onChanged: (value) {
                  widget.notifier.updateSearchQuery(value);
                },
                style: const TextStyle(fontSize: 11),
                decoration: InputDecoration(
                  hintText: 'Search providers...',
                  hintStyle: TextStyle(
                    fontSize: 11,
                    color: theme.colorScheme.onSurfaceVariant
                        .withValues(alpha: 0.6),
                  ),
                  prefixIcon: Padding(
                    padding: const EdgeInsets.only(left: 8, right: 4),
                    child: Icon(
                      Icons.search,
                      size: 14,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  prefixIconConstraints: const BoxConstraints(
                    minWidth: 26,
                    minHeight: 20,
                  ),
                  suffixIcon: SizedBox(
                    width: 24,
                    height: 24,
                    child: state.providerSearchQuery.isNotEmpty
                        ? IconButton(
                            icon: Icon(
                              Icons.clear,
                              size: 14,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                            onPressed: () {
                              _searchController.clear();
                              widget.notifier.updateSearchQuery('');
                            },
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                          )
                        : null,
                  ),
                  isDense: true,
                  filled: true,
                  fillColor: theme.colorScheme.surfaceContainerHighest
                      .withValues(alpha: 0.5),
                  constraints: const BoxConstraints(
                    maxHeight: 32,
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 7,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide.none,
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide.none,
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(
                      color: theme.colorScheme.primary,
                      width: 1.5,
                    ),
                  ),
                ),
              ),
            ),
            Expanded(
              child: state.providers.isEmpty
                  ? const EmptyState(
                      icon: Icons.hub_outlined,
                      message: 'No providers yet',
                      hint: 'Providers appear here once your app creates them',
                    )
                  : filteredProviders.isEmpty
                      ? const EmptyState(
                          icon: Icons.search_off,
                          message: 'No providers found',
                          hint: 'Try a different search query',
                        )
                      : GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () {
                            // Tapping empty area deselects all
                            for (final name
                                in state.selectedProviderNames.toList()) {
                              widget.notifier.removeSelectedProvider(name);
                            }
                          },
                          child: ListView.builder(
                            controller: widget.scrollController,
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            itemCount: filteredProviders.length,
                            itemBuilder: (context, index) {
                              final provider = filteredProviders[index];
                              final isSelected = state.selectedProviderNames
                                  .contains(provider.name);
                              final isFlashing =
                                  state.flashingProviderName == provider.name;
                              return _ProviderListTile(
                                provider: provider,
                                stats: statsByProvider[provider.name],
                                isSelected: isSelected,
                                isFlashing: isFlashing,
                                onPointerDown: (event) {
                                  final isCtrlOrCmd =
                                      event.kind == PointerDeviceKind.mouse &&
                                          (HardwareKeyboard
                                                  .instance.isMetaPressed ||
                                              HardwareKeyboard
                                                  .instance.isControlPressed);

                                  if (isCtrlOrCmd) {
                                    if (isSelected) {
                                      widget.notifier.removeSelectedProvider(
                                          provider.name);
                                    } else {
                                      widget.notifier
                                          .selectProvider(provider.name);
                                    }
                                  } else {
                                    if (isSelected &&
                                        state.selectedProviderNames.length ==
                                            1) {
                                      widget.notifier.removeSelectedProvider(
                                          provider.name);
                                    } else {
                                      // Reset selection and select this one
                                      for (final name in state
                                          .selectedProviderNames
                                          .toList()) {
                                        widget.notifier
                                            .removeSelectedProvider(name);
                                      }
                                      widget.notifier
                                          .selectProvider(provider.name);
                                    }
                                  }
                                },
                              );
                            },
                          ),
                        ),
            ),
            // Operation hint
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest
                    .withValues(alpha: 0.3),
                border: Border(
                  top: BorderSide(
                    color: theme.colorScheme.outline.withValues(alpha: 0.1),
                  ),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.info_outline,
                    size: 10,
                    color: theme.colorScheme.onSurfaceVariant
                        .withValues(alpha: 0.6),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      'Ctrl/Cmd+Click for multi-selection',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 9,
                        color: theme.colorScheme.onSurfaceVariant
                            .withValues(alpha: 0.7),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _ProviderListTile extends StatelessWidget {
  final ProviderInfo provider;
  final ProviderStats? stats;
  final bool isSelected;
  final bool isFlashing;
  final void Function(PointerDownEvent event) onPointerDown;

  const _ProviderListTile({
    required this.provider,
    required this.stats,
    required this.isSelected,
    required this.isFlashing,
    required this.onPointerDown,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isActive = provider.status == ProviderStatus.active;

    return Listener(
      onPointerDown: onPointerDown,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
          decoration: BoxDecoration(
            color: isFlashing
                ? theme.colorScheme.primary.withValues(alpha: 0.3)
                : isSelected
                    ? theme.colorScheme.primary.withValues(alpha: 0.12)
                    : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(
            children: [
              StatusDot(isActive: isActive, size: 7),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  provider.name,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight:
                        isSelected ? FontWeight.w600 : FontWeight.normal,
                    color: isSelected
                        ? theme.colorScheme.primary
                        : isActive
                            ? theme.colorScheme.onSurface
                            : theme.colorScheme.onSurfaceVariant
                                .withValues(alpha: 0.7),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (provider.lastError != null) ...[
                const SizedBox(width: 4),
                Tooltip(
                  message: provider.lastError!['message']?.toString() ??
                      'Provider failed',
                  waitDuration: const Duration(milliseconds: 400),
                  child: Icon(
                    Icons.error,
                    size: 12,
                    color: theme.brightness == Brightness.dark
                        ? const Color(0xFFE57373)
                        : const Color(0xFFD32F2F),
                  ),
                ),
              ],
              if (stats != null &&
                  (stats!.isHighFrequency || stats!.isSlowLoading)) ...[
                const SizedBox(width: 4),
                Tooltip(
                  message: [
                    if (stats!.isHighFrequency)
                      '${stats!.updatesPerSecond.toStringAsFixed(1)} updates/sec',
                    if (stats!.isSlowLoading)
                      'Slow load: ${_formatBadgeDuration(stats!.maxLoadDuration!)}',
                  ].join('\n'),
                  waitDuration: const Duration(milliseconds: 400),
                  child: Icon(
                    stats!.isHighFrequency
                        ? Icons.bolt
                        : Icons.hourglass_bottom,
                    size: 12,
                    color: theme.brightness == Brightness.dark
                        ? const Color(0xFFFFB74D)
                        : const Color(0xFFE65100),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

String _formatBadgeDuration(Duration d) {
  if (d.inMilliseconds < 1000) return '${d.inMilliseconds}ms';
  return '${(d.inMilliseconds / 1000).toStringAsFixed(1)}s';
}
