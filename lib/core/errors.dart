import 'dart:async';
import 'dart:io';

import '../l10n/strings.g.dart';

/// Stable error codes shared with the backend (docs/TECHNICAL_REQUIREMENTS.md §6).
/// The app never shows server-provided text; each code maps to a string resource.
enum ErrorCode {
  invalidRegNo,
  insufficientBalance,
  rechargeRequired,
  recordNotFound,
  providerUnavailable,
  rateLimited,
  paymentFailed,
  network,
  unauthenticated,
  unknown,
}

class AppException implements Exception {
  const AppException(this.code);
  final ErrorCode code;
  @override
  String toString() => 'AppException($code)';
}

String errorMessage(S s, Object error) {
  final code = switch (error) {
    AppException(:final code) => code,
    TimeoutException() || SocketException() => ErrorCode.network,
    _ => ErrorCode.unknown,
  };
  return switch (code) {
    ErrorCode.invalidRegNo => s.errorInvalidRegNo,
    ErrorCode.insufficientBalance => s.errorInsufficientBalance,
    ErrorCode.rechargeRequired => s.errorRechargeRequired,
    ErrorCode.recordNotFound => s.errorRecordNotFound,
    ErrorCode.providerUnavailable => s.errorProviderUnavailable,
    ErrorCode.rateLimited => s.errorRateLimited,
    ErrorCode.paymentFailed => s.errorPaymentFailed,
    ErrorCode.network => s.errorNetwork,
    ErrorCode.unauthenticated => s.errorUnauthenticated,
    ErrorCode.unknown => s.errorUnknown,
  };
}
