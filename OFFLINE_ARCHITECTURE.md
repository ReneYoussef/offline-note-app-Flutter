## Offline Architecture and Sync Flow (Firestore + Bloc + SharedPreferences)

This document explains how Firebase/Firestore offline mode is enabled and used, how `NoteBloc` orchestrates data, what `SharedPreferences` stores, and how manual syncing with your REST API works. It is written to help you reuse the same logic in other projects.

### High-level overview
- **Firestore offline-first**: Firestore persistence is enabled. Reads and writes work offline and are replayed when online.
- **Local immediate UX**: We also keep a lightweight in-memory cache to show changes instantly, even before Firestore returns IDs.
- **Bloc-driven UI**: `NoteBloc` listens to a Firestore stream and emits `NoteState`s. All CRUD goes through Firestore (offline-safe).
- **Manual sync (device-wins)**: A manual Sync action pushes local Firestore notes to the REST API and prunes server notes missing locally. Pull/import is intentionally disabled to avoid re-creating deleted notes.
- **Auth/session**: `SharedPreferences` stores token and user data for reuse on app restarts; `NoteBloc` reads from `AuthBloc` first, then falls back to `SharedPreferences`.

---

## 1) Enabling Firestore offline mode

Offline persistence is enabled centrally during startup via `FirestoreService.initialize()` in `main.dart`.

```16:33:lib/main.dart
void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    // Initialize Firebase
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    print('Firebase initialized successfully');

    // Initialize Firestore service for offline functionality
    await FirestoreService.initialize();
    print('Firestore service initialized for offline functionality');
  } catch (e) {
    print('Error initializing Firebase: $e');
    print('Stack trace: ${StackTrace.current}');
    rethrow;
  }
  // ...
}
```

Inside `FirestoreService.initialize()` we enable persistence and set unlimited cache. We also begin monitoring connectivity to expose a simple status stream for the UI.

```20:42:lib/services/firestore_service.dart
// Initialize connectivity monitoring
static Future<void> initialize() async {
  // Enable offline persistence
  _firestore.settings = const Settings(
    persistenceEnabled: true,
    cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
  );

  // Listen to connectivity changes
  _connectivity.onConnectivityChanged.listen((
    List<ConnectivityResult> results,
  ) {
    _isOnline = results.any((result) => result != ConnectivityResult.none);
    _connectivityController.add(_isOnline);

    // Connectivity changed - no sync needed
  });

  // Check initial connectivity
  final results = await _connectivity.checkConnectivity();
  _isOnline = results.any((result) => result != ConnectivityResult.none);
  _connectivityController.add(_isOnline);
}
```

Key points:
- `persistenceEnabled: true` lets Firestore cache documents locally for offline reads/writes.
- Firestore SDK queues writes when offline and replays them when connected.
- We keep `_isOnline` state and a `connectivityStream` for optional UI hints.

---

## 2) FirestoreService: local cache + Firestore stream

`FirestoreService` is your single source of truth for notes. It merges Firestore documents with a small in-memory cache to provide instant feedback for newly created notes before Firestore assigns IDs.

```5:19:lib/services/firestore_service.dart
class FirestoreService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static final Connectivity _connectivity = Connectivity();

  // Stream controller for connectivity changes
  static final StreamController<bool> _connectivityController =
      StreamController<bool>.broadcast();
  static Stream<bool> get connectivityStream => _connectivityController.stream;

  // Cache for offline data
  static final Map<String, Map<String, dynamic>> _offlineCache = {};

  static bool _isOnline = false;
  static bool get isOnline => _isOnline;
}
```

### Adding a note (offline-first, immediate UX)
- Create a temp ID and put the note into `_offlineCache` with `isLocal: true` so the UI updates instantly.
- Attempt to add to Firestore (works offline too). When Firestore returns a real doc ID, replace the temp cache entry with the Firestore-backed entry.

```49:106:lib/services/firestore_service.dart
// Add a note (works completely offline-first)
static Future<String> addNote(
  String userId,
  Map<String, dynamic> noteData,
) async {
  // Generate temp ID for immediate response
  final tempId = DateTime.now().millisecondsSinceEpoch.toString();

  // Always add to local cache first for immediate UI updates
  _offlineCache[tempId] = {
    ...noteData,
    'id': tempId,
    'isLocal': true, // Mark as local until synced to Firestore
    'createdAt': DateTime.now(),
    'updatedAt': DateTime.now(),
  };

  // Try to add to Firestore (works offline with persistence)
  try {
    // Extract timestamps...
    final docRef = await _getNotesCollection(userId).add({
      'title': noteData['title'] ?? '',
      'body': noteData['body'] ?? '',
      'createdAt': createdAt,
      'updatedAt': updatedAt,
    });

    // Update local cache with Firestore ID
    _offlineCache[docRef.id] = {
      'title': noteData['title'] ?? '',
      'body': noteData['body'] ?? '',
      'id': docRef.id,
      'isLocal': false, // Now synced to Firestore
      'createdAt': createdAt,
      'updatedAt': updatedAt,
    };

    // Remove the temp entry
    _offlineCache.remove(tempId);
    return docRef.id;
  } catch (e) {
    // Keep the local cache entry - it will sync when online
    return tempId;
  }
}
```

### Updating and deleting notes
- Update: modify cache (if present) for instant UI, then update Firestore (safe offline).
- Delete: remove from cache immediately, then delete in Firestore.

```108:151:lib/services/firestore_service.dart
// Update a note (works completely offline-first)
static Future<void> updateNote(
  String userId,
  String noteId,
  Map<String, dynamic> noteData,
) async {
  // Always update local cache first for immediate UI updates
  if (_offlineCache.containsKey(noteId)) {
    _offlineCache[noteId] = {
      ..._offlineCache[noteId]!,
      ...noteData,
      'updatedAt': DateTime.now(),
    };
  }
  // Try to update Firestore...
  await _getNotesCollection(userId).doc(noteId).update(updateData);
}

// Delete a note (works completely offline-first)
static Future<void> deleteNote(String userId, String noteId) async {
  _offlineCache.remove(noteId);
  await _getNotesCollection(userId).doc(noteId).delete();
}
```

### Reading: a single stream that merges Firestore docs and local cache
`getNotesStream(userId)` returns a stream that:
- Listens to `users/{userId}/notes` snapshots (offline-capable)
- Adds any local-only cached notes (`isLocal: true`)
- Sorts by `createdAt` desc

```188:235:lib/services/firestore_service.dart
// Get notes stream (works offline with cached data)
static Stream<List<Map<String, dynamic>>> getNotesStream(String userId) {
  return _getNotesCollection(userId).snapshots().map((snapshot) {
    final List<Map<String, dynamic>> notes = [];

    // Add notes from Firestore
    for (var doc in snapshot.docs) {
      final data = doc.data();
      if (data != null) {
        final noteData = Map<String, dynamic>.from(
          data as Map<dynamic, dynamic>,
        );
        noteData['id'] = doc.id;
        noteData['isLocal'] = false;
        notes.add(noteData);

        // Update cache
        _offlineCache[doc.id] = noteData;
      }
    }

    // Add all local cache notes for this user
    for (var entry in _offlineCache.entries) {
      final noteData = entry.value;
      if (noteData['isLocal'] == true) {
        notes.add(noteData);
      }
    }

    // Sort by creation date (newest first)
    notes.sort((a, b) {
      final aDate = _safeToDateTime(a['createdAt']);
      final bDate = _safeToDateTime(b['createdAt']);
      return bDate.compareTo(aDate);
    });

    return notes;
  });
}
```

Why both Firestore and cache? Firestore’s offline write still assigns the final doc ID asynchronously. The in-memory cache lets the UI show a “pending” note immediately (with `isLocal: true`) that will be replaced by the Firestore-backed document when available.

---

## 3) NoteBloc: orchestrating UI and data

`NoteBloc` wires events to Firestore operations and exposes `NoteState`s to the UI. It also manages manual sync with the REST API.

### Initialization
- Hooks up event handlers and calls `_initializeFirestore()`.
- Subscribes to the `connectivityStream` for optional UI awareness.

```20:45:lib/pages/Notes/Bloc/note_bloc.dart
NoteBloc({required AuthBloc authBloc})
  : _authBloc = authBloc,
    super(const NoteInitial()) {
  // register event handlers
  on<LoadNotes>(_onLoadNotes);
  on<CreateNote>(_onCreateNote);
  on<UpdateNote>(_onUpdateNote);
  on<DeleteNote>(_onDeleteNote);
  on<RefreshNotes>(_onRefreshNotes);
  on<SyncNotes>(_onSyncNotes);

  // Initialize Firestore service
  _initializeFirestore();
}

Future<void> _initializeFirestore() async {
  await FirestoreService.initialize();
  _connectivitySubscription = FirestoreService.connectivityStream.listen((
    isOnline,
  ) {
    // UI-only connectivity monitoring
  });
}
```

### Load notes
- Resolve `userId` from `AuthBloc` or `SharedPreferences`.
- Get the first snapshot from `FirestoreService.getNotesStream(userId)` for immediate render, then listen for updates.
- Rely only on Firestore data for display (no automatic API import).

```54:113:lib/pages/Notes/Bloc/note_bloc.dart
final userId = await _getUserId();
// Listen to Firestore notes stream (works offline)
final initialNotes = await FirestoreService.getNotesStream(userId).first;
emit(NoteLoaded(notes: initialNotes));
_notesSubscription = FirestoreService.getNotesStream(userId).listen(
  (notes) {
    if (!emit.isDone) emit(NoteLoaded(notes: notes));
  },
  onError: (error) {
    if (!emit.isDone) emit(NoteOperationFailure(message: error.toString()));
  },
);
```

### Create / Update / Delete (offline-safe)
Each CRUD action calls the corresponding `FirestoreService` method. The UI updates from the stream; we optionally dispatch `RefreshNotes` to nudge repaint.

```116:173:lib/pages/Notes/Bloc/note_bloc.dart
// Create
await FirestoreService.addNote(userId, {
  'title': event.title,
  'body': event.body,
  'createdAt': Timestamp.fromDate(DateTime.now()),
  'updatedAt': Timestamp.fromDate(DateTime.now()),
});
add(const RefreshNotes());

// Update
await FirestoreService.updateNote(userId, event.id, {
  'title': event.title,
  'body': event.body,
  'updatedAt': Timestamp.fromDate(DateTime.now()),
});
add(const RefreshNotes());
```

Delete also handles immediate server deletion if the note had an `apiId`:

```175:215:lib/pages/Notes/Bloc/note_bloc.dart
// Delete locally first
await FirestoreService.deleteNote(userId, event.id);
emit(NoteLoaded(notes: updatedNotes));

// If note has API ID, delete from REST API immediately
final apiId = noteToDelete['apiId'] as String?;
if (apiId != null) {
  await _deleteFromRailwayApi(userId, apiId);
}
```

### Manual Sync: device-wins strategy
Triggered by `SyncNotes` event. Steps:
- Require Wi‑Fi (safety/cost control).
- PUSH: For notes without `apiId`, create them on the API; then attach the returned API ID back to Firestore (or upgrade a local-only cache entry to a Firestore doc).
- PULL: Disabled by design in device-wins mode to avoid re-creating deletions.
- PRUNE: Delete API notes that don’t exist in Firestore anymore.

```224:355:lib/pages/Notes/Bloc/note_bloc.dart
// Wi‑Fi check
final connectivity = await Connectivity().checkConnectivity();
final isOnWifi = connectivity.contains(ConnectivityResult.wifi);
if (!isOnWifi) {
  emit(const NoteOperationFailure(message: 'Sync requires Wi‑Fi...'));
  return;
}

// PUSH local notes without apiId
for (var note in localNotes) {
  if (note['apiId'] != null) continue;
  final response = await _apiServices.createNote(...);
  final newApiId = response['id'].toString();

  if (note['isLocal'] == true) {
    // create Firestore doc, then remove temp cache
    await FirestoreService.addNote(userId, { ... 'apiId': newApiId, ... });
    await FirestoreService.deleteNote(userId, note['id']);
  } else {
    // attach apiId to existing Firestore doc
    await FirestoreService.updateNote(userId, note['id'], { 'apiId': newApiId });
  }
}

// PRUNE API notes not present locally
final apiNotesNow = await _apiServices.getNotes(token);
for (var apiNote in apiNotesNow) {
  final apiId = apiNote['id'].toString();
  if (!localApiIds.contains(apiId)) {
    await _apiServices.deleteNote(id: int.parse(apiId), token: token);
  }
}
```

Rationale:
- Treat Firestore as the canonical local source. The server is a backup/secondary store.
- Prevent server pull/import from resurrecting notes users deleted locally.

---

## 4) SharedPreferences: session persistence and fallbacks

`SharedPreferencesService` stores minimal auth/session details for reuse between launches: token, userId, name, email, and a boolean `is_logged_in`.

```1:23:lib/services/shared_preferences_service.dart
class SharedPreferencesService {
  static const String _tokenKey = 'user_token';
  static const String _userIdKey = 'user_id';
  static const String _userNameKey = 'user_name';
  static const String _userEmailKey = 'user_email';
  static const String _isLoggedInKey = 'is_logged_in';

  // Save user login data
  static Future<void> saveUserData({ ... }) async { /* writes keys */ }
}
```

`NoteBloc` first tries `AuthBloc` for the current user and token; if absent (e.g., on app restart before auth is rebuilt), it falls back to SharedPreferences.

```357:379:lib/pages/Notes/Bloc/note_bloc.dart
Future<String?> _getUserId() async {
  if (_authBloc.state is AuthAuthenticated) {
    final userId = (_authBloc.state as AuthAuthenticated).userId;
    return userId;
  }
  // fallback
  return await SharedPreferencesService.getUserId();
}

Future<String?> _getToken() async {
  if (_authBloc.currentToken != null) {
    return _authBloc.currentToken;
  }
  return await SharedPreferencesService.getToken();
}
```

This ensures `NoteBloc` can resolve identity and proceed with Firestore operations immediately, even if the UI hasn’t fully rebuilt auth state yet.

---

## 5) How to reuse this pattern in other projects

1. Initialize Firebase and call a central `FirestoreService.initialize()` at startup to enable persistence.
2. Encapsulate Firestore CRUD in a service that:
   - Writes are safe offline (just call Firestore; SDK will queue).
   - Maintains an in-memory cache for instant UX and temp IDs.
   - Exposes a single stream that merges Firestore docs with local-only items.
3. Drive UI with Bloc/Cubit that:
   - Subscribes to the service stream on load and emits view states.
   - Performs CRUD by delegating to the service only (no direct API writes).
   - Performs manual sync if you also have a REST backend.
4. Choose a sync strategy:
   - Device-wins (this repo): push local to server; optionally prune server.
   - Or server-wins / two-way merge if your product requires it.
5. Store minimal session data in `SharedPreferences` so background processes can proceed before full auth rebuild.

---

## 6) Operational notes and gotchas

- Firestore offline is per-app install; cache persists across sessions.
- Avoid auto-importing from server if you allow local delete; otherwise you’ll resurrect deletions.
- When showing notes, rely solely on the Firestore stream; let sync just annotate docs with `apiId` and do server housekeeping.
- Keep `createdAt/updatedAt` as `Timestamp` in Firestore for proper ordering; use a helper to handle mixed types safely.

```169:186:lib/services/firestore_service.dart
// Helper function to safely convert Timestamp or DateTime to DateTime
static DateTime _safeToDateTime(dynamic dateValue) {
  if (dateValue == null) return DateTime.now();
  if (dateValue is Timestamp) return dateValue.toDate();
  if (dateValue is DateTime) return dateValue;
  if (dateValue is String) {
    try { return DateTime.parse(dateValue); } catch (e) { return DateTime.now(); }
  }
  return DateTime.now();
}
```

- For background API deletes, verify token availability and handle errors gracefully; do not block the UI.

```381:419:lib/pages/Notes/Bloc/note_bloc.dart
// Delete note from Railway API immediately (background operation)
Future<void> _deleteFromRailwayApi(String userId, String apiId) async {
  final token = await _getToken();
  if (token == null) return; // no token; skip
  await _apiServices.deleteNote(id: int.parse(apiId), token: token);
  // optional verification step follows in code
}
```

---

## 7) Mental model recap

- Firestore is your offline-capable database. Treat it as the app’s local source of truth.
- An in-memory cache helps bridge the tiny gap between user action and Firestore confirmation.
- Bloc listens to a single stream and renders the UI accordingly.
- Manual sync reconciles with the REST API using a clear conflict policy.
- SharedPreferences just keeps enough auth info to make all of the above work across sessions.

