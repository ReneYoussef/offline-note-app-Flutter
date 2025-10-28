import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'dart:async';

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

  // Get notes collection for a user
  static CollectionReference _getNotesCollection(String userId) {
    return _firestore.collection('users').doc(userId).collection('notes');
  }

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

    print('Note added to local cache with ID: $tempId');

    // Try to add to Firestore (works offline with persistence)
    try {
      // Extract timestamps from noteData if they exist, otherwise use current time
      final createdAt = noteData['createdAt'] is Timestamp
          ? noteData['createdAt'] as Timestamp
          : Timestamp.fromDate(DateTime.now());
      final updatedAt = noteData['updatedAt'] is Timestamp
          ? noteData['updatedAt'] as Timestamp
          : Timestamp.fromDate(DateTime.now());

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

      print('Note added to Firestore with ID: ${docRef.id}');
      return docRef.id;
    } catch (e) {
      print('Error adding note to Firestore (offline): $e');
      // Keep the local cache entry - it will sync when online
      print('Note kept in local cache for offline use');
      return tempId;
    }
  }

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
      print('Note updated in local cache: $noteId');
    }

    // Try to update Firestore (works offline with persistence)
    try {
      // Extract updatedAt from noteData if it exists, otherwise use current time
      final updatedAt = noteData['updatedAt'] is Timestamp
          ? noteData['updatedAt'] as Timestamp
          : Timestamp.fromDate(DateTime.now());

      // Only update fields that are provided in noteData
      Map<String, dynamic> updateData = {'updatedAt': updatedAt};

      if (noteData.containsKey('title')) {
        updateData['title'] = noteData['title'];
      }
      if (noteData.containsKey('body')) {
        updateData['body'] = noteData['body'];
      }
      if (noteData.containsKey('apiId')) {
        updateData['apiId'] = noteData['apiId'];
      }

      await _getNotesCollection(userId).doc(noteId).update(updateData);

      print('Note updated in Firestore: $noteId');
    } catch (e) {
      print('Error updating note in Firestore (offline): $e');
      print('Note kept in local cache for offline use');
    }
  }

  // Delete a note (works completely offline-first)
  static Future<void> deleteNote(String userId, String noteId) async {
    // Always remove from local cache first for immediate UI update
    _offlineCache.remove(noteId);
    print('Note removed from local cache: $noteId');

    // Try to delete from Firestore (works offline with persistence)
    try {
      await _getNotesCollection(userId).doc(noteId).delete();
      print('Note deleted from Firestore: $noteId');
    } catch (e) {
      print('Error deleting note from Firestore (offline): $e');
      print('Note kept deleted in local cache for offline use');
    }
  }

  // Helper function to safely convert Timestamp or DateTime to DateTime
  static DateTime _safeToDateTime(dynamic dateValue) {
    if (dateValue == null) return DateTime.now();

    if (dateValue is Timestamp) {
      return dateValue.toDate();
    } else if (dateValue is DateTime) {
      return dateValue;
    } else if (dateValue is String) {
      try {
        return DateTime.parse(dateValue);
      } catch (e) {
        return DateTime.now();
      }
    }

    return DateTime.now();
  }

  // Get notes stream (works offline with cached data)
  static Stream<List<Map<String, dynamic>>> getNotesStream(String userId) {
    print('Getting notes stream for user: $userId');
    return _getNotesCollection(userId).snapshots().map((snapshot) {
      print('Firestore snapshot received with ${snapshot.docs.length} docs');
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
          print('Added Firestore note: ${doc.id}');
        }
      }

      // Add all local cache notes for this user
      for (var entry in _offlineCache.entries) {
        final noteData = entry.value;
        // Only add if it's a local note (not synced to Firestore yet)
        if (noteData['isLocal'] == true) {
          notes.add(noteData);
          print('Added local cache note: ${entry.key}');
        }
      }

      print(
        'Stream returning ${notes.length} notes (${_offlineCache.length} in cache)',
      );

      // Sort by creation date (newest first) - safely handle both Timestamp and DateTime
      notes.sort((a, b) {
        final aDate = _safeToDateTime(a['createdAt']);
        final bDate = _safeToDateTime(b['createdAt']);
        return bDate.compareTo(aDate);
      });

      return notes;
    });
  }

  // Clear cache (for logout)
  static void clearCache() {
    _offlineCache.clear();
  }
}
