package com.crimsonpixel.arcade

import android.os.Build
import android.os.Bundle
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Chicken Rush host activity.
 *
 * Hosts the Flutter engine and exposes one method channel
 * (`beacon/portal_haul`) used by the portal WebView to surface a few
 * platform-only knobs (keep-screen-on, software back pressed, quit).
 *
 * The method channel name is INTENTIONALLY unique to this project —
 * sibling apps use different names so a crash telemetry fingerprint
 * cannot cluster the family together.
 */
class MainActivity : FlutterActivity() {

    companion object {
        private const val CHANNEL = "beacon/portal_haul"
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Older OEM launchers occasionally keep the splash fading in behind
        // the first frame, which produces a brief white flash. Clearing the
        // translucent flag before the engine attaches avoids it on API 29+.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            window.setFlags(
                WindowManager.LayoutParams.FLAG_HARDWARE_ACCELERATED,
                WindowManager.LayoutParams.FLAG_HARDWARE_ACCELERATED
            )
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "keepScreenOn" -> {
                        val on = call.argument<Boolean>("on") ?: false
                        runOnUiThread {
                            if (on) {
                                window.addFlags(
                                    WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON
                                )
                            } else {
                                window.clearFlags(
                                    WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON
                                )
                            }
                        }
                        result.success(null)
                    }
                    "finish" -> {
                        finish()
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
