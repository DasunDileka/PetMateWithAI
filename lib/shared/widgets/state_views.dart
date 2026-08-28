import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';

/// Standard loading state.
///
/// Every asynchronous surface in PetMate uses these three widgets, so loading,
/// empty and error states look and behave identically everywhere — one of the
/// explicit UI/UX consistency requirements.
class LoadingView extends StatelessWidget {
  const LoadingView({super.key, this.message});

  final String? message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const SizedBox(
            width: 32,
            height: 32,
            child: CircularProgressIndicator(strokeWidth: 3),
          ),
          if (message != null) ...<Widget>[
            const SizedBox(height: AppTheme.gapLg),
            Text(
              message!,
              style: Theme.of(context).textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
          ],
        ],
      ),
    );
  }
}

/// Skeleton placeholder used where a spinner would cause layout jump.
class SkeletonBox extends StatefulWidget {
  const SkeletonBox({
    super.key,
    this.height = 16,
    this.width,
    this.radius = 8,
  });

  final double height;
  final double? width;
  final double radius;

  @override
  State<SkeletonBox> createState() => _SkeletonBoxState();
}

class _SkeletonBoxState extends State<SkeletonBox>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Color base = Theme.of(context).colorScheme.outlineVariant;

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) => Container(
        height: widget.height,
        width: widget.width,
        decoration: BoxDecoration(
          color: base.withValues(alpha: 0.35 + (_controller.value * 0.35)),
          borderRadius: BorderRadius.circular(widget.radius),
        ),
      ),
    );
  }
}

/// Standard empty state: illustration, explanation, and an optional action.
///
/// Empty states always say what the screen *is for* and how to fill it, rather
/// than just reporting that there is nothing here.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
    this.accent,
    this.compact = false,
  });

  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;
  final Color? accent;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final Color color = accent ?? Theme.of(context).colorScheme.primary;

    return Center(
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: AppTheme.gapXl,
          vertical: compact ? AppTheme.gapXl : AppTheme.gapXxl,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Container(
              width: compact ? 56 : 76,
              height: compact ? 56 : 76,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.10),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: compact ? 26 : 36, color: color),
            ),
            SizedBox(height: compact ? AppTheme.gapMd : AppTheme.gapLg),
            Text(
              title,
              style: compact
                  ? Theme.of(context).textTheme.titleSmall
                  : Theme.of(context).textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppTheme.gapSm),
            Text(
              message,
              style: Theme.of(context).textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
            if (actionLabel != null && onAction != null) ...<Widget>[
              const SizedBox(height: AppTheme.gapXl),
              FilledButton.icon(
                onPressed: onAction,
                icon: const Icon(Icons.add_rounded, size: 20),
                label: Text(actionLabel!),
                style: FilledButton.styleFrom(
                  minimumSize: const Size(0, AppTheme.minTapTarget),
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppTheme.gapXl,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Standard error state with a retry affordance.
///
/// Only ever shown user-safe copy — raw exception text is logged in debug
/// builds and never rendered.
class ErrorView extends StatelessWidget {
  const ErrorView({
    super.key,
    required this.message,
    this.onRetry,
    this.compact = false,
  });

  final String message;
  final VoidCallback? onRetry;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppTheme.gapXl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Container(
              width: compact ? 48 : 64,
              height: compact ? 48 : 64,
              decoration: BoxDecoration(
                color: AppColors.danger.withValues(alpha: 0.10),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.cloud_off_rounded,
                size: compact ? 22 : 30,
                color: AppColors.danger,
              ),
            ),
            const SizedBox(height: AppTheme.gapLg),
            Text(
              'Something went wrong',
              style: Theme.of(context).textTheme.titleSmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppTheme.gapSm),
            Text(
              message,
              style: Theme.of(context).textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
            if (onRetry != null) ...<Widget>[
              const SizedBox(height: AppTheme.gapLg),
              OutlinedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded, size: 20),
                label: const Text('Try again'),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(0, AppTheme.minTapTarget),
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppTheme.gapXl,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Inline banner for non-blocking problems, e.g. "you are offline".
class InlineNotice extends StatelessWidget {
  const InlineNotice({
    super.key,
    required this.message,
    this.icon = Icons.info_outline_rounded,
    this.color,
    this.onDismiss,
  });

  final String message;
  final IconData icon;
  final Color? color;
  final VoidCallback? onDismiss;

  @override
  Widget build(BuildContext context) {
    final Color c = color ?? AppColors.warning;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppTheme.gapLg,
        vertical: AppTheme.gapMd,
      ),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(AppTheme.radiusSm + 2),
        border: Border.all(color: c.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: <Widget>[
          Icon(icon, size: 20, color: c),
          const SizedBox(width: AppTheme.gapMd),
          Expanded(
            child: Text(
              message,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: Theme.of(context).colorScheme.onSurface),
            ),
          ),
          if (onDismiss != null)
            IconButton(
              onPressed: onDismiss,
              icon: const Icon(Icons.close_rounded, size: 18),
              visualDensity: VisualDensity.compact,
              tooltip: 'Dismiss',
            ),
        ],
      ),
    );
  }
}
