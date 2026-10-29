# Firebase Cloud Messaging Setup Guide

This guide explains how to set up Firebase Cloud Messaging (FCM) for background push notifications in the RoadGuard AI Flutter app.

## Prerequisites

1. A Google/Firebase account
2. Flutter project already created
3. Android app package name: `com.example.pothole_detector`

## Setup Steps

### 1. Create Firebase Project

1. Go to [Firebase Console](https://console.firebase.google.com/)
2. Click "Add project" or select existing project
3. Enter project name (e.g., "RoadGuard AI")
4. Disable Google Analytics (optional for this app)
5. Click "Create project"

### 2. Add Android App to Firebase

1. In Firebase Console, click the Android icon to add Android app
2. Enter Android package name: `com.example.pothole_detector`
   - Find this in `android/app/build.gradle` under `applicationId`
3. Enter app nickname (optional): "RoadGuard AI Android"
4. Leave SHA-1 empty (not needed for FCM)
5. Click "Register app"

### 3. Download google-services.json

1. Download the `google-services.json` file
2. Place it in: `pothole-flutter-app/android/app/`
3. **IMPORTANT**: Do NOT commit this file to git (already in .gitignore)

### 4. Update Android Build Files

The following changes have already been made:

#### android/build.gradle
```gradle
dependencies {
    classpath 'com.google.gms:google-services:4.4.0'
}
```

#### android/app/build.gradle
Add at the bottom:
```gradle
apply plugin: 'com.google.gms.google-services'
```

### 5. Verify Installation

1. Install dependencies:
   ```bash
   cd pothole-flutter-app
   flutter pub get
   ```

2. Build the app:
   ```bash
   flutter build apk
   ```

3. If successful, Firebase is configured!

## Testing Background Notifications

### Option 1: Test from Flutter App

1. Open the app and log in
2. Go to Settings (if settings screen is available)
3. Enable "Background Pothole Alerts"
4. Grant "Allow all the time" location permission
5. Click "Test Alert Now" button
6. You should receive a notification if there are nearby potholes

### Option 2: Test with Background Task

1. Enable background alerts in the app
2. Close the app completely
3. Wait 15 minutes
4. If you're near a reported pothole (within 1km), you'll get a notification

### Option 3: Test from Firebase Console

1. Go to Firebase Console > Cloud Messaging
2. Click "Send your first message"
3. Enter notification title and text
4. Click "Send test message"
5. Enter your FCM token (printed in app logs on startup)
6. Click "Test"

## How Background Alerts Work

1. **WorkManager** runs a background task every 15 minutes
2. Task checks if background tracking is enabled
3. Gets current device location
4. Calls backend API `/potholes/nearby` with 1km radius
5. If severe potholes found:
   - Shows local notification with distance and count
   - Vibrates device
   - Won't repeat same alert within 15 minutes

## Notification Channels

The app creates three notification channels:

1. **pothole_alerts_high** - Severe pothole alerts (high priority, strong vibration)
2. **pothole_alerts** - Regular pothole alerts (normal priority)
3. **pothole_background_alerts** - Background detected potholes (max priority)

## Troubleshooting

### "Firebase not configured" error
- Make sure `google-services.json` is in `android/app/`
- Rebuild the app after adding the file

### Not receiving background notifications
- Check location permission is set to "Allow all the time"
- Verify background tracking is enabled in app
- Check battery optimization is disabled for the app
- Wait 15 minutes for first background check

### "Token not found" error
- Firebase initialization failed
- Check `google-services.json` is valid
- Check internet connection

## Battery Optimization

Android may kill background tasks to save battery. To prevent this:

1. Open device Settings
2. Go to Apps > RoadGuard AI
3. Battery > Battery optimization
4. Select "Don't optimize"

## Privacy Note

- Location is only tracked when background alerts are enabled
- Location data is only used to check nearby potholes
- No location history is stored on device or server
- Users can disable background tracking anytime

## Optional: Server-Side Push Notifications

If you want the backend server to send push notifications (not implemented yet):

1. Get Firebase Admin SDK credentials:
   - Firebase Console > Project Settings > Service Accounts
   - Click "Generate new private key"
   - Save JSON file securely on server

2. Update backend to use Firebase Admin SDK:
   ```python
   pip install firebase-admin
   ```

3. Send notifications from backend when:
   - Admin changes report status
   - New severe pothole reported in user's area
   - Work completed on nearby pothole

## Support

For issues with Firebase setup, refer to:
- [Firebase Flutter Setup](https://firebase.google.com/docs/flutter/setup)
- [FCM Flutter Guide](https://firebase.google.com/docs/cloud-messaging/flutter/client)
