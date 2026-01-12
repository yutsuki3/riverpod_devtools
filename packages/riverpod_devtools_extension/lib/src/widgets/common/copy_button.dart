import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// A small copy button widget that copies text to clipboard when tapped
class CopyButton extends StatefulWidget {
  final String textToCopy;
  final double size;
  final Color? color;
  final String? tooltipMessage;

  const CopyButton({
    super.key,
    required this.textToCopy,
    this.size = 14,
    this.color,
    this.tooltipMessage,
  });

  @override
  State<CopyButton> createState() => _CopyButtonState();
}

class _CopyButtonState extends State<CopyButton> {
  bool _copied = false;

  void _copyToClipboard() {
    Clipboard.setData(ClipboardData(text: widget.textToCopy));
    setState(() => _copied = true);
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) {
        setState(() => _copied = false);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final iconColor = widget.color ?? theme.colorScheme.onSurfaceVariant;

    return Tooltip(
      message: _copied
          ? 'Copied!'
          : widget.tooltipMessage ?? 'Copy to clipboard',
      child: InkWell(
        onTap: _copyToClipboard,
        borderRadius: BorderRadius.circular(4),
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Icon(
            _copied ? Icons.check : Icons.content_copy,
            size: widget.size,
            color: _copied ? Colors.greenAccent : iconColor,
          ),
        ),
      ),
    );
  }
}
