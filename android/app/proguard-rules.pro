# PayU's optional Google Pay adapter references the Google Pay SDK classes,
# which are not included when Google Pay is not used by the app. R8 otherwise
# treats those optional references as missing classes and fails the release
# build.
-dontwarn com.google.android.apps.nbu.paisa.inapp.client.api.PaymentsClient
-dontwarn com.google.android.apps.nbu.paisa.inapp.client.api.Wallet
-dontwarn com.google.android.apps.nbu.paisa.inapp.client.api.WalletUtils

# shared_preferences_android registers its Pigeon API through JNI/reflection.
# Keep the generated registrar and suspend bridge methods intact in release
# builds; removing them causes SharedPreferences.getInstance() to fail during
# startup with NoSuchMethodError on SharedPreferencesApiRegistrar.getAll().
-keep class io.flutter.plugins.sharedpreferences.** { *; }
