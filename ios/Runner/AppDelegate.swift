import Flutter
import UIKit
import AVFoundation

// Background Audio Recorder Plugin
class BackgroundAudioRecorder: NSObject, FlutterPlugin {
    private var audioRecorder: AVAudioRecorder?
    private var isRecording = false
    private var isPaused = false
    
    static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: "ai_scribe_copilot/audio_recorder", binaryMessenger: registrar.messenger())
        let instance = BackgroundAudioRecorder()
        registrar.addMethodCallDelegate(instance, channel: channel)
    }
    
    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "startRecording":
            guard let args = call.arguments as? [String: Any],
                  let path = args["path"] as? String,
                  let sampleRate = args["sampleRate"] as? Int else {
                result(FlutterError(code: "INVALID_ARGUMENTS", message: "Missing required arguments", details: nil))
                return
            }
            startRecording(path: path, sampleRate: sampleRate, result: result)
            
        case "stopRecording":
            stopRecording(result: result)
            
        case "pauseRecording":
            pauseRecording(result: result)
            
        case "resumeRecording":
            resumeRecording(result: result)
            
        case "isRecording":
            result(isRecording && !isPaused)
            
        default:
            result(FlutterMethodNotImplemented)
        }
    }
    
    private func setupAudioSession() -> Bool {
        let audioSession = AVAudioSession.sharedInstance()
        do {
            // Use .record category as per Apple documentation for background recording
            // This ensures recording continues when app goes to background or screen locks
            try audioSession.setCategory(.record, mode: .default, options: [.allowBluetooth])
            try audioSession.setActive(true, options: [])
            
            return true
        } catch {
            print("Failed to setup audio session: \(error.localizedDescription)")
            return false
        }
    }
    
    private func startRecording(path: String, sampleRate: Int, result: @escaping FlutterResult) {
        // If already recording, just update to new path (for chunking)
        if isRecording && !isPaused {
            // Stop current recording first
            audioRecorder?.stop()
        }
        
        // Setup audio session
        guard setupAudioSession() else {
            result(FlutterError(code: "AUDIO_SESSION_ERROR", message: "Failed to setup audio session", details: nil))
            return
        }
        
        let url = URL(fileURLWithPath: path)
        
        // WAV format settings
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsFloatKey: false,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]
        
        do {
            audioRecorder = try AVAudioRecorder(url: url, settings: settings)
            audioRecorder?.prepareToRecord()
            audioRecorder?.record()
            isRecording = true
            isPaused = false
            result(true)
        } catch {
            result(FlutterError(code: "RECORDING_ERROR", message: "Failed to start recording: \(error.localizedDescription)", details: nil))
        }
    }
    
    private func stopRecording(result: @escaping FlutterResult) {
        guard let recorder = audioRecorder else {
            result(FlutterError(code: "NOT_RECORDING", message: "No recording in progress", details: nil))
            return
        }
        
        recorder.stop()
        isRecording = false
        isPaused = false
        let path = recorder.url.path
        audioRecorder = nil
        result(path)
    }
    
    private func pauseRecording(result: @escaping FlutterResult) {
        guard let recorder = audioRecorder, isRecording else {
            result(FlutterError(code: "NOT_RECORDING", message: "No recording in progress", details: nil))
            return
        }
        
        recorder.pause()
        isPaused = true
        result(true)
    }
    
    private func resumeRecording(result: @escaping FlutterResult) {
        guard let recorder = audioRecorder, isRecording else {
            result(FlutterError(code: "NOT_RECORDING", message: "No recording to resume", details: nil))
            return
        }
        
        recorder.record()
        isPaused = false
        result(true)
    }
}

// Audio Level Monitor Plugin
class AudioLevelMonitor: NSObject, FlutterPlugin, FlutterStreamHandler {
    private var eventSink: FlutterEventSink?
    private var audioRecorder: AVAudioRecorder?
    private var levelTimer: Timer?
    private var isMonitoring = false
    
    static func register(with registrar: FlutterPluginRegistrar) {
        let methodChannel = FlutterMethodChannel(name: "ai_scribe_copilot/audio_level", binaryMessenger: registrar.messenger())
        let eventChannel = FlutterEventChannel(name: "ai_scribe_copilot/audio_level_stream", binaryMessenger: registrar.messenger())
        let instance = AudioLevelMonitor()
        registrar.addMethodCallDelegate(instance, channel: methodChannel)
        eventChannel.setStreamHandler(instance)
    }
    
    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "startMonitoring":
            startMonitoring(result: result)
        case "stopMonitoring":
            stopMonitoring(result: result)
        default:
            result(FlutterMethodNotImplemented)
        }
    }
    
    // FlutterStreamHandler methods
    public func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        self.eventSink = events
        return nil
    }
    
    public func onCancel(withArguments arguments: Any?) -> FlutterError? {
        self.eventSink = nil
        return nil
    }
    
    private func startMonitoring(result: @escaping FlutterResult) {
        guard !isMonitoring else {
            result(true)
            return
        }
        
        // Setup audio session
        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(.record, mode: .measurement, options: [])
            try audioSession.setActive(true)
        } catch {
            result(FlutterError(code: "AUDIO_SESSION_ERROR", message: "Failed to setup audio session: \(error.localizedDescription)", details: nil))
            return
        }
        
        // Create a temporary file for the recorder (required by AVAudioRecorder)
        let tempDir = NSTemporaryDirectory()
        let tempFile = URL(fileURLWithPath: tempDir).appendingPathComponent("temp_audio_level.caf")
        
        // Configure recorder settings
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatAppleIMA4),
            AVSampleRateKey: 44100.0,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: 12800,
            AVLinearPCMBitDepthKey: 16,
            AVEncoderAudioQualityKey: AVAudioQuality.min.rawValue
        ]
        
        do {
            // Create recorder with metering enabled
            audioRecorder = try AVAudioRecorder(url: tempFile, settings: settings)
            audioRecorder?.isMeteringEnabled = true
            audioRecorder?.prepareToRecord()
            audioRecorder?.record()
            
            isMonitoring = true
            
            // Start timer to read audio levels at 10 Hz (every 100ms)
            levelTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
                self?.updateAudioLevel()
            }
            
            result(true)
        } catch {
            result(FlutterError(code: "RECORDER_ERROR", message: "Failed to create audio recorder: \(error.localizedDescription)", details: nil))
        }
    }
    
    private func stopMonitoring(result: @escaping FlutterResult) {
        levelTimer?.invalidate()
        levelTimer = nil
        
        audioRecorder?.stop()
        audioRecorder = nil
        
        isMonitoring = false
        
        // Deactivate audio session
        do {
            try AVAudioSession.sharedInstance().setActive(false)
        } catch {
            print("Failed to deactivate audio session: \(error)")
        }
        
        result(true)
    }
    
    private func updateAudioLevel() {
        guard let recorder = audioRecorder, let sink = eventSink else {
            return
        }
        
        // Update metering
        recorder.updateMeters()
        
        // Get average power in decibels (-160 to 0)
        let averagePower = recorder.averagePower(forChannel: 0)
        
        // Normalize to 0.0 - 1.0 range
        // -160 dB is silence, 0 dB is maximum
        // We'll use -50 dB as our minimum threshold for better visualization
        let minDb: Float = -50.0
        let maxDb: Float = 0.0
        
        let normalizedLevel: Double
        if averagePower < minDb {
            normalizedLevel = 0.0
        } else if averagePower >= maxDb {
            normalizedLevel = 1.0
        } else {
            // Linear interpolation between minDb and maxDb
            normalizedLevel = Double((averagePower - minDb) / (maxDb - minDb))
        }
        
        // Send to Flutter
        sink(normalizedLevel)
    }
}

// Recording Share Handler Plugin
class RecordingShareHandler: NSObject, FlutterPlugin {
    private weak var viewController: UIViewController?
    
    static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: "ai_scribe_copilot/recording_share", binaryMessenger: registrar.messenger())
        let instance = RecordingShareHandler()
        registrar.addMethodCallDelegate(instance, channel: channel)
    }
    
    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "shareRecording":
            guard let args = call.arguments as? [String: Any],
                  let chunkPaths = args["chunkPaths"] as? [String],
                  let sessionId = args["sessionId"] as? String else {
                result(FlutterError(code: "INVALID_ARGUMENTS", message: "Missing required arguments", details: nil))
                return
            }
            shareRecording(chunkPaths: chunkPaths, sessionId: sessionId, result: result)
            
        default:
            result(FlutterMethodNotImplemented)
        }
    }
    
    private func shareRecording(chunkPaths: [String], sessionId: String, result: @escaping FlutterResult) {
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                // Combine chunks into a single WAV file
                let combinedFileURL = try self.combineWAVChunks(chunkPaths: chunkPaths, sessionId: sessionId)
                
                // Present share sheet on main thread
                DispatchQueue.main.async {
                    self.presentShareSheet(fileURL: combinedFileURL, result: result)
                }
            } catch {
                DispatchQueue.main.async {
                    result(FlutterError(code: "COMBINE_ERROR", message: "Failed to combine audio chunks: \(error.localizedDescription)", details: nil))
                }
            }
        }
    }
    
    private func combineWAVChunks(chunkPaths: [String], sessionId: String) throws -> URL {
        guard !chunkPaths.isEmpty else {
            throw NSError(domain: "RecordingShareHandler", code: 1, userInfo: [NSLocalizedDescriptionKey: "No chunks to combine"])
        }
        
        // Read first chunk to get WAV header
        let firstChunkURL = URL(fileURLWithPath: chunkPaths[0])
        let firstChunkData = try Data(contentsOf: firstChunkURL)
        
        // WAV header is 44 bytes
        let headerSize = 44
        guard firstChunkData.count > headerSize else {
            throw NSError(domain: "RecordingShareHandler", code: 2, userInfo: [NSLocalizedDescriptionKey: "Invalid WAV file"])
        }
        
        let header = firstChunkData.prefix(headerSize)
        
        // Collect all audio data (skip headers from each chunk)
        var combinedAudioData = Data()
        for chunkPath in chunkPaths {
            let chunkURL = URL(fileURLWithPath: chunkPath)
            let chunkData = try Data(contentsOf: chunkURL)
            
            // Skip header and append audio data
            if chunkData.count > headerSize {
                combinedAudioData.append(chunkData.suffix(from: headerSize))
            }
        }
        
        // Create output file in temporary directory
        let tempDir = FileManager.default.temporaryDirectory
        let outputFileName = "recording_\(sessionId).wav"
        let outputURL = tempDir.appendingPathComponent(outputFileName)
        
        // Remove existing file if present
        try? FileManager.default.removeItem(at: outputURL)
        
        // Create new WAV file with updated header
        var finalData = Data(header)
        
        // Update file size in header (bytes 4-7)
        let fileSize = UInt32(combinedAudioData.count + headerSize - 8)
        var fileSizeBytes = fileSize.littleEndian
        finalData.replaceSubrange(4..<8, with: Data(bytes: &fileSizeBytes, count: 4))
        
        // Update data chunk size (bytes 40-43)
        var dataSize = UInt32(combinedAudioData.count).littleEndian
        finalData.replaceSubrange(40..<44, with: Data(bytes: &dataSize, count: 4))
        
        // Append audio data
        finalData.append(combinedAudioData)
        
        // Write to file
        try finalData.write(to: outputURL)
        
        print("Combined \(chunkPaths.count) chunks into \(outputURL.path)")
        return outputURL
    }
    
    private func presentShareSheet(fileURL: URL, result: @escaping FlutterResult) {
        // Get the root view controller
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = windowScene.windows.first,
              let rootViewController = window.rootViewController else {
            result(FlutterError(code: "NO_VIEW_CONTROLLER", message: "Could not find view controller", details: nil))
            return
        }
        
        // Create activity view controller
        let activityViewController = UIActivityViewController(
            activityItems: [fileURL],
            applicationActivities: nil
        )
        
        // For iPad, set source view
        if let popoverController = activityViewController.popoverPresentationController {
            popoverController.sourceView = rootViewController.view
            popoverController.sourceRect = CGRect(x: rootViewController.view.bounds.midX, y: rootViewController.view.bounds.midY, width: 0, height: 0)
            popoverController.permittedArrowDirections = []
        }
        
        // Handle completion
        activityViewController.completionWithItemsHandler = { activityType, completed, returnedItems, error in
            // Clean up temporary file
            try? FileManager.default.removeItem(at: fileURL)
            
            if let error = error {
                result(FlutterError(code: "SHARE_ERROR", message: error.localizedDescription, details: nil))
            } else {
                result(completed)
            }
        }
        
        // Present the share sheet
        rootViewController.present(activityViewController, animated: true)
    }
}

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    
    // Register native audio recorder plugin
    let controller = window?.rootViewController as! FlutterViewController
    BackgroundAudioRecorder.register(with: controller.registrar(forPlugin: "BackgroundAudioRecorder")!)
    
    // Register audio level monitor plugin
    AudioLevelMonitor.register(with: controller.registrar(forPlugin: "AudioLevelMonitor")!)
    
    // Register recording share handler plugin
    RecordingShareHandler.register(with: controller.registrar(forPlugin: "RecordingShareHandler")!)
    
    // Configure audio session for background recording at app launch
    // Using .record category as per Apple documentation
    do {
      let audioSession = AVAudioSession.sharedInstance()
      try audioSession.setCategory(.record, mode: .default, options: [.allowBluetooth])
      try audioSession.setActive(true, options: [])
    } catch {
      print("Failed to set up audio session: \(error)")
    }
    
    // Observe audio session interruptions (phone calls, etc.)
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(handleInterruption),
      name: AVAudioSession.interruptionNotification,
      object: AVAudioSession.sharedInstance()
    )
    
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
  
  @objc func handleInterruption(notification: Notification) {
    guard let userInfo = notification.userInfo,
          let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
          let type = AVAudioSession.InterruptionType(rawValue: typeValue) else {
      return
    }
    
    switch type {
    case .began:
      // Audio session was interrupted (phone call, etc.)
      print("Audio session interrupted")
      
    case .ended:
      // Audio session interruption ended
      guard let optionsValue = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt else {
        return
      }
      let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
      if options.contains(.shouldResume) {
        // Resume recording after interruption
        do {
          try AVAudioSession.sharedInstance().setActive(true, options: [])
          print("Audio session resumed after interruption")
        } catch {
          print("Failed to resume audio session: \(error)")
        }
      }
      
    @unknown default:
      break
    }
  }
  
  deinit {
    NotificationCenter.default.removeObserver(self)
  }
}
