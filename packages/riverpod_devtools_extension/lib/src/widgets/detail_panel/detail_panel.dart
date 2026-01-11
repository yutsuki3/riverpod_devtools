import 'package:flutter/material.dart';
import '../../models/event_type.dart';
import '../../models/provider_info.dart';
import '../../providers/inspector_notifier.dart';
import '../common/json_tree_view.dart';

class DetailPanel extends StatelessWidget {
  final InspectorNotifier notifier;
  final VoidCallback? onProviderJump;

  const DetailPanel({
    super.key,
    required this.notifier,
    this.onProviderJump,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ListenableBuilder(
      listenable: notifier,
      builder: (context, child) {
        final state = notifier.state;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              color: theme.colorScheme.surfaceContainerHighest,
              width: double.infinity,
              height: 32,
              alignment: Alignment.centerLeft,
              child: const Text(
                'Provider Details',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
            ),

            // Tabs (only show when multiple providers selected)
            if (state.selectedProviderNames.length > 1)
              Container(
                height: 28,
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(
                      color: theme.colorScheme.outline.withValues(alpha: 0.2),
                    ),
                  ),
                ),
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: state.selectedProviderNames.map((providerName) {
                    final isActive =
                        state.activeTabProviderName == providerName;
                    return InkWell(
                      onTap: () => notifier.setActiveTab(providerName),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: isActive
                              ? theme.colorScheme.primary.withValues(alpha: 0.1)
                              : null,
                          border: isActive
                              ? Border(
                                  bottom: BorderSide(
                                    color: theme.colorScheme.primary,
                                    width: 2,
                                  ),
                                )
                              : null,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              providerName.length > 20
                                  ? '${providerName.substring(0, 20)}...'
                                  : providerName,
                              style: TextStyle(
                                fontSize: 9,
                                fontWeight: isActive
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                                color: isActive
                                    ? theme.colorScheme.primary
                                    : theme.colorScheme.onSurface,
                              ),
                            ),
                            const SizedBox(width: 4),
                            InkWell(
                              onTap: () =>
                                  notifier.removeSelectedProvider(providerName),
                              child: Icon(
                                Icons.close,
                                size: 12,
                                color: theme.colorScheme.onSurfaceVariant
                                    .withValues(alpha: 0.6),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),

            // Content
            Expanded(
              child: state.selectedProviderNames.isEmpty
                  ? Center(
                      child: Text(
                        'Select a provider to view details',
                        style: TextStyle(
                          fontSize: 12,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    )
                  : _buildSelectedProviderDetail(context, state, theme),
            ),
          ],
        );
      },
    );
  }

  Widget _buildSelectedProviderDetail(
      BuildContext context, InspectorState state, ThemeData theme) {
    String displayProviderName;
    if (state.selectedProviderNames.length == 1) {
      displayProviderName = state.selectedProviderNames.first;
    } else {
      if (state.activeTabProviderName != null &&
          state.selectedProviderNames.contains(state.activeTabProviderName)) {
        displayProviderName = state.activeTabProviderName!;
      } else {
        displayProviderName = state.selectedProviderNames.first;
      }
    }

    final provider = state.providers[displayProviderName];
    if (provider == null) {
      return Center(
        child: Text(
          'Provider not found',
          style: TextStyle(
            fontSize: 12,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Provider Name (Large Display)
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  provider.name,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(
                      provider.status == ProviderStatus.active
                          ? Icons.circle
                          : Icons.circle_outlined,
                      size: 12,
                      color: provider.status == ProviderStatus.active
                          ? Colors.greenAccent
                          : theme.colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      provider.status == ProviderStatus.active
                          ? 'Active'
                          : 'Disposed',
                      style: TextStyle(
                        fontSize: 11,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // State Section
          _buildDetailSection(
            theme: theme,
            title: 'Current State',
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest
                    .withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(
                  color: theme.colorScheme.outline.withValues(alpha: 0.2),
                ),
              ),
              child: JsonTreeView(data: provider.value),
            ),
          ),

          const SizedBox(height: 16),

          // Last Update Section
          _buildLastUpdateSection(theme, provider),

          const SizedBox(height: 16),

          // Dependencies Section (with Beta badge)
          _buildDetailSection(
            theme: theme,
            title: 'Dependencies',
            betaBadge: true,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Note UI
                Container(
                  width: double.infinity,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: Colors.blue.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(
                      color: Colors.blue.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Text(
                    'Dependencies are detected by observing update patterns. May include false positives.',
                    style: TextStyle(
                      fontSize: 9,
                      color: theme.colorScheme.onSurfaceVariant,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ),

                // Depends On subsection
                _buildDependencySubsection(
                  context: context,
                  title: 'Depends On',
                  dependencies: provider.dependencies,
                  emptyMessage: 'No dependencies detected yet',
                  theme: theme,
                  state: state,
                ),

                const SizedBox(height: 12),

                // Used By subsection
                _buildDependencySubsection(
                  context: context,
                  title: 'Used By',
                  dependencies: notifier.getUsedBy(provider.name),
                  emptyMessage: 'Not used by any providers',
                  theme: theme,
                  state: state,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLastUpdateSection(ThemeData theme, ProviderInfo provider) {
    // We need to look at events logic here. It's in the notifier.
    // For now we'll just implement it similarly.
    final providerEvents = notifier.filteredEvents
        .where((e) => e.providerName == provider.name)
        .toList();
    final lastEvent = providerEvents.isNotEmpty ? providerEvents.first : null;

    if (lastEvent == null) {
      return _buildDetailSection(
        theme: theme,
        title: 'Last Update',
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest
                .withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: theme.colorScheme.outline.withValues(alpha: 0.2),
            ),
          ),
          child: Text(
            'No changes recorded',
            style: TextStyle(
              fontSize: 10,
              color: theme.colorScheme.onSurfaceVariant,
              fontStyle: FontStyle.italic,
            ),
          ),
        ),
      );
    }

    final eventTypeString = switch (lastEvent.type) {
      EventType.added => 'Added',
      EventType.updated => 'Updated',
      EventType.disposed => 'Disposed',
    };

    final timeString = '${lastEvent.timestamp.hour.toString().padLeft(2, '0')}:'
        '${lastEvent.timestamp.minute.toString().padLeft(2, '0')}:'
        '${lastEvent.timestamp.second.toString().padLeft(2, '0')}';

    return _buildDetailSection(
      theme: theme,
      title: 'Last Update',
      child: Padding(
        padding: const EdgeInsets.only(left: 4, top: 2),
        child: Text(
          '$eventTypeString ($timeString)',
          style: TextStyle(
            fontSize: 10,
            color: theme.colorScheme.onSurface.withValues(alpha: 0.9),
          ),
        ),
      ),
    );
  }

  Widget _buildDetailSection({
    required ThemeData theme,
    required String title,
    required Widget child,
    bool betaBadge = false,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              title,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: theme.colorScheme.primary,
              ),
            ),
            if (betaBadge) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.fromLTRB(3, 2, 3, 1),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest
                      .withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(2),
                  border: Border.all(
                    color: theme.colorScheme.outline.withValues(alpha: 0.3),
                    width: 0.5,
                  ),
                ),
                child: Text(
                  'BETA',
                  style: TextStyle(
                    fontSize: 7,
                    fontWeight: FontWeight.w500,
                    color: theme.colorScheme.onSurfaceVariant
                        .withValues(alpha: 0.6),
                  ),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 4),
        child,
      ],
    );
  }

  Widget _buildDependencySubsection({
    required BuildContext context,
    required String title,
    required List<String> dependencies,
    required String emptyMessage,
    required ThemeData theme,
    required InspectorState state,
  }) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(
              title,
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w600,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          if (dependencies.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 4),
              child: Text(
                emptyMessage,
                style: TextStyle(
                  fontSize: 10,
                  color:
                      theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                  fontStyle: FontStyle.italic,
                ),
              ),
            )
          else
            Wrap(
              spacing: 4,
              runSpacing: 4,
              children: dependencies.map((name) {
                final isSelected = state.selectedProviderNames.contains(name);
                final isActive = state.activeTabProviderName == name;

                return Tooltip(
                  message: isActive
                      ? 'Currently viewing $name'
                      : isSelected
                          ? 'Jump to $name'
                          : 'Add $name to selection',
                  child: InkWell(
                    onTap: () {
                      final wasNotSelected = !isSelected;
                      if (!isSelected) {
                        notifier.selectProvider(name);
                      } else {
                        notifier.setActiveTab(name);
                      }
                      if (wasNotSelected) {
                        notifier.flashProvider(name);
                        onProviderJump?.call();
                      }
                    },
                    borderRadius: BorderRadius.circular(4),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: isActive
                            ? theme.colorScheme.primary
                            : isSelected
                                ? theme.colorScheme.primary
                                    .withValues(alpha: 0.1)
                                : theme.colorScheme.surfaceContainerHighest
                                    .withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                          color: isActive
                              ? theme.colorScheme.primary
                              : isSelected
                                  ? theme.colorScheme.primary
                                      .withValues(alpha: 0.4)
                                  : theme.colorScheme.outline
                                      .withValues(alpha: 0.1),
                          width: 1,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            isActive
                                ? Icons.visibility
                                : isSelected
                                    ? Icons.open_in_new
                                    : Icons.add,
                            size: 10,
                            color: isActive
                                ? theme.colorScheme.onPrimary
                                : theme.colorScheme.primary,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            name,
                            style: TextStyle(
                              fontSize: 9,
                              fontFamily: 'monospace',
                              color: isActive
                                  ? theme.colorScheme.onPrimary
                                  : isSelected
                                      ? theme.colorScheme.primary
                                      : theme.colorScheme.onSurfaceVariant,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
        ],
      ),
    );
  }
}
