# History and wallet state

## Lookup history

The lookup History tab and saved-result reopening flow have been removed.
Lookup results are shown only for the active request and are not persisted by
the current `MockBackend`. Wallet transaction history is separate and remains
available in the Wallet tab.

## Low or empty balance

The lookup screen now shows an explicit message when the wallet is empty or
below the lookup price. A first-time account sees the first-recharge message;
an already-recharged account with insufficient remaining funds sees the
low-balance message. The lookup is not submitted and the user is directed to
Wallet to recharge.

The mock backend also enforces the same rule in `MockBackend.lookup`: it throws
`ErrorCode.rechargeRequired` before the first recharge and
`ErrorCode.insufficientBalance` when the balance is below the price. A
successful provider response debits the balance; provider failures restore the
reserved amount.

## Firestore wallet mapping audit

There is currently **no Firestore wallet mapping** in this checkout. A live
Firestore collection audit found only `accounts`, `account_identities`, and
`auth_sessions`; there are no `wallets`, `ledger`, or wallet transaction
collections. The app's
wallet balance, ledger, orders, and lookup history are all held by
`MockBackend` in local `SharedPreferences`. The deployed `authApi` function
currently writes only `accounts`, `account_identities`, and `auth_sessions`.

`firestore.rules` currently denies all client reads and writes, which is the
correct posture for a server-authoritative wallet. Before production, add a
server-only wallet model keyed by `accountId`, for example:

```text
accounts/{accountId}
wallets/{accountId}                 # balancePaise, version, updatedAt
wallets/{accountId}/ledger/{entryId} # immutable credit/debit entry
```

Balance changes must happen in a trusted backend transaction or callable
function, with an idempotency key and a ledger entry. The client must never be
allowed to directly increase, decrease, or transfer a balance.

The app now uses `FirestoreBackend` and the deployed `authApi` routes for
wallet reads, ledger reads, order creation/status, and server-side lookup
debits. The local mock backend is no longer selected by the app providers.
The first-time recharge screen is controlled by the account-scoped
`walletOnboardingCompleted` flag and is consumed atomically on the first
wallet load, so signing out and signing back in does not show it again.

Production launch still requires real PayU merchant credentials, a server-side
PayU hash implementation, and a verified PayU webhook before successful
payments can credit a wallet. The checked-in `payu_sandbox.json` credentials
must not be used for a production release.

## Crashlytics status

Crashlytics is wired into the Android build and Flutter error handlers. The
Firebase Android app is registered as `com.autointel.ai`, and
`android/app/google-services.json` is present. Crashlytics currently reports no
issues/events for the queried period, so there is no production crash history
to triage yet. Release builds enable the handlers; debug builds intentionally
do not upload crash reports.
