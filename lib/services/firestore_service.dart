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
  static final List<Map<String, dynamic>> _pendingWrites = [];

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

      if (_isOnline) {
        _syncPendingWrites();
      }
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

    // Always add to Firestore first (works offline with persistence)
    try {
      final docRef = await _getNotesCollection(userId).add({
        ...noteData,
        'needsSync': true, // Mark as needing API sync
        'createdAt': Timestamp.fromDate(DateTime.now()),
        'updatedAt': Timestamp.fromDate(DateTime.now()),
      });

      // Add to local cache for instant UI updates
      _offlineCache[docRef.id] = {
        ...noteData,
        'id': docRef.id,
        'isLocal': false,
        'needsSync': true,
        'createdAt': Timestamp.fromDate(DateTime.now()),
        'updatedAt': Timestamp.fromDate(DateTime.now()),
      };

      print('Note added to Firestore with ID: ${docRef.id}');
      return docRef.id;
    } catch (e) {
      print('Error adding note to Firestore: $e');
      // Fallback: Add to local cache only
      _offlineCache[tempId] = {
        ...noteData,
        'id': tempId,
        'isLocal': true,
        'needsSync': true,
        'createdAt': DateTime.now(),
        'updatedAt': DateTime.now(),
      };

      // Add to pending writes for later sync
      _pendingWrites.add({
        'action': 'add',
        'userId': userId,
        'data': noteData,
        'tempId': tempId,
      });

      return tempId;
    }
  }

  // Update a note (works completely offline-first)
  static Future<void> updateNote(
    String userId,
    String noteId,
    Map<String, dynamic> noteData,
  ) async {
    // Always update Firestore first (works offline with persistence)
    try {
      await _getNotesCollection(userId).doc(noteId).update({
        ...noteData,
        'needsSync': true, // Mark as needing API sync
        'updatedAt': Timestamp.fromDate(DateTime.now()),
      });

      // Update local cache for instant UI updates
      if (_offlineCache.containsKey(noteId)) {
        _offlineCache[noteId] = {
          ..._offlineCache[noteId]!,
          ...noteData,
          'needsSync': true,
          'updatedAt': DateTime.now(),
        };
      }

      print('Note updated in Firestore: $noteId');
    } catch (e) {
      print('Error updating note in Firestore: $e');
      // Fallback: Update local cache only
      if (_offlineCache.containsKey(noteId)) {
        _offlineCache[noteId] = {
          ..._offlineCache[noteId]!,
          ...noteData,
          'needsSync': true,
          'updatedAt': DateTime.now(),
        };
      }

      // Add to pending writes for later sync
      _pendingWrites.add({
        'action': 'update',
        'userId': userId,
        'noteId': noteId,
        'data': noteData,
      });
    }
  }

  // Delete a note (works completely offline-first)
  static Future<void> deleteNote(String userId, String noteId) async {
    // Always delete from Firestore first (works offline with persistence)
    try {
      await _getNotesCollection(userId).doc(noteId).delete();

      // Remove from local cache for instant UI update
      _offlineCache.remove(noteId);

      print('Note deleted from Firestore: $noteId');
    } catch (e) {
      print('Error deleting note from Firestore: $e');
      // Fallback: Remove from local cache only
      _offlineCache.remove(noteId);

      // Add to pending writes for later sync
      _pendingWrites.add({
        'action': 'delete',
        'userId': userId,
        'noteId': noteId,
      });
    }
  }

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
          noteData['needsSync'] = false;
          notes.add(noteData);

          // Update cache
          _offlineCache[doc.id] = noteData;
        }
      }

      // Add all local cache notes for this user
      for (var entry in _offlineCache.entries) {
        final noteData = entry.value;
        // Only add if it's a local note (not synced to Firestore yet)
        if (noteData['isLocal'] == true) {
          notes.add(noteData);
        }
      }

      print(
        'Stream returning ${notes.length} notes (${_offlineCache.length} in cache)',
      );

      // Sort by creation date (newest first)
      notes.sort((a, b) {
        final aDate = a['createdAt'] as Timestamp?;
        final bDate = b['createdAt'] as Timestamp?;
        if (aDate == null || bDate == null) return 0;
        return bDate.compareTo(aDate);
      });

      return notes;
    });
  }

  // Sync pending writes when online
  static Future<void> _syncPendingWrites() async {
    if (!_isOnline || _pendingWrites.isEmpty) return;

    print('Syncing ${_pendingWrites.length} pending writes...');

    final writesToProcess = List<Map<String, dynamic>>.from(_pendingWrites);
    _pendingWrites.clear();

    for (var write in writesToProcess) {
      try {
        switch (write['action']) {
          case 'add':
            await _getNotesCollection(write['userId']).add(write['data']);
            break;
          case 'update':
            await _getNotesCollection(
              write['userId'],
            ).doc(write['noteId']).update(write['data']);
            break;
          case 'delete':
            await _getNotesCollection(
              write['userId'],
            ).doc(write['noteId']).delete();
            break;
        }
        print('Synced ${write['action']} operation');
      } catch (e) {
        print('Error syncing ${write['action']}: $e');
        // Re-add to pending writes if sync fails
        _pendingWrites.add(write);
      }
    }
  }

  // Force sync all data
  static Future<void> forceSync() async {
    if (_isOnline) {
      await _syncPendingWrites();
    }
  }

  // Get pending writes count
  static int get pendingWritesCount => _pendingWrites.length;

  // Clear cache (for logout)
  static void clearCache() {
    _offlineCache.clear();
    _pendingWrites.clear();
  }
}
