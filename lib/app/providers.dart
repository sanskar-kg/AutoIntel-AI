import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/backend.dart';
import '../data/auth_repository.dart';
import '../data/firestore_backend.dart';
import '../data/models.dart';
import '../data/payu_payment_gateway.dart';
import '../data/remote_config_service.dart';

final sharedPrefsProvider = Provider<SharedPreferences>(
  (ref) => throw UnimplementedError('Override sharedPrefsProvider in main()'),
);

final backendProvider = Provider<Backend>(
  (ref) => FirestoreBackend(ref.watch(authRepositoryProvider)),
);
final paymentGatewayProvider = Provider<PaymentGateway>((ref) {
  final backend = ref.watch(backendProvider);
  return PayUPaymentGateway(
    hashProvider: const PayUSandboxHashProvider(),
    settleSandboxOrder: backend.reportGatewayOutcome,
  );
});
final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => ProductionAuthRepository(ref.watch(sharedPrefsProvider)),
);

final accountProvider = FutureProvider<Account?>(
  (ref) => ref.watch(authRepositoryProvider).restore(),
);

final configProvider = FutureProvider<AppConfig>(
  (ref) => ref.watch(backendProvider).getConfig(),
);

final remoteSettingsProvider = FutureProvider<RemoteSettings>(
  (ref) => const RemoteConfigService().load(),
);

// ---- Wallet ----

class WalletState {
  const WalletState({
    required this.balancePaise,
    required this.minRechargeDone,
    required this.showRechargeGate,
    required this.ledger,
    this.pendingOrderId,
  });
  final int balancePaise;
  final bool minRechargeDone;
  final bool showRechargeGate;
  final List<LedgerEntry> ledger;
  final String? pendingOrderId;
}

class PaymentResult {
  const PaymentResult({
    required this.status,
    required this.amountPaise,
    required this.balancePaise,
  });
  final OrderStatus status;
  final int amountPaise;
  final int balancePaise;
}

class WalletController extends AsyncNotifier<WalletState> {
  Backend get _backend => ref.read(backendProvider);
  bool _rechargeGateDeferred = false;

  @override
  Future<WalletState> build() => _fetch(null);

  Future<WalletState> _fetch(String? pendingOrderId) async {
    final results = await Future.wait([
      _backend.getWallet(),
      _backend.getLedger(),
    ]);
    final wallet = results[0] as WalletSnapshot;
    return WalletState(
      balancePaise: wallet.balancePaise,
      minRechargeDone: wallet.minRechargeDone,
      showRechargeGate: wallet.showRechargeGate && !_rechargeGateDeferred,
      ledger: results[1] as List<LedgerEntry>,
      pendingOrderId: pendingOrderId,
    );
  }

  /// Lets the user enter the app and choose to recharge later in this session.
  /// The backend still enforces the minimum recharge when a lookup is attempted.
  void deferRechargeGate() {
    _rechargeGateDeferred = true;
    final current = state.value;
    if (current != null) {
      state = AsyncData(
        WalletState(
          balancePaise: current.balancePaise,
          minRechargeDone: current.minRechargeDone,
          showRechargeGate: false,
          ledger: current.ledger,
          pendingOrderId: current.pendingOrderId,
        ),
      );
    }
  }

  /// Re-reads the wallet without flipping to a loading state (so screens don't flash).
  Future<void> refresh() async {
    try {
      state = AsyncData(await _fetch(state.value?.pendingOrderId));
    } catch (_) {
      // Keep showing the last known wallet; the next action will surface errors.
    }
  }

  /// Creates the order, opens checkout, then confirms with the server.
  /// The wallet is credited only when the server says the order succeeded.
  Future<PaymentResult> recharge(BuildContext context, int amountPaise) async {
    final order = await _backend.createOrder(amountPaise);
    final account = await ref.read(accountProvider.future);
    if (account == null) throw StateError('Sign in before recharging.');
    if (!context.mounted) throw StateError('Screen closed during recharge');
    await ref.read(paymentGatewayProvider).checkout(context, order, account);
    return _confirm(order.id);
  }

  /// Re-checks an order that was still pending (e.g. user returned later).
  Future<PaymentResult?> checkPending() async {
    final id = state.value?.pendingOrderId;
    if (id == null) return null;
    return _confirm(id, attempts: 1);
  }

  Future<PaymentResult> _confirm(String orderId, {int attempts = 3}) async {
    var order = await _backend.getOrder(orderId);
    for (var i = 1; i < attempts && !order.isTerminal; i++) {
      await Future<void>.delayed(const Duration(seconds: 2));
      order = await _backend.getOrder(orderId);
    }
    final pending = order.isTerminal ? null : orderId;
    state = AsyncData(await _fetch(pending));
    return PaymentResult(
      status: order.isTerminal ? order.status : OrderStatus.pending,
      amountPaise: order.amountPaise,
      balancePaise: state.value?.balancePaise ?? 0,
    );
  }
}

final walletProvider = AsyncNotifierProvider<WalletController, WalletState>(
  WalletController.new,
);

// ---- Navigation (bottom tabs) ----

class TabController extends Notifier<int> {
  @override
  int build() => 0;
  void select(int index) => state = index;
}

final tabProvider = NotifierProvider<TabController, int>(TabController.new);

// ---- Language ----

class LanguageController extends Notifier<Locale?> {
  static const _key = 'app.language';

  @override
  Locale? build() {
    final tag = ref.read(sharedPrefsProvider).getString(_key);
    return tag == null ? null : _parse(tag);
  }

  Future<void> set(Locale? locale) async {
    state = locale;
    final prefs = ref.read(sharedPrefsProvider);
    if (locale == null) {
      await prefs.remove(_key);
    } else {
      await prefs.setString(_key, _tag(locale));
    }
  }

  static String _tag(Locale l) => l.countryCode == null
      ? l.languageCode
      : '${l.languageCode}_${l.countryCode}';

  static Locale _parse(String tag) {
    final parts = tag.split('_');
    return Locale(parts[0], parts.length > 1 ? parts[1] : null);
  }
}

final languageProvider = NotifierProvider<LanguageController, Locale?>(
  LanguageController.new,
);
