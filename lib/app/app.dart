import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:showcaseview/showcaseview.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/errors.dart';
import '../core/analytics.dart';
import '../core/theme.dart';
import '../core/widgets.dart';
import '../features/auth/auth_screen.dart';
import '../features/home/home_screen.dart';
import '../features/settings/settings_screen.dart';
import '../features/settings/language_sheet.dart';
import '../features/wallet/recharge_gate_screen.dart';
import '../features/wallet/wallet_screen.dart';
import '../l10n/strings.g.dart';
import '../l10n/android_localization.dart';
import 'providers.dart';

class AutoIntelApp extends ConsumerStatefulWidget {
  const AutoIntelApp({super.key});

  @override
  ConsumerState<AutoIntelApp> createState() => _AutoIntelAppState();
}

class _AutoIntelAppState extends ConsumerState<AutoIntelApp> {
  @override
  void initState() {
    super.initState();
    _loadNativeTranslations();
  }

  Future<void> _loadNativeTranslations() async {
    final locale = ref.read(languageProvider);
    await AndroidLocalization.load(locale: locale?.toLanguageTag());
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(languageProvider);
    final locale = ref.watch(languageProvider);
    return MaterialApp(
      onGenerateTitle: (context) => S.of(context).brandWordmark,
      debugShowCheckedModeBanner: false,
      theme: appTheme(),
      locale: locale,
      localeResolutionCallback: (deviceLocale, supportedLocales) {
        final language = deviceLocale?.languageCode;
        for (final supported in supportedLocales) {
          if (supported.languageCode == language) return supported;
        }
        return const Locale('en');
      },
      supportedLocales: [
        for (final tag in supportedIndianLanguageTags)
          Locale(tag.split('_').first),
      ],
      localizationsDelegates: [
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
        if (remoteSettings.onboardingWalletSpotlightEnabled &&
            wallet.showRechargeGate &&
            !wallet.minRechargeDone) {
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
  static const _spotlightSeenKey = 'onboarding.spotlight_seen.v1';
  final _homeSpotlightKey = GlobalKey<State<StatefulWidget>>();
  final _walletSpotlightKey = GlobalKey<State<StatefulWidget>>();
  final _settingsSpotlightKey = GlobalKey<State<StatefulWidget>>();
  BuildContext? _showcaseContext;
  bool _spotlightCompleted = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _startFirstRunSpotlight(),
    );
    unawaited(AppAnalytics.screen('home'));
  }

  Future<void> _startFirstRunSpotlight() async {
    final prefs = ref.read(sharedPrefsProvider);
    if (prefs.getBool(_spotlightSeenKey) ?? false) return;

    await AppAnalytics.log(
      'onboarding_started',
      parameters: {'journey': 'spotlight'},
    );

    for (var attempt = 0; attempt < 4 && mounted; attempt++) {
      await Future<void>.delayed(const Duration(milliseconds: 250));
      if (!mounted) return;
      final showcaseContext = _showcaseContext;
      if (showcaseContext == null) continue;
      final remote = ref.read(remoteSettingsProvider).value;
      final keys = <GlobalKey<State<StatefulWidget>>>[
        _homeSpotlightKey,
        if (remote?.onboardingWalletSpotlightEnabled ?? true)
          _walletSpotlightKey,
        _settingsSpotlightKey,
      ];
      ShowCaseWidget.of(showcaseContext).startShowCase(keys);
      return;
    }
  }

  void _selectTab(int index) {
    ref.read(tabProvider.notifier).select(index);
    final screen = switch (index) {
      0 => 'home',
      1 => 'wallet',
      _ => 'settings',
    };
    unawaited(AppAnalytics.log('tab_selected', parameters: {'tab': screen}));
    unawaited(AppAnalytics.screen(screen));
  }

  Future<void> _completeSpotlight() async {
    if (_spotlightCompleted) return;
    _spotlightCompleted = true;
    await ref.read(sharedPrefsProvider).setBool(_spotlightSeenKey, true);
    await AppAnalytics.log(
      'onboarding_done',
      parameters: {'journey': 'spotlight'},
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final index = ref.watch(tabProvider);
    return ShowCaseWidget(
      onFinish: _completeSpotlight,
      onDismiss: (_) => _completeSpotlight(),
      disableBarrierInteraction: true,
      builder: (showcaseContext) {
        _showcaseContext = showcaseContext;
        return Scaffold(
          body: IndexedStack(
            index: index,
            children: const [HomeScreen(), WalletScreen(), SettingsScreen()],
          ),
          bottomNavigationBar: Container(
            decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: AppColors.hairline)),
            ),
            child: BottomNavigationBar(
              type: BottomNavigationBarType.fixed,
              currentIndex: index,
              onTap: _selectTab,
              backgroundColor: Colors.white,
              selectedItemColor: AppColors.blue,
              unselectedItemColor: AppColors.muted,
              selectedLabelStyle: sora(12, weight: FontWeight.w600),
              unselectedLabelStyle: sora(12),
              items: [
                BottomNavigationBarItem(
                  icon: Showcase.withWidget(
                    key: _homeSpotlightKey,
                    targetShapeBorder: const CircleBorder(),
                    overlayColor: Colors.black,
                    overlayOpacity: 0.64,
                    disableBarrierInteraction: true,
                    container: _SpotlightCard(
                      body: s.onboardingHomeBody,
                      isLast: false,
                      onNext: () {
                        unawaited(
                          AppAnalytics.log(
                            'onboarding_step_completed',
                            parameters: {'step': 'home'},
                          ),
                        );
                        ShowCaseWidget.of(showcaseContext).next();
                      },
                      onSkip: () =>
                          ShowCaseWidget.of(showcaseContext).dismiss(),
                    ),
                    child: const Icon(Icons.home_rounded),
                  ),
                  label: s.navHome,
                ),
                BottomNavigationBarItem(
                  icon: Showcase.withWidget(
                    key: _walletSpotlightKey,
                    targetShapeBorder: const CircleBorder(),
                    overlayColor: Colors.black,
                    overlayOpacity: 0.64,
                    disableBarrierInteraction: true,
                    container: _SpotlightCard(
                      body: s.onboardingWalletBody,
                      isLast: false,
                      onNext: () {
                        unawaited(
                          AppAnalytics.log(
                            'onboarding_step_completed',
                            parameters: {'step': 'wallet'},
                          ),
                        );
                        ShowCaseWidget.of(showcaseContext).next();
                      },
                      onSkip: () =>
                          ShowCaseWidget.of(showcaseContext).dismiss(),
                    ),
                    child: const Icon(Icons.account_balance_wallet_rounded),
                  ),
                  label: s.navWallet,
                ),
                BottomNavigationBarItem(
                  icon: Showcase.withWidget(
                    key: _settingsSpotlightKey,
                    targetShapeBorder: const CircleBorder(),
                    overlayColor: Colors.black,
                    overlayOpacity: 0.64,
                    disableBarrierInteraction: true,
                    container: _SpotlightCard(
                      body: s.onboardingSettingsBody,
                      isLast: true,
                      onNext: () {
                        unawaited(
                          AppAnalytics.log(
                            'onboarding_step_completed',
                            parameters: {'step': 'settings'},
                          ),
                        );
                        ShowCaseWidget.of(showcaseContext).next();
                      },
                      onSkip: () =>
                          ShowCaseWidget.of(showcaseContext).dismiss(),
                    ),
                    child: const Icon(Icons.settings_rounded),
                  ),
                  label: s.navSettings,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _SpotlightCard extends StatelessWidget {
  const _SpotlightCard({
    required this.body,
    required this.isLast,
    required this.onNext,
    required this.onSkip,
  });

  final String body;
  final bool isLast;
  final VoidCallback onNext;
  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    return Semantics(
      container: true,
      label: body,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 300),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.border),
            boxShadow: const [
              BoxShadow(
                color: Color(0x33000000),
                blurRadius: 18,
                offset: Offset(0, 8),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 10, 10),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(body, style: sora(13, height: 1.45)),
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: onSkip,
                      child: Text(s.onboardingSkip),
                    ),
                    TextButton(
                      onPressed: onNext,
                      child: Text(
                        isLast ? s.onboardingDone : s.onboardingNext,
                        style: sora(
                          13,
                          weight: FontWeight.w700,
                          color: AppColors.blue,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
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
