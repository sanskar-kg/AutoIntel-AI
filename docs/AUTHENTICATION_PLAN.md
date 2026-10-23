# Authentication Integration Plan

## Goal

Replace `FakeAuthRepository` with Truecaller OAuth SDK 3.1.0 as the primary Android sign-in method. After user consent, the system will obtain the Truecaller subject/mobile/name profile, create or locate the corresponding AutoIntel account, and issue an app session used by the wallet and lookup APIs.

## Primary Flow: Truecaller OAuth

1. The Flutter app invokes a small Android platform bridge. The native layer initializes `TcSdk` once, checks `isOAuthFlowUsable`, and starts `getAuthorizationCode(activity)`.
2. The callback validates the returned `state` against the request state and forwards the one-time authorization code, verifier, and state to the backend. The app must not exchange the code or retain Truecaller access tokens.
3. A Firebase Cloud Function exchanges the code at Truecaller’s `/v1/token` endpoint using the server-held client ID, then calls `/v1/userinfo` with the access token.
4. The backend validates the response (`sub`, verified phone, and granted `openid` scope), normalizes the E.164 phone number, and upserts the account.
5. The backend returns an opaque AutoIntel session token and a minimal profile to the app. Existing wallet, ledger, and lookup data remain keyed by the AutoIntel account ID.

Truecaller documents the authorization callback, state checking, usability check, token exchange, and profile endpoint in its [OAuth SDK 3.1.0 documentation](https://docs.truecaller.com/truecaller-sdk/android/oauth-sdk-3.1.0) and [backend integration guide](https://docs.truecaller.com/truecaller-sdk/android/oauth-sdk-3.1.0/integration-steps/integrating-with-your-backend).

## Firestore Account Mapping

Proposed documents:

- `accounts/{accountId}`: display name, normalized phone, Truecaller subject, provider, consent/terms version, created/last-login timestamps, and status.
- `account_identities/{provider}:{subject}`: unique provider-to-account mapping.
- `auth_sessions/{sha256(token)}`: hashed opaque token, account ID, expiry, created/revoked timestamps.

Never use the phone number or display name as the primary key. Enforce uniqueness in a transaction and handle the same phone or Truecaller subject arriving again. Store only the profile fields required by the product; do not persist access tokens.

## Fallback: Firebase Anonymous Auth

If Truecaller is unavailable, cancelled, unsupported, or temporarily fails, create/sign in a Firebase anonymous user and use its Firebase UID as a temporary AutoIntel account identity. This keeps the app usable while showing a clear “temporary account” state. Anonymous Auth does not prove ownership of a phone number and cannot reliably supply the user’s Truecaller name or mobile number, so the fallback must not claim verified identity or enable identity-sensitive features without an approved product rule.

Firebase lists Authentication (most options), including anonymous accounts, as no-cost; its documented limits include up to 100 million anonymous accounts. Firestore reads/writes, Cloud Functions, and other Firebase services can still incur quota or Blaze-plan charges, so billing alerts and quotas are required. See [Firebase pricing](https://firebase.google.com/docs/projects/billing/firebase-pricing-plans), [Flutter anonymous auth](https://firebase.google.com/docs/auth/flutter/anonymous-auth), and [Auth limits](https://firebase.google.com/docs/auth/limits).

When Truecaller later succeeds, link/migrate the temporary account only through a server-controlled merge transaction. Preserve wallet/history data, prevent duplicate accounts, and require an explicit conflict-resolution rule if the anonymous account and Truecaller account already contain data.

## Implementation Phases

1. Add Firebase project configuration, Android Truecaller SDK dependency, platform-channel contract, and a real `AuthRepository` while retaining the fake implementation for tests.
2. Implement the native callback and backend token/profile exchange with state, expiry, replay, and error handling.
3. Add Firestore account/session repositories and attach the session token to the real backend client.
4. Add anonymous fallback, temporary-account UI, sign-out, session restore, and migration/merge handling.
5. Add tests for success, cancellation, unavailable SDK, invalid state, expired/replayed code, duplicate identities, fallback creation, session restore, and account merge.

## Release and Privacy Checks

Before release, configure Truecaller application credentials and SHA fingerprints per build variant, verify production approval requirements, document consent/privacy text, minimize stored PII, redact tokens and phone numbers from logs, and add rate limits, App Check/Play Integrity, audit logging, and Firebase budget alerts. Confirm the current Truecaller SDK version and terms before implementation begins.

## Acceptance Criteria

The user can sign in with Truecaller and return to the same wallet/history account; the backend—not the client—decides identity and session validity; fallback users can be distinguished from verified users; no duplicate account is created on repeat sign-in; and all auth failures leave wallet funds and account data unchanged.
