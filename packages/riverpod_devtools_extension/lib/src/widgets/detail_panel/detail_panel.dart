import 'dart:async';

import 'package:devtools_extensions/devtools_extensions.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../models/event_type.dart';
import '../../models/provider_info.dart';
import '../../providers/inspector_notifier.dart';
import '../common/error_details.dart';
import '../common/json_tree_view.dart';
import '../common/copy_button.dart';
import '../common/panel_ui.dart';

class DetailPanel extends StatelessWidget {
  final InspectorNotifier notifier;
  final VoidCallback? onProviderJump;

  /// Hint shown when no provider is selected. The default matches the
  /// Inspector view; the Graph view passes its own wording since there is
  /// no provider list there.
  final String noSelectionHint;

  const DetailPanel({
    super.key,
    required this.notifier,
    this.onProviderJump,
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
                SelectableText(
                  provider.name,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.2,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 6),
                _ProviderCommandBar(
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
                        _UpdateInfoDropdown(
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
                          _LoadErrorDropdown(
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
                              _NameMismatchDropdown(theme: theme),
                            ],
                          )
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const SizedBox(height: 2),
                              _StaticAnalysisRequiredDropdown(
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
                        onProviderJump?.call();
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

/// Collapsible dropdown widget for provider name mismatch warning
class _NameMismatchDropdown extends StatefulWidget {
  final ThemeData theme;

  const _NameMismatchDropdown({
    required this.theme,
  });

  @override
  State<_NameMismatchDropdown> createState() => _NameMismatchDropdownState();
}

class _NameMismatchDropdownState extends State<_NameMismatchDropdown> {
  bool _isExpanded = false;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: _isExpanded
            ? widget.theme.colorScheme.surfaceContainerHighest
                .withValues(alpha: 0.2)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        border: _isExpanded
            ? Border.all(
                color: widget.theme.colorScheme.outline.withValues(alpha: 0.15),
              )
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header with warning icon and title
          InkWell(
            onTap: () {
              setState(() {
                _isExpanded = !_isExpanded;
              });
            },
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
              child: Row(
                children: [
                  Icon(
                    Icons.warning_amber_rounded,
                    size: 9,
                    color: widget.theme.colorScheme.onSurfaceVariant
                        .withValues(alpha: 0.4),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      'Provider Name Mismatch',
                      style: TextStyle(
                        fontSize: 7.5,
                        color: widget.theme.colorScheme.onSurfaceVariant
                            .withValues(alpha: 0.5),
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ),
                  Icon(
                    _isExpanded ? Icons.expand_less : Icons.expand_more,
                    size: 12,
                    color: widget.theme.colorScheme.onSurfaceVariant
                        .withValues(alpha: 0.4),
                  ),
                ],
              ),
            ),
          ),

          // Expanded content
          if (_isExpanded) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(
                    color:
                        widget.theme.colorScheme.outline.withValues(alpha: 0.1),
                  ),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'The static analysis JSON file was loaded, but this provider name doesn\'t exactly match any entry in the file. Provider names must match exactly (case-sensitive).',
                    style: TextStyle(
                      fontSize: 8,
                      color: widget.theme.colorScheme.onSurfaceVariant
                          .withValues(alpha: 0.7),
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'To fix this issue:',
                    style: TextStyle(
                      fontSize: 8,
                      fontWeight: FontWeight.w600,
                      color: widget.theme.colorScheme.onSurfaceVariant
                          .withValues(alpha: 0.7),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '1. Update provider name in your code to match the JSON file',
                    style: TextStyle(
                      fontSize: 8,
                      color: widget.theme.colorScheme.onSurfaceVariant
                          .withValues(alpha: 0.7),
                      height: 1.3,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '2. Re-run the analyzer to update the JSON file',
                    style: TextStyle(
                      fontSize: 8,
                      color: widget.theme.colorScheme.onSurfaceVariant
                          .withValues(alpha: 0.7),
                      height: 1.3,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    width: double.infinity,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                    decoration: BoxDecoration(
                      color: widget.theme.colorScheme.surfaceContainerHighest
                          .withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(3),
                      border: Border.all(
                        color: widget.theme.colorScheme.outline
                            .withValues(alpha: 0.15),
                        width: 0.5,
                      ),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: SelectableText(
                            'dart run riverpod_devtools:analyze',
                            style: TextStyle(
                              fontSize: 8,
                              fontFamily: 'monospace',
                              color: widget.theme.colorScheme.onSurfaceVariant
                                  .withValues(alpha: 0.7),
                            ),
                          ),
                        ),
                        const SizedBox(width: 4),
                        CopyButton(
                          textToCopy: 'dart run riverpod_devtools:analyze',
                          size: 10,
                          color: widget.theme.colorScheme.onSurfaceVariant
                              .withValues(alpha: 0.5),
                          tooltipMessage: 'Copy command',
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Collapsible dropdown shown when the dependency JSON was found but failed
/// to parse (DependencySource.loadError). Unlike the "not set up" and "name
/// mismatch" states, this one carries the actual failure reason from the
/// observer, so the user sees *why* instead of just an empty graph.
class _LoadErrorDropdown extends StatefulWidget {
  final ThemeData theme;

  /// The parse-failure reason reported by the observer; null when an older
  /// observer sent the source without the message.
  final String? message;

  const _LoadErrorDropdown({
    required this.theme,
    required this.message,
  });

  @override
  State<_LoadErrorDropdown> createState() => _LoadErrorDropdownState();
}

class _LoadErrorDropdownState extends State<_LoadErrorDropdown> {
  bool _isExpanded = false;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: _isExpanded
            ? widget.theme.colorScheme.surfaceContainerHighest
                .withValues(alpha: 0.2)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        border: _isExpanded
            ? Border.all(
                color: widget.theme.colorScheme.outline.withValues(alpha: 0.15),
              )
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header with warning icon and title
          InkWell(
            onTap: () {
              setState(() {
                _isExpanded = !_isExpanded;
              });
            },
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
              child: Row(
                children: [
                  Icon(
                    Icons.error_outline_rounded,
                    size: 9,
                    color: widget.theme.colorScheme.error.withValues(alpha: 0.6),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      'Dependency Data Failed to Load',
                      style: TextStyle(
                        fontSize: 7.5,
                        color: widget.theme.colorScheme.onSurfaceVariant
                            .withValues(alpha: 0.5),
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ),
                  Icon(
                    _isExpanded ? Icons.expand_less : Icons.expand_more,
                    size: 12,
                    color: widget.theme.colorScheme.onSurfaceVariant
                        .withValues(alpha: 0.4),
                  ),
                ],
              ),
            ),
          ),

          // Expanded content
          if (_isExpanded) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(
                    color:
                        widget.theme.colorScheme.outline.withValues(alpha: 0.1),
                  ),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'riverpod_dependencies.json was found but could not be '
                    'parsed, so no dependency data is available.',
                    style: TextStyle(
                      fontSize: 8,
                      color: widget.theme.colorScheme.onSurfaceVariant
                          .withValues(alpha: 0.7),
                      height: 1.4,
                    ),
                  ),
                  if (widget.message != null) ...[
                    const SizedBox(height: 6),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 3),
                      decoration: BoxDecoration(
                        color: widget.theme.colorScheme.surfaceContainerHighest
                            .withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(3),
                        border: Border.all(
                          color: widget.theme.colorScheme.error
                              .withValues(alpha: 0.25),
                          width: 0.5,
                        ),
                      ),
                      child: SelectableText(
                        widget.message!,
                        style: TextStyle(
                          fontSize: 8,
                          fontFamily: 'monospace',
                          color: widget.theme.colorScheme.onSurfaceVariant
                              .withValues(alpha: 0.7),
                          height: 1.3,
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 8),
                  Text(
                    'To fix this issue, regenerate the file and hot-restart:',
                    style: TextStyle(
                      fontSize: 8,
                      fontWeight: FontWeight.w600,
                      color: widget.theme.colorScheme.onSurfaceVariant
                          .withValues(alpha: 0.7),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    width: double.infinity,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                    decoration: BoxDecoration(
                      color: widget.theme.colorScheme.surfaceContainerHighest
                          .withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(3),
                      border: Border.all(
                        color: widget.theme.colorScheme.outline
                            .withValues(alpha: 0.15),
                        width: 0.5,
                      ),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: SelectableText(
                            'dart run riverpod_devtools:analyze',
                            style: TextStyle(
                              fontSize: 8,
                              fontFamily: 'monospace',
                              color: widget.theme.colorScheme.onSurfaceVariant
                                  .withValues(alpha: 0.7),
                            ),
                          ),
                        ),
                        const SizedBox(width: 4),
                        CopyButton(
                          textToCopy: 'dart run riverpod_devtools:analyze',
                          size: 10,
                          color: widget.theme.colorScheme.onSurfaceVariant
                              .withValues(alpha: 0.5),
                          tooltipMessage: 'Copy command',
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Collapsible dropdown widget for static analysis setup instructions
class _StaticAnalysisRequiredDropdown extends StatefulWidget {
  final ThemeData theme;
  final Widget Function({
    required ThemeData theme,
    required String number,
    required String title,
    required String description,
    required String code,
  }) buildSetupStep;

  const _StaticAnalysisRequiredDropdown({
    required this.theme,
    required this.buildSetupStep,
  });

  @override
  State<_StaticAnalysisRequiredDropdown> createState() =>
      _StaticAnalysisRequiredDropdownState();
}

class _StaticAnalysisRequiredDropdownState
    extends State<_StaticAnalysisRequiredDropdown> {
  bool _isExpanded = false;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: _isExpanded
            ? widget.theme.colorScheme.surfaceContainerHighest
                .withValues(alpha: 0.2)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        border: _isExpanded
            ? Border.all(
                color: widget.theme.colorScheme.outline.withValues(alpha: 0.15),
              )
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header with warning icon and title
          InkWell(
            onTap: () {
              setState(() {
                _isExpanded = !_isExpanded;
              });
            },
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
              child: Row(
                children: [
                  Icon(
                    Icons.warning_amber_outlined,
                    size: 9,
                    color: widget.theme.colorScheme.onSurfaceVariant
                        .withValues(alpha: 0.4),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      'Static Analysis Required',
                      style: TextStyle(
                        fontSize: 7.5,
                        color: widget.theme.colorScheme.onSurfaceVariant
                            .withValues(alpha: 0.5),
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ),
                  Icon(
                    _isExpanded ? Icons.expand_less : Icons.expand_more,
                    size: 12,
                    color: widget.theme.colorScheme.onSurfaceVariant
                        .withValues(alpha: 0.4),
                  ),
                ],
              ),
            ),
          ),

          // Expanded content
          if (_isExpanded) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(
                    color:
                        widget.theme.colorScheme.outline.withValues(alpha: 0.1),
                  ),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'To view provider dependencies, run the analyzer and configure your app:',
                    style: TextStyle(
                      fontSize: 8,
                      color: widget.theme.colorScheme.onSurfaceVariant
                          .withValues(alpha: 0.7),
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 8),
                  widget.buildSetupStep(
                    theme: widget.theme,
                    number: '1',
                    title: 'Run the analyzer to detect dependencies',
                    description:
                        'Analyzes your code to find all ref.watch/read calls',
                    code: 'dart run riverpod_devtools:analyze',
                  ),
                  const SizedBox(height: 6),
                  widget.buildSetupStep(
                    theme: widget.theme,
                    number: '2',
                    title: 'Register the generated JSON as an asset',
                    description:
                        'Makes the dependency data available to your app',
                    code:
                        'flutter:\n  assets:\n    - lib/riverpod_dependencies.json',
                  ),
                  const SizedBox(height: 6),
                  // Step 3 with highlighted code
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '3. ',
                            style: TextStyle(
                              fontSize: 8,
                              fontWeight: FontWeight.w600,
                              color: widget.theme.colorScheme.onSurfaceVariant
                                  .withValues(alpha: 0.7),
                            ),
                          ),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Load dependency data in main()',
                                  style: TextStyle(
                                    fontSize: 8,
                                    fontWeight: FontWeight.w600,
                                    color: widget
                                        .theme.colorScheme.onSurfaceVariant
                                        .withValues(alpha: 0.7),
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'Add this code before runApp() to load the JSON file',
                                  style: TextStyle(
                                    fontSize: 8,
                                    color: widget
                                        .theme.colorScheme.onSurfaceVariant
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
                        margin: const EdgeInsets.only(left: 14),
                        decoration: BoxDecoration(
                          color: widget
                              .theme.colorScheme.surfaceContainerHighest
                              .withValues(alpha: 0.5),
                          borderRadius: BorderRadius.circular(3),
                          border: Border.all(
                            color: widget.theme.colorScheme.outline
                                .withValues(alpha: 0.2),
                          ),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: RichText(
                                text: TextSpan(
                                  style: TextStyle(
                                    fontSize: 8,
                                    fontFamily: 'monospace',
                                    color: widget
                                        .theme.colorScheme.onSurfaceVariant
                                        .withValues(alpha: 0.7),
                                    height: 1.4,
                                  ),
                                  children: [
                                    const TextSpan(
                                        text: 'void main() async {\n'),
                                    const TextSpan(
                                        text:
                                            '  WidgetsFlutterBinding.ensureInitialized();\n\n'),
                                    const TextSpan(
                                        text:
                                            '  // Load static dependencies\n'),
                                    const TextSpan(text: '  try {\n'),
                                    const TextSpan(text: '    final json = '),
                                    TextSpan(
                                      text: 'await rootBundle.loadString',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: widget
                                            .theme.colorScheme.onSurfaceVariant,
                                      ),
                                    ),
                                    const TextSpan(text: '(\n'),
                                    TextSpan(
                                      text:
                                          '      \'lib/riverpod_dependencies.json\'',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: widget
                                            .theme.colorScheme.onSurfaceVariant,
                                      ),
                                    ),
                                    const TextSpan(text: ',\n'),
                                    const TextSpan(text: '    );\n'),
                                    TextSpan(
                                      text:
                                          '    RiverpodDevToolsRegistry.instance\n        .loadFromJson(json)',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: widget
                                            .theme.colorScheme.onSurfaceVariant,
                                      ),
                                    ),
                                    const TextSpan(text: ';\n'),
                                    const TextSpan(text: '  } catch (_) {\n'),
                                    const TextSpan(
                                        text:
                                            '    // DevTools shows setup instructions\n'),
                                    const TextSpan(text: '  }\n\n'),
                                    const TextSpan(
                                        text: '  runApp(ProviderScope(\n'),
                                    TextSpan(
                                      text:
                                          '    observers: [RiverpodDevToolsObserver()]',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: widget
                                            .theme.colorScheme.onSurfaceVariant,
                                      ),
                                    ),
                                    const TextSpan(text: ',\n'),
                                    const TextSpan(
                                        text: '    child: MyApp(),\n'),
                                    const TextSpan(text: '  ));\n'),
                                    const TextSpan(text: '}'),
                                  ],
                                ),
                              ),
                            ),
                            const CopyButton(
                              textToCopy:
                                  'void main() async {\n  WidgetsFlutterBinding.ensureInitialized();\n\n  // Load static dependencies\n  try {\n    final json = await rootBundle.loadString(\n      \'lib/riverpod_dependencies.json\',\n    );\n    RiverpodDevToolsRegistry.instance\n        .loadFromJson(json);\n  } catch (_) {\n    // DevTools shows setup instructions\n  }\n\n  runApp(ProviderScope(\n    observers: [RiverpodDevToolsObserver()],\n    child: MyApp(),\n  ));\n}',
                              size: 12,
                              tooltipMessage: 'Copy code',
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '4. ',
                        style: TextStyle(
                          fontSize: 8,
                          fontWeight: FontWeight.w600,
                          color: widget.theme.colorScheme.onSurfaceVariant
                              .withValues(alpha: 0.7),
                        ),
                      ),
                      Expanded(
                        child: Text(
                          'Restart your app after completing these steps.',
                          style: TextStyle(
                            fontSize: 8,
                            color: widget.theme.colorScheme.onSurfaceVariant
                                .withValues(alpha: 0.7),
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  // Link to pub.dev documentation
                  InkWell(
                    onTap: () async {
                      final url = Uri.parse(
                          'https://pub.dev/packages/riverpod_devtools#getting-started');
                      if (await canLaunchUrl(url)) {
                        await launchUrl(url,
                            mode: LaunchMode.externalApplication);
                      }
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 4, vertical: 2),
                      child: Row(
                        children: [
                          Icon(
                            Icons.open_in_new,
                            size: 10,
                            color: widget.theme.colorScheme.primary
                                .withValues(alpha: 0.7),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'See full documentation on pub.dev',
                            style: TextStyle(
                              fontSize: 8,
                              color: widget.theme.colorScheme.primary
                                  .withValues(alpha: 0.7),
                              decoration: TextDecoration.underline,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Collapsible dropdown widget for dependency update information
class _UpdateInfoDropdown extends StatefulWidget {
  final ThemeData theme;
  final DateTime generatedAt;
  final String Function(DateTime) formatDateTime;

  const _UpdateInfoDropdown({
    required this.theme,
    required this.generatedAt,
    required this.formatDateTime,
  });

  @override
  State<_UpdateInfoDropdown> createState() => _UpdateInfoDropdownState();
}

class _UpdateInfoDropdownState extends State<_UpdateInfoDropdown> {
  bool _isExpanded = false;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: _isExpanded
            ? widget.theme.colorScheme.surfaceContainerHighest
                .withValues(alpha: 0.2)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        border: _isExpanded
            ? Border.all(
                color: widget.theme.colorScheme.outline.withValues(alpha: 0.15),
              )
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header with timestamp and dropdown icon
          InkWell(
            onTap: () {
              setState(() {
                _isExpanded = !_isExpanded;
              });
            },
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
              child: Row(
                children: [
                  Icon(
                    Icons.access_time,
                    size: 9,
                    color: widget.theme.colorScheme.onSurfaceVariant
                        .withValues(alpha: 0.4),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      'Last updated: ${widget.formatDateTime(widget.generatedAt)}',
                      style: TextStyle(
                        fontSize: 7.5,
                        color: widget.theme.colorScheme.onSurfaceVariant
                            .withValues(alpha: 0.5),
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ),
                  Icon(
                    _isExpanded ? Icons.expand_less : Icons.expand_more,
                    size: 12,
                    color: widget.theme.colorScheme.onSurfaceVariant
                        .withValues(alpha: 0.4),
                  ),
                ],
              ),
            ),
          ),

          // Expanded content
          if (_isExpanded) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(
                    color:
                        widget.theme.colorScheme.outline.withValues(alpha: 0.1),
                  ),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Keep dependency information up-to-date by running the analyzer in your terminal after code changes:',
                    style: TextStyle(
                      fontSize: 8,
                      color: widget.theme.colorScheme.onSurfaceVariant
                          .withValues(alpha: 0.7),
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    width: double.infinity,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                    decoration: BoxDecoration(
                      color: widget.theme.colorScheme.surfaceContainerHighest
                          .withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(3),
                      border: Border.all(
                        color: widget.theme.colorScheme.outline
                            .withValues(alpha: 0.15),
                        width: 0.5,
                      ),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: SelectableText(
                            'dart run riverpod_devtools:analyze',
                            style: TextStyle(
                              fontSize: 8,
                              fontFamily: 'monospace',
                              color: widget.theme.colorScheme.onSurfaceVariant
                                  .withValues(alpha: 0.7),
                            ),
                          ),
                        ),
                        const SizedBox(width: 4),
                        CopyButton(
                          textToCopy: 'dart run riverpod_devtools:analyze',
                          size: 10,
                          color: widget.theme.colorScheme.onSurfaceVariant
                              .withValues(alpha: 0.5),
                          tooltipMessage: 'Copy command',
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Outcome of a command sent to the running app: whether it succeeded and,
/// when it didn't, the error message to surface.
typedef CommandResult = ({bool ok, String? message});

/// Sends a state command (`invalidate` / `refresh`) for a provider and
/// resolves to its result. Injectable so tests can drive success/error
/// without a live VM service.
typedef CommandSender = Future<CommandResult> Function(
    String action, String provider);

/// The provider status badge plus Invalidate / Refresh actions, executed
/// inside the running app via the `ext.riverpod_devtools.command` service
/// extension registered by RiverpodDevToolsObserver. The command result is
/// shown inline (the extension has no Scaffold for a snackbar) on its own
/// full-width line below the buttons, so a long error message is readable
/// rather than clipped to a sliver.
class _ProviderCommandBar extends StatefulWidget {
  final String providerName;
  final bool isActive;

  const _ProviderCommandBar({
    required this.providerName,
    required this.isActive,
  });

  @override
  State<_ProviderCommandBar> createState() => _ProviderCommandBarState();
}

class _ProviderCommandBarState extends State<_ProviderCommandBar> {
  static const _commandExtension = 'ext.riverpod_devtools.command';

  String? _feedback;
  bool _feedbackIsError = false;
  bool _busy = false;
  Timer? _feedbackTimer;

  @override
  void didUpdateWidget(_ProviderCommandBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Switching to a different provider must not carry over the previous
    // one's result label.
    if (oldWidget.providerName != widget.providerName) {
      _feedbackTimer?.cancel();
      _feedback = null;
    }
  }

  @override
  void dispose() {
    _feedbackTimer?.cancel();
    super.dispose();
  }

  Future<CommandResult> _defaultSend(String action, String provider) async {
    final service = serviceManager.service;
    final isolateId = serviceManager.isolateManager.mainIsolate.value?.id;
    if (service == null || isolateId == null) {
      return (ok: false, message: 'App not connected');
    }
    final response = await service.callServiceExtension(
      _commandExtension,
      isolateId: isolateId,
      args: {'action': action, 'provider': provider},
    );
    final json = response.json ?? const {};
    if (json['status'] == 'ok') return (ok: true, message: null);
    return (
      ok: false,
      message: json['message']?.toString() ?? 'Command failed',
    );
  }

  Future<void> _send(String action) async {
    // Re-entrancy guard: a fast second click can arrive before the
    // disabled state from the first click has rebuilt the buttons, so the
    // in-flight flag — not just the disabled `onPressed` — is what
    // prevents a double command.
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final result = await (DetailPanel.debugCommandSender ?? _defaultSend)(
        action,
        widget.providerName,
      );
      if (result.ok) {
        _showFeedback(action == 'refresh' ? 'Refreshed' : 'Invalidated');
      } else {
        _showFeedback(result.message ?? 'Command failed', isError: true);
      }
    } catch (error) {
      // Typically: the app runs an older riverpod_devtools without the
      // command extension.
      _showFeedback('Not supported by the running app ($error)',
          isError: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _showFeedback(String message, {bool isError = false}) {
    if (!mounted) return;
    _feedbackTimer?.cancel();
    setState(() {
      _feedback = message;
      _feedbackIsError = isError;
    });
    _feedbackTimer = Timer(const Duration(seconds: 4), () {
      if (mounted) setState(() => _feedback = null);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            StatusBadge(isActive: widget.isActive),
            const SizedBox(width: 8),
            // The panel is user-resizable: at narrow widths the buttons
            // scale down (right-aligned) instead of overflowing.
            Expanded(
              child: Align(
                alignment: Alignment.centerRight,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerRight,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _CommandButton(
                        icon: Icons.restart_alt,
                        label: 'Invalidate',
                        tooltip: 'Mark this provider for rebuild '
                            '(rebuilds on next read/listen)',
                        onPressed: widget.isActive && !_busy
                            ? () => _send('invalidate')
                            : null,
                      ),
                      const SizedBox(width: 4),
                      _CommandButton(
                        icon: Icons.refresh,
                        label: 'Refresh',
                        tooltip:
                            'Invalidate and rebuild this provider immediately',
                        onPressed: widget.isActive && !_busy
                            ? () => _send('refresh')
                            : null,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
        if (_feedback != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: _CommandFeedback(
              message: _feedback!,
              isError: _feedbackIsError,
            ),
          ),
      ],
    );
  }
}

/// The inline result of a command: an icon plus the message on a full-width
/// line, ellipsized to two lines with the complete text available on hover.
class _CommandFeedback extends StatelessWidget {
  final String message;
  final bool isError;

  const _CommandFeedback({required this.message, required this.isError});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color =
        isError ? theme.colorScheme.error : theme.colorScheme.primary;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            isError ? Icons.error_outline : Icons.check_circle_outline,
            size: 13,
            color: color,
          ),
          const SizedBox(width: 5),
          Expanded(
            child: Tooltip(
              message: message,
              waitDuration: const Duration(milliseconds: 400),
              child: Text(
                message,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 10, height: 1.3, color: color),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CommandButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final String tooltip;
  final VoidCallback? onPressed;

  const _CommandButton({
    required this.icon,
    required this.label,
    required this.tooltip,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final enabled = onPressed != null;
    final color = enabled
        ? theme.colorScheme.primary
        : theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.4);

    return Tooltip(
      message: tooltip,
      waitDuration: const Duration(milliseconds: 400),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(6),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: enabled
                  ? theme.colorScheme.primary.withValues(alpha: 0.4)
                  : theme.colorScheme.outline.withValues(alpha: 0.2),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 11, color: color),
              const SizedBox(width: 3),
              Text(
                label,
                style: TextStyle(
                  fontSize: 9.5,
                  fontWeight: FontWeight.w600,
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
