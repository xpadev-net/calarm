package dev.xpa.calarm

import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        AndroidAlarmBridge(this).register(flutterEngine.dartExecutor.binaryMessenger)
    }
}
