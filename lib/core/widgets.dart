import 'package:flutter/material.dart';

import '../l10n/strings.g.dart';
import 'theme.dart';

/// Wordmark + family tagline (MIC's `Brand` pattern).
class Brand extends StatelessWidget {
  const Brand({super.key});

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          s.brandWordmark,
          style: sora(
            24,
            weight: FontWeight.w800,
            color: AppColors.blue,
            height: 1,
          ),
        ),
        const SizedBox(height: 3),
        Text(s.brandTagline, style: sora(11, color: AppColors.muted)),
      ],
    );
  }
}

class PrimaryButton extends StatelessWidget {
  const PrimaryButton(
    this.label, {
    super.key,
    required this.onPressed,
    this.busy = false,
    this.icon,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool busy;
  final IconData? icon;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: double.infinity,
    height: 48,
    child: FilledButton(
      onPressed: busy ? null : onPressed,
      child: busy
          ? SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
                semanticsLabel: S.of(context).commonLoading,
              ),
            )
          : Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 18),
                  const SizedBox(width: 8),
                ],
                Flexible(child: Text(label, textAlign: TextAlign.center)),
              ],
            ),
    ),
  );
}

class ErrorMessage extends StatelessWidget {
  const ErrorMessage(this.message, {super.key});
  final String? message;

  @override
  Widget build(BuildContext context) => message == null
      ? const SizedBox.shrink()
      : Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Semantics(
            liveRegion: true,
            child: Text(
              message!,
              textAlign: TextAlign.center,
              style: sora(12, color: AppColors.error, height: 1.4),
            ),
          ),
        );
}

/// Round back button used in MIC's utility screens.
class BackCircle extends StatelessWidget {
  const BackCircle({super.key});

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: S.of(context).a11yBack,
    onPressed: () => Navigator.maybePop(context),
    icon: const Icon(Icons.arrow_back, size: 20, color: AppColors.navy),
    padding: EdgeInsets.zero,
    constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
    style: IconButton.styleFrom(
      backgroundColor: AppColors.chipBg,
      shape: const CircleBorder(),
    ),
  );
}

/// Header row used on pushed screens: back circle + brand.
class ScreenHeader extends StatelessWidget {
  const ScreenHeader({super.key, this.trailing});
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
    child: Row(
      children: [
        const BackCircle(),
        const SizedBox(width: 16),
        const Brand(),
        const Spacer(),
        ?trailing,
      ],
    ),
  );
}

/// White card with MIC's hairline border.
class SoftCard extends StatelessWidget {
  const SoftCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.color = Colors.white,
    this.border = true,
    this.onTap,
  });

  final Widget child;
  final EdgeInsets padding;
  final Color color;
  final bool border;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: color,
    clipBehavior: Clip.antiAlias,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(14),
      side: border
          ? const BorderSide(color: AppColors.hairline)
          : BorderSide.none,
    ),
    child: InkWell(
      onTap: onTap,
      child: Padding(padding: padding, child: child),
    ),
  );
}

/// Centers content and caps width on tablets/foldables (MIC uses 520).
class PageWidth extends StatelessWidget {
  const PageWidth({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.topCenter,
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 520),
      child: child,
    ),
  );
}
