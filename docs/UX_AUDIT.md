# UI / UX Audit

Scope: the Flutter build (mock backend), reviewed from the code, widget tests, and walkthroughs on a Redmi Note 7 Pro (Android 10, MIUI). Verified on the device: launch, recharge gate, payment confirmation, home, registration input, confirm sheet, RC result, phone result (via the CTA), history, wallet and the Add money picker. See "Not yet verified" for the rest.

## Fixed in this pass

| # | Finding | Fix |
|---|---------|-----|
| 1 | Very little space above the header; brand sat right under the status bar | +16dp top padding on Home and pushed screens, +12dp on tab titles (History / Wallet / Settings), +12dp on the recharge gate |
| 2 | Home tiles side by side were narrow, cramped and overflowed at larger font sizes | Tiles are full width and stacked, 150dp minimum height, text reserved clear of the artwork, grow with font size instead of overflowing |
| 3 | Black screen for ~7s on launch (debug) on a phone in dark mode: the Android launch window used the dark theme although the app is light-only | Removed the dark launch theme; launch window is now the brand blue and matches the in-app splash |
| 4 | MIUI auto-dark ("ForceDarkHelper" in logs) could invert colours | `forceDarkAllowed=false` on both app themes |
| 5 | Language switcher showed "EN" with only one language available (dead control) | Hidden in Home/Gate and Settings until a translation exists |
| 6 | Forced line breaks (`\n`) inside tile titles/subtitles in strings.xml would break in other languages | Removed; text reflows |
| 7 | Secondary text on pastel tiles was borderline contrast at 11sp | New `mutedOnTint` colour, 12sp |
| 8 | Bottom-nav labels 11sp | 12sp |
| 9 | Pay button on the recharge gate scrolled off screen | Pinned to the bottom |
| 10 | Payment confirmation could be skipped after the first recharge (gate screen replaced while awaiting) | Result screen now pushed through a navigator captured up front |
| 11 | Crash in `SoftCard` (shape and borderRadius both set), plus two layout overflows on Home | Fixed; covered by widget tests |
| 12 | Amount presets wrapped, leaving "₹500" alone on a second row in the Wallet card | Four equal-width buttons in one row |
| 13 | Result actions were too busy | Removed copy/share actions; retained Call |
| 14 | `FLAG_SECURE` made screenshots of result screens impossible in debug, hiding them from QA | Secure flag is release-only; force in debug with `--dart-define=FORCE_SECURE=true` |

## Open recommendations (not done)

**High**
- **Verify every screen on the device** at 100% and 130% font size, and with a long Hindi/Marathi translation once generated.
- **Share / save result**: sharing is intentionally not offered because phone numbers are sensitive (PRD risk R1). Saved results remain available in History.
- **Android back on a non-Home tab** exits the app; it should go to Home first.

**Medium**
- History is a flat list; group by date ("Today", "Yesterday") as the spec says.
- Recharge amount field: show the ₹ prefix at all times, not just when focused.
- Result screen: add a "Search another vehicle" action so users don't need to go back twice.
- Consider haptic feedback on successful search and payment.
- Wallet: a low-balance nudge (e.g. below the price of one phone lookup) with a one-tap Add money.
- Empty states are text only; add a small illustration from MIC's assets.

**Low**
- Provider extra fields show raw keys until a label string exists (`_RcDetails._label`); add labels as the real provider schema becomes known.
- Splash is text only; use the final wordmark/icon once designed.
- No dark theme (intentional for v1; MIC has none).

## Accessibility checklist

| Check | Status |
|-------|--------|
| 48dp touch targets on buttons, chips, icon buttons | Done |
| Screen-reader labels on icon-only controls (back, clear, language, wallet chip) | Done |
| Error text announced (live region) | Done |
| Text scales with system font size | Done; verify on device |
| Contrast ≥ 4.5:1 for body text | Muted on white passes; on tints uses `mutedOnTint` |
| Colour is not the only status signal (credit/debit also use icon and sign) | Done |
| RTL-safe layout | Not tested (no RTL language planned) |

## Not yet verified on a device
Settings and its info pages; failure/pending payment screens and the pending banner in Wallet; "not found" / "provider unavailable" / insufficient-balance states; language sheet (hidden until a translation exists); tap-to-call; screenshot blocking in a release build; large font scale (130%+); small phones (< 360dp wide).
