# Authentication Function

`authApi` implements `POST /v1/auth/truecaller`. It exchanges the one-time Truecaller authorization code for a profile, upserts the Firestore account/identity mapping, and returns an opaque session token. Truecaller access tokens are never returned to the app or stored in Firestore.

Set these server-side environment variables before deployment:

```text
TRUECALLER_CLIENT_ID=...
TRUECALLER_TOKEN_URL=https://oauth-account-noneu.truecaller.com/v1/token
TRUECALLER_USERINFO_URL=https://oauth-account-noneu.truecaller.com/v1/userinfo
```

The Flutter app must be built with `--dart-define=AUTH_API_BASE_URL=...`, where the value is the deployed `authApi` base URL. The Truecaller Client ID is a public app identifier required in `strings.xml`; do not put provider access tokens or private secrets in Dart, `strings.xml`, or `google-services.json`.

For this Android OAuth setup, `tool/sync_truecaller_client_id.ps1` copies the app's Truecaller Client ID into the ignored `functions/.env.autointel-ai-app` file before deployment. Run it from the repository root, then deploy with `firebase deploy --only functions`. The current function URL is `https://asia-south1-autointel-ai-app.cloudfunctions.net/authApi`; pass that URL as `AUTH_API_BASE_URL` when building or running the app.

## PayU production

Set the PayU secrets in Firebase Secret Manager before deploying:

```powershell
firebase functions:secrets:set PAYU_MERCHANT_KEY
firebase functions:secrets:set PAYU_MERCHANT_SALT
firebase deploy --only functions:authApi
```

The production webhook endpoint is:

```text
https://asia-south1-autointel-ai-app.cloudfunctions.net/authApi/v1/webhooks/payu
```

Configure that URL in PayU Dashboard → Developers → Webhooks for payment
success and failure events. The Flutter release build needs the public merchant
key through an ignored `payu_production.json` file; never put the PayU salt in
that file or in Flutter code. Example:

```json
{
  "PAYU_MERCHANT_KEY": "your-live-merchant-key",
  "AUTH_API_BASE_URL": "https://asia-south1-autointel-ai-app.cloudfunctions.net/authApi"
}
```

Build with:

```powershell
flutter build appbundle --release --dart-define-from-file=payu_production.json
```

Firebase requires the project to use the Blaze pay-as-you-go plan before Cloud Functions can be deployed.

## Vehicle provider keys

The upstream vehicle provider is called only from `authApi`; the Flutter APK
never receives either provider key. Store the two keys in Firebase Secret
Manager and deploy the function with those secrets attached:

```powershell
firebase functions:secrets:set CSTUDIO_RCPLUS_KEY
firebase functions:secrets:set CSTUDIO_RC2NUM_KEY
firebase deploy --only functions:authApi
```

`CSTUDIO_RCPLUS_KEY` is used for the vehicle-details lookup and
`CSTUDIO_RC2NUM_KEY` is used for the registered-phone lookup. Do not put these
values in Dart, `--dart-define`, Android resources, `google-services.json`,
Git, or a client-side URL. The two credentials supplied during development
should be rotated before production because they have been shared in chat.

The function calls `https://apiv2.cstudio.sbs/` with the provider's `rcplus`
or `rc2num` type and returns `PROVIDER_UNAVAILABLE` for timeout, non-JSON,
non-2xx, or malformed responses. A provider failure is not charged to the
wallet. Confirm the provider's permitted use, rate limits, retention terms,
and whether the `rc2num` response is lawful for the intended users before
enabling that product path.
