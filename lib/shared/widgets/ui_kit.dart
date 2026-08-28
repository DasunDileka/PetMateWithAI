import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../features/pets/pet_repository.dart' show DataFailure;

/// Section title with an optional trailing action.
class SectionHeader extends StatelessWidget {
  const SectionHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.actionLabel,
    this.onAction,
    this.icon,
  });

  final String title;
  final String? subtitle;
  final String? actionLabel;
  final VoidCallback? onAction;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppTheme.gapMd),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          if (icon != null) ...<Widget>[
            Icon(icon, size: 18, color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: AppTheme.gapSm),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(title, style: Theme.of(context).textTheme.titleMedium),
                if (subtitle != null) ...<Widget>[
                  const SizedBox(height: 2),
                  Text(subtitle!, style: Theme.of(context).textTheme.bodySmall),
                ],
              ],
            ),
          ),
          if (actionLabel != null && onAction != null)
            TextButton(
              onPressed: onAction,
              child: Text(actionLabel!),
            ),
        ],
      ),
    );
  }
}

/// Rounded surface used for every card in the app.
class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(AppTheme.gapLg),
    this.onTap,
    this.accent,
    this.borderColor,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;

  /// Draws a coloured stripe down the leading edge — used to key a card to a
  /// care domain without relying on colour alone for meaning.
  final Color? accent;

  final Color? borderColor;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    final Widget body = Padding(padding: padding, child: child);

    // The accent stripe has to match the card's height, which means
    // CrossAxisAlignment.stretch — but a card inside a ListView is laid out
    // with an *unbounded* height, and stretch would then force an infinite
    // height constraint onto the content and fail to lay out.
    // IntrinsicHeight bounds the row to its tallest child first, so stretch
    // becomes well-defined. Cards without a stripe skip the Row (and the
    // intrinsic pass) entirely, which is the common case.
    final Widget inner = accent == null
        ? body
        : IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Container(width: 4, color: accent),
                Expanded(child: body),
              ],
            ),
          );

    final Widget content = Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        border: Border.all(color: borderColor ?? theme.colorScheme.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: inner,
    );

    if (onTap == null) return content;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        child: content,
      ),
    );
  }
}

/// Compact metric tile used across the dashboard and analytics screens.
class StatTile extends StatelessWidget {
  const StatTile({
    super.key,
    required this.label,
    required this.value,
    this.caption,
    this.icon,
    this.color,
    this.progress,
  });

  final String label;
  final String value;
  final String? caption;
  final IconData? icon;
  final Color? color;

  /// 0–1. Renders a thin progress bar beneath the value when supplied.
  final double? progress;

  @override
  Widget build(BuildContext context) {
    final Color c = color ?? Theme.of(context).colorScheme.primary;

    return AppCard(
      padding: const EdgeInsets.all(AppTheme.gapLg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Row(
            children: <Widget>[
              if (icon != null) ...<Widget>[
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: c.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon, size: 15, color: c),
                ),
                const SizedBox(width: AppTheme.gapSm),
              ],
              Expanded(
                child: Text(
                  label,
                  style: Theme.of(context).textTheme.labelMedium,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppTheme.gapMd),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: Theme.of(context)
                  .textTheme
                  .headlineSmall
                  ?.copyWith(color: c, fontWeight: FontWeight.w800),
            ),
          ),
          if (progress != null) ...<Widget>[
            const SizedBox(height: AppTheme.gapSm),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: progress!.clamp(0.0, 1.0),
                minHeight: 5,
                backgroundColor: c.withValues(alpha: 0.14),
                valueColor: AlwaysStoppedAnimation<Color>(c),
              ),
            ),
          ],
          if (caption != null) ...<Widget>[
            const SizedBox(height: AppTheme.gapSm),
            Text(
              caption!,
              style: Theme.of(context).textTheme.bodySmall,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ],
      ),
    );
  }
}

/// Small rounded status/label pill.
class AppPill extends StatelessWidget {
  const AppPill({
    super.key,
    required this.label,
    this.color,
    this.icon,
    this.filled = false,
  });

  final String label;
  final Color? color;
  final IconData? icon;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final Color c = color ?? Theme.of(context).colorScheme.primary;

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: icon == null ? 10 : 8,
        vertical: 5,
      ),
      decoration: BoxDecoration(
        color: filled ? c : c.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppTheme.radiusPill),
        border: filled ? null : Border.all(color: c.withValues(alpha: 0.30)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (icon != null) ...<Widget>[
            Icon(icon, size: 13, color: filled ? Colors.white : c),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              color: filled ? Colors.white : c,
              letterSpacing: 0.1,
            ),
          ),
        ],
      ),
    );
  }
}

/// Row of key/value detail, used on every "view record" sheet.
class DetailRow extends StatelessWidget {
  const DetailRow({
    super.key,
    required this.label,
    required this.value,
    this.icon,
  });

  final String label;
  final String value;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppTheme.gapSm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (icon != null) ...<Widget>[
            Icon(icon, size: 17, color: AppColors.inkFaint),
            const SizedBox(width: AppTheme.gapMd),
          ],
          SizedBox(
            width: 108,
            child: Text(label, style: Theme.of(context).textTheme.bodySmall),
          ),
          Expanded(
            child: Text(
              value,
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

/// Circular icon tile keyed to a care domain colour.
class CareIconTile extends StatelessWidget {
  const CareIconTile({
    super.key,
    required this.icon,
    required this.color,
    this.size = 40,
  });

  final IconData icon;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(size * 0.30),
      ),
      child: Icon(icon, size: size * 0.5, color: color),
    );
  }
}

/// Confirmation dialog used before every destructive action.
Future<bool> confirmAction(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'Delete',
  bool destructive = true,
}) async {
  final bool? result = await showDialog<bool>(
    context: context,
    builder: (BuildContext ctx) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(ctx).pop(true),
          style: destructive
              ? FilledButton.styleFrom(backgroundColor: AppColors.danger)
              : null,
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return result ?? false;
}

/// Consistent snackbar helper. Keeps success/error styling uniform.
void showAppSnack(
  BuildContext context,
  String message, {
  bool isError = false,
}) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Row(
          children: <Widget>[
            Icon(
              isError ? Icons.error_outline_rounded : Icons.check_circle_outline_rounded,
              color: Colors.white,
              size: 20,
            ),
            const SizedBox(width: AppTheme.gapMd),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: isError ? AppColors.danger : AppColors.success,
        duration: Duration(seconds: isError ? 4 : 2),
      ),
    );
}

/// Runs a repository action from a tap handler and reports any failure.
///
/// Repository methods throw [DataFailure] on a permission problem, a lost
/// connection or a deleted record. Call sites used to `await` them bare inside
/// `onPressed`, so a failure became an unhandled asynchronous error: the tap
/// appeared to do nothing at all and the user was never told why. Returns true
/// when the action completed.
Future<bool> runGuarded(
  BuildContext context,
  Future<void> Function() action, {
  String? successMessage,
  String failureMessage = 'That did not save. Please try again.',
}) async {
  try {
    await action();
    if (context.mounted && successMessage != null) {
      showAppSnack(context, successMessage);
    }
    return true;
  } on DataFailure catch (e) {
    if (context.mounted) showAppSnack(context, e.message, isError: true);
    return false;
  } catch (e) {
    if (kDebugMode) debugPrint('guarded action failed: $e');
    if (context.mounted) showAppSnack(context, failureMessage, isError: true);
    return false;
  }
}
