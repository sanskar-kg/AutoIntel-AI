# Repository Guidelines

## Project Structure & Module Organization

This repository is a Flutter Android app. Application code is in `lib/`, organized by responsibility:

- `lib/app/`: app composition and Riverpod providers.
- `lib/core/`: shared widgets, theme, validation, formatting, errors, and security helpers.
- `lib/data/`: models, backend interfaces, and the mock backend.
- `lib/features/`: screen-level flows such as lookup, wallet, history, home, and settings.
- `test/`: unit and widget/integration-style tests.
- `tool/`: localization generation and hard-coded-string checks.
- `assets/`: images and fonts; `android/` contains the Android host project.
- `docs/` and `ASO/`: product/technical documentation and store assets.

## Build, Test, and Development Commands

Run these from the repository root:

```powershell
flutter pub get                  # Install Dart/Flutter dependencies
flutter run                      # Run the app on a connected device/emulator
powershell ./ci.ps1              # Analyze, validate strings, and run all tests
flutter test                     # Run the test suite
flutter analyze                  # Run Dart/Flutter static analysis
```

After editing Android string resources, regenerate accessors with `dart run tool/gen_strings.dart`. Use `--check` to verify generated files without changing them.

## Coding Style & Naming Conventions

Follow `flutter_lints` configured in `analysis_options.yaml`. Use two-space indentation, trailing commas for readable multi-line Dart expressions, `PascalCase` for types/widgets, `camelCase` for variables and methods, and `snake_case.dart` filenames. Keep feature-specific code in its feature directory. Do not hard-code user-facing text in widgets; update `android/app/src/main/res/values/strings.xml`, then regenerate localization accessors.

## Testing Guidelines

Tests use `flutter_test`. Name files with the `_test.dart` suffix and group cases by behavior. Add unit tests for validation, formatting, and backend rules; add widget tests for user flows and visible state changes. Run `flutter test` (or `powershell ./ci.ps1`) before submitting changes.

## Commit & Pull Request Guidelines

Git history is not available in this checkout, so no existing commit convention could be verified. Use concise imperative commits, preferably scoped (for example, `wallet: prevent duplicate recharge credit`). Pull requests should explain the user-visible change, list verification commands, link relevant issues or docs, and include screenshots or recordings for UI changes. Call out changes to mock/backend behavior, localization, or Android configuration.

## Security & Configuration Tips

The current app uses a mock backend and demo authentication/payment flows. Keep secrets and production credentials out of source control. Treat provider, payment, and authentication integrations as swap points defined in `lib/app/providers.dart`.
