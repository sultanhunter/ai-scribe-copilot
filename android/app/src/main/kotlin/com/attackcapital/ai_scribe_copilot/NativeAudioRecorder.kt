package com.attackcapital.ai_scribe_copilot

import android.media.AudioFormat
import android.media.AudioRecord
import android.media.MediaRecorder
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import java.io.File
import java.io.FileOutputStream
import java.io.RandomAccessFile
import java.util.concurrent.atomic.AtomicBoolean
import kotlin.concurrent.thread

import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.PowerManager

class NativeAudioRecorder : FlutterPlugin, MethodCallHandler {
    private lateinit var channel: MethodChannel
    private lateinit var context: Context
    private var audioRecord: AudioRecord? = null
    private var recordingThread: Thread? = null
    private var wakeLock: PowerManager.WakeLock? = null
    private val isRecording = AtomicBoolean(false)
    private val isPaused = AtomicBoolean(false)
    private var filePath: String? = null
    private var sampleRate = 16000
    private var bufferSize = 0

    override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        context = flutterPluginBinding.applicationContext
        channel = MethodChannel(flutterPluginBinding.binaryMessenger, "ai_scribe_copilot/audio_recorder")
        channel.setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: Result) {
        when (call.method) {
            "startRecording" -> {
                val path = call.argument<String>("path")
                val rate = call.argument<Int>("sampleRate")
                if (path != null && rate != null) {
                    startRecording(path, rate, result)
                } else {
                    result.error("INVALID_ARGUMENTS", "Path or sampleRate is null", null)
                }
            }
            "stopRecording" -> stopRecording(result)
            "pauseRecording" -> pauseRecording(result)
            "resumeRecording" -> resumeRecording(result)
            "isRecording" -> result.success(isRecording.get())
            else -> result.notImplemented()
        }
    }

    private fun startRecording(path: String, rate: Int, result: Result) {
        if (isRecording.get()) {
            result.error("ALREADY_RECORDING", "Recording is already in progress", null)
            return
        }

        filePath = path
        sampleRate = rate
        bufferSize = AudioRecord.getMinBufferSize(
            sampleRate,
            AudioFormat.CHANNEL_IN_MONO,
            AudioFormat.ENCODING_PCM_16BIT
        )

        if (bufferSize == AudioRecord.ERROR || bufferSize == AudioRecord.ERROR_BAD_VALUE) {
            result.error("AUDIO_RECORD_INIT_ERROR", "Invalid buffer size", null)
            return
        }

        try {
            audioRecord = AudioRecord(
                MediaRecorder.AudioSource.MIC,
                sampleRate,
                AudioFormat.CHANNEL_IN_MONO,
                AudioFormat.ENCODING_PCM_16BIT,
                bufferSize
            )

            if (audioRecord?.state != AudioRecord.STATE_INITIALIZED) {
                result.error("AUDIO_RECORD_INIT_ERROR", "AudioRecord not initialized", null)
                return
            }

            // Acquire WakeLock with 10 minute timeout (will be renewed if recording continues)
            if (wakeLock == null) {
                val powerManager = context.getSystemService(Context.POWER_SERVICE) as PowerManager
                wakeLock = powerManager.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "AiScribeCopilot::RecordingWakeLock")
                wakeLock?.setReferenceCounted(false)
            }
            wakeLock?.acquire(10 * 60 * 1000L) // 10 minutes

            // Start foreground service
            val serviceIntent = Intent(context, RecordingForegroundService::class.java)
            serviceIntent.action = RecordingForegroundService.ACTION_START_RECORDING
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(serviceIntent)
            } else {
                context.startService(serviceIntent)
            }

            audioRecord?.startRecording()
            isRecording.set(true)
            isPaused.set(false)

            recordingThread = thread(start = true) {
                writeAudioDataToFile()
            }

            result.success(true)
        } catch (e: Exception) {
            releaseWakeLock()
            result.error("START_RECORDING_FAILED", e.message, null)
        }
    }

    private fun writeAudioDataToFile() {
        val file = File(filePath!!)
        if (file.exists()) {
            file.delete()
        }
        
        val outputStream = FileOutputStream(file)
        val data = ByteArray(bufferSize)

        // Write initial valid header with 0 data size
        outputStream.write(createWavHeader(0))

        while (isRecording.get()) {
            if (!isPaused.get()) {
                val read = audioRecord?.read(data, 0, bufferSize) ?: 0
                if (read > 0) {
                    outputStream.write(data, 0, read)
                }
            } else {
                try {
                    Thread.sleep(100)
                } catch (e: InterruptedException) {
                    e.printStackTrace()
                }
            }
        }

        outputStream.close()
        updateWavHeader(file)
    }



    private fun pauseRecording(result: Result) {
        if (isRecording.get() && !isPaused.get()) {
            isPaused.set(true)
            try {
                audioRecord?.stop()
            } catch (e: Exception) {
                // Ignore error if already stopped
            }
            result.success(true)
        } else {
            result.success(false)
        }
    }

    private fun resumeRecording(result: Result) {
        if (isRecording.get() && isPaused.get()) {
            try {
                audioRecord?.startRecording()
                isPaused.set(false)
                result.success(true)
            } catch (e: Exception) {
                result.error("RESUME_FAILED", e.message, null)
            }
        } else {
            result.success(false)
        }
    }

    private fun updateWavHeader(file: File) {
        val audioLen = file.length() - 44
        
        val randomAccessFile = RandomAccessFile(file, "rw")
        randomAccessFile.seek(0)
        randomAccessFile.write(createWavHeader(audioLen))
        randomAccessFile.close()
    }

    private fun createWavHeader(audioLen: Long): ByteArray {
        val totalDataLen = audioLen + 36
        val byteRate = sampleRate * 1 * 16 / 8
        val header = ByteArray(44)
        val channels = 1
        val bitDepth = 16
        
        // RIFF
        header[0] = 'R'.code.toByte()
        header[1] = 'I'.code.toByte()
        header[2] = 'F'.code.toByte()
        header[3] = 'F'.code.toByte()
        
        // File Size
        header[4] = (totalDataLen and 0xff).toByte()
        header[5] = ((totalDataLen shr 8) and 0xff).toByte()
        header[6] = ((totalDataLen shr 16) and 0xff).toByte()
        header[7] = ((totalDataLen shr 24) and 0xff).toByte()
        
        // WAVE
        header[8] = 'W'.code.toByte()
        header[9] = 'A'.code.toByte()
        header[10] = 'V'.code.toByte()
        header[11] = 'E'.code.toByte()
        
        // fmt
        header[12] = 'f'.code.toByte()
        header[13] = 'm'.code.toByte()
        header[14] = 't'.code.toByte()
        header[15] = ' '.code.toByte()
        
        // Subchunk1Size (16 for PCM)
        header[16] = 16
        header[17] = 0
        header[18] = 0
        header[19] = 0
        
        // AudioFormat (1 for PCM)
        header[20] = 1
        header[21] = 0
        
        // NumChannels
        header[22] = channels.toByte()
        header[23] = 0
        
        // SampleRate
        header[24] = (sampleRate and 0xff).toByte()
        header[25] = ((sampleRate shr 8) and 0xff).toByte()
        header[26] = ((sampleRate shr 16) and 0xff).toByte()
        header[27] = ((sampleRate shr 24) and 0xff).toByte()
        
        // ByteRate
        header[28] = (byteRate and 0xff).toByte()
        header[29] = ((byteRate shr 8) and 0xff).toByte()
        header[30] = ((byteRate shr 16) and 0xff).toByte()
        header[31] = ((byteRate shr 24) and 0xff).toByte()
        
        // BlockAlign
        header[32] = (channels * bitDepth / 8).toByte()
        header[33] = 0
        
        // BitsPerSample
        header[34] = bitDepth.toByte()
        header[35] = 0
        
        // data
        header[36] = 'd'.code.toByte()
        header[37] = 'a'.code.toByte()
        header[38] = 't'.code.toByte()
        header[39] = 'a'.code.toByte()
        
        // Subchunk2Size
        header[40] = (audioLen and 0xff).toByte()
        header[41] = ((audioLen shr 8) and 0xff).toByte()
        header[42] = ((audioLen shr 16) and 0xff).toByte()
        header[43] = ((audioLen shr 24) and 0xff).toByte()
        
        return header
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        stopRecording(null)
    }

    private fun stopRecording(result: Result?) {
        if (!isRecording.get()) {
            result?.success(null)
            return
        }

        isRecording.set(false)
        isPaused.set(false)
        
        try {
            audioRecord?.stop()
            audioRecord?.release()
            audioRecord = null
            recordingThread?.join() // Wait for thread to finish writing
            releaseWakeLock()
            
            // Stop foreground service
            val serviceIntent = Intent(context, RecordingForegroundService::class.java)
            serviceIntent.action = RecordingForegroundService.ACTION_STOP_RECORDING
            context.startService(serviceIntent)
            
            result?.success(filePath)
        } catch (e: Exception) {
            releaseWakeLock()
            result?.error("STOP_RECORDING_FAILED", e.message, null)
        }
    }

    private fun releaseWakeLock() {
        if (wakeLock?.isHeld == true) {
            wakeLock?.release()
        }
    }
}
