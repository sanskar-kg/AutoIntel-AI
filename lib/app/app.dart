import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/errors.dart';
import '../core/theme.dart';
import '../core/widgets.dart';
import '../features/auth/auth_screen.dart';
import '../features/home/home_screen.dart';
import '../features/settings/settings_screen.dart';
import '../features/wallet/recharge_gate_screen.dart';
import '../features/wallet/wallet_screen.dart';
import '../l10n/strings.g.dart';
import 'providers.dart';

class AutoIntelApp extends ConsumerWidget {
  const AutoIntelApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locale = ref.watch(languageProvider);
    return MaterialApp(
      onGenerateTitle: (context) => S.of(context).brandWordmark,
      debugShowCheckedModeBanner: false,
      theme: appTheme(),
      locale: locale,
      supportedLocales: [
        for (final tag in supportedLanguageTags) Locale(tag.split('_').first),
      ],
      localizationsDelegates: const [
        S.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: const _Root(),
    );
  }
}

/// Splash while booting, then authentication, the recharge gate, and the app.
class _Root extends ConsumerWidget {
  const _Root();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final boot = ref.watch(_bootProvider);
    return boot.when(
      loading: () => const _Splash(),
      error: (e, _) =>
          _BootError(error: e, onRetry: () => ref.invalidate(_bootProvider)),
      data: (_) {
        final account = ref.watch(accountProvider);
        if (account.isLoading) return const _Splash();
        if (account.hasError) {
          return _BootError(
            error: account.error!,
            onRetry: () => ref.invalidate(accountProvider),
          );
        }
        if (account.value == null) return const AuthScreen();
        final remoteSettings = ref.watch(remoteSettingsProvider).value;
        if (remoteSettings == null) return const _Splash();
        if (remoteSettings.stallModeEnabled) {
          return _RemoteGate(
            title: S.of(context).remoteStallTitle,
            message: remoteSettings.stallMessage.isEmpty
                ? S.of(context).remoteStallBody
                : remoteSettings.stallMessage,
            actionLabel: S.of(context).commonRetry,
            onAction: () => ref.invalidate(remoteSettingsProvider),
          );
        }
        if (remoteSettings.forceUpdateEnabled) {
          return _RemoteGate(
            title: S.of(context).remoteUpdateTitle,
            message: S.of(context).remoteUpdateBody,
            actionLabel: remoteSettings.updateUrl.isEmpty
                ? S.of(context).commonRetry
                : S.of(context).remoteUpdateAction,
            onAction: remoteSettings.updateUrl.isEmpty
                ? () => ref.invalidate(remoteSettingsProvider)
                : () => launchUrl(Uri.parse(remoteSettings.updateUrl)),
          );
        }
        final configState = ref.watch(configProvider);
        final walletState = ref.watch(walletProvider);
        if (configState.isLoading || walletState.isLoading) {
          return const _Splash();
        }
        if (configState.hasError) {
          return _BootError(
            error: configState.error!,
            onRetry: () => ref.invalidate(configProvider),
          );
        }
        if (walletState.hasError) {
          return _BootError(
            error: walletState.error!,
            onRetry: () => ref.invalidate(walletProvider),
          );
        }
        final wallet = walletState.value;
        final config = configState.value;
        if (wallet == null || config == null) return const _Splash();
        if (wallet.showRechargeGate && !wallet.minRechargeDone) {
          return RechargeGateScreen(config: config);
        }
        return const _MainShell();
      },
    );
  }
}

/// Minimum splash time plus authentication and remote settings.
///
/// Wallet/config are intentionally loaded only after authentication succeeds;
/// both backend calls require a session token.
final _bootProvider = FutureProvider<void>((ref) async {
  await Future.wait([
    Future<void>.delayed(const Duration(milliseconds: 1100)),
    ref.read(accountProvider.future),
    ref.read(remoteSettingsProvider.future),
  ]);
});

class _Splash extends StatelessWidget {
  const _Splash();

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFF0066FD),
    body: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            S.of(context).brandWordmark,
            style: sora(
              40,
              weight: FontWeight.w800,
              color: Colors.white,
              spacing: -1,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            S.of(context).brandTagline,
            style: sora(12, color: Colors.white70),
          ),
        ],
      ),
    ),
  );
}

class _BootError extends StatelessWidget {
  const _BootError({required this.error, required this.onRetry});
  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Brand(),
                const SizedBox(height: 24),
                ErrorMessage(errorMessage(s, error)),
                const SizedBox(height: 16),
                PrimaryButton(s.commonRetry, onPressed: onRetry),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MainShell extends ConsumerStatefulWidget {
  const _MainShell();

  @override
  ConsumerState<_MainShell> createState() => _MainShellState();
}

class _MainShellState extends ConsumerState<_MainShell> {
  static const _tooltipsSeenKey = 'onboarding.tooltips_seen.v1';
  final _homeTooltipKey = GlobalKey<TooltipState>();
  final _walletTooltipKey = GlobalKey<TooltipState>();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _showFirstRunTooltips(),
    );
  }

  Future<void> _showFirstRunTooltips() async {
    final prefs = ref.read(sharedPrefsProvider);
    if (prefs.getBool(_tooltipsSeenKey) ?? false) return;

    TooltipState? homeTooltip;
    for (var attempt = 0; attempt < 3 && mounted; attempt++) {
      await Future<void>.delayed(const Duration(milliseconds: 350));
      homeTooltip = _homeTooltipKey.currentState;
      if (homeTooltip != null) break;
    }
    if (!mounted || homeTooltip == null) return;

    homeTooltip.ensureTooltipVisible();
    await Future<void>.delayed(const Duration(seconds: 3));
    if (!mounted) return;
    _walletTooltipKey.currentState?.ensureTooltipVisible();
    await prefs.setBool(_tooltipsSeenKey, true);
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final index = ref.watch(tabProvider);
    return Scaffold(
      body: IndexedStack(
        index: index,
        children: const [
          HomeScreen(),
          WalletScreen(),
          SettingsScreen(),
        ],
      ),
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: AppColors.hairline)),
        ),
        child: BottomNavigationBar(
          type: BottomNavigationBarType.fixed,
          currentIndex: index,
          onTap: ref.read(tabProvider.notifier).select,
          backgroundColor: Colors.white,
          selectedItemColor: AppColors.blue,
          unselectedItemColor: AppColors.muted,
          selectedLabelStyle: sora(12, weight: FontWeight.w600),
          unselectedLabelStyle: sora(12),
          items: [
            BottomNavigationBarItem(
              icon: Tooltip(
                key: _homeTooltipKey,
                message: s.tooltipHome,
                triggerMode: TooltipTriggerMode.manual,
                child: const Icon(Icons.home_rounded),
              ),
              label: s.navHome,
            ),
            BottomNavigationBarItem(
              icon: Tooltip(
                key: _walletTooltipKey,
                message: s.tooltipWallet,
                triggerMode: TooltipTriggerMode.manual,
                child: const Icon(Icons.account_balance_wallet_rounded),
              ),
              label: s.navWallet,
            ),
            BottomNavigationBarItem(
              icon: const Icon(Icons.settings_rounded),
              label: s.navSettings,
            ),
          ],
        ),
      ),
    );
  }
}

class _RemoteGate extends StatelessWidget {
  const _RemoteGate({
    required this.title,
    required this.message,
    required this.actionLabel,
    required this.onAction,
  });

  final String title;
  final String message;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Brand(),
              const SizedBox(height: 24),
              Text(title, style: sora(24, weight: FontWeight.w800)),
              const SizedBox(height: 8),
              Text(message, textAlign: TextAlign.center),
              const SizedBox(height: 20),
              PrimaryButton(actionLabel, onPressed: onAction),
            ],
          ),
        ),
      ),
    ),
  );
}
