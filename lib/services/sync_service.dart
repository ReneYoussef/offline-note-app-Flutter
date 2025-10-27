import 'package:cloud_firestore/cloud_firestore.dart';
import 'api_services.dart';

class SyncService {
  static final ApiServices _apiServices = ApiServices();

  // Sync notes from API to Firestore
  static Future<void> syncFromApiToFirestore(
    String userId,
    String token,
  ) async {
    try {
      print('Starting sync from API to Firestore...');

      // Get notes from API
      final apiNotes = await _apiServices.getNotes(token);
      print('Retrieved ${apiNotes.length} notes from API');

      // Get current Firestore notes
      final firestoreNotes = await _getFirestoreNotes(userId);
      print('Retrieved ${firestoreNotes.length} notes from Firestore');

      // Create a map of existing Firestore notes by API ID
      final Map<String, Map<String, dynamic>> firestoreMap = {};
      for (var note in firestoreNotes) {
        final apiId = note['apiId'] as String?;
        if (apiId != null) {
          firestoreMap[apiId] = note;
        }
      }

      // Sync API notes to Firestore
      for (var apiNote in apiNotes) {
        final apiId = apiNote['id'].toString();
        final firestoreNote = firestoreMap[apiId];

        if (firestoreNote == null) {
          // Note doesn't exist in Firestore, add it
          await _addNoteToFirestore(userId, apiNote);
          print('Added note $apiId to Firestore');
        } else {
          // Note exists, check if it needs updating
          if (_needsUpdate(firestoreNote, apiNote)) {
            await _updateNoteInFirestore(userId, firestoreNote['id'], {
              'title': apiNote['title'] ?? '',
              'content': apiNote['body'] ?? '',
              'updatedAt': apiNote['updated_at'] != null
                  ? Timestamp.fromDate(DateTime.parse(apiNote['updated_at']))
                  : Timestamp.now(),
            });
            print('Updated note $apiId in Firestore');
          }
        }
      }

      // Remove notes from Firestore that don't exist in API
      for (var firestoreNote in firestoreNotes) {
        final apiId = firestoreNote['apiId'] as String?;
        if (apiId != null &&
            !apiNotes.any((note) => note['id'].toString() == apiId)) {
          await _deleteNoteFromFirestore(userId, firestoreNote['id']);
          print('Removed note $apiId from Firestore');
        }
      }

      print('Sync from API to Firestore completed');
    } catch (e) {
      print('Error syncing from API to Firestore: $e');
    }
  }

  // Sync notes from Firestore to API
  static Future<void> syncFromFirestoreToApi(
    String userId,
    String token,
  ) async {
    try {
      print('Starting sync from Firestore to API...');

      // Get local notes that need sync
      final localNotes = await _getLocalNotesNeedingSync(userId);
      print('Found ${localNotes.length} local notes needing sync');

      for (var note in localNotes) {
        try {
          if (note['apiId'] == null) {
            // New note, create in API
            final apiResponse = await _apiServices.createNote(
              title: note['title'] ?? '',
              body: note['content'] ?? '',
              token: token,
            );

            // Update Firestore with API ID
            await _updateNoteInFirestore(userId, note['id'], {
              'apiId': apiResponse['id'].toString(),
              'needsSync': false,
            });

            print('Created note ${note['id']} in API');
          } else {
            // Existing note, update in API
            await _apiServices.updateNote(
              id: int.parse(note['apiId']),
              title: note['title'] ?? '',
              body: note['content'] ?? '',
              token: token,
            );

            // Mark as synced
            await _updateNoteInFirestore(userId, note['id'], {
              'needsSync': false,
            });

            print('Updated note ${note['apiId']} in API');
          }
        } catch (e) {
          print('Error syncing note ${note['id']} to API: $e');
        }
      }

      print('Sync from Firestore to API completed');
    } catch (e) {
      print('Error syncing from Firestore to API: $e');
    }
  }

  // Full bidirectional sync
  static Future<void> fullSync(String userId, String token) async {
    try {
      print('Starting full bidirectional sync...');

      // First sync from API to Firestore (get latest from server)
      await syncFromApiToFirestore(userId, token);

      // Then sync from Firestore to API (upload local changes)
      await syncFromFirestoreToApi(userId, token);

      print('Full sync completed');
    } catch (e) {
      print('Error during full sync: $e');
    }
  }

  // Helper methods
  static Future<List<Map<String, dynamic>>> _getFirestoreNotes(
    String userId,
  ) async {
    final snapshot = await FirebaseFirestore.instance
        .collection('users')
        .doc(userId)
        .collection('notes')
        .get();

    return snapshot.docs.map((doc) {
      final data = doc.data();
      data['id'] = doc.id;
      return data;
    }).toList();
  }

  static Future<List<Map<String, dynamic>>> _getLocalNotesNeedingSync(
    String userId,
  ) async {
    final snapshot = await FirebaseFirestore.instance
        .collection('users')
        .doc(userId)
        .collection('notes')
        .where('needsSync', isEqualTo: true)
        .get();

    return snapshot.docs.map((doc) {
      final data = doc.data();
      data['id'] = doc.id;
      return data;
    }).toList();
  }

  static Future<void> _addNoteToFirestore(
    String userId,
    Map<String, dynamic> apiNote,
  ) async {
    await FirebaseFirestore.instance
        .collection('users')
        .doc(userId)
        .collection('notes')
        .add({
          'title': apiNote['title'] ?? '',
          'content': apiNote['body'] ?? '',
          'apiId': apiNote['id'].toString(),
          'createdAt': apiNote['created_at'] != null
              ? Timestamp.fromDate(DateTime.parse(apiNote['created_at']))
              : Timestamp.now(),
          'updatedAt': apiNote['updated_at'] != null
              ? Timestamp.fromDate(DateTime.parse(apiNote['updated_at']))
              : Timestamp.now(),
          'needsSync': false,
        });
  }

  static Future<void> _updateNoteInFirestore(
    String userId,
    String noteId,
    Map<String, dynamic> data,
  ) async {
    await FirebaseFirestore.instance
        .collection('users')
        .doc(userId)
        .collection('notes')
        .doc(noteId)
        .update(data);
  }

  static Future<void> _deleteNoteFromFirestore(
    String userId,
    String noteId,
  ) async {
    await FirebaseFirestore.instance
        .collection('users')
        .doc(userId)
        .collection('notes')
        .doc(noteId)
        .delete();
  }

  static bool _needsUpdate(
    Map<String, dynamic> firestoreNote,
    Map<String, dynamic> apiNote,
  ) {
    final firestoreUpdated = firestoreNote['updatedAt'] as Timestamp?;
    final apiUpdated = apiNote['updated_at'] != null
        ? DateTime.parse(apiNote['updated_at'])
        : null;

    if (firestoreUpdated == null || apiUpdated == null) return true;

    return apiUpdated.isAfter(firestoreUpdated.toDate());
  }
}
