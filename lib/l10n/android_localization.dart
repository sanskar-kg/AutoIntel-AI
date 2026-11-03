import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'strings.g.dart';
import 'strings_runtime.dart';

class AndroidLocalization {
  static const _channel = MethodChannel('motorinfo/localization');

  static Future<void> load({String? locale}) async {
    try {
      final effectiveLocale = locale == null || locale.isEmpty
          ? WidgetsBinding.instance.platformDispatcher.locale.languageCode
          : locale.split('_').first;
      final raw = await _channel.invokeMethod<Map<Object?, Object?>>(
        'loadStrings',
        {
          'tags': locale == null || locale.isEmpty
              ? <String>[]
              : <String>[locale.replaceAll('_', '-')],
          'keys': stringResourceKeys,
        },
      );
      final response = Map<Object?, Object?>.from(raw ?? const {});
      setRuntimeTranslations(
        strings: {
          effectiveLocale: Map<String, String>.from(
            response.map(
              (key, value) => MapEntry(key.toString(), value.toString()),
            ),
          ),
        },
        plurals: const {},
      );
    } on MissingPluginException {
      // Non-Android targets retain the generated English resources.
    } on PlatformException {
      // A translation bridge failure must not prevent startup.
    }
  }
}
