# PayU Checkout Pro

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

## Production setup status

The production Checkout Pro path, backend hash endpoint, PayU webhook, Verify
Payment reconciliation, and idempotent wallet crediting are implemented.
Follow [functions/README.md](../functions/README.md) to set the Firebase
secrets, deploy `authApi`, and configure the PayU webhook before accepting live
payments.

The release build requires the public merchant key in the ignored
`payu_production.json` file. Never pass the production salt through
`--dart-define` or store it in the app.

PayU notes that UPI in-app and intent flows are unavailable in test mode. Use
the test card or net-banking credentials documented by PayU when validating the
sandbox checkout.
