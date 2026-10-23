import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Blocks screenshots and the recents preview while [child] is on screen
/// (Android FLAG_SECURE, see MainActivity.kt). Used on results that contain personal data.
class SecureScreen extends StatefulWidget {
  const SecureScreen({super.key, required this.child});
  final Widget child;

  @override
  State<SecureScreen> createState() => _SecureScreenState();
}

class _SecureScreenState extends State<SecureScreen> {
  static const _channel = MethodChannel('autointel/secure_screen');

  /// Debug builds stay screenshot-able for QA; release always blocks.
  /// Force it in debug with `--dart-define=FORCE_SECURE=true`.
  static const _active = !kDebugMode || bool.fromEnvironment('FORCE_SECURE');

  @override
  void initState() {
    super.initState();
    if (_active) _set(true);
  }

  @override
  void dispose() {
    if (_active) _set(false);
    super.dispose();
  }

  Future<void> _set(bool on) async {
    try {
      await _channel.invokeMethod<void>(on ? 'enable' : 'disable');
    } on MissingPluginException {
      // Tests / non-Android platforms.
    } on PlatformException {
      // Best effort.
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
