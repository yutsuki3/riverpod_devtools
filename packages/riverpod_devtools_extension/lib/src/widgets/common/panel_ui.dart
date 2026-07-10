import 'package:flutter/material.dart';

/// Shared UI building blocks that give every panel a consistent,
/// modern card-based look.

/// A rounded card that wraps a panel's content.
class PanelCard extends StatelessWidget {
  final Widget child;

  const PanelCard({
    super.key,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: theme.colorScheme.outline.withValues(alpha: 0.15),
        ),
      ),
      child: child,
    );
  }
}

/// A consistent panel header with an icon, title, optional count badge and
/// trailing actions.
class PanelHeader extends StatelessWidget {
  final IconData icon;
  final String title;
  final int? count;
  final List<Widget> actions;

  const PanelHeader({
    super.key,
    required this.icon,
    required this.title,
    this.count,
    this.actions = const [],
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
        border: Border(
          bottom: BorderSide(
            color: theme.colorScheme.outline.withValues(alpha: 0.12),
          ),
        ),
      ),
      child: Row(
        children: [
          Icon(
            icon,
            size: 14,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 12,
                letterSpacing: 0.2,
                color: theme.colorScheme.onSurface,
              ),
            ),
          ),
          if (count != null) ...[
            const SizedBox(width: 6),
            CountBadge(count: count!),
          ],
          const Spacer(),
          ...actions,
        ],
      ),
    );
  }
}

/// A small rounded pill showing a count.
class CountBadge extends StatelessWidget {
  final int count;

  const CountBadge({
    super.key,
    required this.count,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: theme.colorScheme.primary.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        '$count',
        style: TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.w600,
          color: theme.colorScheme.primary,
        ),
      ),
    );
  }
}

/// A compact text action used inside [PanelHeader].
class HeaderActionButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback onPressed;

  const HeaderActionButton({
    super.key,
    required this.label,
    this.icon,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(
                icon,
                size: 12,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 4),
            ],
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w500,
                color: theme.colorScheme.primary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A status pill for active / disposed providers.
class StatusBadge extends StatelessWidget {
  final bool isActive;

  const StatusBadge({
    super.key,
    required this.isActive,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = isActive
        ? (theme.brightness == Brightness.dark
            ? const Color(0xFF4ADE80)
            : const Color(0xFF16A34A))
        : theme.colorScheme.onSurfaceVariant;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          StatusDot(isActive: isActive, size: 6),
          const SizedBox(width: 5),
          Text(
            isActive ? 'Active' : 'Disposed',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

/// A small colored dot indicating provider status. Active dots get a
/// subtle glow.
class StatusDot extends StatelessWidget {
  final bool isActive;
  final double size;

  const StatusDot({
    super.key,
    required this.isActive,
    this.size = 7,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = isActive
        ? (theme.brightness == Brightness.dark
            ? const Color(0xFF4ADE80)
            : const Color(0xFF16A34A))
        : theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5);

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: isActive ? color : Colors.transparent,
        shape: BoxShape.circle,
        border: isActive ? null : Border.all(color: color, width: 1.2),
        boxShadow: isActive
            ? [
                BoxShadow(
                  color: color.withValues(alpha: 0.5),
                  blurRadius: 4,
                ),
              ]
            : null,
      ),
    );
  }
}

/// A friendly centered empty state with an icon and message.
class EmptyState extends StatelessWidget {
  final IconData icon;
  final String message;
  final String? hint;

  const EmptyState({
    super.key,
    required this.icon,
    required this.message,
    this.hint,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 28,
              color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.35),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            if (hint != null) ...[
              const SizedBox(height: 4),
              Text(
                hint!,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 10,
                  color: theme.colorScheme.onSurfaceVariant
                      .withValues(alpha: 0.6),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
