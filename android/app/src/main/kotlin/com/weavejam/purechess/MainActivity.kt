package com.weavejam.purechess

import android.os.Build
import android.view.WindowInsets
import android.view.WindowInsetsController
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "purechess/display")
            .setMethodCallHandler { call, result ->
                if (call.method != "setImmersive") {
                    result.notImplemented()
                } else if (call.arguments !is Boolean) {
                    result.error("invalid_argument", "Expected an immersive boolean", null)
                } else {
                    if (Build.VERSION.SDK_INT >= 35) {
                        val controller = window.insetsController
                        if (controller == null) {
                            result.error("window_unavailable", "Window insets are unavailable", null)
                            return@setMethodCallHandler
                        }
                        if (call.arguments == true) {
                            controller.systemBarsBehavior =
                                WindowInsetsController.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
                            controller.hide(WindowInsets.Type.systemBars())
                        } else {
                            controller.show(WindowInsets.Type.systemBars())
                        }
                    }
                    result.success(null)
                }
            }
    }
}
