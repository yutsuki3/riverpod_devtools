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
  final FocusNode _searchFocus = FocusNode();

  /// Receives arrow / Esc / `/` keys for the whole panel. Tapping a tile
  /// moves focus here so the keyboard keeps working after a mouse click.
  final FocusNode _panelFocus = FocusNode(debugLabel: 'provider list');

  /// Keys of the rows currently built, used to scroll a keyboard-selected
  /// provider into view.
  final Map<String, GlobalKey> _tileKeys = {};

  /// Family names whose instances are currently collapsed (hidden). Kept
  /// in local state — it survives the ListenableBuilder rebuilds that fire
  /// on every provider event.
  final Set<String> _collapsedFamilies = {};

  @override
  void initState() {
    super.initState();
    _searchController.text = widget.notifier.state.providerSearchQuery;
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocus.dispose();
    _panelFocus.dispose();
    super.dispose();
  }

  /// Visible provider rows in display order (collapsed family instances and
  /// family headers are skipped).
  List<String> _visibleProviderNames() => [
        for (final row in _buildRows(widget.notifier.filteredProviders))
          if (row.provider != null) row.provider!.name,
      ];

  /// Moves the single selection one row up/down; from no selection, Down
  /// picks the first row and Up the last.
  void _moveSelection(int delta) {
    final names = _visibleProviderNames();
    if (names.isEmpty) return;
    final selected = widget.notifier.state.selectedProviderNames;
    final current =
        selected.isEmpty ? -1 : names.lastIndexWhere(selected.contains);
    final int next;
    if (current == -1) {
      next = delta > 0 ? 0 : names.length - 1;
    } else {
      next = (current + delta).clamp(0, names.length - 1);
    }
    // selectOnly() toggles a lone selection off (click semantics); at the
    // ends of the list the arrow must instead stay put.
    if (selected.length == 1 && selected.first == names[next]) return;
    widget.notifier.selectOnly(names[next]);
    _scrollIntoView(names[next], next, names.length);
  }

  void _scrollIntoView(String name, int index, int count) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final context = _tileKeys[name]?.currentContext;
      if (context != null) {
        Scrollable.ensureVisible(context, alignment: 0.5);
        return;
      }
      // Not built yet (far off-screen): jump near it, then settle exactly.
      if (!widget.scrollController.hasClients || count < 2) return;
      final max = widget.scrollController.position.maxScrollExtent;
      widget.scrollController.jumpTo(max * index / (count - 1));
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final built = _tileKeys[name]?.currentContext;
        if (mounted && built != null) {
          Scrollable.ensureVisible(built, alignment: 0.5);
        }
      });
    });
  }

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowDown) {
      _moveSelection(1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp) {
      _moveSelection(-1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.escape) {
      if (widget.notifier.state.providerSearchQuery.isNotEmpty) {
        _searchController.clear();
        widget.notifier.updateSearchQuery('');
      } else if (widget.notifier.state.selectedProviderNames.isNotEmpty) {
        widget.notifier.clearSelection();
      } else {
        return KeyEventResult.ignored;
      }
      _panelFocus.requestFocus();
      return KeyEventResult.handled;
    }
    // "/" jumps to search, but must stay typeable inside the search field.
    if (key == LogicalKeyboardKey.slash && !_searchFocus.hasFocus) {
      _searchFocus.requestFocus();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  /// Applies the click-selection rules used by both standalone tiles and
  /// family-instance tiles (Ctrl/Cmd toggles multi-select; a plain click
  /// selects just this one, or deselects if it was the only selection).
  /// Reads the notifier's *current* state so the outcome cannot depend on
  /// how long ago the surrounding widget was built.
  void _handleSelect(String name, bool isCtrlOrCmd) {
    _panelFocus.requestFocus();
    if (isCtrlOrCmd) {
      if (widget.notifier.state.selectedProviderNames.contains(name)) {
        widget.notifier.removeSelectedProvider(name);
      } else {
        widget.notifier.selectProvider(name);
      }
      return;
    }
    widget.notifier.selectOnly(name);
  }

  /// Groups [providers] into display rows: a family with 2+ instances gets
  /// a collapsible header followed by its (optionally hidden) instances;
  /// everything else is a plain provider row. First-appearance order is
  /// preserved.
  List<_ListRow> _buildRows(List<ProviderInfo> providers) {
    final families = <String, List<ProviderInfo>>{};
    for (final p in providers) {
      if (p.family != null) {
        families.putIfAbsent(p.family!, () => []).add(p);
      }
    }

    final rows = <_ListRow>[];
    final emitted = <String>{};
    for (final p in providers) {
      final family = p.family;
      final grouped = family != null && families[family]!.length > 1;
      if (grouped) {
        if (!emitted.add(family)) continue; // header already emitted
        final instances = families[family]!;
        rows.add(_ListRow.familyHeader(family, instances));
        if (!_collapsedFamilies.contains(family)) {
          for (final inst in instances) {
            rows.add(_ListRow.provider(inst, isFamilyInstance: true));
          }
        }
      } else {
        rows.add(_ListRow.provider(p, isFamilyInstance: false));
      }
    }
    return rows;
  }

  @override
  Widget build(BuildContext context) => Focus(
        focusNode: _panelFocus,
        onKeyEvent: _handleKey,
        child: _buildPanel(context),
      );

  Widget _buildPanel(BuildContext context) {
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
                    onPressed: widget.notifier.clearSelection,
                  ),
              ],
            ),
            // Search field
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
              child: TextField(
                controller: _searchController,
                focusNode: _searchFocus,
                onChanged: (value) {
                  widget.notifier.updateSearchQuery(value);
                },
                style: const TextStyle(fontSize: 11),
                decoration: InputDecoration(
                  hintText: 'Search providers...  ( / )',
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
                          // Tapping empty area deselects all. Tile taps
                          // never reach this: each tile has its own tap
                          // recognizer, which wins the gesture arena as
                          // the deeper node.
                          onTap: widget.notifier.clearSelection,
                          child: Builder(
                            builder: (context) {
                              final rows = _buildRows(filteredProviders);
                              return ListView.builder(
                                controller: widget.scrollController,
                                padding:
                                    const EdgeInsets.symmetric(vertical: 4),
                                itemCount: rows.length,
                                itemBuilder: (context, index) {
                                  final row = rows[index];
                                  if (row.familyName != null) {
                                    return _FamilyHeaderTile(
                                      family: row.familyName!,
                                      instanceCount: row.instances!.length,
                                      collapsed: _collapsedFamilies
                                          .contains(row.familyName),
                                      onToggle: () => setState(() {
                                        if (!_collapsedFamilies
                                            .remove(row.familyName)) {
                                          _collapsedFamilies
                                              .add(row.familyName!);
                                        }
                                      }),
                                    );
                                  }
                                  final provider = row.provider!;
                                  final isSelected = state.selectedProviderNames
                                      .contains(provider.name);
                                  return _ProviderListTile(
                                    key: _tileKeys.putIfAbsent(
                                        provider.name, () => GlobalKey()),
                                    provider: provider,
                                    stats: statsByProvider[provider.name],
                                    isSelected: isSelected,
                                    isFlashing: state.flashingProviderName ==
                                        provider.name,
                                    isFamilyInstance: row.isFamilyInstance,
                                    onSelect: (isCtrlOrCmd) => _handleSelect(
                                        provider.name, isCtrlOrCmd),
                                  );
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
                      'Ctrl/Cmd+Click multi-select · ↑↓ move · / search · Esc clear',
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

/// One row of the provider list: either a plain provider, a family
/// instance (indented under its header), or a family header.
class _ListRow {
  final ProviderInfo? provider;
  final bool isFamilyInstance;
  final String? familyName;
  final List<ProviderInfo>? instances;

  _ListRow.provider(this.provider, {required this.isFamilyInstance})
      : familyName = null,
        instances = null;

  _ListRow.familyHeader(this.familyName, this.instances)
      : provider = null,
        isFamilyInstance = false;
}

/// Collapsible header for a `.family` — groups its instances and shows how
/// many there are.
class _FamilyHeaderTile extends StatelessWidget {
  final String family;
  final int instanceCount;
  final bool collapsed;
  final VoidCallback onToggle;

  const _FamilyHeaderTile({
    required this.family,
    required this.instanceCount,
    required this.collapsed,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onToggle,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
        child: Row(
          children: [
            Icon(
              collapsed ? Icons.chevron_right : Icons.expand_more,
              size: 16,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 2),
            Icon(Icons.workspaces_outline,
                size: 12, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                family,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: theme.colorScheme.onSurface,
                ),
              ),
            ),
            const SizedBox(width: 6),
            CountBadge(count: instanceCount),
          ],
        ),
      ),
    );
  }
}

class _ProviderListTile extends StatefulWidget {
  final ProviderInfo provider;
  final ProviderStats? stats;
  final bool isSelected;
  final bool isFlashing;
  final bool isFamilyInstance;

  /// Called on tap with whether Ctrl/Cmd was held when the press started.
  final void Function(bool isCtrlOrCmd) onSelect;

  const _ProviderListTile({
    super.key,
    required this.provider,
    required this.stats,
    required this.isSelected,
    required this.isFlashing,
    required this.onSelect,
    this.isFamilyInstance = false,
  });

  @override
  State<_ProviderListTile> createState() => _ProviderListTileState();
}

class _ProviderListTileState extends State<_ProviderListTile> {
  /// Modifier state captured at pointer-down: by the time onTap fires (on
  /// pointer-up) the user may already have released Ctrl/Cmd.
  bool _ctrlOrCmdAtPress = false;

  ProviderInfo get provider => widget.provider;
  ProviderStats? get stats => widget.stats;
  bool get isSelected => widget.isSelected;
  bool get isFlashing => widget.isFlashing;
  bool get isFamilyInstance => widget.isFamilyInstance;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isActive = provider.status == ProviderStatus.active;
    // Under a family header the base name is redundant; show just the
    // argument (e.g. "1" for userProvider(1)).
    final label = isFamilyInstance
        ? '(${provider.argument ?? provider.name})'
        : provider.name;

    // A real tap gesture (not a raw pointer listener): the tile enters the
    // gesture arena and, as the deeper node, beats the surrounding
    // "tap empty area to deselect" GestureDetector. With the old
    // Listener.onPointerDown approach both fired on every click, so
    // whether a selection survived depended on frame timing.
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) {
        _ctrlOrCmdAtPress = HardwareKeyboard.instance.isMetaPressed ||
            HardwareKeyboard.instance.isControlPressed;
      },
      onTap: () => widget.onSelect(_ctrlOrCmdAtPress),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          margin: EdgeInsets.only(
            left: isFamilyInstance ? 24 : 6,
            right: 6,
            top: 1,
            bottom: 1,
          ),
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
                  label,
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
