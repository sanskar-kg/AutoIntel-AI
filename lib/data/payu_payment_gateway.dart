import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:payu_checkoutpro_flutter/PayUConstantKeys.dart';
import 'package:payu_checkoutpro_flutter/payu_checkoutpro_flutter.dart';

import 'backend.dart';
import 'models.dart';

typedef SandboxOrderSettler =
    Future<void> Function(String orderId, OrderStatus status);

/// PayU Checkout Pro configured for PayU's test environment.
///
/// The bundled credentials are PayU's public sample credentials and are only
/// accepted in debug builds. A production integration must replace
/// [PayUSandboxHashProvider] with a provider backed by the merchant server and
/// credit the wallet only after server-side verification/webhook processing.
class PayUPaymentGateway implements PaymentGateway, PayUCheckoutProProtocol {
  PayUPaymentGateway({
    required PayUHashProvider hashProvider,
    required SandboxOrderSettler settleSandboxOrder,
  }) : this._(
         hashProvider,
         settleSandboxOrder,
         PayUCheckoutProFlutter(_PendingProtocol()),
       );

  PayUPaymentGateway._(
    this._hashProvider,
    this._settleSandboxOrder,
    this._checkoutPro,
  ) {
    _checkoutPro.delegate = this;
  }

  static const _merchantKey = String.fromEnvironment(
    'PAYU_TEST_MERCHANT_KEY',
  );
  static const _successUrl = 'https://cbjs.payu.in/sdk/success';
  static const _failureUrl = 'https://cbjs.payu.in/sdk/failure';

  final PayUHashProvider _hashProvider;
  final SandboxOrderSettler _settleSandboxOrder;
  final PayUCheckoutProFlutter _checkoutPro;

  Completer<void>? _completion;
  PaymentOrder? _activeOrder;
  bool _finishing = false;

  @override
  Future<void> checkout(
    BuildContext context,
    PaymentOrder order,
    Account account,
  ) async {
    if (!kDebugMode) {
      throw StateError(
        'The PayU sandbox gateway is disabled outside debug builds. Configure '
        'server-side PayU hashing and verification before a release build.',
      );
    }
    if (_completion != null) {
      throw StateError('A PayU checkout is already in progress.');
    }

    final completion = Completer<void>();
    _completion = completion;
    _activeOrder = order;
    _finishing = false;

    try {
      // payu_checkoutpro_flutter 1.4.5 never completes the Android
      // openCheckoutScreen MethodChannel result. Checkout completion arrives
      // through the delegate callbacks instead, so awaiting this Future would
      // leave the recharge button loading forever after PayU closes.
      unawaited(_checkoutPro.openCheckoutScreen(
        payUPaymentParams: _paymentParams(order, account),
        payUCheckoutProConfig: _checkoutConfig(order),
      ));
      await completion.future.timeout(
        const Duration(minutes: 10),
        onTimeout: () => _finish(OrderStatus.pending),
      );
    } finally {
      _completion = null;
      _activeOrder = null;
      _finishing = false;
    }
  }

  Map<String, Object?> _paymentParams(PaymentOrder order, Account account) {
    final firstName = account.firstName.isEmpty
        ? 'AutoIntel'
        : account.firstName;
    final email = account.email.trim().isEmpty
        ? 'sandbox@autointel.ai'
        : account.email.trim();
    final phoneDigits = account.phone.replaceAll(RegExp(r'\D'), '');
    final phone = phoneDigits.length >= 10
        ? phoneDigits.substring(phoneDigits.length - 10)
        : '9999999999';
    final userId = _safeUserId(account.id, phone);

    return <String, Object?>{
      PayUPaymentParamKey.key: _merchantKey,
      PayUPaymentParamKey.amount: (order.amountPaise / 100).toStringAsFixed(2),
      PayUPaymentParamKey.productInfo: 'AutoIntel wallet recharge',
      PayUPaymentParamKey.firstName: firstName,
      PayUPaymentParamKey.email: email,
      PayUPaymentParamKey.phone: phone,
      PayUPaymentParamKey.android_surl: _successUrl,
      PayUPaymentParamKey.android_furl: _failureUrl,
      PayUPaymentParamKey.ios_surl: _successUrl,
      PayUPaymentParamKey.ios_furl: _failureUrl,
      PayUPaymentParamKey.environment: '1',
      PayUPaymentParamKey.userCredential: '$_merchantKey:$userId',
      PayUPaymentParamKey.transactionId: _transactionId(order.id),
      PayUPaymentParamKey.enableNativeOTP: true,
      PayUPaymentParamKey.additionalParam: <String, String>{
        PayUAdditionalParamKeys.udf1: order.id,
        PayUAdditionalParamKeys.udf2: userId,
      },
    };
  }

  Map<String, Object?> _checkoutConfig(PaymentOrder order) => <String, Object?>{
    PayUCheckoutProConfigKeys.primaryColor: '#0068EF',
    PayUCheckoutProConfigKeys.secondaryColor: '#FFFFFF',
    PayUCheckoutProConfigKeys.merchantName: 'AutoIntel',
    PayUCheckoutProConfigKeys.showMerchantLogo: false,
    PayUCheckoutProConfigKeys.showExitConfirmationOnCheckoutScreen: true,
    PayUCheckoutProConfigKeys.showExitConfirmationOnPaymentScreen: true,
    PayUCheckoutProConfigKeys.autoSelectOtp: true,
    PayUCheckoutProConfigKeys.autoApprove: true,
    PayUCheckoutProConfigKeys.merchantSMSPermission: false,
    PayUCheckoutProConfigKeys.showCbToolbar: true,
    PayUCheckoutProConfigKeys.enableSslDialog: true,
    PayUCheckoutProConfigKeys.merchantResponseTimeout: 30000,
    PayUCheckoutProConfigKeys.waitingTime: 30000,
    PayUCheckoutProConfigKeys.cartDetails: <Map<String, String>>[
      <String, String>{
        'Wallet recharge':
            'INR ${(order.amountPaise / 100).toStringAsFixed(2)}',
      },
    ],
  };

  static String _safeUserId(String accountId, String fallback) {
    final value = accountId.replaceAll(RegExp('[^A-Za-z0-9]'), '');
    if (value.isEmpty) return fallback;
    return value.length <= 40 ? value : value.substring(0, 40);
  }

  static String _transactionId(String orderId) {
    final value = orderId.replaceAll(RegExp('[^A-Za-z0-9]'), '');
    if (value.isEmpty) {
      return DateTime.now().millisecondsSinceEpoch.toString();
    }
    return value.length <= 25 ? value : value.substring(value.length - 25);
  }

  @override
  void generateHash(Map response) {
    unawaited(_generateHash(response));
  }

  Future<void> _generateHash(Map response) async {
    try {
      final hash = await _hashProvider.generate(response);
      await _checkoutPro.hashGenerated(hash: hash);
    } catch (_) {
      await _finish(OrderStatus.failed);
    }
  }

  @override
  void onPaymentSuccess(dynamic response) {
    // This callback is sufficient only for the local sandbox backend. A real
    // backend must verify the transaction/webhook before crediting the wallet.
    unawaited(_finish(OrderStatus.success));
  }

  @override
  void onPaymentFailure(dynamic response) {
    unawaited(_finish(OrderStatus.failed));
  }

  @override
  void onPaymentCancel(Map? response) {
    unawaited(_finish(OrderStatus.failed));
  }

  @override
  void onError(Map? response) {
    unawaited(_finish(OrderStatus.failed));
  }

  Future<void> _finish(OrderStatus status) async {
    final completion = _completion;
    final order = _activeOrder;
    if (completion == null || order == null || _finishing) return;
    _finishing = true;
    try {
      await _settleSandboxOrder(order.id, status);
      if (!completion.isCompleted) completion.complete();
    } catch (error, stackTrace) {
      if (!completion.isCompleted) {
        completion.completeError(error, stackTrace);
      }
    }
  }
}

abstract interface class PayUHashProvider {
  Future<Map<String, String>> generate(Map response);
}

/// Local hashing for PayU's public sample sandbox merchant only.
///
/// Never replace these values with a real merchant salt. Production hashes
/// belong on the merchant server, as required by PayU's integration guide.
class PayUSandboxHashProvider implements PayUHashProvider {
  const PayUSandboxHashProvider();

  static const _merchantSalt = String.fromEnvironment(
    'PAYU_TEST_MERCHANT_SALT',
  );
  static const _merchantSecretKey = String.fromEnvironment(
    'PAYU_TEST_MERCHANT_SECRET',
  );

  @override
  Future<Map<String, String>> generate(Map response) async {
    if (!kDebugMode) {
      throw StateError('Local PayU hashing is allowed only in debug builds.');
    }

    final hashName = response[PayUHashConstantsKeys.hashName]?.toString();
    final hashString = response[PayUHashConstantsKeys.hashString]?.toString();
    final hashType = response[PayUHashConstantsKeys.hashType]?.toString();
    final postSalt = response[PayUHashConstantsKeys.postSalt]?.toString();
    if (hashName == null || hashName.isEmpty || hashString == null) {
      throw const FormatException(
        'PayU hash callback is missing required data.',
      );
    }

    late final String hash;
    if (hashType == PayUHashConstantsKeys.hashVersionV2) {
      hash = base64Encode(
        Hmac(
          sha256,
          utf8.encode(_merchantSalt),
        ).convert(utf8.encode(hashString)).bytes,
      );
    } else if (hashName == PayUHashConstantsKeys.mcpLookup) {
      if (_merchantSecretKey.isEmpty) {
        throw StateError('PAYU_TEST_MERCHANT_SECRET is required for MCP.');
      }
      hash = Hmac(
        sha1,
        utf8.encode(_merchantSecretKey),
      ).convert(utf8.encode(hashString)).toString();
    } else {
      hash = sha512
          .convert(utf8.encode('$hashString$_merchantSalt${postSalt ?? ''}'))
          .toString();
    }
    return <String, String>{hashName: hash};
  }
}

/// Temporary delegate used only while constructing [PayUCheckoutProFlutter].
class _PendingProtocol implements PayUCheckoutProProtocol {
  @override
  void generateHash(Map response) {}

  @override
  void onError(Map? response) {}

  @override
  void onPaymentCancel(Map? response) {}

  @override
  void onPaymentFailure(dynamic response) {}

  @override
  void onPaymentSuccess(dynamic response) {}
}
