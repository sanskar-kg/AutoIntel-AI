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

Firebase requires the project to use the Blaze pay-as-you-go plan before Cloud Functions can be deployed.
