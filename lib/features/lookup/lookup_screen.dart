import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/errors.dart';
import '../../core/money.dart';
import '../../core/reg_no.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../../data/models.dart';
import '../../l10n/strings.g.dart';
import 'result_screen.dart';

/// Shared screen for both paid lookups. Same input and charge flow, different price/endpoint.
class LookupScreen extends ConsumerStatefulWidget {
  const LookupScreen({super.key, required this.type, this.initialRegNo = ''});
  final LookupType type;
  final String initialRegNo;

  @override
  ConsumerState<LookupScreen> createState() => _LookupScreenState();
}

class _LookupScreenState extends ConsumerState<LookupScreen> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialRegNo,
  );
  final _rand = Random();
  bool _touched = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool get _valid => isValidRegNo(_controller.text);

  String _rechargeRequiredMessage(S s) => widget.type == LookupType.rc
      ? s.errorRechargeVehicle
      : s.errorRechargePhone;

  String _newKey() =>
      '${DateTime.now().microsecondsSinceEpoch}-${_rand.nextInt(1 << 32)}';

  Future<void> _search(AppConfig config, int balance) async {
    final s = S.of(context);
    if (!_valid) {
      setState(() => _touched = true);
      return;
    }
    final reg = normalizeRegNo(_controller.text);
    final price = config.priceFor(widget.type);
    if (balance < price) {
      ref.read(tabProvider.notifier).select(1);
      Navigator.of(context).popUntil((r) => r.isFirst);
      return;
    }
    final ok = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      backgroundColor: Colors.white,
      builder: (_) => _ConfirmSheet(reg: reg, price: price, balance: balance),
    );
    if (ok != true || !mounted) return;

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final lookup = await ref
          .read(backendProvider)
          .lookup(widget.type, reg, _newKey());
      await ref.read(walletProvider.notifier).refresh();
      if (!mounted) return;
      await Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(builder: (_) => ResultScreen(lookup: lookup)),
      );
      return;
    } catch (e) {
      if (mounted) {
        setState(
          () => _error = e is AppException &&
                  e.code == ErrorCode.rechargeRequired
              ? _rechargeRequiredMessage(s)
              : errorMessage(s, e),
        );
        // The server may have rejected on a stale balance; resync.
        ref.read(walletProvider.notifier).refresh();
      }
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final isRc = widget.type == LookupType.rc;
    final config = ref.watch(configProvider).value;
    final wallet = ref.watch(walletProvider).value;
    final price = config?.priceFor(widget.type);
    final balance = wallet?.balancePaise ?? 0;
    final lowBalance = price != null && balance < price;

    return Scaffold(
      backgroundColor: AppColors.surfaceAlt,
      body: SafeArea(
        child: Column(
          children: [
            const ScreenHeader(),
            Expanded(
              child: PageWidth(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isRc ? s.lookupRcTitle : s.lookupPhoneTitle,
                        style: sora(
                          23,
                          weight: FontWeight.w700,
                          color: AppColors.navy,
                          height: 1.1,
                          spacing: -0.5,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        isRc ? s.lookupRcIntro : s.lookupPhoneIntro,
                        style: sora(13, color: AppColors.muted, height: 1.4),
                      ),
                      const SizedBox(height: 24),
                      TextField(
                        controller: _controller,
                        enabled: !_busy,
                        textCapitalization: TextCapitalization.characters,
                        autocorrect: false,
                        enableSuggestions: false,
                        keyboardType: TextInputType.visiblePassword,
                        textInputAction: TextInputAction.search,
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(
                            RegExp(r'[A-Za-z0-9 \-]'),
                          ),
                          LengthLimitingTextInputFormatter(14),
                          _UpperCaseFormatter(),
                        ],
                        onChanged: (_) => setState(() {
                          _error = null;
                        }),
                        onSubmitted: (_) {
                          if (config != null) _search(config, balance);
                        },
                        style: sora(
                          20,
                          weight: FontWeight.w700,
                          color: AppColors.navy,
                          spacing: 1.5,
                        ),
                        decoration: InputDecoration(
                          labelText: s.lookupFieldLabel,
                          hintText: s.lookupFieldHint,
                          hintStyle: sora(
                            20,
                            weight: FontWeight.w400,
                            color: AppColors.placeholder,
                            spacing: 1.5,
                          ),
                          errorText: _touched && !_valid
                              ? s.lookupErrorInvalid
                              : null,
                          suffixIcon: _controller.text.isEmpty
                              ? null
                              : IconButton(
                                  tooltip: s.a11yClear,
                                  icon: const Icon(
                                    Icons.close_rounded,
                                    size: 20,
                                  ),
                                  onPressed: () => setState(() {
                                    _controller.clear();
                                    _touched = false;
                                  }),
                                ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      if (price != null)
                        Row(
                          children: [
                            const Icon(
                              Icons.account_balance_wallet_outlined,
                              size: 18,
                              color: AppColors.muted,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                s.lookupCostInfo(
                                  formatPaise(price),
                                  formatPaise(balance),
                                ),
                                style: sora(
                                  12,
                                  weight: FontWeight.w600,
                                  color: AppColors.muted,
                                ),
                              ),
                            ),
                          ],
                        ),
                      const SizedBox(height: 20),
                      PrimaryButton(
                        lowBalance
                            ? s.lookupButtonRecharge
                            : s.lookupButtonSearch(
                                price == null ? '' : formatPaise(price),
                              ),
                        busy: _busy,
                        onPressed: config == null
                            ? null
                            : (_valid || lowBalance)
                            ? () => _search(config, balance)
                            : null,
                      ),
                      ErrorMessage(
                        _error ??
                            (wallet == null
                                ? null
                                : !wallet.minRechargeDone
                                ? _rechargeRequiredMessage(s)
                                : lowBalance
                                ? s.errorInsufficientBalance
                                : null),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _UpperCaseFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) => newValue.copyWith(text: newValue.text.toUpperCase());
}

class _ConfirmSheet extends StatelessWidget {
  const _ConfirmSheet({
    required this.reg,
    required this.price,
    required this.balance,
  });
  final String reg;
  final int price;
  final int balance;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    Widget row(String label, String value, {bool bold = false}) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Flexible(
            child: Text(label, style: sora(13, color: AppColors.muted)),
          ),
          const SizedBox(width: 12),
          Text(
            value,
            style: sora(
              14,
              weight: bold ? FontWeight.w800 : FontWeight.w600,
              color: AppColors.navy,
            ),
          ),
        ],
      ),
    );

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 0, 22, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              s.confirmTitle,
              style: sora(20, weight: FontWeight.w700, color: AppColors.navy),
            ),
            const SizedBox(height: 12),
            row(s.confirmRegLabel, reg, bold: true),
            const Divider(height: 1, color: AppColors.hairline),
            row(s.confirmPriceLabel, formatPaise(price)),
            const Divider(height: 1, color: AppColors.hairline),
            row(s.confirmBalanceAfterLabel, formatPaise(balance - price)),
            const SizedBox(height: 16),
            PrimaryButton(
              s.lookupButtonSearch(formatPaise(price)),
              onPressed: () => Navigator.pop(context, true),
            ),
            const SizedBox(height: 4),
            Center(
              child: TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text(s.commonCancel),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
