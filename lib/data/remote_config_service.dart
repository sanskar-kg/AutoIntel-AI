import 'package:firebase_remote_config/firebase_remote_config.dart';

import '../core/crash_reporting.dart';

class RemoteSettings {
  const RemoteSettings({
    required this.forceUpdateEnabled,
    required this.stallModeEnabled,
    required this.autoRentalEnabled,
    required this.minimumVersion,
    required this.updateUrl,
    required this.stallMessage,
  });

  static const defaults = RemoteSettings(
    forceUpdateEnabled: false,
    stallModeEnabled: false,
    autoRentalEnabled: false,
    minimumVersion: '',
    updateUrl: '',
    stallMessage: '',
  );

  final bool forceUpdateEnabled;
  final bool stallModeEnabled;
  final bool autoRentalEnabled;
  final String minimumVersion;
  final String updateUrl;
  final String stallMessage;

  factory RemoteSettings.from(FirebaseRemoteConfig config) => RemoteSettings(
    forceUpdateEnabled: config.getBool('force_update_enabled'),
    stallModeEnabled: config.getBool('stall_mode_enabled'),
    autoRentalEnabled: config.getBool('auto_rental_enabled'),
    minimumVersion: config.getString('minimum_app_version'),
    updateUrl: config.getString('update_url'),
    stallMessage: config.getString('stall_message'),
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
          minimumFetchInterval: const Duration(hours: 1),
        ),
      );
      await config.setDefaults({
        'force_update_enabled': false,
        'stall_mode_enabled': false,
        'auto_rental_enabled': false,
        'minimum_app_version': '',
        'update_url': '',
        'stall_message': '',
      });
      await config.fetchAndActivate();
      return RemoteSettings.from(config);
    } catch (error, stack) {
      CrashReporter.recordError(error, stack, reason: 'remote_config_load');
      return RemoteSettings.defaults;
    }
  }
}
