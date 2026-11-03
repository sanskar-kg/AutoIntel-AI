import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:payu_checkoutpro_flutter/PayUConstantKeys.dart';
import 'package:payu_checkoutpro_flutter/payu_checkoutpro_flutter.dart';

import 'backend.dart';
import '../core/analytics.dart';
import 'models.dart';

/// PayU Checkout Pro production gateway.
///
/// The merchant salt and all payment confirmation logic stay on the server.
/// The app only receives dynamic hashes from Firebase and polls the server for
/// the final order status after Checkout Pro returns.
class PayUPaymentGateway implements PaymentGateway, PayUCheckoutProProtocol {
  PayUPaymentGateway({required PayUHashProvider hashProvider})
    : this._(hashProvider, PayUCheckoutProFlutter(_PendingProtocol()));

  PayUPaymentGateway._(this._hashProvider, this._checkoutPro) {
    _checkoutPro.delegate = this;
  }

  static const _merchantKey = String.fromEnvironment('PAYU_MERCHANT_KEY');
  static const _successUrl = 'https://cbjs.payu.in/sdk/success';
  static const _failureUrl = 'https://cbjs.payu.in/sdk/failure';

  final PayUHashProvider _hashProvider;
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
    if (_merchantKey.isEmpty) {
      throw StateError('PAYU_MERCHANT_KEY is required for PayU checkout.');
    }
    if (_completion != null) {
      throw StateError('A PayU checkout is already in progress.');
    }

    final completion = Completer<void>();
    _completion = completion;
    _activeOrder = order;
    _finishing = false;

    try {
      await AppAnalytics.log(
        'payment_checkout_opened',
        parameters: {
          'gateway': order.gateway.toLowerCase(),
          'amount_bucket': AppAnalytics.amountBucket(order.amountPaise),
        },
      );
      // payu_checkoutpro_flutter 1.4.5 never completes the Android
      // openCheckoutScreen MethodChannel result. Checkout completion arrives
      // through the delegate callbacks instead, so awaiting this Future would
      // leave the recharge button loading forever after PayU closes.
      unawaited(
        _checkoutPro.openCheckoutScreen(
          payUPaymentParams: _paymentParams(order, account),
          payUCheckoutProConfig: _checkoutConfig(order),
        ),
      );
      await completion.future.timeout(
        const Duration(minutes: 10),
        onTimeout: _finish,
      );
    } finally {
      _completion = null;
      _activeOrder = null;
      _finishing = false;
    }
  }

  Map<String, Object?> _paymentParams(PaymentOrder order, Account account) {
    final firstName = account.firstName.isEmpty
        ? 'MotorInfo'
        : account.firstName;
    final email = account.email.trim().isEmpty
        ? 'support@autointel.ai'
        : account.email.trim();
    final phoneDigits = account.phone.replaceAll(RegExp(r'\D'), '');
    final phone = phoneDigits.length >= 10
        ? phoneDigits.substring(phoneDigits.length - 10)
        : '9999999999';
    final userId = _safeUserId(account.id, phone);

    return <String, Object?>{
      PayUPaymentParamKey.key: _merchantKey,
      PayUPaymentParamKey.amount: (order.amountPaise / 100).toStringAsFixed(2),
      PayUPaymentParamKey.productInfo: 'MotorInfo wallet recharge',
      PayUPaymentParamKey.firstName: firstName,
      PayUPaymentParamKey.email: email,
      PayUPaymentParamKey.phone: phone,
      PayUPaymentParamKey.android_surl: _successUrl,
      PayUPaymentParamKey.android_furl: _failureUrl,
      PayUPaymentParamKey.ios_surl: _successUrl,
      PayUPaymentParamKey.ios_furl: _failureUrl,
      PayUPaymentParamKey.environment: '0',
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
    PayUCheckoutProConfigKeys.merchantName: 'MotorInfo',
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
      await _finish();
    }
  }

  @override
  void onPaymentSuccess(dynamic response) {
    unawaited(
      AppAnalytics.log(
        'payment_gateway_callback',
        parameters: {'status': 'success'},
      ),
    );
    // The callback is not trusted. The webhook and Verify Payment API update
    // the order; the caller polls the server after this completes.
    unawaited(_finish());
  }

  @override
  void onPaymentFailure(dynamic response) {
    unawaited(
      AppAnalytics.log(
        'payment_gateway_callback',
        parameters: {'status': 'failure'},
      ),
    );
    unawaited(_finish());
  }

  @override
  void onPaymentCancel(Map? response) {
    unawaited(
      AppAnalytics.log(
        'payment_gateway_callback',
        parameters: {'status': 'cancelled'},
      ),
    );
    unawaited(_finish());
  }

  @override
  void onError(Map? response) {
    unawaited(
      AppAnalytics.log(
        'payment_gateway_callback',
        parameters: {'status': 'error'},
      ),
    );
    unawaited(_finish());
  }

  Future<void> _finish() async {
    final completion = _completion;
    final order = _activeOrder;
    if (completion == null || order == null || _finishing) return;
    _finishing = true;
    if (!completion.isCompleted) completion.complete();
  }
}

abstract interface class PayUHashProvider {
  Future<Map<String, String>> generate(Map response);
}

/// Requests the dynamic Checkout Pro hash from Firebase. The salt never enters
/// the Flutter process.
class PayUServerHashProvider implements PayUHashProvider {
  const PayUServerHashProvider(this._backend);
  final Backend _backend;

  @override
  Future<Map<String, String>> generate(Map response) =>
      _backend.generatePayUHash(Map<String, Object?>.from(response));
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
