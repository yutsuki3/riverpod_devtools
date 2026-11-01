
import 'package:flutter/material.dart';
import '../../models/event_type.dart';
import '../../models/provider_info.dart';
import '../../providers/inspector_notifier.dart';
import '../common/error_details.dart';
import '../common/json_tree_view.dart';
import '../common/copy_button.dart';
import '../common/copy_for_ai_button.dart';
import '../../utils/provider_brief.dart';
import '../common/panel_ui.dart';
import 'name_mismatch_dropdown.dart';
import 'load_error_dropdown.dart';
import 'static_analysis_required_dropdown.dart';
import 'update_info_dropdown.dart';
import 'command_bar.dart';

export 'command_bar.dart' show CommandResult, CommandSender;

class DetailPanel extends StatelessWidget {
  final InspectorNotifier notifier;

  /// Hint shown when no provider is selected. The default matches the
  /// Inspector view; the Graph view passes its own wording since there is
  /// no provider list there.
  final String noSelectionHint;

  const DetailPanel({
    super.key,
    required this.notifier,
    this.noSelectionHint = 'Pick a provider from the list on the left',
  });

  /// Test seam: when set, Invalidate/Refresh route here instead of the real
  /// `ext.riverpod_devtools.command` service extension, so the command bar
  /// can be driven without a live VM service.
  @visibleForTesting
  static CommandSender? debugCommandSender;

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
            const PanelHeader(
              icon: Icons.description_outlined,
              title: 'Provider Details',
            ),

            // Tabs (only show when multiple providers selected)
            if (state.selectedProviderNames.length > 1)
              Container(
                height: 34,
                padding: const EdgeInsets.symmetric(horizontal: 6),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(
                      color: theme.colorScheme.outline.withValues(alpha: 0.12),
                    ),
                  ),
                ),
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: state.selectedProviderNames.map((providerName) {
                    final isActive =
                        state.activeTabProviderName == providerName;
                    return Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 2, vertical: 5),
                      child: InkWell(
                        onTap: () => notifier.setActiveTab(providerName),
                        borderRadius: BorderRadius.circular(999),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 3),
                          decoration: BoxDecoration(
                            color: isActive
                                ? theme.colorScheme.primary
                                    .withValues(alpha: 0.12)
                                : theme.colorScheme.surfaceContainerHighest
                                    .withValues(alpha: 0.4),
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(
                              color: isActive
                                  ? theme.colorScheme.primary
                                      .withValues(alpha: 0.5)
                                  : theme.colorScheme.outline
                                      .withValues(alpha: 0.15),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                providerName.length > 20
                                    ? '${providerName.substring(0, 20)}...'
                                    : providerName,
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: isActive
                                      ? FontWeight.w600
                                      : FontWeight.normal,
                                  color: isActive
                                      ? theme.colorScheme.primary
                                      : theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                              const SizedBox(width: 5),
                              InkWell(
                                onTap: () => notifier
                                    .removeSelectedProvider(providerName),
                                borderRadius: BorderRadius.circular(999),
                                child: Icon(
                                  Icons.close,
                                  size: 11,
                                  color: theme.colorScheme.onSurfaceVariant
                                      .withValues(alpha: 0.6),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),

            // Content
            Expanded(
              child: state.selectedProviderNames.isEmpty
                  ? EmptyState(
                      icon: Icons.touch_app_outlined,
                      message: 'Select a provider to view details',
                      hint: noSelectionHint,
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
      return const EmptyState(
        icon: Icons.error_outline,
        message: 'Provider not found',
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Provider Name (Large Display)
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: SelectableText(
                        provider.name,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.2,
                          color: theme.colorScheme.onSurface,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    CopyForAiButton(
                      textBuilder: () => buildProviderBrief(
                        provider,
                        usedBy: notifier.getUsedBy(provider.name),
                        events: notifier.eventsFor(provider.name),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                ProviderCommandBar(
                  sender: debugCommandSender,
                  providerName: provider.name,
                  isActive: provider.status == ProviderStatus.active,
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
                    .withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: theme.colorScheme.outline.withValues(alpha: 0.12),
                ),
              ),
              child: JsonTreeView(data: provider.value),
            ),
          ),

          const SizedBox(height: 16),

          // Error Section (only while the provider is in a failed state)
          if (provider.lastError != null) ...[
            _buildDetailSection(
              theme: theme,
              title: 'Error',
              child: ErrorDetails(error: provider.lastError),
            ),
            const SizedBox(height: 16),
          ],

          // Last Update Section
          _buildLastUpdateSection(theme, provider),

          const SizedBox(height: 16),

          // Dependencies Section
          _buildDetailSection(
            theme: theme,
            title: 'Dependencies',
            betaBadge:
                false, // No beta badge - static analysis is the only method
            child: provider.dependenciesSource == DependencySource.static
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Collapsible update info dropdown
                      if (provider.dependenciesGeneratedAt != null) ...[
                        const SizedBox(height: 2),
                        UpdateInfoDropdown(
                          theme: theme,
                          generatedAt: provider.dependenciesGeneratedAt!,
                          formatDateTime: _formatDateTime,
                        ),
                        const SizedBox(height: 8),
                      ],

                      // Depends On subsection
                      _buildDependencySubsection(
                        context: context,
                        title: 'Depends On',
                        dependencies: provider.dependencies,
                        emptyMessage: 'No dependencies',
                        theme: theme,
                        state: state,
                        dependencySource: provider.dependenciesSource,
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
                        dependencySource: null, // Used By doesn't have a source
                      ),
                    ],
                  )
                : provider.dependenciesSource == DependencySource.loadError
                    ? // The dependency JSON exists but could not be parsed
                    Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: 2),
                          LoadErrorDropdown(
                            theme: theme,
                            message: provider.dependenciesLoadError,
                          ),
                        ],
                      )
                    : provider.dependenciesSource ==
                            DependencySource.nameMismatch
                        ? // Provider name mismatch warning (no Depends On/Used By sections)
                        Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const SizedBox(height: 2),
                              NameMismatchDropdown(theme: theme),
                            ],
                          )
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const SizedBox(height: 2),
                              StaticAnalysisRequiredDropdown(
                                theme: theme,
                                buildSetupStep: _buildSetupStep,
                              ),
                            ],
                          ),
          ),
        ],
      ),
    );
  }

  Widget _buildLastUpdateSection(ThemeData theme, ProviderInfo provider) {
    final lastEvent = notifier.latestEventFor(provider.name);

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
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: theme.colorScheme.outline.withValues(alpha: 0.12),
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
      EventType.failed => 'Failed',
      EventType.disposed => 'Disposed',
    };

    final timeString = '${lastEvent.timestamp.hour.toString().padLeft(2, '0')}:'
        '${lastEvent.timestamp.minute.toString().padLeft(2, '0')}:'
        '${lastEvent.timestamp.second.toString().padLeft(2, '0')}';

    final triggerSuffix = lastEvent.triggeredBy.isEmpty
        ? ''
        : ' · triggered by '
            '${lastEvent.triggeredBy.map((t) => t.provider).join(', ')}';

    return _buildDetailSection(
      theme: theme,
      title: 'Last Update',
      child: Padding(
        padding: const EdgeInsets.only(left: 4, top: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.schedule,
              size: 11,
              color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
            ),
            const SizedBox(width: 5),
            Flexible(
              child: SelectableText(
                '$eventTypeString ($timeString)$triggerSuffix',
                style: TextStyle(
                  fontSize: 10,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.9),
                ),
              ),
            ),
          ],
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
            Container(
              width: 3,
              height: 11,
              margin: const EdgeInsets.only(right: 6),
              decoration: BoxDecoration(
                color: theme.colorScheme.primary,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Text(
              title,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.3,
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
    DependencySource? dependencySource,
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
              spacing: 5,
              runSpacing: 5,
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
                      }
                    },
                    borderRadius: BorderRadius.circular(999),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: isActive
                            ? theme.colorScheme.primary
                            : isSelected
                                ? theme.colorScheme.primary
                                    .withValues(alpha: 0.12)
                                : theme.colorScheme.surfaceContainerHighest
                                    .withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                          color: isActive
                              ? theme.colorScheme.primary
                              : isSelected
                                  ? theme.colorScheme.primary
                                      .withValues(alpha: 0.4)
                                  : theme.colorScheme.outline
                                      .withValues(alpha: 0.15),
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
                              fontSize: 9.5,
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

  Widget _buildSetupStep({
    required ThemeData theme,
    required String number,
    required String title,
    required String description,
    required String code,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '$number. ',
              style: TextStyle(
                fontSize: 8,
                fontWeight: FontWeight.w600,
                color:
                    theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 8,
                      fontWeight: FontWeight.w600,
                      color: theme.colorScheme.onSurfaceVariant
                          .withValues(alpha: 0.7),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    description,
                    style: TextStyle(
                      fontSize: 8,
                      color: theme.colorScheme.onSurfaceVariant
                          .withValues(alpha: 0.7),
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(6),
          margin: const EdgeInsets.only(left: 20),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest
                .withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(3),
            border: Border.all(
              color: theme.colorScheme.outline.withValues(alpha: 0.2),
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: SelectableText(
                  code,
                  style: TextStyle(
                    fontSize: 8,
                    fontFamily: 'monospace',
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              CopyButton(
                textToCopy: code,
                size: 12,
                tooltipMessage: 'Copy code',
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// Format DateTime to a readable string: "yyyy/MM/dd HH:mm:ss"
  String _formatDateTime(DateTime dateTime) {
    final year = dateTime.year;
    final month = dateTime.month.toString().padLeft(2, '0');
    final day = dateTime.day.toString().padLeft(2, '0');
    final hour = dateTime.hour.toString().padLeft(2, '0');
    final minute = dateTime.minute.toString().padLeft(2, '0');
    final second = dateTime.second.toString().padLeft(2, '0');
    return '$year/$month/$day $hour:$minute:$second';
  }
}
