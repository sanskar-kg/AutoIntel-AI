import 'package:flutter/widgets.dart';

import 'models.dart';

/// Everything the app needs from the server. The production implementation is
/// [FirestoreBackend], which talks to the authenticated Firebase function.
/// an HTTP client against the real API (docs/TECHNICAL_REQUIREMENTS.md §5) later.
/// The app never talks to the third-party vehicle API or the payment gateway's servers directly.
abstract class Backend {
  Future<AppConfig> getConfig();
  Future<WalletSnapshot> getWallet();
  Future<List<LedgerEntry>> getLedger();

  /// Charges the wallet only if the provider call succeeds (server-side reserve/refund).
  Future<Lookup> lookup(LookupType type, String regNo, String idempotencyKey);
  Future<PaymentOrder> createOrder(int amountPaise);

  /// Server truth for an order (the server asks the gateway); never trust the client callback.
  Future<PaymentOrder> getOrder(String orderId);

  /// Reports checkout completion to the server. A successful client callback
  /// is never sufficient to credit funds; the server waits for gateway proof.
  Future<void> reportGatewayOutcome(String orderId, OrderStatus status);
}

/// Opens the gateway's checkout UI (PayU / PhonePe SDK). Completion of the UI says nothing
/// about success: the caller must confirm through [Backend.getOrder].
abstract class PaymentGateway {
  Future<void> checkout(
    BuildContext context,
    PaymentOrder order,
    Account account,
  );
}

/// Current account. Implementations may use Truecaller or temporary anonymous auth;
/// the rest of the app only sees this interface.
abstract class AuthRepository {
  Future<Account?> restore();
  Future<Account> signIn();
  Future<Account> signInAnonymously();
  Future<String?> sessionToken();
  Future<void> signOut();
}

class FakeAuthRepository implements AuthRepository {
  @override
  Future<Account?> restore() async =>
      const Account(id: 'demo', name: 'Demo User');

  @override
  Future<Account> signIn() async =>
      const Account(id: 'demo', name: 'Demo User');

  @override
  Future<Account> signInAnonymously() async => const Account(
    id: 'demo-anonymous',
    name: 'Temporary account',
    provider: 'anonymous',
    isTemporary: true,
  );

  @override
  Future<String?> sessionToken() async => 'demo-session';

  @override
  Future<void> signOut() async {}
}
