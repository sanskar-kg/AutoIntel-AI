# UI Design Specification

## AutoIntel AI — aligned with the MIC design language

AutoIntel AI is a sibling app to **MIC** (`H:\Sanskar\Work\Coding\MIC`). Tokens below are taken directly from MIC's `lib/ui/mic_theme.dart` and screens so the two apps feel like one family. Both apps are Flutter, so `mic_theme.dart` (colors, `sora()` text style, theme, `PrimaryButton`, `ErrorMessage`, `Brand`) can be copied or extracted into a shared package. Pixel values below are logical pixels (dp).

---

## 1. Design Tokens (from MIC)

### Colors
| Token | Hex | Use |
|-------|-----|-----|
| `primary` (MIC blue) | `#0068EF` | Buttons, active tab, links, brand wordmark |
| `heading` | `#11161B` | Body/headings |
| `navy` | `#07143A` | Titles, icons, strong text |
| `muted` | `#68758E` | Secondary text, helper text |
| `secondary` | `#6E767D` | Disclaimers |
| `border` | `#D1D5DA` | Input borders |
| `hairline` | `#E4EAF2` | Card borders, nav top divider |
| `surface-alt` | `#F8F9FB` | Utility screen background |
| `chip-bg` | `#F2F7FD` | Circular back-button background |
| `error` | `#B3261E` | Error text |
| Tile tints | `#EAF7FF` (blue), `#FFF8E9` (amber), `#EAFFF3` (green), `#F5F0FF` (violet), `#FFF0F5` (pink) | Feature tiles/cards |

Suggested semantic additions (not in MIC): `success #1E8E3E`, `warning #B26A00` for wallet states.

### Typography — **Sora** (variable font)
Reuse `assets/fonts/Sora.ttf` from MIC (OFL licensed; ship `OFL.txt`).

| Style | Size / weight | Notes |
|-------|---------------|-------|
| Wordmark | 24 / 800, blue | Brand block; 8sp muted subtitle beneath |
| Screen title | 23 / 700, navy, tracking -0.5 | e.g. "Vehicle Lookup" |
| Greeting name | 29 / 700, tracking -0.87 | Home |
| Body | 13–14 / 400, muted | |
| Button | 14 / 600 | |
| Caption | 10–12 | Disclaimers, nav labels (10 / 600 selected) |

Respect system font scaling (use `sp`), and test at 130% scale; MIC's 8–10sp captions should be raised to a minimum of 11sp for readability.

### Shape, spacing, elevation
- Primary buttons: full-width, **48dp** height, **14dp** corner radius.
- Cards/tiles: **12–14dp** radius, flat (1dp `hairline` border, no heavy shadow).
- Screen horizontal padding **20–22dp**; content max width 520dp (tablet/foldable).
- Tile grid: 2 columns, 10dp gap, tile height ~182dp, illustration anchored bottom-right.
- Back button: 40dp circle, `#F2F7FD` fill, navy arrow.

### Icons & imagery
- Material rounded icons as used in MIC (`home_rounded`, `person_rounded`, `settings_rounded`, `directions_car`, `verified_user`, `language`, `arrow_back`).
- Reuse MIC illustrations where suitable from `assets/images` (`private_car.png`, `two_wheeler.png`, `taxi.png`, `bus.png`, `goods_vehicle.png`, `three_wheeler.png`, `SUV.svg`, `sedan.svg`) and `assets/figma/*` for the pastel feature-tile style.
- App icon: same construction as MIC (adaptive icon, `#0066FD` background, artwork inside the safe zone); distinct glyph so the two apps are distinguishable on a launcher. **Needs a new icon asset.**
- Copy needed assets into `assets/` and use `flutter_svg` for SVGs, as MIC does. Compress PNGs.

### Language
Plain, short, friendly copy. All of it lives in `strings.xml` (TRD §9). The brand header pattern is the wordmark + tiny "powered by" subtitle; AutoIntel's wordmark replaces "MIC", and a small "A MIC product" tagline ties the family together.

---

## 2. Navigation
Bottom bar (white, 1dp `hairline` top border, blue selected / muted unselected, 10sp labels):
**Home · History · Wallet · Settings**. A **wallet balance chip** (₹ icon + amount, blue-tint pill) sits in the top-right of Home, next to the language button (MIC has the globe + language code there).

## 3. Screens

### 3.1 Splash
Blue (`#0066FD`) full-bleed with wordmark, matching MIC's branded splash.

### 3.2 Language picker (first launch + Settings)
List of languages shown in their own script, radio selection, "Continue". Same bottom-sheet picker pattern as MIC's `language_picker`.

### 3.3 Sign in
Two tabs/screens modeled on MIC's auth screens. **Log in:** email or mobile field + password (show/hide) + "Forgot password?" + primary "Log in". **Create account:** name, email, mobile (+91), password, terms checkbox + primary "Create account". Error text in red under the form (live region for TalkBack). *(Built after the rest of the app.)*

### 3.4 First recharge gate
Shown immediately after sign-in and whenever balance is below the minimum on a locked account.
- Title: "Add money to get started"
- Explanation: "A minimum recharge of ₹X is needed to use lookups."
- Preset amount chips (₹50, ₹100, ₹200, ₹500) + custom amount field (min enforced).
- Price list card: "Vehicle details ₹2 · Owner phone ₹5" (values from config).
- Primary button "Pay ₹100" → gateway checkout.
- Lookup tiles on Home are visible but show a lock overlay until this is done.

### 3.5 Home
```
[AutoIntel]                      [₹ 120]  [🌐 EN]
Welcome back
Sanskar
┌──────────────┐ ┌──────────────┐
│ Vehicle      │ │ Owner Phone  │
│ Details      │ │ Lookup       │
│ ₹2           │ │ ₹5           │
│        [car] │ │       [phone]│
└──────────────┘ └──────────────┘   ← pastel tiles (#EAF7FF, #FFF8E9)
Recent lookups
 MH12****34   Vehicle details   Today
```
Two large tiles in MIC's tile style with the price shown as a small pill. Below, a "Recent lookups" list (free to reopen).

### 3.6 Lookup screen (shared layout for F1 and F2)
Back circle + title ("Vehicle Details" / "Owner Phone").
- Registration number field: large, auto-capitalised, monospace-ish spacing, placeholder `MH12AB1234`, inline validation.
- Info row: "This search costs ₹2 · Balance ₹120".
- Primary button: "Search for ₹2". Disabled until valid.
- Tapping shows a **confirm bottom sheet**: reg number, price, resulting balance, "Confirm" / "Cancel". (Prevents accidental charges.)
- Insufficient balance state: the button becomes "Recharge to continue" and opens the recharge sheet.
- Loading: button becomes a spinner (MIC's `PrimaryButton busy`), 8 s max, then retry state.
- Disclaimer in 10–11sp muted: data is sourced from third-party providers; independent app, not affiliated with any government body (mirrors MIC's disclaimer pattern).

### 3.7 Result screen
- Hero card: reg number plate chip, maker + model as title.
- Details card: label/value rows (Owner name, Maker, Model, plus provider extras).
- CTA card (RC result only): "Get owner's phone number — ₹5" (tinted `#FFF8E9`, one tap, goes through the confirm sheet).
- Phone result: large number, **Call** button, short responsible-use note.
- Screenshots blocked by default (see TRD §8).
- Footer: "Saved to History — reopening is free."

### 3.8 Wallet
- Balance card (blue background, white text, large amount, "Add money" button).
- Preset amount chips + custom amount.
- Transactions list: icon (↑ credit green / ↓ debit navy), title ("Wallet recharge", "Vehicle details MH12****34"), date, signed amount. Filter chips: All · Recharges · Searches.
- Pending payments show a "Processing…" row with a refresh action.

### 3.9 Payment result
Full-screen states: **Success** (check illustration `assets/check.svg`, new balance), **Pending** ("We're confirming your payment; balance updates automatically"), **Failed** (reason, retry).

### 3.10 History
List grouped by date; chips for type (Details / Phone). Tap opens the stored result at no charge.

### 3.11 Settings
Language, Privacy policy, Terms, Help/Support, Delete account, App version, Sign out.

---

## 4. States & Components checklist
- Components: `BrandHeader`, `PrimaryButton(busy)`, `ErrorMessage`, `WalletChip`, `FeatureTile`, `RegNoField`, `ConfirmChargeSheet`, `ResultRow`, `AmountChips`, `TransactionRow`, `LanguageSheet`, `LockOverlay`.
- Every screen defines: loading, empty, error, offline (cached history still opens), insufficient-balance.
- Accessibility: 48dp minimum targets, content descriptions on icon-only buttons, 4.5:1 contrast (muted `#68758E` on white passes for body size ≥ 14sp; use `navy` for smaller text), dynamic type support, no color-only status.
- Localization: allow +30–40% text expansion; avoid fixed-width buttons/pills; mirror-safe layout (`start`/`end`).
- Dark theme: not in MIC; out of scope for v1.

## 5. Open design items
- AutoIntel wordmark and app icon artwork.
- Final tile illustrations (reuse MIC's vehicle art vs. new).
- Gateway checkout look (PayU/PhonePe SDK UI is gateway-provided).
