import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/providers.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../../l10n/strings.g.dart';
import 'language_sheet.dart';

/// Shown in Settings → About. Not user-facing copy, so it lives here and not in strings.xml.
const appVersion = '1.0.0';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  static final _supportEmail = Uri(
    scheme: 'mailto',
    path: 'contactus@kalagato.co',
    queryParameters: {'subject': 'AutoIntel support'},
  );
  static final _motorInsuranceCalculatorUrl = Uri.parse(
    'https://play.google.com/store/apps/details?id=com.insurance.calculator.motor',
  );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = S.of(context);
    final locale = ref.watch(languageProvider);
    final account = ref.watch(accountProvider).value;
    final languageLabel = locale == null
        ? s.languageSystemDefault
        : nativeLanguageName(locale.languageCode);

    return SafeArea(
      child: PageWidth(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
          children: [
            Text(
              s.settingsTitle,
              style: sora(
                23,
                weight: FontWeight.w700,
                color: AppColors.navy,
                spacing: -0.5,
              ),
            ),
            const SizedBox(height: 16),
            _SettingsTile(
              icon: Icons.language,
              title: s.settingsLanguage,
              trailing: languageLabel,
              onTap: () => showLanguageSheet(context),
            ),
            if (account != null) ...[
              _SettingsTile(
                icon: Icons.person_outline_rounded,
                title: account.name,
              ),
              _SettingsTile(
                icon: Icons.logout_rounded,
                title: s.settingsSignOut,
                color: Colors.white,
                backgroundColor: Colors.red,
                onTap: () async {
                  await ref.read(authRepositoryProvider).signOut();
                  ref.invalidate(accountProvider);
                  ref.invalidate(walletProvider);
                },
              ),
            ],
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text(
                s.settingsSectionAbout,
                style: sora(
                  12,
                  weight: FontWeight.w700,
                  color: AppColors.muted,
                ),
              ),
            ),
            const SizedBox(height: 8),
            _SettingsTile(
              icon: Icons.privacy_tip_outlined,
              title: s.settingsPrivacy,
              onTap: () =>
                  _openInfo(context, s.settingsPrivacy, s.settingsPrivacyBody),
            ),
            _SettingsTile(
              icon: Icons.gavel_outlined,
              title: s.settingsTerms,
              onTap: () =>
                  _openInfo(context, s.settingsTerms, s.settingsTermsBody),
            ),
            _SettingsTile(
              icon: Icons.support_agent_outlined,
              title: s.settingsHelp,
              onTap: () => _openInfo(
                context,
                s.settingsHelp,
                s.settingsHelpBody,
                actionLabel: s.settingsWriteToUs,
                onAction: () => launchUrl(
                  _supportEmail,
                  mode: LaunchMode.platformDefault,
                ),
              ),
            ),
            _SettingsTile(
              icon: Icons.info_outline,
              title: s.settingsVersion,
              trailing: appVersion,
            ),
            const SizedBox(height: 8),
            _OtherAppCard(
              title: s.settingsOtherAppTitle,
              appName: s.settingsOtherAppName,
              openLabel: s.settingsOpenGooglePlay,
              onTap: () => launchUrl(
                _motorInsuranceCalculatorUrl,
                mode: LaunchMode.externalApplication,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _openInfo(
    BuildContext context,
    String title,
    String body, {
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => InfoScreen(
          title: title,
          body: body,
          actionLabel: actionLabel,
          onAction: onAction,
        ),
      ),
    );
  }
}

class _OtherAppCard extends StatelessWidget {
  const _OtherAppCard({
    required this.title,
    required this.appName,
    required this.openLabel,
    required this.onTap,
  });

  final String title;
  final String appName;
  final String openLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => SoftCard(
    color: AppColors.tintBlue,
    onTap: onTap,
    padding: const EdgeInsets.all(16),
    child: Row(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: SizedBox.square(
            dimension: 88,
            child: Image.asset(
              'assets/images/MIC_app_icon.png',
              fit: BoxFit.cover,
            ),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: sora(12, weight: FontWeight.w600, color: AppColors.muted),
              ),
              const SizedBox(height: 4),
              Text(
                appName,
                style: sora(
                  16,
                  weight: FontWeight.w700,
                  color: AppColors.navy,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Text(
                    openLabel,
                    style: sora(12, weight: FontWeight.w700, color: AppColors.blue),
                  ),
                  const SizedBox(width: 4),
                  const Icon(Icons.open_in_new, size: 15, color: AppColors.blue),
                ],
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _SettingsTile extends StatelessWidget {
  const _SettingsTile({
    required this.icon,
    required this.title,
    this.trailing,
    this.color,
    this.backgroundColor,
    this.onTap,
  });
  final IconData icon;
  final String title;
  final String? trailing;
  final Color? color;
  final Color? backgroundColor;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: SoftCard(
      color: backgroundColor ?? Colors.white,
      onTap: onTap,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      child: Row(
        children: [
          Icon(icon, size: 22, color: color ?? AppColors.navy),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              title,
              style: sora(
                14,
                weight: FontWeight.w600,
                color: color ?? AppColors.navy,
              ),
            ),
          ),
          if (trailing != null)
            Text(trailing!, style: sora(12, color: AppColors.muted)),
          if (onTap != null)
            Icon(Icons.chevron_right_rounded, color: color ?? AppColors.muted),
        ],
      ),
    ),
  );
}

class InfoScreen extends StatelessWidget {
  const InfoScreen({
    super.key,
    required this.title,
    required this.body,
    this.actionLabel,
    this.onAction,
  });
  final String title;
  final String body;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => Scaffold(
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
                      title,
                      style: sora(
                        23,
                        weight: FontWeight.w700,
                        color: AppColors.navy,
                        spacing: -0.5,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      body,
                      style: sora(13, color: AppColors.muted, height: 1.6),
                    ),
                    if (actionLabel != null && onAction != null) ...[
                      const SizedBox(height: 24),
                      PrimaryButton(actionLabel!, onPressed: onAction),
                    ],
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
