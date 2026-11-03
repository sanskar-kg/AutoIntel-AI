import 'package:firebase_analytics/firebase_analytics.dart';

/// Centralized analytics wrapper. Event names and parameters are kept stable so
/// the Firebase Analytics catalogue can be used by dashboards and experiments.
class AppAnalytics {
  AppAnalytics._();

  static FirebaseAnalytics? _analytics;

  static void configure({required bool firebaseReady}) {
    _analytics = firebaseReady ? FirebaseAnalytics.instance : null;
  }

  static Future<void> log(
    String name, {
    Map<String, Object>? parameters,
  }) async {
    final analytics = _analytics;
    if (analytics == null) return;
    try {
      await analytics.logEvent(name: name, parameters: parameters);
    } catch (_) {
      // Analytics must never interrupt a user action.
    }
  }

  static Future<void> screen(String name) =>
      log('screen_viewed', parameters: {'screen': name});

  static String amountBucket(int paise) {
    final rupees = paise / 100;
    if (rupees <= 100) return '0_100';
    if (rupees <= 500) return '101_500';
    if (rupees <= 1000) return '501_1000';
    return '1001_plus';
  }
}
