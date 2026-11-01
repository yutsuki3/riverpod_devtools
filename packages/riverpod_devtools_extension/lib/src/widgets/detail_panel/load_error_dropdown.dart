import 'package:flutter/material.dart';
import '../common/copy_button.dart';

/// Collapsible dropdown shown when the dependency JSON was found but failed
/// to parse (DependencySource.loadError). Unlike the "not set up" and "name
/// mismatch" states, this one carries the actual failure reason from the
/// observer, so the user sees *why* instead of just an empty graph.
class LoadErrorDropdown extends StatefulWidget {
  final ThemeData theme;

  /// The parse-failure reason reported by the observer; null when an older
  /// observer sent the source without the message.
  final String? message;

  const LoadErrorDropdown({
    super.key,
    required this.theme,
    required this.message,
  });

  @override
  State<LoadErrorDropdown> createState() => _LoadErrorDropdownState();
}

class _LoadErrorDropdownState extends State<LoadErrorDropdown> {
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
