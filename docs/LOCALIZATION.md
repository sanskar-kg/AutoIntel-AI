# App localization

The English strings in `android/app/src/main/res/values/strings.xml` are the
source of truth. `dart run tool/gen_strings.dart` reads translated Android
resource folders and generates the Dart localization map used by the Flutter
UI.

## Play Console Indian languages

The current Play Console app-string translation list includes these Indian
languages and Android resource folders:

| Play language | Code | Android folder |
| --- | --- | --- |
| Bangla | `bn-BD` | `values-bn-rBD` |
| Gujarati | `gu` | `values-gu` |
| Hindi | `hi-IN` | `values-hi-rIN` |
| Kannada | `kn-IN` | `values-kn-rIN` |
| Malayalam | `ml-IN` | `values-ml-rIN` |
| Marathi | `mr-IN` | `values-mr-rIN` |
| Punjabi | `pa` | `values-pa` |
| Tamil | `ta-IN` | `values-ta-rIN` |
| Telugu | `te-IN` | `values-te-rIN` |
| Urdu | `ur` | `values-ur` |

Play Console's app-string translation service can generate and apply
translations to uploaded app bundles. For this Flutter app, the translated
`strings.xml` files must also be present in the source checkout before the
Dart generator runs, because the Flutter UI reads the generated Dart map
rather than Android's runtime `getString()` API.

When translated files are available, place them in the folders above and run:

```powershell
dart run tool/gen_strings.dart
dart run tool/gen_strings.dart --check
```

The language selector is generated from the locale folders, so untranslated
languages are intentionally not exposed in the app yet.
