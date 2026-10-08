package app.darkelektron.klotter

import android.os.Bundle
import androidx.activity.enableEdgeToEdge
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterFragmentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        enableEdgeToEdge()
        super.onCreate(savedInstanceState)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // The phone's own font, for the System choice in Settings; see
        // SystemFont, and lib/utils/system_font.dart for the other end.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "klotter/system_font")
            .setMethodCallHandler { call, result ->
                if (call.method != "flipFont") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                // Off the main thread: it opens and measures other apps' fonts.
                Thread {
                    val bytes = try {
                        SystemFont.flipFontBytes(applicationContext)
                    } catch (e: Exception) {
                        null
                    }
                    runOnUiThread { result.success(bytes) }
                }.start()
            }
    }
}
