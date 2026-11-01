import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Labeled button that copies [textBuilder]'s result — a Markdown brief meant
/// for pasting into an AI chat. The text is built on tap so it reflects the
/// state at that moment, not at the last rebuild.
class CopyForAiButton extends StatefulWidget {
  final String Function() textBuilder;

  const CopyForAiButton({super.key, required this.textBuilder});

  @override
  State<CopyForAiButton> createState() => _CopyForAiButtonState();
}

class _CopyForAiButtonState extends State<CopyForAiButton> {
  bool _copied = false;
  Timer? _timer;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: widget.textBuilder()));
    if (!mounted) return;
    setState(() => _copied = true);
    _timer?.cancel();
    _timer = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Tooltip(
      message: 'Copy this provider\'s state, error, dependencies and recent '
          'events as Markdown for an AI chat',
      child: OutlinedButton.icon(
        onPressed: _copy,
        icon: Icon(_copied ? Icons.check : Icons.auto_awesome, size: 13),
        label: Text(_copied ? 'Copied' : 'Copy for AI'),
        style: OutlinedButton.styleFrom(
          visualDensity: VisualDensity.compact,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          textStyle: const TextStyle(fontSize: 10),
          foregroundColor: _copied
              ? Colors.greenAccent.shade700
              : theme.colorScheme.onSurface,
        ),
      ),
    );
  }
}
