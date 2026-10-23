import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/providers.dart';
import '../../core/money.dart';
import '../../core/secure_screen.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../../data/models.dart';
import '../../l10n/strings.g.dart';
import 'lookup_screen.dart';

/// Displays the result of a fresh lookup.
class ResultScreen extends ConsumerWidget {
  const ResultScreen({super.key, required this.lookup});
  final Lookup lookup;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = S.of(context);
    final isRc = lookup.type == LookupType.rc;
    return SecureScreen(
      child: Scaffold(
        backgroundColor: AppColors.surfaceAlt,
        body: SafeArea(
          child: Column(
            children: [
              const ScreenHeader(),
              Expanded(
                child: PageWidth(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                    children: [
                      Text(
                        isRc ? s.resultTitleRc : s.resultTitlePhone,
                        style: sora(
                          23,
                          weight: FontWeight.w700,
                          color: AppColors.navy,
                          spacing: -0.5,
                        ),
                      ),
                      const SizedBox(height: 14),
                      _PlateCard(lookup: lookup),
                      const SizedBox(height: 14),
                      if (isRc)
                        _RcDetails(rc: lookup.rc!)
                      else
                        _PhoneCard(phone: lookup.phone ?? ''),
                      if (isRc) ...[
                        const SizedBox(height: 14),
                        _PhoneCta(regNo: lookup.regNo),
                      ],
                    ],
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

class _PlateCard extends StatelessWidget {
  const _PlateCard({required this.lookup});
  final Lookup lookup;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final rc = lookup.rc;
    return SoftCard(
      color: AppColors.tintBlue,
      border: false,
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.navy, width: 1.5),
            ),
            child: Text(
              lookup.regNo,
              style: sora(
                15,
                weight: FontWeight.w800,
                color: AppColors.navy,
                spacing: 1.2,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (rc != null)
                  Text(
                    '${rc.maker} ${rc.model}',
                    style: sora(
                      14,
                      weight: FontWeight.w700,
                      color: AppColors.navy,
                    ),
                  ),
                Text(
                  '${s.resultPaid} ${formatPaise(lookup.chargedPaise)}'
                  '${lookup.isDemo ? ' · ${s.resultDemoNote}' : ''}',
                  style: sora(11, color: AppColors.muted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RcDetails extends StatelessWidget {
  const _RcDetails({required this.rc});
  final RcResult rc;

  String _label(S s, String key) => switch (key) {
    'fuelType' => s.resultFuelType,
    'vehicleClass' => s.resultVehicleClass,
    'registrationDate' => s.resultRegistrationDate,
    'rto' => s.resultRto,
    'color' => s.resultColor,
    // Unknown provider field: show its raw key until it gets a translated label.
    _ => key,
  };

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final rows = <(String, String)>[
      (s.resultOwnerName, rc.ownerName),
      (s.resultMaker, rc.maker),
      (s.resultModel, rc.model),
      for (final e in rc.extra.entries) (_label(s, e.key), e.value),
    ];
    return SoftCard(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Column(
        children: [
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0) const Divider(height: 1, color: AppColors.hairline),
            _DetailRow(label: rows[i].$1, value: rows[i].$2),
          ],
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 4,
            child: Text(label, style: sora(12, color: AppColors.muted)),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 6,
            child: Text(
              value,
              style: sora(
                13,
                weight: FontWeight.w600,
                color: AppColors.navy,
                height: 1.3,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PhoneCard extends StatelessWidget {
  const _PhoneCard({required this.phone});
  final String phone;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    return SoftCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(s.resultPhoneLabel, style: sora(12, color: AppColors.muted)),
          const SizedBox(height: 8),
          SelectableText(
            phone.isEmpty ? s.commonNotAvailable : phone,
            style: sora(
              28,
              weight: FontWeight.w800,
              color: AppColors.navy,
              spacing: 1,
            ),
          ),
          const SizedBox(height: 16),
          if (phone.isNotEmpty)
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () => launchUrl(Uri(scheme: 'tel', path: phone)),
                icon: const Icon(Icons.call_rounded, size: 18),
                label: Text(s.resultPhoneCall),
              ),
            ),
          const SizedBox(height: 14),
          Text(
            s.resultPhoneNote,
            style: sora(11, color: AppColors.muted, height: 1.4),
          ),
        ],
      ),
    );
  }
}

/// On an RC result: jump to the phone lookup without retyping.
class _PhoneCta extends ConsumerWidget {
  const _PhoneCta({required this.regNo});
  final String regNo;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = S.of(context);
    final config = ref.watch(configProvider).value;
    if (config == null) return const SizedBox.shrink();

    return SoftCard(
      color: AppColors.tintAmber,
      border: false,
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => LookupScreen(
            type: LookupType.phone,
            initialRegNo: regNo,
          ),
        ),
      ),
      child: Row(
        children: [
          const Icon(Icons.phone_in_talk_rounded, color: AppColors.navy),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  s.resultGetPhoneCta(formatPaise(config.phonePricePaise)),
                  style: sora(
                    13,
                    weight: FontWeight.w700,
                    color: AppColors.navy,
                    height: 1.3,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  s.resultGetPhoneCtaSub,
                  style: sora(11, color: AppColors.muted),
                ),
              ],
            ),
          ),
          const Icon(Icons.chevron_right_rounded, color: AppColors.navy),
        ],
      ),
    );
  }
}
