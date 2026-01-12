import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../models/event_type.dart';
import '../../models/provider_info.dart';
import '../../providers/inspector_notifier.dart';
import '../common/json_tree_view.dart';
import '../common/copy_button.dart';

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
                SelectableText(
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
                : provider.dependenciesSource == DependencySource.nameMismatch
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
        child: SelectableText(
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
                color: theme.colorScheme.onSurfaceVariant
                    .withValues(alpha: 0.7),
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
        borderRadius: BorderRadius.circular(4),
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
            borderRadius: BorderRadius.circular(4),
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
                    color: widget.theme.colorScheme.outline
                        .withValues(alpha: 0.1),
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
        borderRadius: BorderRadius.circular(4),
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
            borderRadius: BorderRadius.circular(4),
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
                    color: widget.theme.colorScheme.outline
                        .withValues(alpha: 0.1),
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
                                    color: widget.theme.colorScheme.onSurfaceVariant
                                        .withValues(alpha: 0.7),
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'Add this code before runApp() to load the JSON file',
                                  style: TextStyle(
                                    fontSize: 8,
                                    color: widget.theme.colorScheme.onSurfaceVariant
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
                          color: widget.theme.colorScheme.surfaceContainerHighest
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
                                    color: widget.theme.colorScheme.onSurfaceVariant
                                        .withValues(alpha: 0.7),
                                    height: 1.4,
                                  ),
                                  children: [
                                    const TextSpan(text: 'void main() async {\n'),
                                    const TextSpan(text: '  WidgetsFlutterBinding.ensureInitialized();\n\n'),
                                    const TextSpan(text: '  // Load static dependencies\n'),
                                    const TextSpan(text: '  try {\n'),
                                    const TextSpan(text: '    final json = '),
                                    TextSpan(
                                      text: 'await rootBundle.loadString',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: widget.theme.colorScheme.onSurfaceVariant,
                                      ),
                                    ),
                                    const TextSpan(text: '(\n'),
                                    TextSpan(
                                      text: '      \'lib/riverpod_dependencies.json\'',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: widget.theme.colorScheme.onSurfaceVariant,
                                      ),
                                    ),
                                    const TextSpan(text: ',\n'),
                                    const TextSpan(text: '    );\n'),
                                    TextSpan(
                                      text: '    RiverpodDevToolsRegistry.instance\n        .loadFromJson(json)',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: widget.theme.colorScheme.onSurfaceVariant,
                                      ),
                                    ),
                                    const TextSpan(text: ';\n'),
                                    const TextSpan(text: '  } catch (e) {\n'),
                                    const TextSpan(text: '    print(\'⚠️  Static analysis not available\');\n'),
                                    const TextSpan(text: '  }\n\n'),
                                    const TextSpan(text: '  runApp(ProviderScope(\n'),
                                    TextSpan(
                                      text: '    observers: [RiverpodDevToolsObserver()]',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: widget.theme.colorScheme.onSurfaceVariant,
                                      ),
                                    ),
                                    const TextSpan(text: ',\n'),
                                    const TextSpan(text: '    child: MyApp(),\n'),
                                    const TextSpan(text: '  ));\n'),
                                    const TextSpan(text: '}'),
                                  ],
                                ),
                              ),
                            ),
                            CopyButton(
                              textToCopy:
                                  'void main() async {\n  WidgetsFlutterBinding.ensureInitialized();\n\n  // Load static dependencies\n  try {\n    final json = await rootBundle.loadString(\n      \'lib/riverpod_dependencies.json\',\n    );\n    RiverpodDevToolsRegistry.instance\n        .loadFromJson(json);\n  } catch (e) {\n    print(\'⚠️  Static analysis not available\');\n  }\n\n  runApp(ProviderScope(\n    observers: [RiverpodDevToolsObserver()],\n    child: MyApp(),\n  ));\n}',
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
        borderRadius: BorderRadius.circular(4),
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
            borderRadius: BorderRadius.circular(4),
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
                    color: widget.theme.colorScheme.outline
                        .withValues(alpha: 0.1),
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
