# Development Roadmap

## Phase 1: MVP Foundation ✅ COMPLETE

### Architecture & Setup

- [x] Project structure with clean architecture
- [x] Riverpod state management setup
- [x] Theme system (Light/Dark/System)
- [x] Localization (English/Hindi)
- [x] Data models with Hive
- [x] Service layer (API + Audio)
- [x] Basic UI screens

**Status**: All core foundation complete

---

## Phase 2: Backend Integration & Core Features 🎯 NEXT

### Priority 1: Backend Development

- [ ] Create Node.js/Express backend (or your choice)
- [ ] Implement all API endpoints:
  - [ ] POST /v1/upload-session
  - [ ] POST /v1/get-presigned-url
  - [ ] PUT {presignedUrl} (S3 or similar)
  - [ ] POST /v1/notify-chunk-uploaded
  - [ ] GET /v1/patients?userId={userId}
  - [ ] POST /v1/add-patient-ext
  - [ ] GET /v1/fetch-session-by-patient/{patientId}
- [ ] Setup S3 or local file storage
- [ ] Docker containerization
- [ ] Deploy to cloud (AWS/Heroku/DigitalOcean)

### Priority 2: Complete Audio Streaming

- [ ] Implement actual file upload in `_uploadChunk`
- [ ] Read audio file from local path
- [ ] Upload to presigned URL
- [ ] Handle upload failures
- [ ] Implement retry logic (exponential backoff)
- [ ] Queue failed chunks for later upload
- [ ] Persist queue to Hive
- [ ] Background upload worker

### Priority 3: Offline Support

- [ ] Create upload queue manager
- [ ] Store failed chunks in Hive
- [ ] Detect network changes with connectivity_plus
- [ ] Auto-retry when network returns
- [ ] Show upload status in UI
- [ ] Handle app restart with pending uploads

**Estimated Time**: 2-3 days

---

## Phase 3: Background & Interruption Handling 🔧

### iOS Background Audio

- [ ] Configure audio session in Swift
- [ ] Add background audio capability
- [ ] Test recording with screen locked
- [ ] Handle interruptions (calls, alarms)
- [ ] Test app switching scenarios

### Android Foreground Service

- [ ] Create foreground service in Kotlin
- [ ] Show notification during recording
- [ ] Add pause/resume controls to notification
- [ ] Handle service lifecycle
- [ ] Test with app in background

### App Lifecycle Management

- [ ] Detect phone calls (platform channels)
- [ ] Auto-pause on call start
- [ ] Auto-resume after call ends
- [ ] Handle app backgrounding
- [ ] Recover state after app kill
- [ ] Save session state periodically

**Estimated Time**: 2-3 days

---

## Phase 4: Native Features 📱

### Camera Integration

- [ ] Add image_picker package
- [ ] Create patient photo capture
- [ ] Store photos locally
- [ ] Upload photos to backend
- [ ] Display patient photos in list

### Native Share

- [ ] Add share_plus package
- [ ] Share recording sessions
- [ ] Share transcriptions (when available)
- [ ] Platform-specific share UI

### System Integration

- [ ] Haptic feedback on key actions
- [ ] System notifications with actions
- [ ] Respect Do Not Disturb mode
- [ ] Battery optimization handling

**Estimated Time**: 1-2 days

---

## Phase 5: Polish & Production Ready 🎨

### UI/UX Improvements

- [ ] Splash screen
- [ ] App icon design
- [ ] Adaptive icons (Android)
- [ ] Loading states everywhere
- [ ] Error messages user-friendly
- [ ] Empty states for all screens
- [ ] Pull to refresh on patient list

### Accessibility

- [ ] Screen reader support
- [ ] Dynamic type support
- [ ] High contrast mode
- [ ] Keyboard navigation
- [ ] ARIA labels

### Performance

- [ ] Optimize audio chunk size
- [ ] Reduce memory usage
- [ ] Lazy load patient list
- [ ] Image caching
- [ ] Network request caching

### Testing

- [ ] Unit tests for services
- [ ] Widget tests for screens
- [ ] Integration tests
- [ ] Platform-specific tests
- [ ] Performance testing

**Estimated Time**: 2-3 days

---

## Phase 6: Advanced Features (Bonus) ⭐

### On-Device Transcription

- [ ] Add speech_to_text package
- [ ] iOS Speech framework integration
- [ ] Android SpeechRecognizer integration
- [ ] Live transcription preview
- [ ] Confidence scores
- [ ] Speaker diarization (if possible)

### Analytics & Monitoring

- [ ] Firebase Analytics
- [ ] Crashlytics
- [ ] Performance monitoring
- [ ] User behavior tracking
- [ ] Error reporting

### Professional Features

- [ ] Session notes
- [ ] Patient history
- [ ] Search functionality
- [ ] Export transcriptions
- [ ] Share via email
- [ ] Cloud backup

**Estimated Time**: 3-4 days

---

## Testing Scenarios (Must Pass)

### Test 1: Long Recording with Lock

```
1. Start 5-minute recording
2. Lock phone
3. Leave locked for full duration
4. Unlock and verify
✅ Pass: Audio streams to backend, no data loss
```

### Test 2: Phone Call Interruption

```
1. Start recording
2. Receive phone call
3. Answer and talk
4. End call
✅ Pass: Auto-pause, auto-resume, no audio lost
```

### Test 3: Network Outage

```
1. Start recording
2. Enable airplane mode
3. Continue recording
4. Disable airplane mode
✅ Pass: Chunks queue locally, upload when connected
```

### Test 4: App Switching

```
1. Start recording
2. Open camera app
3. Take photo
4. Return to app
✅ Pass: Recording continues, proper native integration
```

### Test 5: App Kill

```
1. Start recording
2. Force kill app
3. Reopen app
✅ Pass: Graceful recovery, clear session state
```

---

## Build & Deployment Checklist

### Android

- [ ] Update versionCode in build.gradle
- [ ] Update versionName in build.gradle
- [ ] Test on physical device
- [ ] Build release APK: `flutter build apk --release`
- [ ] Upload to GitHub Releases
- [ ] Add download link to README

### iOS

- [ ] Update version in Xcode
- [ ] Configure code signing
- [ ] Test on physical iPhone
- [ ] Record comprehensive Loom video
- [ ] Test all features in video
- [ ] Add video link to README

### Backend

- [ ] Create Dockerfile
- [ ] Create docker-compose.yml
- [ ] Test: `docker-compose up`
- [ ] Deploy to production
- [ ] Update backend URL in app
- [ ] Add deployment URL to README

### Documentation

- [ ] Update README with all links
- [ ] Add setup instructions
- [ ] Record demo video (5 minutes)
- [ ] Show all test scenarios
- [ ] Submit deliverables

---

## Time Estimates

| Phase     | Description                | Time           |
| --------- | -------------------------- | -------------- |
| Phase 1   | MVP Foundation             | ✅ Complete    |
| Phase 2   | Backend & Streaming        | 2-3 days       |
| Phase 3   | Background & Interruptions | 2-3 days       |
| Phase 4   | Native Features            | 1-2 days       |
| Phase 5   | Polish & Production        | 2-3 days       |
| Phase 6   | Bonus Features             | 3-4 days       |
| **Total** | **Full Implementation**    | **10-15 days** |

---

## Current Progress

**Completed**: Phase 1 (MVP Foundation)  
**Next Up**: Phase 2 (Backend Integration)  
**Overall**: ~20% complete

The solid foundation is in place. Now focus on connecting everything together and handling edge cases!
