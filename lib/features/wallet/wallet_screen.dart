import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../app/providers.dart';
import '../../core/errors.dart';
import '../../core/money.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../../data/models.dart';
import '../../l10n/strings.g.dart';
import 'amount_picker.dart';
import 'payment_result_screen.dart';

enum _TxFilter { all, recharges, searches }

class WalletScreen extends ConsumerStatefulWidget {
  const WalletScreen({super.key});

  @override
  ConsumerState<WalletScreen> createState() => _WalletScreenState();
}

class _WalletScreenState extends ConsumerState<WalletScreen> {
  _TxFilter _filter = _TxFilter.all;
  int? _amount;
  bool _busy = false;
  bool _showPicker = false;
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
      if (mounted) setState(() => _showPicker = false);
    } catch (e) {
      if (mounted) setState(() => _error = errorMessage(S.of(context), e));
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _checkPending() async {
    setState(() => _busy = true);
    try {
      final result = await ref.read(walletProvider.notifier).checkPending();
      if (result != null && mounted && result.status != OrderStatus.pending) {
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => PaymentResultScreen(result: result),
          ),
        );
      }
    } catch (e) {
      if (mounted) setState(() => _error = errorMessage(S.of(context), e));
    }
    if (mounted) setState(() => _busy = false);
  }

  bool _matches(LedgerEntry e) => switch (_filter) {
    _TxFilter.all => true,
    _TxFilter.recharges => e.category == LedgerCategory.topup,
    _TxFilter.searches =>
      e.category == LedgerCategory.rcLookup ||
          e.category == LedgerCategory.phoneLookup,
  };

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final wallet = ref.watch(walletProvider);
    final config = ref.watch(configProvider).value;

    return SafeArea(
      child: PageWidth(
        child: RefreshIndicator(
          onRefresh: () => ref.read(walletProvider.notifier).refresh(),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
            children: [
              Text(
                s.walletTitle,
                style: sora(
                  23,
                  weight: FontWeight.w700,
                  color: AppColors.navy,
                  spacing: -0.5,
                ),
              ),
              const SizedBox(height: 16),
              wallet.when(
                loading: () => const Padding(
                  padding: EdgeInsets.all(40),
                  child: Center(child: CircularProgressIndicator()),
                ),
                error: (e, _) => Column(
                  children: [
                    ErrorMessage(errorMessage(s, e)),
                    TextButton(
                      onPressed: () => ref.invalidate(walletProvider),
                      child: Text(s.commonRetry),
                    ),
                  ],
                ),
                data: (w) => _content(context, s, w, config),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _content(BuildContext context, S s, WalletState w, AppConfig? config) {
    final entries = w.ledger.where(_matches).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: AppColors.blue,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                s.walletBalanceLabel,
                style: sora(12, color: Colors.white70),
              ),
              const SizedBox(height: 6),
              Text(
                formatPaise(w.balancePaise),
                style: sora(
                  34,
                  weight: FontWeight.w800,
                  color: Colors.white,
                  height: 1.1,
                  spacing: -1,
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                height: 44,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: AppColors.blue,
                    minimumSize: const Size(0, 44),
                    padding: const EdgeInsets.symmetric(horizontal: 18),
                  ),
                  onPressed: config == null
                      ? null
                      : () => setState(() => _showPicker = !_showPicker),
                  icon: const Icon(Icons.add_rounded, size: 20),
                  label: Text(s.walletAddMoney),
                ),
              ),
            ],
          ),
        ),
        if (w.pendingOrderId != null) ...[
          const SizedBox(height: 12),
          SoftCard(
            color: AppColors.tintAmber,
            border: false,
            child: Row(
              children: [
                const Icon(
                  Icons.hourglass_top_rounded,
                  color: AppColors.warning,
                  size: 20,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    s.walletPendingPayment,
                    style: sora(
                      12,
                      weight: FontWeight.w600,
                      color: AppColors.navy,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: _busy ? null : _checkPending,
                  child: Text(s.walletPendingRefresh),
                ),
              ],
            ),
          ),
        ],
        if (_showPicker && config != null) ...[
          const SizedBox(height: 16),
          SoftCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AmountPicker(
                  config: config,
                  onChanged: (v) => setState(() => _amount = v),
                ),
                const SizedBox(height: 16),
                PrimaryButton(
                  s.gatePayButton(_amount == null ? '' : formatPaise(_amount!)),
                  busy: _busy,
                  onPressed: _amount == null ? null : _pay,
                ),
              ],
            ),
          ),
        ],
        ErrorMessage(_error),
        const SizedBox(height: 24),
        Text(
          s.walletTransactionsTitle,
          style: sora(16, weight: FontWeight.w700, color: AppColors.navy),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          children: [
            _chip(s.walletFilterAll, _TxFilter.all),
            _chip(s.walletFilterRecharges, _TxFilter.recharges),
            _chip(s.walletFilterSearches, _TxFilter.searches),
          ],
        ),
        const SizedBox(height: 8),
        if (entries.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 32),
            child: Center(
              child: Text(
                s.walletEmpty,
                style: sora(13, color: AppColors.muted),
              ),
            ),
          )
        else
          for (final e in entries) _TxRow(entry: e),
      ],
    );
  }

  Widget _chip(String label, _TxFilter value) => ChoiceChip(
    label: Text(label),
    selected: _filter == value,
    showCheckmark: false,
    onSelected: (_) => setState(() => _filter = value),
    labelStyle: sora(
      12,
      weight: FontWeight.w600,
      color: _filter == value ? Colors.white : AppColors.navy,
    ),
    selectedColor: AppColors.blue,
    backgroundColor: AppColors.chipBg,
    side: BorderSide.none,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
  );
}

class _TxRow extends StatelessWidget {
  const _TxRow({required this.entry});
  final LedgerEntry entry;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final title = switch (entry.category) {
      LedgerCategory.topup => s.walletTxRecharge,
      LedgerCategory.rcLookup => s.walletTxRc(entry.regNoMasked),
      LedgerCategory.phoneLookup => s.walletTxPhone(entry.regNoMasked),
      LedgerCategory.refund => s.walletTxRefund,
    };
    final locale = Localizations.localeOf(context).toString();
    final date = DateFormat.yMMMd(locale).add_jm().format(entry.createdAt);
    final amount =
        '${entry.isCredit ? '+' : '−'}${formatPaise(entry.amountPaise)}';
    final color = entry.isCredit ? AppColors.success : AppColors.navy;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: entry.isCredit ? AppColors.tintGreen : AppColors.chipBg,
              shape: BoxShape.circle,
            ),
            child: Icon(
              entry.isCredit
                  ? Icons.south_west_rounded
                  : Icons.north_east_rounded,
              size: 18,
              color: color,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: sora(
                    13,
                    weight: FontWeight.w600,
                    color: AppColors.navy,
                  ),
                ),
                const SizedBox(height: 2),
                Text(date, style: sora(11, color: AppColors.muted)),
              ],
            ),
          ),
          Text(
            amount,
            style: sora(14, weight: FontWeight.w700, color: color),
          ),
        ],
      ),
    );
  }
}
