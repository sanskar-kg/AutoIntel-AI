import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/money.dart';
import '../../core/analytics.dart';
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
  late final PaymentResult result;
  try {
    result = await ref
        .read(walletProvider.notifier)
        .recharge(context, amountPaise);
  } catch (error) {
    await AppAnalytics.log(
      'recharge_failed',
      parameters: {'reason': _reason(error)},
    );
    rethrow;
  }
  if (result.status == OrderStatus.success) {
    await AppAnalytics.log('recharge_success');
  } else if (result.status == OrderStatus.failed) {
    await AppAnalytics.log(
      'recharge_failed',
      parameters: {'reason': 'payment_failed'},
    );
  } else {
    await AppAnalytics.log('recharge_pending');
  }
  await navigator.push(
    MaterialPageRoute<void>(
      builder: (_) => PaymentResultScreen(result: result),
    ),
  );
}

String _reason(Object error) => error.runtimeType.toString().toLowerCase();

class PaymentResultScreen extends ConsumerWidget {
  const PaymentResultScreen({super.key, required this.result});
  final PaymentResult result;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = S.of(context);
    unawaited(
      AppAnalytics.log(
        'payment_result_viewed',
        parameters: {'status': result.status.name},
      ),
    );
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
