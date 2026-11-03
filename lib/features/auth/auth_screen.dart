import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../../core/analytics.dart';
import '../../l10n/strings.g.dart';
import '../settings/language_sheet.dart';

class AuthScreen extends ConsumerStatefulWidget {
  const AuthScreen({super.key});

  @override
  ConsumerState<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends ConsumerState<AuthScreen> {
  bool _loading = false;
  bool _fallbackAvailable = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(AppAnalytics.screen('auth'));
  }

  bool get _showFallback => _fallbackAvailable;

  bool _isDismissedTruecallerError(Object error) {
    final message = error.toString().toLowerCase();
    return message.contains('denied') ||
        message.contains('dismiss') ||
        message.contains('consent') ||
        message.contains('cancel') ||
        message.contains('footer');
  }

  Future<void> _signIn({required bool anonymous}) async {
    await AppAnalytics.log(
      'auth_method_selected',
      parameters: {'method': anonymous ? 'anonymous' : 'truecaller'},
    );
    setState(() {
      _loading = true;
      _error = null;
      _fallbackAvailable = false;
    });
    try {
      final auth = ref.read(authRepositoryProvider);
      if (anonymous) {
        await auth.signInAnonymously();
        await AppAnalytics.log(
          'signup_completed',
          parameters: {'method': 'anonymous'},
        );
      } else {
        await auth.signIn();
        await AppAnalytics.log(
          'login_completed',
          parameters: {'method': 'truecaller'},
        );
      }
      ref.invalidate(accountProvider);
      ref.invalidate(walletProvider);
    } catch (error) {
      await AppAnalytics.log(
        'auth_failed',
        parameters: {
          'method': anonymous ? 'anonymous' : 'truecaller',
          'reason': error.runtimeType.toString().toLowerCase(),
        },
      );
      if (mounted) {
        setState(() {
          _fallbackAvailable = true;
          _error = _isDismissedTruecallerError(error) ? null : error.toString();
        });
        await AppAnalytics.log('auth_fallback_shown');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 12, 14, 0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [const Brand(), const LanguageButton()],
              ),
            ),
            Expanded(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 420),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          s.authTitle,
                          style: sora(28, weight: FontWeight.w800),
                        ),
                        const SizedBox(height: 28),
                        if (_error != null) ...[
                          Text(
                            _error!,
                            style: sora(13, color: Colors.red.shade700),
                          ),
                          const SizedBox(height: 12),
                        ],
                        PrimaryButton(
                          s.authTruecaller,
                          onPressed: _loading
                              ? null
                              : () => _signIn(anonymous: false),
                        ),
                        if (_showFallback) ...[
                          const SizedBox(height: 12),
                          OutlinedButton(
                            onPressed: _loading
                                ? null
                                : () => _signIn(anonymous: true),
                            child: Text(s.authTemporary),
                          ),
                        ],
                        if (_loading) ...[
                          const SizedBox(height: 16),
                          const Center(child: CircularProgressIndicator()),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
