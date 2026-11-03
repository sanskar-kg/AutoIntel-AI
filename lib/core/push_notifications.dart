import 'package:firebase_messaging/firebase_messaging.dart';

import 'crash_reporting.dart';

/// Receives background messages without doing any UI work.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {}

Future<void> configurePushNotifications() async {
  try {
    final messaging = FirebaseMessaging.instance;
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
    await messaging.setAutoInitEnabled(true);
    await messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      provisional: true,
    );
    // Token registration can be added to the authenticated backend later. The
    // Firebase client is initialized now so notifications and token refreshes
    // are available for the production messaging flow.
    await messaging.getToken();
    messaging.onTokenRefresh.listen((_) {});
  } catch (error, stack) {
    CrashReporter.recordError(error, stack, reason: 'push_notifications_setup');
  }
}
