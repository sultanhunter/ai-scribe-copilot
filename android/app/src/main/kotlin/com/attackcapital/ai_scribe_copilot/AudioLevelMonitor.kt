package com.attackcapital.ai_scribe_copilot

import android.media.MediaRecorder
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.embedding.engine.plugins.FlutterPlugin
import java.io.File
import kotlin.math.log10

class AudioLevelMonitor : FlutterPlugin, MethodChannel.MethodCallHandler, EventChannel.StreamHandler {
    private var methodChannel: MethodChannel? = null
    private var eventChannel: EventChannel? = null
    private var eventSink: EventChannel.EventSink? = null
    
    private var mediaRecorder: MediaRecorder? = null
    private var isMonitoring = false
    private val handler = Handler(Looper.getMainLooper())
    private var levelRunnable: Runnable? = null
    private var tempFile: File? = null
    
    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        methodChannel = MethodChannel(binding.binaryMessenger, "ai_scribe_copilot/audio_level")
        methodChannel?.setMethodCallHandler(this)
        
        eventChannel = EventChannel(binding.binaryMessenger, "ai_scribe_copilot/audio_level_stream")
        eventChannel?.setStreamHandler(this)
    }
    
    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        methodChannel?.setMethodCallHandler(null)
        methodChannel = null
        
        eventChannel?.setStreamHandler(null)
        eventChannel = null
    }
    
    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "startMonitoring" -> startMonitoring(result)
            "stopMonitoring" -> stopMonitoring(result)
            else -> result.notImplemented()
        }
    }
    
    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        eventSink = events
    }
    
    override fun onCancel(arguments: Any?) {
        eventSink = null
    }
    
    private fun startMonitoring(result: MethodChannel.Result) {
        if (isMonitoring) {
            result.success(true)
            return
        }
        
        try {
            // Create a temporary file for recording
            tempFile = File.createTempFile("audio_level", ".3gp")
            
            // Initialize MediaRecorder
            mediaRecorder = MediaRecorder().apply {
                setAudioSource(MediaRecorder.AudioSource.MIC)
                setOutputFormat(MediaRecorder.OutputFormat.THREE_GPP)
                setAudioEncoder(MediaRecorder.AudioEncoder.AMR_NB)
                setOutputFile(tempFile?.absolutePath)
                prepare()
                start()
            }
            
            isMonitoring = true
            
            // Start polling audio levels at 10 Hz (every 100ms)
            levelRunnable = object : Runnable {
                override fun run() {
                    updateAudioLevel()
                    if (isMonitoring) {
                        handler.postDelayed(this, 100)
                    }
                }
            }
            handler.post(levelRunnable!!)
            
            result.success(true)
        } catch (e: Exception) {
            result.error("RECORDER_ERROR", "Failed to start monitoring: ${e.message}", null)
        }
    }
    
    private fun stopMonitoring(result: MethodChannel.Result) {
        try {
            isMonitoring = false
            
            // Stop the handler
            levelRunnable?.let { handler.removeCallbacks(it) }
            levelRunnable = null
            
            // Stop and release MediaRecorder
            mediaRecorder?.apply {
                try {
                    stop()
                } catch (e: Exception) {
                    // Ignore stop errors
                }
                release()
            }
            mediaRecorder = null
            
            // Delete temp file
            tempFile?.delete()
            tempFile = null
            
            result.success(true)
        } catch (e: Exception) {
            result.error("STOP_ERROR", "Failed to stop monitoring: ${e.message}", null)
        }
    }
    
    private fun updateAudioLevel() {
        try {
            val amplitude = mediaRecorder?.maxAmplitude ?: 0
            
            // Normalize amplitude to 0.0 - 1.0 range
            // MediaRecorder.getMaxAmplitude() returns 0-32767
            val normalizedLevel = if (amplitude > 0) {
                // Convert to decibels and normalize
                // Reference: 20 * log10(amplitude / 32767)
                val db = 20 * log10(amplitude.toDouble() / 32767.0)
                
                // Map from -50 dB to 0 dB range to 0.0 - 1.0
                val minDb = -50.0
                val maxDb = 0.0
                
                when {
                    db < minDb -> 0.0
                    db >= maxDb -> 1.0
                    else -> (db - minDb) / (maxDb - minDb)
                }
            } else {
                0.0
            }
            
            // Send to Flutter
            handler.post {
                eventSink?.success(normalizedLevel)
            }
        } catch (e: Exception) {
            // Ignore errors during level reading
        }
    }
}
