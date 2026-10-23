# Local CI: run before pushing.
flutter analyze; if ($LASTEXITCODE) { exit 1 }
dart run tool/gen_strings.dart --check; if ($LASTEXITCODE) { exit 1 }
dart run tool/check_hardcoded_strings.dart; if ($LASTEXITCODE) { exit 1 }
flutter test
