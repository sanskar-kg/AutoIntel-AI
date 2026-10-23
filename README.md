# AutoIntel AI

Pay-per-use Android app (Flutter): look up vehicle details and the owner's phone number from a registration number, paid from a prepaid in-app wallet. Sibling app of MIC (shared design language).

Docs live in [`docs/`](docs/README.md): PRD, technical requirements, UI spec.

## Status

Built against a **mock backend** so every screen and flow works end to end before the real pieces exist:

| Piece | State |
|-------|-------|
| UI: recharge gate, home, RC lookup, phone lookup, results, history, wallet, settings, language picker | Done |
| Wallet rules (min-recharge gate, charge only on success, idempotency, refunds on failure) | Done in `lib/data/mock_backend.dart`; to be re-implemented server-side |
| Auth (register / login with email or mobile + password, MIC-style) | **Not built yet** (`FakeAuthRepository` signs in a demo user) |
| Third-party vehicle API | Not connected (mock returns demo data, flagged "Demo data" in the UI) |
| PayU / PhonePe | Not connected (`MockPaymentGateway` lets you pick success / pending / failure) |

Swap points are the providers in `lib/app/providers.dart` (`backendProvider`, `paymentGatewayProvider`, `authRepositoryProvider`).

Mock lookup hooks: a registration number ending `0000` returns "not found", ending `9999` returns "provider unavailable" (neither is charged).

## Strings and localization

Never hard-code UI text. All strings live in `android/app/src/main/res/values/strings.xml`.

```
dart run tool/gen_strings.dart            # regenerate lib/l10n/strings.g.dart after editing strings.xml
dart run tool/gen_strings.dart --check    # CI: generated file is up to date
dart run tool/check_hardcoded_strings.dart # CI: no string literals in Text(...) etc.
```

Translations from Play Console go in `values-xx/strings.xml`; re-run the generator and commit. See `docs/TECHNICAL_REQUIREMENTS.md` §10.

## Develop

```
flutter pub get
powershell ./ci.ps1        # analyze + string checks + tests
flutter run
```

`android/gradle.properties` sets `kotlin.incremental=false` because the project (H:) and the pub cache (C:) are on different drives.
