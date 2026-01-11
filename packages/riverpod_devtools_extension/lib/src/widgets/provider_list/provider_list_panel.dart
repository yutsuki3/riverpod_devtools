import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../models/provider_info.dart';
import '../../providers/inspector_notifier.dart';

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

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              color: theme.colorScheme.surfaceContainerHighest,
              width: double.infinity,
              height: 32,
              alignment: Alignment.centerLeft,
              child: Row(
                children: [
                  const Text(
                    'Providers',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                  const Spacer(),
                  if (state.selectedProviderNames.isNotEmpty)
                    TextButton(
                      onPressed: () {
                        for (final name
                            in state.selectedProviderNames.toList()) {
                          widget.notifier.removeSelectedProvider(name);
                        }
                      },
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        minimumSize: const Size(0, 24),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child:
                          const Text('Clear', style: TextStyle(fontSize: 10)),
                    ),
                ],
              ),
            ),
            // Search field
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
              child: TextField(
                controller: _searchController,
                onChanged: (value) {
                  widget.notifier.updateSearchQuery(value);
                },
                style: const TextStyle(fontSize: 10),
                decoration: InputDecoration(
                  hintText: 'Search providers...',
                  hintStyle: TextStyle(
                    fontSize: 10,
                    color: theme.colorScheme.onSurfaceVariant
                        .withValues(alpha: 0.6),
                  ),
                  prefixIcon: Padding(
                    padding: const EdgeInsets.only(left: 6),
                    child: Icon(
                      Icons.search,
                      size: 14,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  prefixIconConstraints: const BoxConstraints(
                    minWidth: 20,
                    minHeight: 20,
                  ),
                  suffixIcon: SizedBox(
                    width: 20,
                    height: 20,
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
                  constraints: const BoxConstraints(
                    maxHeight: 32,
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 6,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(4),
                    borderSide: BorderSide(
                      color: theme.colorScheme.outline.withValues(alpha: 0.3),
                    ),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(4),
                    borderSide: BorderSide(
                      color: theme.colorScheme.outline.withValues(alpha: 0.3),
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(4),
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
                  ? Center(
                      child: Text(
                        'No providers yet',
                        style: TextStyle(
                          fontSize: 12,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    )
                  : filteredProviders.isEmpty
                      ? Center(
                          child: Text(
                            'No providers found',
                            style: TextStyle(
                              fontSize: 12,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
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
                            itemCount: filteredProviders.length,
                            itemBuilder: (context, index) {
                              final provider = filteredProviders[index];
                              final isSelected = state.selectedProviderNames
                                  .contains(provider.name);
                              final isFlashing =
                                  state.flashingProviderName == provider.name;
                              return Theme(
                                data: Theme.of(context).copyWith(
                                  splashFactory: NoSplash.splashFactory,
                                  highlightColor: Colors.transparent,
                                ),
                                child: Listener(
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
                                  child: InkWell(
                                    onTap: () {},
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 4,
                                      ),
                                      color: isFlashing
                                          ? theme.colorScheme.primary
                                              .withValues(alpha: 0.3)
                                          : isSelected
                                              ? theme.colorScheme.primary
                                                  .withValues(alpha: 0.1)
                                              : null,
                                      child: Row(
                                        children: [
                                          Icon(
                                            provider.status ==
                                                    ProviderStatus.active
                                                ? Icons.circle
                                                : Icons.circle_outlined,
                                            size: 8,
                                            color: provider.status ==
                                                    ProviderStatus.active
                                                ? Colors.greenAccent
                                                : theme.colorScheme
                                                    .onSurfaceVariant,
                                          ),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: Text(
                                              provider.name,
                                              style:
                                                  const TextStyle(fontSize: 10),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
            ),
            // Operation hint
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              color: theme.colorScheme.surfaceContainerHighest
                  .withValues(alpha: 0.3),
              child: Text(
                'Tip: Ctrl/Cmd+Click for multi-selection',
                style: TextStyle(
                  fontSize: 8,
                  color:
                      theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
