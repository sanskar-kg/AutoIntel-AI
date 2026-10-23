import 'dart:convert';

import 'package:http/http.dart' as http;

import '../core/errors.dart';
import '../core/reg_no.dart';
import 'backend.dart';
import 'models.dart';

/// Production backend client. Firestore is accessed only by the HTTPS
/// function; the mobile app never receives direct write access to wallet data.
class FirestoreBackend implements Backend {
  static const _requestTimeout = Duration(seconds: 15);

  FirestoreBackend(this._auth);

  static const _baseUrl = String.fromEnvironment(
    'AUTH_API_BASE_URL',
    defaultValue:
        'https://asia-south1-autointel-ai-app.cloudfunctions.net/authApi',
  );
  final AuthRepository _auth;

  Future<Map<String, Object?>> _request(
    String method,
    String path, {
    Map<String, Object?>? body,
  }) async {
    final token = await _auth.sessionToken();
    if (token == null || token.isEmpty) {
      throw const AppException(ErrorCode.unauthenticated);
    }
    final uri = Uri.parse('$_baseUrl$path');
    final response = switch (method) {
      'GET' => await http
          .get(uri, headers: _headers(token))
          .timeout(_requestTimeout),
      'POST' => await http.post(
            uri,
            headers: _headers(token),
            body: jsonEncode(body ?? const {}),
          ).timeout(_requestTimeout),
      _ => throw StateError('Unsupported HTTP method: $method'),
    };
    final payload = response.body.isEmpty
        ? <String, Object?>{}
        : Map<String, Object?>.from(jsonDecode(response.body) as Map);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw _serverError(payload['error']?.toString());
    }
    return payload;
  }

  Map<String, String> _headers(String token) => {
    'Authorization': 'Bearer $token',
    'Content-Type': 'application/json',
  };

  AppException _serverError(String? code) => AppException(
    switch (code) {
      'INSUFFICIENT_BALANCE' => ErrorCode.insufficientBalance,
      'RECHARGE_REQUIRED' => ErrorCode.rechargeRequired,
      'INVALID_REG_NO' => ErrorCode.invalidRegNo,
      'RECORD_NOT_FOUND' => ErrorCode.recordNotFound,
      'PROVIDER_UNAVAILABLE' => ErrorCode.providerUnavailable,
      'PAYMENT_FAILED' => ErrorCode.paymentFailed,
      'UNAUTHENTICATED' => ErrorCode.unauthenticated,
      _ => ErrorCode.unknown,
    },
  );

  @override
  Future<AppConfig> getConfig() async {
    final data = await _request('GET', '/v1/config');
    return AppConfig(
      rcPricePaise: _int(data['rcPricePaise']),
      phonePricePaise: _int(data['phonePricePaise']),
      minRechargePaise: _int(data['minRechargePaise']),
      maxRechargePaise: _int(data['maxRechargePaise']),
      presetsPaise: [
        for (final value in (data['presetsPaise'] as List? ?? const []))
          _int(value),
      ],
    );
  }

  @override
  Future<WalletSnapshot> getWallet() async {
    final data = await _request('GET', '/v1/wallet');
    return WalletSnapshot(
      balancePaise: _int(data['balancePaise']),
      minRechargeDone: data['minRechargeDone'] == true,
      showRechargeGate: data['showRechargeGate'] == true,
    );
  }

  @override
  Future<List<LedgerEntry>> getLedger() async {
    final data = await _request('GET', '/v1/wallet/ledger');
    return [
      for (final value in (data['entries'] as List? ?? const []))
        _ledger(Map<String, Object?>.from(value as Map)),
    ];
  }

  @override
  Future<Lookup> lookup(
    LookupType type,
    String regNo,
    String idempotencyKey,
  ) async {
    final data = await _request(
      'POST',
      '/v1/lookup',
      body: {
        'type': type.name,
        'regNo': normalizeRegNo(regNo),
        'idempotencyKey': idempotencyKey,
      },
    );
    return _lookup(data);
  }

  @override
  Future<PaymentOrder> createOrder(int amountPaise) async {
    final data = await _request(
      'POST',
      '/v1/wallet/orders',
      body: {'amountPaise': amountPaise},
    );
    return _order(data);
  }

  @override
  Future<PaymentOrder> getOrder(String orderId) async {
    final data = await _request('GET', '/v1/wallet/orders/$orderId');
    return _order(data);
  }

  @override
  Future<void> reportGatewayOutcome(String orderId, OrderStatus status) async {
    await _request(
      'POST',
      '/v1/wallet/orders/$orderId/gateway-result',
      body: {'status': status.name},
    );
  }

  static int _int(Object? value) => value is int
      ? value
      : int.parse(value?.toString() ?? '0');

  static LedgerEntry _ledger(Map<String, Object?> data) => LedgerEntry(
    id: data['id']! as String,
    type: LedgerType.values.byName(data['type']! as String),
    category: LedgerCategory.values.byName(data['category']! as String),
    amountPaise: _int(data['amountPaise']),
    balanceAfterPaise: _int(data['balanceAfterPaise']),
    createdAt: DateTime.parse(data['createdAt']! as String),
    regNoMasked: (data['regNoMasked'] as String?) ?? '',
  );

  static Lookup _lookup(Map<String, Object?> data) => Lookup(
    id: data['id']! as String,
    type: LookupType.values.byName(data['type']! as String),
    regNo: data['regNo']! as String,
    regNoMasked: data['regNoMasked']! as String,
    chargedPaise: _int(data['chargedPaise']),
    createdAt: DateTime.parse(data['createdAt']! as String),
    rc: data['rc'] == null
        ? null
        : RcResult.fromJson(Map<String, Object?>.from(data['rc']! as Map)),
    phone: data['phone'] as String?,
    isDemo: data['isDemo'] == true,
  );

  static PaymentOrder _order(Map<String, Object?> data) => PaymentOrder(
    id: data['id']! as String,
    amountPaise: _int(data['amountPaise']),
    status: OrderStatus.values.byName(data['status']! as String),
    gateway: (data['gateway'] as String?) ?? 'PAYU',
  );
}
