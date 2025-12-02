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
