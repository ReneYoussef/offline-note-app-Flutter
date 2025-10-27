# Offline Note App

A Flutter note-taking application with offline/online sync capabilities using BLoC architecture and Laravel API backend.

## Features

- 🔐 **User Authentication** - Register and login with persistent sessions
- 📝 **Note Management** - Create, read, update, and delete notes
- 🔄 **BLoC Architecture** - Clean state management with flutter_bloc
- 💾 **Local Storage** - SharedPreferences for persistent login state
- 🌐 **API Integration** - Laravel backend for data synchronization
- 📱 **Cross-Platform** - Works on Android, iOS, Web, and Desktop

## Setup Instructions

### 1. Environment Configuration

Create a `.env` file in the project root with your API URL:

```bash
API_URL=https://your-api-url-here.com/api
```

**Important:** The `.env` file is already in `.gitignore` and will not be committed to version control.

### 2. Install Dependencies

```bash
flutter pub get
```

### 3. Run the App

```bash
flutter run
```

## Project Structure

```
lib/
├── Database/           # Drift database (commented for future offline sync)
├── pages/
│   ├── auth/          # Authentication pages and BLoC
│   └── Notes/         # Notes pages and BLoC
├── services/          # API services and SharedPreferences
└── widgets/           # Reusable UI components
```

## Architecture

- **BLoC Pattern** - State management with events and states
- **Repository Pattern** - API services for data access
- **SharedPreferences** - Local storage for user sessions
- **Future Offline Sync** - Drift database ready for connectivity_plus integration

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Lab: Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Cookbook: Useful Flutter samples](https://docs.flutter.dev/cookbook)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.
