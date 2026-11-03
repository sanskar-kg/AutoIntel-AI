package com.autointel.ai

import android.content.res.Configuration
import android.os.Build
import android.os.LocaleList
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivityLaunchConfigs
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterFragmentActivity() {
    override fun getBackgroundMode(): FlutterActivityLaunchConfigs.BackgroundMode {
        return FlutterActivityLaunchConfigs.BackgroundMode.transparent
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Lets Dart block screenshots / recents preview on screens showing personal data.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "autointel/secure_screen")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "enable" -> {
                        window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
                        result.success(null)
                    }
                    "disable" -> {
                        window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "motorinfo/localization")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "loadStrings" -> {
                        val tags = (call.argument<List<String>>("tags") ?: emptyList())
                        val keys = (call.argument<List<String>>("keys") ?: emptyList())
                        result.success(loadStrings(tags, keys))
                    }
                    else -> result.notImplemented()
                }
            }
    }

    /**
     * Resolves Android resources for an in-app language selection. Play Console
     * injects translated values-xx resources into the uploaded bundle, so the
     * normal Android resource resolver provides the translated value and falls
     * back to the default English resource when one is unavailable.
     */
    private fun loadStrings(tags: List<String>, keys: List<String>): Map<String, String> {
        val localized = if (tags.isEmpty()) this else {
            val configuration = Configuration(resources.configuration)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                configuration.setLocales(
                    LocaleList(*tags.map { java.util.Locale.forLanguageTag(it) }.toTypedArray()),
                )
            } else {
                @Suppress("DEPRECATION")
                configuration.locale = java.util.Locale.forLanguageTag(tags.first())
            }
            createConfigurationContext(configuration)
        }
        val values = mutableMapOf<String, String>()
        for (key in keys) {
            val id = localized.resources.getIdentifier(key, "string", packageName)
            if (id != 0) values[key] = localized.resources.getString(id)
        }
        return values
    }
}
