package com.attackcapital.ai_scribe_copilot

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        // Register audio level monitor plugin
        flutterEngine.plugins.add(AudioLevelMonitor())
        
        // Register recording share handler plugin
        flutterEngine.plugins.add(RecordingShareHandler())
    }
}
