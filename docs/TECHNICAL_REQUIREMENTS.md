# Technical Requirements Document (TRD)

## AutoIntel AI — v1 (Vehicle RC lookup, Owner phone lookup, Wallet)

Companion to `PRD.md` and `UI_DESIGN_SPEC.md`.
**Decisions locked:** Flutter client (Android target), **no Firebase Auth and no paid SMS/OTP** — plain account with name, email, mobile and password (same approach as MIC's own auth), owner **phone** lookup (not chassis).

---

## 1. Architecture Overview

```
┌────────────────────┐      HTTPS + Bearer session token     ┌──────────────────────────────┐
│  Flutter App       │ ────────────────────────────────────▶ │  Backend API                 │
│  (Android)         │                                       │  Firebase Cloud Function     │
│  Riverpod, Hive    │ ◀──────────────────────────────────── │  (Express-style, as MIC)     │
└────────┬───────────┘                                       │  - auth (email/mobile + pwd) │
         │ PayU / PhonePe SDK (checkout UI only)             │  - wallet / lookup services  │
         ▼                                                   │  - payment webhooks          │
┌────────────────────┐                                       └───┬──────────────┬───────────┘
│ Payment Gateway    │ ── signed webhook ───────────────────────▶│              │
└────────────────────┘                                           ▼              ▼
                                                        ┌───────────────┐ ┌─────────────┐
                                                        │   Firestore   │ │ 3rd-party   │
                                                        │ (transactions)│ │ Vehicle API │
                                                        └───────────────┘ └─────────────┘
```

**Principle:** the app is a thin client. Provider API keys, prices, wallet debits, credential checks, and payment verification all live on the server. The app never calls the 3rd-party vehicle API directly. This mirrors MIC's backend (a single Cloud Function API over Firestore; its code states "Firebase Authentication is deliberately not used").

## 2. Technology Choices

| Layer | Choice | Rationale |
|-------|--------|-----------|
| Client | **Flutter (Dart ≥ 3.12, Material 3), Android first** | Same framework as MIC: reuse `mic_theme.dart`, Sora font, icons and illustrations. |
| State / routing | Riverpod, `go_router` | Testable; small |
| Local store | `hive_ce_flutter` (history cache, same as MIC), `flutter_secure_storage` (tokens) | Offline history, free re-open |
| Networking | `dio` (or `http`, as MIC) + auth interceptor (Bearer session token; sign out on 401) | |
| Auth | **Own account system, as in MIC**: name + email + mobile + password; login with email *or* mobile + password; server-issued opaque session token | No Firebase Auth, no SMS/OTP cost. See §4. |
| Device integrity | Play Integrity API (optional, phase 2) | Hardens signup/payment against emulators/bots; free quota |
| Backend | **Firebase Cloud Functions (Node.js), single HTTPS API** — same pattern as MIC's `micApi` | Reuses MIC's infra, deployment and know-how; pay-per-use, no servers |
| Database | **Firestore** (Admin SDK only; client rules deny all access) | Atomic transactions are sufficient for the wallet ledger; no extra DB to pay for |
| Secrets | Functions secrets / Secret Manager | Provider keys, gateway salts |
| Crash / analytics | Crashlytics + Firebase Analytics (same as MIC; neither needs Firebase Auth) — optional | Reuse MIC setup, no PII |
| Push (optional) | FCM | Recharge/refund notices |
| Payments (client) | Official PayU CheckoutPro and/or PhonePe PG Flutter plugins (verify maintenance/version before choosing) | Checkout UI only; verification is server-side |

> Firebase is used as infrastructure (Functions, Firestore, optional Crashlytics/Analytics/FCM), exactly as in MIC — but **Firebase Authentication is not used**.

## 3. Data Model (Firestore, server-access only)

Money is stored as **integer paise**, never floats. Clients have no direct Firestore access (rules: `allow read, write: if false`).

```
accounts/{accountId}
  name, email (lowercase), phone (E.164)
  passwordHash            // scrypt$<salt>$<hash>, never returned to the app
  status: ACTIVE | BLOCKED | DELETED
  minRechargeDone: bool
  language, termsVersion, createdAt, lastLoginAt, passwordChangedAt

identity_index/{sha256(email) | sha256(phone)} → accountId   // uniqueness, written in a transaction

auth_sessions/{sha256(token)}
  accountId, createdAt, expiresAt, deviceInfo, revokedAt

login_attempts/{sha256(identifier)}
  attempts, windowStartedAt

wallets/{accountId}
  balancePaise, updatedAt

wallets/{accountId}/ledger/{entryId}            // append-only
  type: CREDIT | DEBIT | REFUND
  amountPaise, balanceAfterPaise
  category: TOPUP | RC_LOOKUP | PHONE_LOOKUP | REFUND
  refId, status: PENDING | FINAL | REVERSED, createdAt

payment_orders/{orderId}
  accountId, amountPaise, gateway: PAYU | PHONEPE
  status: CREATED | PENDING | SUCCESS | FAILED
  gatewayTxnId, createdAt, verifiedAt

lookups/{lookupId}
  accountId, type: RC | PHONE
  regNoHash, regNoMasked
  chargedPaise, status: SUCCESS | FAILED | REFUNDED
  resultEnc            // application-level encrypted
  idempotencyKey, providerRef, createdAt
```

Every wallet write happens inside one Firestore **transaction** (read wallet → check → write wallet + ledger), which serializes concurrent spends on the same wallet.

## 4. Authentication (own accounts, modeled on MIC)

Behaviour taken from MIC's `functions/index.js` and `lib/auth/*`: custom endpoints, scrypt hashing, opaque server-side sessions, rate-limited login. **Difference from MIC:** MIC uses a 4-digit MPIN; AutoIntel holds real money, so we use a **password** (min 8 characters, at least one letter and one digit).

**Create account** — `POST /v1/auth/register { name, email, phone, password, termsVersion }`
- Validate email format, Indian mobile (10 digits, starts 6–9, stored as `+91…`), password policy. Email and phone are canonicalized (lowercase / digits only) before hashing for the uniqueness index.
- Reject duplicates (`ACCOUNT_EXISTS`). Hash the password with **scrypt** and a per-user random salt (`scrypt$salt$hash`). Create `accounts` + `wallets` docs; return a session token and profile.
- Mobile/email are **not verified** in v1 (no SMS cost). A user could enter someone else's number or email, so they are contact details, not proof of identity. Do not rely on them for anything security-critical other than recovery (below).

**Login** — `POST /v1/auth/login { identifier, password }`
- `identifier` is an email **or** a mobile number; the server detects which and looks it up via the index.
- Rate limit per identifier hash: **5 failed attempts per 15 minutes**, then `RATE_LIMITED` (same as MIC). Also a coarse per-IP limit. Same generic `INVALID_CREDENTIALS` for unknown account and wrong password (no account enumeration). Constant-time hash comparison.
- Returns a random 32-byte opaque token (`base64url`). The server stores only its SHA-256 in `auth_sessions`, with an expiry (e.g. 30 days, sliding). The app keeps the token in `flutter_secure_storage` and sends `Authorization: Bearer …`.

**Session** — `GET /v1/auth/session` restores the profile on app start (as MIC's `restore()`); `POST /v1/auth/signout` revokes the session. `DELETE /v1/account` deletes the account and data (Play requirement) after password confirmation.

**Change password** — `POST /v1/auth/change-password { current, new }`; revokes all other sessions.

**Forgotten password (no SMS)**
- MIC resets by matching email + phone, with no proof of ownership. That is acceptable for a free calculator but **not for a wallet**: anyone who knows a victim's email and mobile could take over the account and spend its balance.
- v1 recommendation: **email reset code** through a near-free email service (Amazon SES, Resend, or Brevo free tier — effectively no cost at this volume). Code is 6 digits, hashed, 15-minute expiry, 5 attempts, single use; a successful reset revokes all sessions.
- Zero-infrastructure fallback: reset only through support (WhatsApp, verified manually). Decide before build (PRD open questions).

**Biometrics (optional, from MIC):** `local_auth` re-login. MIC stores credentials in secure storage and replays them; for AutoIntel, prefer unlocking an **already-valid session token** with biometrics and never store the password.

**Abuse limits that stand in for OTP:** one account per email/mobile, signup rate limit per IP/device, Play Integrity on register/login (phase 2), and lookup rate limits (§7). A fake account gets no free credit, and the mandatory first recharge deters account farming.

## 5. Backend API

All state-changing calls (except register/login) require `Authorization: Bearer <session token>` and an `Idempotency-Key` (UUID per user action).

| Endpoint | Purpose |
|----------|---------|
| `GET /config` | Prices, minimum recharge, active gateway, feature flags (server-authoritative; app may cache) |
| `POST /lookup/rc { regNo }` | F1 |
| `POST /lookup/phone { regNo }` | F2 |
| `GET /lookups?cursor=` / `GET /lookups/:id` | History; reopening is free |
| `POST /payments/orders { amountPaise }` | Creates order, returns gateway checkout params (hash/token) |
| `POST /payments/webhook` (public, signature-verified) | Gateway → server confirmation, credits wallet |
| `GET /payments/orders/:id` | Server queries the gateway and returns the true status |
| `GET /wallet`, `GET /wallet/ledger?cursor=` | Balance and history |

### 5.1 Lookup flow (F1 / F2)

1. Normalize/validate `regNo` (uppercase, strip separators, regex).
2. Same `Idempotency-Key` seen before → return stored result (no second charge).
3. Reject if `minRechargeDone = false` (server-side gate).
4. Price from server config. In **one Firestore transaction**: read wallet, check balance ≥ price, **reserve** (insert `PENDING` ledger DEBIT, decrement balance).
5. Call provider with 8 s timeout and one retry on timeout/5xx.
6. Success → normalize, encrypt, store in `lookups`, mark ledger `FINAL`, return.
7. Failure/timeout → insert REFUND entry / mark `REVERSED`, restore balance, return typed error. A failed call is never charged.
8. Insufficient balance → `INSUFFICIENT_BALANCE`, no provider call.

A background job reverses any `PENDING` reservation older than 2 minutes (covers server crashes mid-call).

## 6. Error Contract

Stable codes; the app maps each to a string resource and never shows server text:
`INVALID_REG_NO`, `INSUFFICIENT_BALANCE`, `RECHARGE_REQUIRED`, `RECORD_NOT_FOUND`, `PROVIDER_UNAVAILABLE`, `RATE_LIMITED`, `PAYMENT_FAILED`, `PAYMENT_PENDING`, `INVALID_CREDENTIALS`, `ACCOUNT_EXISTS`, `WEAK_PASSWORD`, `UNAUTHENTICATED`, `UNKNOWN`.

## 7. Third-Party Vehicle API Integration

- Endpoints/schema **TBD** (you will supply). Server-side `VehicleProvider` interface: `fetchRc(regNo)`, `fetchOwnerPhone(regNo)`.
- Normalized outputs so the app doesn't depend on provider format:
  - `RcResult { ownerName, maker, model, extra: Map<String,String> }` (`extra` renders as label/value rows)
  - `PhoneResult { phone }`
- API key in Secret Manager only. Per-user rate limits (e.g. 10/min) and a daily cap to limit scraping and cost.
- Result caching across users only if the provider contract allows it.

## 8. Payments (PayU or PhonePe)

- Server `PaymentGateway` interface: `createOrder`, `verifyWebhook`, `fetchStatus`; implementations `PayuGateway` and `PhonePeGateway`, chosen by config. The app just launches checkout with returned params.
- **Never credit from the client callback.** Credit only on a signature-verified webhook or a server-side status fetch reporting SUCCESS.
- Crediting is idempotent per order (transaction checks `status != SUCCESS`).
- App checks `GET /payments/orders/:id` on return from checkout and on next launch for any non-terminal order.
- Scheduled reconciliation for orders `PENDING` > 15 min.
- **Compliance before release:** Google Play payments policy for wallet top-ups (PRD R2) and RBI PPI applicability (PRD R5).

## 9. Security & Privacy

- Wallet balance and prices are server-authoritative.
- Play Integrity token (phase 2) on register, login, and payment order creation.
- TLS only (`usesCleartextTraffic=false`); optional certificate pinning.
- Owner name and phone are PII: encrypted at rest (DB + application-level encryption of `result_enc`, key in KMS), excluded from logs, analytics, and Crashlytics. Local Hive history box is encrypted (`HiveAesCipher`, key in `flutter_secure_storage`).
- `FLAG_SECURE` on result screens (via a platform channel / `flutter_windowmanager`-style plugin) to block screenshots and recents preview; configurable.
- Log only lookup id, status, latency; reg numbers masked (`MH12****34`). Store `reg_no_hash`, not plaintext, where feasible.
- In-app: privacy policy, terms/acceptable use, account + data deletion, "report misuse" contact.
- Minimum-recharge gate enforced server-side, not just in UI.

## 10. Localization (strings.xml + Play Console auto-translate, in Flutter)

**Goal:** no hard-coded strings anywhere; `strings.xml` is the single source of truth so Play Console's translation service can read it.

### 10.1 How it works in Flutter
Flutter UI text is Dart, which Play cannot see, so we keep the strings in the **Android resource file** and generate Dart from it:

```
android/app/src/main/res/values/strings.xml        ← English source (edit here only)
android/app/src/main/res/values-hi/strings.xml     ← Play-generated translations (committed)
android/app/src/main/res/values-mr/ ...
        │
        ▼  tool/gen_strings.dart  (run by `dart run tool/gen_strings.dart`, CI, and pre-build)
lib/l10n/strings.g.dart   (generated, committed; do not edit)
   AppStrings.of(context).lookupRcButtonSearch(price)
```

- The generator parses every `values*/strings.xml`, including `<string>` and `<plurals>`, and emits typed getters/functions per key, with positional placeholders (`%1$s`, `%1$d`) turned into Dart parameters. A missing key in a locale falls back to English.
- Runtime locale: user choice (stored in prefs) → device locale → English. A `LocalizationsDelegate` plus `supportedLocales` is generated from the list of `values-*` folders. Plural selection uses `intl` plural rules.
- Android 13+ per-app language: add `res/xml/locales_config.xml` (generated from the same folder list) and reference it in the manifest, so Settings → App language works too.
- Amounts and dates use `intl` `NumberFormat.currency(locale:, symbol: '₹')` / `DateFormat`, never string concatenation.

### 10.2 Rules (enforced in CI)
1. No user-facing string literals in Dart. A custom lint (`custom_lint`) or a CI grep script flags string literals passed to `Text(`, `SnackBar`, `AppBar(title:`, `labelText`, `hintText`, `tooltip`, `semanticsLabel`, etc. Failing = build fails.
2. All text goes in `values/strings.xml` with a translator comment (`<!-- Button: charges wallet. %1$s is a price like ₹2 -->`).
3. Use positional placeholders and plurals; never build sentences by concatenation.
4. Mark non-translatable items (`app_name`, URLs, regex) `translatable="false"`.
5. Server error codes map to string keys (§6); the server never sends display text.
6. Naming: `screen_element_purpose`, e.g. `lookup_rc_button_search`, `error_insufficient_balance`.
7. CI check: every `values-*` file has the same keys and placeholder signatures as default; generated `strings.g.dart` must be up to date (`git diff --exit-code`).
8. Pseudo-locale test (long strings + RTL) in debug to catch overflow.

### 10.3 Play Console workflow
1. Build the AAB. `strings.xml` is compiled into the bundle's Android resources.
2. **Keep the strings in the bundle even though Dart doesn't reference them via `R.string`**: add `android/app/src/main/res/raw/keep.xml` with `<resources xmlns:tools="http://schemas.android.com/tools" tools:keep="@string/*" />`, otherwise resource shrinking may strip them and Play will not see them.
3. Play Console → *Grow users → Translation service*: select the app/bundle, pick target languages, choose machine or paid human translation.
4. Download the generated `values-<lang>/strings.xml`, commit, run the generator, release.
5. Human-review money, legal, and error strings in each language before launch.
6. **Spike first (½ day):** upload a test AAB with a few strings to an internal track and confirm Play detects them in a Flutter build. If it does not, fall back to manually exporting `values/strings.xml` to Play's translation tool/Google Translate and importing results into `values-xx/` — the rest of the pipeline is unchanged.

### 10.4 Caveats
- `strings.xml` is Android-specific; if iOS is added later, the same generator can also emit an iOS-compatible format, but Play auto-translation only covers Android.
- The app's own UI strings are only translated if Dart reads them through the generated class; the AAB copy exists purely for Play detection and per-app locale support.

## 11. App Structure (Flutter)

```
lib/
  main.dart
  core/        theme (ported from MIC mic_theme.dart), widgets, network, errors, util
  l10n/        strings.g.dart (generated), language_controller.dart
  features/
    auth/      register, login, forgot_password, session (token store)
    home/
    lookup/    reg_no_field, confirm_charge_sheet, rc_screen, phone_screen, results
    wallet/    balance, recharge, ledger, payment_status
    history/
    settings/  language, privacy, support, delete_account
  data/        api client, repositories, hive models
tool/gen_strings.dart
android/app/src/main/res/values*/strings.xml, raw/keep.xml, xml/locales_config.xml
assets/fonts/Sora.ttf, assets/images, assets/figma (copied from MIC as needed)
```

Navigation: `go_router` with a bottom bar (Home, History, Wallet, Settings), following MIC's tab pattern.

## 12. Analytics (no PII)
`signup_completed`, `login_completed`, `onboarding_done`, `recharge_started{amount_bucket,gateway}`, `recharge_success`, `recharge_failed{reason}`, `lookup_started{type}`, `lookup_success{type}`, `lookup_failed{type,code}`, `insufficient_balance_shown`, `language_changed{lang}`. Never log reg numbers, names, or phone numbers.

## 13. Testing & CI
- Dart unit tests: reg-number validator, ledger/amount formatting, error mapping, string generator (placeholders, plurals, fallback).
- Widget tests: lookup flow states (valid, invalid, insufficient balance, loading, error).
- Backend tests: concurrent lookups cannot overdraw (Firestore emulator transaction test); duplicate webhooks credit once; provider timeout refunds; login rate limiting and lockout; duplicate email/mobile rejected; session revoked on sign-out and password change.
- Gateway sandbox end-to-end for success/failure/pending.
- CI: `flutter analyze`, localization lint + generator diff check, tests, release build.

## 14. Release Checklist
- [ ] Provider contract, endpoints, schema, per-call cost confirmed
- [ ] Password-reset method decided (email service vs. support-only)
- [ ] Gateway chosen, merchant account live, webhook URL configured
- [ ] Play policy review: wallet top-ups and personal-data lookup (PRD R1, R2)
- [ ] Privacy policy, terms, data-safety form, account deletion flow
- [ ] Play auto-translation spike passed; translations committed and spot-reviewed
- [ ] Play Integrity enabled; Firestore scheduled backups enabled
- [ ] Prices and minimum recharge set in server config
