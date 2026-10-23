import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/errors.dart';
import '../core/reg_no.dart';
import '../core/theme.dart';
import '../l10n/strings.g.dart';
import 'backend.dart';
import 'models.dart';

/// Local stand-in for the real server so every screen and flow can be built and tested
/// before the API, provider and payment gateway exist. It mimics the server rules:
/// minimum-recharge gate, reserve-then-charge (failed lookups are never charged),
/// idempotency keys, and orders confirmed only by "server" state.
///
/// Test hooks for lookups (on the registration number):
///   ends with 0000 → RECORD_NOT_FOUND    ends with 9999 → PROVIDER_UNAVAILABLE
class MockBackend implements Backend {
  MockBackend(this._prefs, {this.latency = const Duration(milliseconds: 700)}) {
    _load();
  }

  static const _key = 'mock.backend.v1';
  final SharedPreferences _prefs;
  final Duration latency;
  final _rand = Random();

  int _balance = 0;
  bool _minRechargeDone = false;
  final List<LedgerEntry> _ledger = [];
  final Map<String, PaymentOrder> _orders = {};
  final Map<String, DateTime> _pendingSince = {};

  static const _config = AppConfig(
    rcPricePaise: 200,
    phonePricePaise: 500,
    minRechargePaise: 2000,
    maxRechargePaise: 1000000,
    presetsPaise: [5000, 10000, 20000, 50000],
  );

  void _load() {
    final raw = _prefs.getString(_key);
    if (raw == null) return;
    try {
      final j = Map<String, Object?>.from(jsonDecode(raw) as Map);
      _balance = j['balance']! as int;
      _minRechargeDone = j['minRechargeDone']! as bool;
      _ledger.addAll(
        (j['ledger']! as List).map(
          (e) => LedgerEntry.fromJson(Map<String, Object?>.from(e as Map)),
        ),
      );
      for (final e in (j['orders']! as List)) {
        final o = PaymentOrder.fromJson(Map<String, Object?>.from(e as Map));
        _orders[o.id] = o;
      }
    } catch (_) {
      // Corrupt mock state: start fresh.
      _balance = 0;
      _minRechargeDone = false;
      _ledger.clear();
      _orders.clear();
    }
  }

  Future<void> _save() => _prefs.setString(
    _key,
    jsonEncode({
      'balance': _balance,
      'minRechargeDone': _minRechargeDone,
      'ledger': _ledger.map((e) => e.toJson()).toList(),
      'orders': _orders.values.map((e) => e.toJson()).toList(),
    }),
  );

  Future<void> _delay() => Future<void>.delayed(latency);

  String _id(String prefix) =>
      '$prefix${DateTime.now().microsecondsSinceEpoch}${_rand.nextInt(9999)}';

  @override
  Future<AppConfig> getConfig() async => _config;

  @override
  Future<WalletSnapshot> getWallet() async {
    await _delay();
    return WalletSnapshot(
      balancePaise: _balance,
      minRechargeDone: _minRechargeDone,
      showRechargeGate: !_minRechargeDone,
    );
  }

  @override
  Future<List<LedgerEntry>> getLedger() async {
    await _delay();
    return List.unmodifiable(_ledger.reversed);
  }

  @override
  Future<Lookup> lookup(
    LookupType type,
    String regNo,
    String idempotencyKey,
  ) async {
    await _delay();
    final reg = normalizeRegNo(regNo);
    if (!isValidRegNo(reg)) throw const AppException(ErrorCode.invalidRegNo);
    if (!_minRechargeDone) {
      throw const AppException(ErrorCode.rechargeRequired);
    }
    final price = _config.priceFor(type);
    if (_balance < price) {
      throw const AppException(ErrorCode.insufficientBalance);
    }

    // Reserve, then call the (mock) provider; restore on failure so it is never charged.
    _balance -= price;
    try {
      await Future<void>.delayed(latency);
      if (reg.endsWith('0000')) {
        throw const AppException(ErrorCode.recordNotFound);
      }
      if (reg.endsWith('9999')) {
        throw const AppException(ErrorCode.providerUnavailable);
      }
    } catch (_) {
      _balance += price;
      rethrow;
    }

    final now = DateTime.now();
    final lookup = Lookup(
      id: _id('lk'),
      type: type,
      regNo: reg,
      regNoMasked: maskRegNo(reg),
      chargedPaise: price,
      createdAt: now,
      rc: type == LookupType.rc ? _fakeRc(reg) : null,
      phone: type == LookupType.phone ? _fakePhone(reg) : null,
      isDemo: true,
    );
    _ledger.add(
      LedgerEntry(
        id: _id('le'),
        type: LedgerType.debit,
        category: type == LookupType.rc
            ? LedgerCategory.rcLookup
            : LedgerCategory.phoneLookup,
        amountPaise: price,
        balanceAfterPaise: _balance,
        createdAt: now,
        regNoMasked: lookup.regNoMasked,
      ),
    );
    await _save();
    return lookup;
  }

  @override
  Future<PaymentOrder> createOrder(int amountPaise) async {
    await _delay();
    if (amountPaise < _config.minRechargePaise ||
        amountPaise > _config.maxRechargePaise) {
      throw const AppException(ErrorCode.paymentFailed);
    }
    final order = PaymentOrder(
      id: _id('ord'),
      amountPaise: amountPaise,
      status: OrderStatus.created,
    );
    _orders[order.id] = order;
    await _save();
    return order;
  }

  @override
  Future<PaymentOrder> getOrder(String orderId) async {
    await _delay();
    var order = _orders[orderId];
    if (order == null) throw const AppException(ErrorCode.unknown);
    // A pending payment resolves on its own after a while, like a late bank confirmation.
    if (order.status == OrderStatus.pending) {
      final since = _pendingSince[orderId] ?? DateTime.now();
      _pendingSince[orderId] = since;
      if (DateTime.now().difference(since) > const Duration(seconds: 8)) {
        await settleOrder(orderId, OrderStatus.success);
        order = _orders[orderId]!;
      }
    }
    return order;
  }

  @override
  Future<void> reportGatewayOutcome(String orderId, OrderStatus status) =>
      settleOrder(orderId, status);

  /// Simulates the gateway webhook. Crediting is idempotent per order.
  Future<void> settleOrder(String orderId, OrderStatus status) async {
    final order = _orders[orderId];
    if (order == null || order.status == OrderStatus.success) return;
    _orders[orderId] = order.copyWith(status: status);
    if (status == OrderStatus.pending) {
      _pendingSince[orderId] = DateTime.now();
    }
    if (status == OrderStatus.success) {
      _balance += order.amountPaise;
      _minRechargeDone = true;
      _ledger.add(
        LedgerEntry(
          id: _id('le'),
          type: LedgerType.credit,
          category: LedgerCategory.topup,
          amountPaise: order.amountPaise,
          balanceAfterPaise: _balance,
          createdAt: DateTime.now(),
        ),
      );
    }
    await _save();
  }

  // ---- fake provider data (clearly flagged as demo in the UI) ----

  static const _owners = [
    'Rohan Mehta',
    'Anita Deshmukh',
    'Imran Shaikh',
    'Priya Nair',
    'Karthik Reddy',
    'Sunita Verma',
  ];
  static const _vehicles = [
    ['Maruti Suzuki', 'Swift VXi'],
    ['Hyundai', 'Creta SX'],
    ['Tata', 'Nexon XZ+'],
    ['Honda', 'Activa 6G'],
    ['Mahindra', 'Scorpio S11'],
    ['Bajaj', 'Pulsar 150'],
  ];
  static const _fuels = ['Petrol', 'Diesel', 'CNG', 'Petrol'];

  int _seed(String reg) =>
      reg.codeUnits.fold(7, (a, c) => (a * 31 + c) & 0x7fffffff);

  RcResult _fakeRc(String reg) {
    final seed = _seed(reg);
    final v = _vehicles[seed % _vehicles.length];
    return RcResult(
      ownerName: _owners[seed % _owners.length],
      maker: v[0],
      model: v[1],
      extra: {
        'fuelType': _fuels[seed % _fuels.length],
        'vehicleClass': seed % 6 == 3 ? 'Motor Cycle' : 'Motor Car',
        'registrationDate': '${2015 + seed % 9}-0${1 + seed % 9}-1${seed % 9}',
        'rto': reg.substring(0, 4),
      },
    );
  }

  String _fakePhone(String reg) {
    final seed = _seed(reg);
    final digits = (seed * 7919).toString().padLeft(9, '0');
    return '9${digits.substring(digits.length - 9)}';
  }
}

/// Debug-only stand-in for the PayU / PhonePe checkout: lets you pick the outcome.
class MockPaymentGateway implements PaymentGateway {
  MockPaymentGateway(this._backend);
  final MockBackend _backend;

  @override
  Future<void> checkout(
    BuildContext context,
    PaymentOrder order,
    Account account,
  ) async {
    final s = S.of(context);
    final outcome = await showDialog<OrderStatus>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Text(s.mockpayTitle, style: sora(16, weight: FontWeight.w700)),
        content: Text(s.mockpayBody, style: sora(13, color: AppColors.muted)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, OrderStatus.failed),
            child: Text(s.mockpayFailed),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, OrderStatus.pending),
            child: Text(s.mockpayPending),
          ),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(0, 40)),
            onPressed: () => Navigator.pop(ctx, OrderStatus.success),
            child: Text(s.mockpaySuccess),
          ),
        ],
      ),
    );
    await _backend.settleOrder(order.id, outcome ?? OrderStatus.failed);
  }
}
