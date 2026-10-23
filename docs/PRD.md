# Product Requirements Document (PRD)

## AutoIntel AI — Vehicle Info Lookup (v1 Scope)

> Supersedes `archive/PRD-original-vehicle-info-services.md` and `archive/TECHNICAL_ARCHITECTURE-original.md` for v1. Those describe a much larger platform (DL, PAN, IRDAI, insurance, B2B API); everything not listed here is **out of scope for v1**.

---

## 1. Summary

AutoIntel AI is a small, pay-per-use Android utility. A user enters a vehicle registration number and pays a few rupees from an in-app prepaid wallet to get vehicle details. It is a **secondary app under the MIC brand family**, so it shares MIC's design language (see `UI_DESIGN_SPEC.md`).

## 2. Scope

### In scope (v1)

| # | Feature | Input | Output | Price (configurable) |
|---|---------|-------|--------|----------------------|
| F1 | **Vehicle RC Intelligence** | Registration number | Owner name, maker, model, and other fields the 3rd-party API returns | ₹2 |
| F2 | **Vehicle Owner Phone Lookup** | Registration number | Owner's phone number | ₹5 (TBC) |
| F3 | **Wallet** | Recharge amount | Balance, transaction history | — |
| F4 | **Wallet recharge** | Amount | Credited balance via PayU **or** PhonePe | — |
| F5 | **Localization** | — | UI in multiple languages, auto-translated via Play Console | — |

Both features take the **same input** (registration number) and call **external APIs supplied by a 3rd party**. Response shape is not yet known; the app treats the provider response as an opaque, normalized object (see TRD §6).

### Out of scope (v1)
Chassis/VIN lookup, ownership history, insurance, DL, PAN, IRDAI, PDF reports, OCR plate scanner, expiry alerts, B2B API/web dashboard, iOS, subscriptions.

> The earlier draft listed "lookup by chassis/VIN" as feature 2. Per your latest direction, feature 2 is now the **phone-number lookup by registration number**. Chassis lookup is deferred.

## 3. Users

Anyone needing quick vehicle details: used-car dealers/brokers, buyers, mechanics, and fleet/insurance field staff. Common need: fast, cheap, one-off lookups without a subscription.

## 4. Functional Requirements

### 4.1 Onboarding & auth
- FR-1: Create an account with name, email, mobile and password; log in with email **or** mobile + password. Own backend auth modeled on MIC (no Firebase Auth, no SMS/OTP cost). Wallet and history are tied to the account. *(Auth implementation deferred; app is built against an `AuthRepository` interface first.)*
- FR-2: After first sign-in the user **must complete a minimum wallet recharge** before using any lookup. Until then, lookup screens are gated by a recharge prompt. Minimum amount: **₹ TBD** (e.g. ₹20), remote-configurable.
- FR-3: Language picker available on first launch and in Settings (defaults to device locale).

### 4.2 Vehicle RC lookup (F1)
- FR-4: Input field accepts Indian registration formats (e.g. `MH12AB1234`, BH series); uppercase, strips spaces/hyphens, validates before any charge.
- FR-5: Before the call, show the price and the user's balance; require explicit "Search for ₹X".
- FR-6: If balance < price → show "Insufficient balance" with a one-tap recharge CTA. No API call is made.
- FR-7: On success, show result card(s) with owner name, maker, model, and remaining fields from the provider. Wallet is debited **only on a successful provider response**.
- FR-8: On provider failure/timeout, no charge (or automatic reversal) and a retry option.

### 4.3 Phone number lookup (F2)
- FR-9: Same input rules and charge-confirmation flow as F1, at the higher price.
- FR-10: Result shows the phone number with tap-to-call. It is not shown on the RC result unless the user bought it.
- FR-11: Can be started from an F1 result ("Get owner's phone — ₹5") so the user doesn't retype the number.

### 4.4 Wallet (F3, F4)
- FR-12: Wallet balance is visible on Home and in a persistent header chip.
- FR-13: Recharge via **PayU or PhonePe** (final choice TBD; the app is built behind a gateway abstraction — TRD §7). Preset amounts (₹50 / ₹100 / ₹200 / ₹500) plus custom amount.
- FR-14: Balance is credited only after **server-side** payment confirmation, never from the client's success callback alone.
- FR-15: Transaction history (recharges, debits, refunds) with date, amount, description, and status; paginated.
- FR-16: Prices for F1 and F2 and the minimum recharge are server-configurable (no app update to change them).

### 4.5 Localization (F5)
- FR-18: No user-visible string is hard-coded in code. All strings live in `res/values/strings.xml` (see TRD §9).
- FR-19: Launch languages: English (source) + languages chosen via Play Console auto-translation (suggested: Hindi, Marathi, Gujarati, Bengali, Tamil, Telugu, Kannada — **list TBD**).

## 5. Non-functional Requirements
- **Platform:** Android (minSdk 24+). Flutter (same as MIC). Strings live in Android `strings.xml` and are converted to Dart by a generator (TRD §10).
- **Performance:** lookup result in < 3 s on 4G typical; balance screen from cache instantly.
- **Security:** third-party API keys and payment-gateway secrets live **only on the server**; wallet balance is server-authoritative.
- **Privacy:** DPDPA 2023 compliant privacy policy and consent; no PII in logs/analytics.
- **Accessibility:** 48dp touch targets, TalkBack labels, supports font scaling and RTL-safe layouts.

## 6. Success Metrics
- Recharge conversion: % of installs completing the minimum recharge.
- Lookups per paying user; repeat-recharge rate (D30).
- Lookup success rate (provider non-error responses).
- Revenue per lookup minus provider cost (margin).

## 7. Risks & Open Questions

| # | Item | Why it matters |
|---|------|----------------|
| R1 | **Phone number lookup (F2) is sensitive.** Exposing an owner's phone number from a plate number raises DPDPA 2023 and Google Play *User Data / Personal & Sensitive Information* policy exposure, and risk of stalking/harassment use. | Could cause Play rejection or takedown. Need provider's legal basis, an acceptable-use policy, consent/terms screen, and probably a "report misuse" path. Recommend reviewing before building F2. |
| R2 | **Wallet top-ups on Google Play.** Play policy generally requires Google Play Billing for digital goods/services consumed in the app; a PayU/PhonePe wallet may be flagged. | Could block release. Verify against current Play payments policy (and India-specific alternative billing options) before launch. |
| R3 | Provider response schema, SLAs, per-call cost, rate limits unknown. | Pricing (₹2 / ₹5) must exceed provider cost + gateway fees (~2%). |
| R4 | PayU vs PhonePe not decided. | Affects TRD §7 only (abstracted). |
| R5 | Minimum first recharge amount, refund policy (wallet balance refundability), and KYC requirements for wallets (RBI PPI rules may apply to *stored-value* wallets that can be cashed out; closed-loop, non-refundable credits are usually treated differently). | Needs legal/finance confirmation. |
| R6 | Final launch language list. | Drives string review effort. |

## 8. Milestones (suggested)
1. Design system + screens (Flutter, reusing MIC theme), strings.xml generator + Play translation spike.
2. Auth + wallet ledger + recharge (sandbox gateway).
3. F1 and F2 integration against provider sandbox.
4. Hardening, privacy policy, Play listing, closed testing, auto-translation review.
