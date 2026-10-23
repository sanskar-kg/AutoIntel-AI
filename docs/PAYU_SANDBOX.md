# PayU Checkout Pro sandbox

The debug Android build uses PayU Checkout Pro in test mode for wallet
recharges. It uses the public sample merchant key and salt from PayU's Flutter
sample project, so no real money is charged.

## Test build

```powershell
flutter run -d <device-id> --dart-define-from-file=payu_sandbox.json
```

Optional overrides for a merchant's own PayU test account:

```powershell
flutter run -d <device-id> `
  --dart-define=PAYU_TEST_MERCHANT_KEY=<test-key> `
  --dart-define=PAYU_TEST_MERCHANT_SALT=<test-salt>
```

The test salt is used locally only in debug builds. Never pass a production
salt through `--dart-define` or store it in the app.

## Before production

1. Add a backend endpoint that accepts PayU's `hashName`, `hashString`,
   `hashType`, and optional `postSalt`, then generates the required hash using
   the merchant salt stored in a server secret manager.
2. Replace `PayUSandboxHashProvider` with a backend-backed hash provider.
3. Create wallet orders on the backend and credit the wallet only after a
   verified PayU webhook or Verify Payment API response. Never trust the SDK's
   client success callback as proof of payment.
4. Use production merchant credentials and PayU's production environment.
5. Configure merchant-owned HTTPS success/failure URLs and remove all PayU
   test-only Android metadata (already isolated to `src/debug`).

PayU notes that UPI in-app and intent flows are unavailable in test mode. Use
the test card or net-banking credentials documented by PayU when validating the
sandbox checkout.
