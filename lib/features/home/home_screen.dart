import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/money.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../../data/models.dart';
import '../../l10n/strings.g.dart';
import '../lookup/lookup_screen.dart';
import '../settings/language_sheet.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = S.of(context);
    final wallet = ref.watch(walletProvider).value;
    final config = ref.watch(configProvider).value;

    return SafeArea(
      child: PageWidth(
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(22, 16, 14, 0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Expanded(child: Brand()),
                    Row(
                      children: [
                        if (wallet != null)
                          _WalletChip(balancePaise: wallet.balancePaise),
                        const LanguageButton(),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 28),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  children: [
                    _FeatureTile(
                      tint: AppColors.tintBlue,
                      title: s.homeTileRcTitle,
                      subtitle: s.homeTileRcSubtitle,
                      price: config == null
                          ? null
                          : s.homeTilePrice(formatPaise(config.rcPricePaise)),
                      art: Image.asset(
                        'assets/images/car.png',
                        width: 150,
                        height: 105,
                        fit: BoxFit.contain,
                      ),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) =>
                              const LookupScreen(type: LookupType.rc),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    _FeatureTile(
                      tint: AppColors.tintAmber,
                      title: s.homeTilePhoneTitle,
                      subtitle: s.homeTilePhoneSubtitle,
                      price: config == null
                          ? null
                          : s.homeTilePrice(
                              formatPaise(config.phonePricePaise),
                            ),
                      art: Image.asset(
                        'assets/images/phone.png',
                        width: 120,
                        height: 120,
                        fit: BoxFit.contain,
                      ),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) =>
                              const LookupScreen(type: LookupType.phone),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}

class _WalletChip extends ConsumerWidget {
  const _WalletChip({required this.balancePaise});
  final int balancePaise;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final amount = formatPaise(balancePaise);
    return Semantics(
      button: true,
      label: S.of(context).a11yWalletChip(amount),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => ref.read(tabProvider.notifier).select(1),
        child: Container(
          constraints: const BoxConstraints(minHeight: 40),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: AppColors.tintBlue,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.account_balance_wallet_rounded,
                size: 16,
                color: AppColors.blue,
              ),
              const SizedBox(width: 6),
              ExcludeSemantics(
                child: Text(
                  amount,
                  style: sora(
                    13,
                    weight: FontWeight.w700,
                    color: AppColors.navy,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FeatureTile extends StatelessWidget {
  const _FeatureTile({
    required this.tint,
    required this.title,
    required this.subtitle,
    required this.price,
    required this.art,
    required this.onTap,
  });

  final Color tint;
  final String title;
  final String subtitle;
  final String? price;
  final Widget art;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => ConstrainedBox(
    // Grows with large fonts / long translations instead of overflowing.
    constraints: const BoxConstraints(minHeight: 150),
    child: Material(
      color: tint,
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Stack(
          children: [
            Positioned(right: 0, bottom: 0, child: art),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 18, 150, 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: sora(
                      16,
                      weight: FontWeight.w700,
                      color: AppColors.navy,
                      height: 1.2,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    subtitle,
                    style: sora(12, color: AppColors.mutedOnTint, height: 1.4),
                  ),
                  const SizedBox(height: 14),
                  if (price != null)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        price!,
                        style: sora(
                          11,
                          weight: FontWeight.w700,
                          color: AppColors.blue,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
