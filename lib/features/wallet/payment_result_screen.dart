import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/money.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../../data/models.dart';
import '../../l10n/strings.g.dart';

/// Starts a recharge and shows the result screen. Throws on errors creating the order.
Future<void> runRecharge(
  BuildContext context,
  WidgetRef ref,
  int amountPaise,
) async {
  // Grab the navigator first: on a successful first recharge the gate screen is replaced by the
  // main app while we await, so `context` may be gone but the confirmation must still show.
  final navigator = Navigator.of(context);
  final result = await ref
      .read(walletProvider.notifier)
      .recharge(context, amountPaise);
  await navigator.push(
    MaterialPageRoute<void>(
      builder: (_) => PaymentResultScreen(result: result),
    ),
  );
}

class PaymentResultScreen extends ConsumerWidget {
  const PaymentResultScreen({super.key, required this.result});
  final PaymentResult result;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = S.of(context);
    final (icon, color, title, body) = switch (result.status) {
      OrderStatus.success => (
        Icons.check_circle_rounded,
        AppColors.success,
        s.paymentSuccessTitle,
        s.paymentSuccessBody(formatPaise(result.balancePaise)),
      ),
      OrderStatus.failed => (
        Icons.cancel_rounded,
        AppColors.error,
        s.paymentFailedTitle,
        s.paymentFailedBody,
      ),
      _ => (
        Icons.hourglass_top_rounded,
        AppColors.warning,
        s.paymentPendingTitle,
        s.paymentPendingBody,
      ),
    };

    return Scaffold(
      body: SafeArea(
        child: PageWidth(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                const Spacer(),
                Icon(icon, size: 88, color: color),
                const SizedBox(height: 24),
                Semantics(
                  liveRegion: true,
                  child: Text(
                    title,
                    textAlign: TextAlign.center,
                    style: sora(
                      23,
                      weight: FontWeight.w700,
                      color: AppColors.navy,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  body,
                  textAlign: TextAlign.center,
                  style: sora(14, color: AppColors.muted, height: 1.5),
                ),
                const Spacer(),
                PrimaryButton(
                  result.status == OrderStatus.pending
                      ? s.commonClose
                      : s.commonContinue,
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
