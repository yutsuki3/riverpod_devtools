import 'package:flutter/material.dart';
import 'copy_button.dart';

/// Renders a provider failure: error type + message, with the stack trace
/// in a collapsed-by-default expander and a copy button for the whole
/// error. Shared by the Event Log (expanded failed events) and the
/// Provider Details "Error" section.
class ErrorDetails extends StatefulWidget {
  /// `type` / `message` / `stackTrace` strings from a provider_failed
  /// event payload.
  final Map<String, dynamic>? error;

  const ErrorDetails({super.key, required this.error});

  @override
  State<ErrorDetails> createState() => _ErrorDetailsState();
}

class _ErrorDetailsState extends State<ErrorDetails> {
  bool _stackTraceExpanded = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final errorColor =
        isDark ? const Color(0xFFE57373) : const Color(0xFFD32F2F);

    final type = widget.error?['type'] as String?;
    final message = widget.error?['message'] as String? ?? 'Unknown error';
    final stackTrace = widget.error?['stackTrace'] as String?;

    final copyText = [
      if (type != null) type,
      message,
      if (stackTrace != null) stackTrace,
    ].join('\n');

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: errorColor.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: errorColor.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: SelectableText(
                  type != null ? '$type: $message' : message,
                  style: TextStyle(
                    fontSize: 10,
                    fontFamily: 'monospace',
                    color: errorColor,
                  ),
                ),
              ),
              CopyButton(
                textToCopy: copyText,
                size: 12,
                tooltipMessage: 'Copy error and stack trace',
              ),
            ],
          ),
          if (stackTrace != null && stackTrace.isNotEmpty) ...[
            const SizedBox(height: 4),
            InkWell(
              onTap: () =>
                  setState(() => _stackTraceExpanded = !_stackTraceExpanded),
              borderRadius: BorderRadius.circular(4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    _stackTraceExpanded
                        ? Icons.expand_less
                        : Icons.expand_more,
                    size: 14,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  Text(
                    'Stack trace',
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w600,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            if (_stackTraceExpanded)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: SelectableText(
                  stackTrace,
                  style: TextStyle(
                    fontSize: 9,
                    fontFamily: 'monospace',
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }
}
