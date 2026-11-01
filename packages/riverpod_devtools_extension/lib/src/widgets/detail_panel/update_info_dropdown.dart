import 'package:flutter/material.dart';
import '../common/copy_button.dart';

/// Collapsible dropdown widget for dependency update information
class UpdateInfoDropdown extends StatefulWidget {
  final ThemeData theme;
  final DateTime generatedAt;
  final String Function(DateTime) formatDateTime;

  const UpdateInfoDropdown({
    super.key,
    required this.theme,
    required this.generatedAt,
    required this.formatDateTime,
  });

  @override
  State<UpdateInfoDropdown> createState() => _UpdateInfoDropdownState();
}

class _UpdateInfoDropdownState extends State<UpdateInfoDropdown> {
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
