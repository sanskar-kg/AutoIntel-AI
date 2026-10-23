# Authentication Implementation Notes

The client and backend seams for the approved authentication plan are now in place.

## Local setup

The app remains runnable without external credentials. In that mode, the Truecaller button falls back to a local temporary account and the anonymous button creates the same temporary-account type. Widget tests override the repository with `FakeAuthRepository`.

For Firebase Anonymous Auth, add the Firebase-generated `android/app/google-services.json` locally. The Gradle Google Services plugin is applied only when that file exists. Enable Anonymous sign-in in Firebase Console, then run:

```powershell
flutter pub get
flutter run
```

The production Firebase Function URL is the app default. Use
`--dart-define=AUTH_API_BASE_URL=...` only when pointing a local or staging
build at a different backend.

Do not commit `google-services.json` or provider credentials. Check the generated `.gitignore` before adding a Firebase project configuration.

## Backend deployment

`functions/index.js` exports `authApi`, which accepts `POST /v1/auth/truecaller`. It exchanges the one-time Truecaller authorization code with Truecaller, fetches the verified profile, upserts `accounts` and `account_identities`, and stores only a SHA-256 session-token key in `auth_sessions`.

From `functions/`, install dependencies and deploy with the Firebase CLI after selecting the project:

```powershell
npm install
firebase deploy --only functions:authApi
```

Configure `TRUECALLER_CLIENT_ID` as a server-side runtime secret/environment variable. The Flutter client sends authorization code, PKCE verifier, state, and granted scopes to the function; it never receives or stores the Truecaller access token.

## Remaining production wiring

- Register the Android package and release/debug SHA fingerprints in Truecaller Developer Console.
- Replace `REPLACE_WITH_TRUECALLER_CLIENT_ID` in a non-committed release resource or build-time resource overlay.
- Add the deployed session token to the real HTTP backend client’s `Authorization` header.
- Make wallet/history documents and API authorization resolve from the account ID in `auth_sessions`.
- Add Firebase App Check, rate limits, budget alerts, and Firestore security rules before launch.
