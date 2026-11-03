import 'package:firebase_remote_config/firebase_remote_config.dart';

import '../core/crash_reporting.dart';

class RemoteSettings {
  const RemoteSettings({
    required this.forceUpdateEnabled,
    required this.stallModeEnabled,
    required this.autoRentalEnabled,
    required this.onboardingWalletSpotlightEnabled,
    required this.minimumRechargeAmount,
    required this.minimumVersion,
    required this.updateUrl,
    required this.stallMessage,
    required this.rcPricePaise,
    required this.phonePricePaise,
  });

  static const defaults = RemoteSettings(
    forceUpdateEnabled: false,
    stallModeEnabled: false,
    autoRentalEnabled: false,
    onboardingWalletSpotlightEnabled: true,
    minimumRechargeAmount: '20',
    minimumVersion: '',
    updateUrl: '',
    stallMessage: '',
    rcPricePaise: 200,
    phonePricePaise: 700,
  );

  final bool forceUpdateEnabled;
  final bool stallModeEnabled;
  final bool autoRentalEnabled;
  final bool onboardingWalletSpotlightEnabled;
  /// String by design: this is edited as a human-readable rupee amount in
  /// Firebase Remote Config (for example, "20" or "25.00").
  final String minimumRechargeAmount;
  final String minimumVersion;
  final String updateUrl;
  final String stallMessage;
  final int rcPricePaise;
  final int phonePricePaise;

  factory RemoteSettings.from(FirebaseRemoteConfig config) => RemoteSettings(
    forceUpdateEnabled: config.getBool('force_update_enabled'),
    stallModeEnabled: config.getBool('stall_mode_enabled'),
    autoRentalEnabled: config.getBool('auto_rental_enabled'),
    onboardingWalletSpotlightEnabled: config.getBool(
      'onboarding_wallet_spotlight_enabled',
    ),
    minimumRechargeAmount: config.getString('onboarding_wallet_min_recharge'),
    minimumVersion: config.getString('minimum_app_version'),
    updateUrl: config.getString('update_url'),
    stallMessage: config.getString('stall_message'),
    rcPricePaise: config.getInt('lookup_rc_price_paise'),
    phonePricePaise: config.getInt('lookup_phone_price_paise'),
  );
}

class RemoteConfigService {
  const RemoteConfigService();

  Future<RemoteSettings> load() async {
    try {
      final config = FirebaseRemoteConfig.instance;
      await config.setConfigSettings(
        RemoteConfigSettings(
          fetchTimeout: const Duration(seconds: 8),
          // Pricing should reflect a newly published value on the next app
          // launch instead of remaining stale for the normal feature-flag
          // cache window.
          minimumFetchInterval: Duration.zero,
        ),
      );
      await config.setDefaults({
        'force_update_enabled': false,
        'stall_mode_enabled': false,
        'auto_rental_enabled': false,
        'onboarding_wallet_spotlight_enabled': true,
        'onboarding_wallet_min_recharge': '20',
        'minimum_app_version': '',
        'update_url': '',
        'stall_message': '',
        'lookup_rc_price_paise': 200,
        'lookup_phone_price_paise': 700,
      });
      await config.fetchAndActivate();
      return RemoteSettings.from(config);
    } catch (error, stack) {
      CrashReporter.recordError(error, stack, reason: 'remote_config_load');
      return RemoteSettings.defaults;
    }
  }
}
