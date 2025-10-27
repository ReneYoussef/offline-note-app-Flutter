# 🔥 Firebase Setup Guide for Offline Notes App

## **Step 1: Create Firebase Project**

1. Go to [Firebase Console](https://console.firebase.google.com/)
2. Click **"Add project"** or **"Create a project"**
3. Enter project name: `offline-note-app` (or your preferred name)
4. Enable Google Analytics (optional)
5. Click **"Create project"**

## **Step 2: Enable Firestore Database**

1. In your Firebase project, go to **"Firestore Database"**
2. Click **"Create database"**
3. Choose **"Start in test mode"** (for development)
4. Select a location (choose closest to your users)
5. Click **"Done"**

## **Step 3: Add Flutter App to Firebase**

### **For Android:**
1. Click **"Add app"** → **Android icon**
2. Enter package name: `com.example.offline_note_app`
3. Download `google-services.json`
4. Replace the file in `android/app/google-services.json`

### **For iOS:**
1. Click **"Add app"** → **iOS icon**
2. Enter bundle ID: `com.example.offlineNoteApp`
3. Download `GoogleService-Info.plist`
4. Replace the file in `ios/Runner/GoogleService-Info.plist`

## **Step 4: Update Firebase Configuration**

Replace the placeholder values in `firebase_options.dart` with your actual Firebase project values:

```dart
// Get these values from Firebase Console → Project Settings → General
static const FirebaseOptions android = FirebaseOptions(
  apiKey: 'your-actual-android-api-key',
  appId: 'your-actual-android-app-id',
  messagingSenderId: 'your-actual-sender-id',
  projectId: 'your-actual-project-id',
  storageBucket: 'your-actual-project-id.appspot.com',
);
```

## **Step 5: Configure Firestore Security Rules**

In Firebase Console → Firestore Database → Rules:

```javascript
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    // Allow users to read/write their own notes
    match /users/{userId}/notes/{noteId} {
      allow read, write: if request.auth != null && request.auth.uid == userId;
    }
  }
}
```

## **Step 6: Enable Offline Persistence**

The app is already configured for offline persistence! Firestore automatically:
- ✅ Caches data locally
- ✅ Works offline
- ✅ Syncs when online
- ✅ Handles conflicts

## **Step 7: Test Your Setup**

1. Run your Flutter app: `flutter run`
2. Create a note (works offline)
3. Check Firebase Console → Firestore to see the data
4. Turn off internet, create another note
5. Turn internet back on - data should sync automatically

## **Firestore Database Structure**

Your app will create this structure:
```
users/
  {userId}/
    notes/
      {noteId}/
        - title: "Note Title"
        - content: "Note Content"
        - createdAt: Timestamp
        - updatedAt: Timestamp
        - needsSync: boolean
        - apiId: string (for API sync)
```

## **Troubleshooting**

### **Common Issues:**
1. **"No Firebase App '[DEFAULT]' has been created"**
   - Make sure `firebase_options.dart` has correct values
   - Check that `google-services.json` is in `android/app/`

2. **"Permission denied"**
   - Check Firestore security rules
   - Make sure user is authenticated

3. **"Offline not working"**
   - Firestore offline is enabled by default
   - Check internet connection status indicator

### **Need Help?**
- Check Firebase Console for error logs
- Verify all configuration files are in place
- Test with a simple note creation first

## **Next Steps**

Once Firebase is set up:
1. Your app will work completely offline
2. Data syncs automatically when online
3. Users can create/edit/delete notes without internet
4. Everything syncs with your existing API when connected

🎉 **You're all set!** Your offline-first notes app is ready to use!
