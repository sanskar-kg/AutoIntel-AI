import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../../l10n/strings.g.dart';

class AuthScreen extends ConsumerStatefulWidget {
  const AuthScreen({super.key});

  @override
  ConsumerState<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends ConsumerState<AuthScreen> {
  bool _loading = false;
  String? _error;

  Future<void> _signIn({required bool anonymous}) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final auth = ref.read(authRepositoryProvider);
      if (anonymous) {
        await auth.signInAnonymously();
      } else {
        await auth.signIn();
      }
      ref.invalidate(accountProvider);
      ref.invalidate(walletProvider);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Brand(),
                  const SizedBox(height: 32),
                  Text(s.authTitle, style: sora(28, weight: FontWeight.w800)),
                  const SizedBox(height: 28),
                  if (_error != null) ...[
                    Text(_error!, style: sora(13, color: Colors.red.shade700)),
                    const SizedBox(height: 12),
                  ],
                  PrimaryButton(
                    s.authTruecaller,
                    onPressed: _loading
                        ? null
                        : () => _signIn(anonymous: false),
                  ),
                  if (_error != null) ...[
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
    );
  }
}
