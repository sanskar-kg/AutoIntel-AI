import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/errors.dart';
import '../../core/money.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../../data/models.dart';
import '../../l10n/strings.g.dart';
import '../settings/language_sheet.dart';
import 'amount_picker.dart';
import 'payment_result_screen.dart';

/// Shown until the user completes the mandatory minimum recharge.
class RechargeGateScreen extends ConsumerStatefulWidget {
  const RechargeGateScreen({super.key, required this.config});
  final AppConfig config;

  @override
  ConsumerState<RechargeGateScreen> createState() => _RechargeGateScreenState();
}

class _RechargeGateScreenState extends ConsumerState<RechargeGateScreen> {
  int? _amount;
  bool _busy = false;
  String? _error;

  Future<void> _pay() async {
    final amount = _amount;
    if (amount == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await runRecharge(context, ref, amount);
    } catch (e) {
      if (mounted) setState(() => _error = errorMessage(S.of(context), e));
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final c = widget.config;
    return Scaffold(
      body: SafeArea(
        child: PageWidth(
          child: Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(22, 20, 22, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Brand(),
                          const LanguageButton(),
                        ],
                      ),
                      const SizedBox(height: 28),
                      Text(
                        s.gateTitle,
                        style: sora(
                          26,
                          weight: FontWeight.w700,
                          color: AppColors.navy,
                          height: 1.15,
                          spacing: -0.6,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        s.gateBody(formatPaise(c.minRechargePaise)),
                        style: sora(13, color: AppColors.muted, height: 1.5),
                      ),
                      const SizedBox(height: 22),
                      SoftCard(
                        color: AppColors.tintBlue,
                        border: false,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              s.gatePricesTitle,
                              style: sora(
                                13,
                                weight: FontWeight.w700,
                                color: AppColors.navy,
                              ),
                            ),
                            const SizedBox(height: 10),
                            _PriceRow(
                              s.gatePriceRc,
                              formatPaise(c.rcPricePaise),
                            ),
                            const SizedBox(height: 6),
                            _PriceRow(
                              s.gatePricePhone,
                              formatPaise(c.phonePricePaise),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),
                      AmountPicker(
                        config: c,
                        onChanged: (v) => setState(() => _amount = v),
                      ),
                    ],
                  ),
                ),
              ),
              // Pinned so the pay button is always reachable, even on small screens / large fonts.
              Padding(
                padding: const EdgeInsets.fromLTRB(22, 8, 22, 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    PrimaryButton(
                      s.gatePayButton(
                        _amount == null ? '' : formatPaise(_amount!),
                      ),
                      busy: _busy,
                      onPressed: _amount == null ? null : _pay,
                    ),
                    TextButton(
                      onPressed: _busy
                          ? null
                          : ref.read(walletProvider.notifier).deferRechargeGate,
                      child: Text(s.gateLaterButton),
                    ),
                    ErrorMessage(_error),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PriceRow extends StatelessWidget {
  const _PriceRow(this.label, this.price);
  final String label;
  final String price;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisAlignment: MainAxisAlignment.spaceBetween,
    children: [
      Flexible(
        child: Text(label, style: sora(13, color: AppColors.muted)),
      ),
      const SizedBox(width: 12),
      Text(
        price,
        style: sora(14, weight: FontWeight.w700, color: AppColors.navy),
      ),
    ],
  );
}
