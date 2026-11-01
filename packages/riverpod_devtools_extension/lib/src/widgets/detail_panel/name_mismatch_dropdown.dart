import 'package:flutter/material.dart';
import '../common/copy_button.dart';

/// Collapsible dropdown widget for provider name mismatch warning
class NameMismatchDropdown extends StatefulWidget {
  final ThemeData theme;

  const NameMismatchDropdown({
    super.key,
    required this.theme,
  });

  @override
  State<NameMismatchDropdown> createState() => _NameMismatchDropdownState();
}

class _NameMismatchDropdownState extends State<NameMismatchDropdown> {
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
