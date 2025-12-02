# AI Scribe Copilot - Medical Transcription App MVP

A Flutter-based medical transcription app that records audio during medical consultations and streams it to a backend for AI transcription. Built with production-grade architecture and resilience.

## 🚀 Current Status: MVP Complete

### ✅ Implemented Features

#### Core Functionality

- **Patient Management**
  - List all patients
  - Add new patients with details (name, phone, email, age)
  - Select patient for recording session
- **Audio Recording**
  - Real-time audio recording with native microphone access
  - Audio level visualization
  - Pause/Resume recording
  - Recording duration timer
  - Chunk-based audio streaming (5-second chunks)
- **Theme & Localization** (State Management Test)

  - ✅ Dark/Light/System theme switching
  - ✅ Persistent theme preference (no restart required)
  - ✅ English/Hindi language support
  - ✅ Persistent language preference (no restart required)
  - ✅ Full UI translation system

- **State Management**
  - Using **Riverpod** for robust state management
  - Persistent storage with SharedPreferences
  - Hive for local data caching

#### Technical Architecture

- **Clean Architecture**: Separated into features, core, models, services, and providers
- **Riverpod State Management**: Type-safe, compile-time checked state management
- **Service Layer**: API service for backend communication, Audio recording service
- **Data Models**: Patient, RecordingSession, AudioChunk with Hive persistence
- **Localization**: JSON-based translation system supporting English and Hindi

## 📦 Project Structure

```
lib/
├── core/
│   ├── constants/
│   │   └── app_constants.dart       # App-wide constants
│   ├── localization/
│   │   └── app_localizations.dart   # Localization system
│   └── theme/
│       └── app_theme.dart           # Light & dark themes
├── features/
│   ├── patients/
│   │   └── patients_screen.dart     # Patient list & add patient
│   ├── recording/
│   │   └── recording_screen.dart    # Recording interface
│   └── settings/
│       └── settings_screen.dart     # Theme & language settings
├── models/
│   ├── audio_chunk.dart             # Audio chunk data model
│   ├── patient.dart                 # Patient data model
│   └── recording_session.dart       # Recording session model
├── providers/
│   ├── app_providers.dart           # Theme & locale providers
│   ├── patient_providers.dart       # Patient state providers
│   └── service_providers.dart       # Service instances
├── services/
│   ├── api_service.dart             # Backend API communication
│   └── audio_recording_service.dart # Native audio recording
└── main.dart                         # App entry point

assets/
└── translations/
    ├── en.json                       # English translations
    └── hi.json                       # Hindi translations
```

## 🛠️ Setup Instructions

### Prerequisites

- Flutter SDK 3.10.0 or higher
- Xcode (for iOS development)
- Android Studio (for Android development)

### Installation

1. **Clone the repository**

```bash
git clone <your-repo-url>
cd ai-scribe-copilot
```

2. **Install dependencies**

```bash
flutter pub get
```

3. **Generate code (Hive adapters, etc.)**

```bash
flutter pub run build_runner build --delete-conflicting-outputs
```

4. **Configure Backend URL**
   Edit `lib/core/constants/app_constants.dart`:

```dart
static const String baseUrl = 'YOUR_BACKEND_URL';
```

5. **Run the app**

```bash
# iOS
flutter run -d ios

# Android
flutter run -d android
```

### Building Release Versions

**Android APK:**

```bash
flutter build apk --release
```

APK location: `build/app/outputs/flutter-apk/app-release.apk`

**iOS:**

```bash
flutter build ios --release
```

## 📱 Platform Configuration

### Android Permissions

Already configured in `android/app/src/main/AndroidManifest.xml`:

- Microphone permission
- Storage permissions
- Internet access

### iOS Permissions

Add to `ios/Runner/Info.plist`:

```xml
<key>NSMicrophoneUsageDescription</key>
<string>This app needs microphone access to record patient consultations</string>
```

## 🎯 State Management Choice: Riverpod

**Why Riverpod?**

- ✅ **Compile-time safety**: Catches errors before runtime
- ✅ **No BuildContext needed**: Access state from anywhere
- ✅ **Built-in async support**: Perfect for API calls and streaming
- ✅ **Easy testing**: Providers can be easily mocked
- ✅ **Hot reload friendly**: State persists across rebuilds
- ✅ **Better than Provider**: More modern, safer, more features
- ✅ **Perfect for this use case**: Handles theme/locale persistence, async API calls, and streaming audio

## 🔧 Key Technologies

| Technology        | Purpose                  | Version |
| ----------------- | ------------------------ | ------- |
| Flutter           | Cross-platform framework | 3.10.0+ |
| Riverpod          | State management         | 2.5.1   |
| Hive              | Local database           | 2.2.3   |
| Dio               | HTTP client              | 5.7.0   |
| Record            | Audio recording          | 5.1.2   |
| SharedPreferences | Settings persistence     | 2.3.2   |

## 🎨 Features Showcase

### Theme Switching (No Restart Required)

- System theme detection
- Manual dark/light mode toggle
- Persistent across app restarts

### Language Switching (No Restart Required)

- English (en)
- Hindi (hi)
- Full UI translation
- Persistent across app restarts

### Recording Features

- Real-time audio level visualization
- Pause/Resume functionality
- Chunk-based streaming
- Upload progress tracking
- Session persistence

## 📋 What's Next?

### To Complete Full Requirements:

1. **Background Recording**
   - iOS: Configure background audio mode
   - Android: Implement foreground service
2. **Interruption Handling**
   - Phone call detection and auto-pause/resume
   - App lifecycle management
   - Network reconnection logic
3. **Chunk Upload System**
   - Implement actual file upload to presigned URLs
   - Retry logic for failed uploads
   - Queue management for offline chunks
4. **Native Platform Features**
   - Camera integration for patient ID
   - Native share sheet
   - Haptic feedback
   - System notifications
5. **Backend Development**
   - Mock backend with Docker
   - Implement all API endpoints
   - Deploy live version

## 🧪 Testing the MVP

```bash
# Run the app
flutter run

# Test features:
1. Open Settings → Switch theme (observe immediate change)
2. Open Settings → Switch language (observe immediate change)
3. Add a patient from patients screen
4. Select patient → Start recording
5. Observe audio level visualization
6. Pause and resume recording
7. Stop recording
```

## 📝 Notes

- Backend URL needs to be configured before API features work
- Currently using mock/offline mode for patient data
- Audio recording works with microphone permissions granted
- Chunk upload logic is stubbed out (marked with TODOs)

## 🔗 Resources

- **API Documentation**: https://docs.google.com/document/d/1hzfry0fg7qQQb39cswEychYMtBiBKDAqIg6LamAKENI/edit?usp=sharing
- **Postman Collection**: https://drive.google.com/file/d/1rnEjRzH64ESlIi5VQekG525Dsf8IQZTP/view?usp=sharing

## Flutter Version

```
Flutter 3.38.3 • channel stable
Framework • revision 19074d12f7 (11 days ago)
Engine • revision 8bf2090718fea3655f466049a757f823898f0ad1
Tools • Dart 3.10.1 • DevTools 2.51.1
```

## 👨‍💻 Development

Built with clean architecture principles and production-ready patterns. The codebase is organized for scalability and maintainability.

### State Management Architecture

- **App-level state**: Theme, Locale (persisted)
- **Feature state**: Patients, Recording session
- **Service providers**: API service, Audio service (singleton)

### Code Generation

This project uses code generation for:

- Hive type adapters (run `flutter pub run build_runner build`)

---

**Status**: MVP Complete ✅  
**Next Steps**: Implement background recording, interruption handling, and full chunk upload system
