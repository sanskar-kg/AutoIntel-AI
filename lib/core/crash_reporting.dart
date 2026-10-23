import 'dart:ui';

import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';

/// Centralizes Crashlytics setup so local development and widget tests can run
/// without a Firebase app configuration.
class CrashReporter {
  const CrashReporter._();

  static bool _enabled = false;

  static void configure({required bool firebaseReady}) {
    if (!firebaseReady || !kReleaseMode) return;
    _enabled = true;
    FlutterError.onError = FirebaseCrashlytics.instance.recordFlutterFatalError;
    PlatformDispatcher.instance.onError = (error, stack) {
      FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
      return true;
    };
  }

  static void recordError(Object error, StackTrace stack, {String? reason}) {
    if (!_enabled) return;
    FirebaseCrashlytics.instance.recordError(error, stack, reason: reason);
  }
}
