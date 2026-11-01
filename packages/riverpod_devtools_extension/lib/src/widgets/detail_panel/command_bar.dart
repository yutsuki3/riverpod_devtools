import 'dart:async';
import 'package:devtools_extensions/devtools_extensions.dart';
import 'package:flutter/material.dart';
import '../common/panel_ui.dart';

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
class ProviderCommandBar extends StatefulWidget {
  final String providerName;
  final bool isActive;

  /// Test seam passed down by [DetailPanel]; null sends for real.
  final CommandSender? sender;

  const ProviderCommandBar({
    super.key,
    this.sender,
    required this.providerName,
    required this.isActive,
  });

  @override
  State<ProviderCommandBar> createState() => _ProviderCommandBarState();
}

class _ProviderCommandBarState extends State<ProviderCommandBar> {
  static const _commandExtension = 'ext.riverpod_devtools.command';

  String? _feedback;
  bool _feedbackIsError = false;
  bool _busy = false;
  Timer? _feedbackTimer;

  @override
  void didUpdateWidget(ProviderCommandBar oldWidget) {
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
      final result = await (widget.sender ?? _defaultSend)(
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
