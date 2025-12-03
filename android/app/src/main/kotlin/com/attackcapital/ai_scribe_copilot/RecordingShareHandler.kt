package com.attackcapital.ai_scribe_copilot

import android.content.Context
import android.content.Intent
import androidx.core.content.FileProvider
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream
import java.nio.ByteBuffer
import java.nio.ByteOrder

class RecordingShareHandler : FlutterPlugin, MethodChannel.MethodCallHandler {
    private lateinit var channel: MethodChannel
    private lateinit var context: Context

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, "ai_scribe_copilot/recording_share")
        channel.setMethodCallHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "shareRecording" -> {
                val chunkPaths = call.argument<List<String>>("chunkPaths")
                val sessionId = call.argument<String>("sessionId")

                if (chunkPaths == null || sessionId == null) {
                    result.error("INVALID_ARGUMENTS", "Missing required arguments", null)
                    return
                }

                shareRecording(chunkPaths, sessionId, result)
            }
            else -> result.notImplemented()
        }
    }

    private fun shareRecording(chunkPaths: List<String>, sessionId: String, result: MethodChannel.Result) {
        Thread {
            try {
                // Combine chunks into a single WAV file
                val combinedFile = combineWAVChunks(chunkPaths, sessionId)

                // Create content URI for sharing
                val contentUri = FileProvider.getUriForFile(
                    context,
                    "${context.packageName}.fileprovider",
                    combinedFile
                )

                // Create share intent
                val shareIntent = Intent(Intent.ACTION_SEND).apply {
                    type = "audio/wav"
                    putExtra(Intent.EXTRA_STREAM, contentUri)
                    addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                }

                // Start share activity
                val chooserIntent = Intent.createChooser(shareIntent, "Share Recording")
                chooserIntent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                context.startActivity(chooserIntent)

                // Return success
                result.success(true)

                // Clean up after a delay (5 seconds)
                Thread.sleep(5000)
                combinedFile.delete()
            } catch (e: Exception) {
                result.error("COMBINE_ERROR", "Failed to combine audio chunks: ${e.message}", null)
            }
        }.start()
    }

    private fun combineWAVChunks(chunkPaths: List<String>, sessionId: String): File {
        if (chunkPaths.isEmpty()) {
            throw IllegalArgumentException("No chunks to combine")
        }

        // Read first chunk to get WAV header
        val firstChunkFile = File(chunkPaths[0])
        val firstChunkData = firstChunkFile.readBytes()

        // WAV header is 44 bytes
        val headerSize = 44
        if (firstChunkData.size <= headerSize) {
            throw IllegalArgumentException("Invalid WAV file")
        }

        val header = firstChunkData.copyOfRange(0, headerSize)

        // Collect all audio data (skip headers from each chunk)
        val combinedAudioData = mutableListOf<Byte>()
        for (chunkPath in chunkPaths) {
            val chunkFile = File(chunkPath)
            val chunkData = chunkFile.readBytes()

            // Skip header and append audio data
            if (chunkData.size > headerSize) {
                combinedAudioData.addAll(chunkData.copyOfRange(headerSize, chunkData.size).toList())
            }
        }

        // Create output file in cache directory
        val outputFile = File(context.cacheDir, "recording_$sessionId.wav")
        if (outputFile.exists()) {
            outputFile.delete()
        }

        // Create new WAV file with updated header
        FileOutputStream(outputFile).use { output ->
            // Write header
            output.write(header)

            // Update file size in header (bytes 4-7)
            val fileSize = combinedAudioData.size + headerSize - 8
            val fileSizeBytes = ByteBuffer.allocate(4).order(ByteOrder.LITTLE_ENDIAN).putInt(fileSize).array()
            output.channel.position(4)
            output.write(fileSizeBytes)

            // Update data chunk size (bytes 40-43)
            val dataSize = combinedAudioData.size
            val dataSizeBytes = ByteBuffer.allocate(4).order(ByteOrder.LITTLE_ENDIAN).putInt(dataSize).array()
            output.channel.position(40)
            output.write(dataSizeBytes)

            // Append audio data
            output.channel.position(headerSize.toLong())
            output.write(combinedAudioData.toByteArray())
        }

        println("Combined ${chunkPaths.size} chunks into ${outputFile.path}")
        return outputFile
    }
}
