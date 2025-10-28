import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:offline_note_app/pages/Notes/Bloc/note_event.dart';
import 'package:offline_note_app/pages/Notes/Bloc/note_state.dart';
import 'package:offline_note_app/services/firestore_service.dart';
import 'package:offline_note_app/services/api_services.dart';
import 'package:offline_note_app/pages/auth/Bloc/auth_bloc.dart';
import 'package:offline_note_app/pages/auth/Bloc/auth_state.dart';
import 'package:offline_note_app/services/shared_preferences_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'dart:async';

class NoteBloc extends Bloc<NoteEvent, NoteState> {
  final AuthBloc _authBloc;
  final ApiServices _apiServices = ApiServices();
  StreamSubscription<List<Map<String, dynamic>>>? _notesSubscription;

  StreamSubscription<bool>? _connectivitySubscription;

  NoteBloc({required AuthBloc authBloc})
    : _authBloc = authBloc,
      super(const NoteInitial()) {
    print('NoteBloc constructor called - new instance created');
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

    // Listen to connectivity changes
    _connectivitySubscription = FirestoreService.connectivityStream.listen((
      isOnline,
    ) {
      // Connectivity monitoring for UI updates only
      print('Connectivity changed: $isOnline');
    });
  }

  @override
  Future<void> close() {
    _notesSubscription?.cancel();
    _connectivitySubscription?.cancel();
    return super.close();
  }

  Future<void> _onLoadNotes(LoadNotes event, Emitter<NoteState> emit) async {
    print('LoadNotes event triggered - checking for note recreation');
    emit(const NoteLoading());

    try {
      final userId = await _getUserId();
      if (userId == null) {
        emit(const NoteOperationFailure(message: 'User not authenticated'));
        return;
      }

      // Listen to Firestore notes stream (works offline)
      _notesSubscription?.cancel();
      print('Setting up notes stream listener for user: $userId');

      // Use first() to get the initial data and then listen for updates
      final initialNotes = await FirestoreService.getNotesStream(userId).first;
      print('Initial notes received: ${initialNotes.length}');
      print(
        'Firestore notes: ${initialNotes.map((note) => '${note['id']}: ${note['title']} (apiId: ${note['apiId']})').toList()}',
      );

      // Important: Do NOT auto-import notes from the API here.
      // This previously re-created notes that the user deleted locally.
      // Only rely on Firestore's offline-first source for displayed notes.
      emit(NoteLoaded(notes: initialNotes));

      // Now set up the stream listener for updates
      _notesSubscription = FirestoreService.getNotesStream(userId).listen(
        (notes) {
          print('Stream listener received ${notes.length} notes');
          // Check if emitter is still active before emitting
          if (!emit.isDone) {
            try {
              print('Emitting NoteLoaded with ${notes.length} notes');
              emit(NoteLoaded(notes: notes));
            } catch (e) {
              print('Error emitting state: $e');
            }
          } else {
            print('Emitter is done, not emitting state');
          }
        },
        onError: (error) {
          print('Error in notes stream: $error');
          if (!emit.isDone) {
            try {
              emit(NoteOperationFailure(message: error.toString()));
            } catch (e) {
              print('Error emitting error state: $e');
            }
          }
        },
      );

      // Notes loaded successfully
    } catch (e) {
      print('Error in _onLoadNotes: $e');
      emit(NoteOperationFailure(message: e.toString()));
    }
  }

  Future<void> _onCreateNote(CreateNote event, Emitter<NoteState> emit) async {
    emit(const NoteCreating());

    try {
      final userId = await _getUserId();
      if (userId == null) {
        emit(const NoteOperationFailure(message: 'User not authenticated'));
        return;
      }

      // Add note to Firestore (works completely offline)
      await FirestoreService.addNote(userId, {
        'title': event.title,
        'body': event.body,
        'createdAt': Timestamp.fromDate(DateTime.now()),
        'updatedAt': Timestamp.fromDate(DateTime.now()),
      });

      // Note added successfully - the Firestore stream will update the UI
      print('Note created and stored in Firestore');

      // Force refresh to ensure UI updates immediately (especially when offline)
      add(const RefreshNotes());

      // Note will be synced manually via the sync button
    } catch (e) {
      emit(NoteOperationFailure(message: e.toString()));
    }
  }

  Future<void> _onUpdateNote(UpdateNote event, Emitter<NoteState> emit) async {
    emit(const NoteUpdating());

    try {
      final userId = await _getUserId();
      if (userId == null) {
        emit(const NoteOperationFailure(message: 'User not authenticated'));
        return;
      }

      // Update note in Firestore (works completely offline)
      await FirestoreService.updateNote(userId, event.id, {
        'title': event.title,
        'body': event.body,
        'updatedAt': Timestamp.fromDate(DateTime.now()),
      });

      // Note updated successfully - the Firestore stream will update the UI
      print('Note updated and stored in Firestore');

      // Force refresh to ensure UI updates immediately (especially when offline)
      add(const RefreshNotes());

      // Note will be synced manually via the sync button
    } catch (e) {
      emit(NoteOperationFailure(message: e.toString()));
    }
  }

  Future<void> _onDeleteNote(DeleteNote event, Emitter<NoteState> emit) async {
    emit(const NoteDeleting());

    try {
      final userId = await _getUserId();
      if (userId == null) {
        emit(const NoteOperationFailure(message: 'User not authenticated'));
        return;
      }

      // Get the note data before deleting to check for API ID
      final notes = await FirestoreService.getNotesStream(userId).first;
      final noteToDelete = notes.firstWhere(
        (note) => note['id'] == event.id,
        orElse: () => <String, dynamic>{},
      );

      // Delete note from Firestore (works completely offline)
      await FirestoreService.deleteNote(userId, event.id);

      // Note deleted successfully - immediately update UI
      print('Note deleted from Firestore');

      // Create updated notes list by removing the deleted note
      final updatedNotes = notes
          .where((note) => note['id'] != event.id)
          .toList();
      emit(NoteLoaded(notes: updatedNotes));

      // If note has API ID, immediately delete from Railway API
      final apiId = noteToDelete['apiId'] as String?;
      if (apiId != null) {
        print('Note has API ID $apiId, deleting from Railway API immediately');
        // Delete from Railway API immediately and wait for completion
        await _deleteFromRailwayApi(userId, apiId);
        print('Successfully deleted note $apiId from Railway API');
      }
    } catch (e) {
      emit(NoteOperationFailure(message: e.toString()));
    }
  }

  Future<void> _onRefreshNotes(
    RefreshNotes event,
    Emitter<NoteState> emit,
  ) async {
    add(const LoadNotes());
  }

  Future<void> _onSyncNotes(SyncNotes event, Emitter<NoteState> emit) async {
    try {
      final userId = await _getUserId();
      final token = await _getToken();

      if (userId == null || token == null) {
        emit(const NoteOperationFailure(message: 'User not authenticated'));
        return;
      }

      // Wi-Fi only: block sync if not on Wi-Fi
      final connectivity = await Connectivity().checkConnectivity();
      final isOnWifi = connectivity.contains(ConnectivityResult.wifi);
      if (!isOnWifi) {
        emit(
          const NoteOperationFailure(
            message: 'Sync requires Wi‑Fi. Connect to Wi‑Fi and try again.',
          ),
        );
        return;
      }

      print('Starting manual sync: device-wins (push + prune, no import)');

      // Get all notes from Firestore (local)
      final localNotes = await FirestoreService.getNotesStream(userId).first;
      print('Found ${localNotes.length} local notes');

      int pushedCount = 0;
      int pullAddedCount = 0;
      int errorCount = 0;
      int prunedCount = 0;

      // 1) PUSH: Sync local notes without apiId to API
      for (var note in localNotes) {
        try {
          if (note['apiId'] != null) {
            continue; // already synced
          }

          final response = await _apiServices.createNote(
            title: note['title'] ?? '',
            body: note['body'] ?? note['content'] ?? '',
            token: token,
          );

          final newApiId = response['id'].toString();

          // If this is a local-only cached note (no Firestore doc yet),
          // create a proper Firestore doc and remove the temp cache entry.
          if (note['isLocal'] == true) {
            await FirestoreService.addNote(userId, {
              'title': note['title'] ?? '',
              'body': note['body'] ?? note['content'] ?? '',
              'apiId': newApiId,
              'createdAt': Timestamp.fromDate(DateTime.now()),
              'updatedAt': Timestamp.fromDate(DateTime.now()),
            });
            // Remove the temp local cache note
            await FirestoreService.deleteNote(userId, note['id']);
          } else {
            // Existing Firestore doc: just attach apiId
            await FirestoreService.updateNote(userId, note['id'], {
              'apiId': newApiId,
            });
          }

          pushedCount++;
          print(
            'Pushed local note ${note['id']} to API with ID ${response['id']}',
          );
        } catch (e) {
          errorCount++;
          print('Error pushing note ${note['id']}: $e');
        }
      }

      // 2) PULL: Disabled in device-wins mode

      // 3) PRUNE: Delete API notes that were deleted locally (not present in Firestore)
      try {
        final afterPullLocal = await FirestoreService.getNotesStream(
          userId,
        ).first;
        final localApiIds = afterPullLocal
            .where((n) => n['apiId'] != null)
            .map((n) => n['apiId'].toString())
            .toSet();

        final apiNotesNow = await _apiServices.getNotes(token);
        for (var apiNote in apiNotesNow) {
          final apiId = apiNote['id'].toString();
          if (!localApiIds.contains(apiId)) {
            try {
              await _apiServices.deleteNote(id: int.parse(apiId), token: token);
              prunedCount++;
              print('Pruned API note not in Firestore: $apiId');
            } catch (e) {
              errorCount++;
              print('Error pruning API note $apiId: $e');
            }
          }
        }
      } catch (e) {
        print('Error during server prune phase: $e');
      }

      // Emit result and refresh display from Firestore only
      final refreshed = await FirestoreService.getNotesStream(userId).first;
      final msg =
          'Pushed $pushedCount, pulled $pullAddedCount, pruned $prunedCount';
      if (errorCount > 0) {
        emit(
          NoteOperationFailure(
            message: 'Sync partial: $msg, errors: $errorCount',
          ),
        );
      } else {
        emit(
          NoteOperationSuccess(
            message: 'Sync complete: $msg',
            notes: refreshed,
          ),
        );
      }

      add(const RefreshNotes());
    } catch (e) {
      print('Error during sync: $e');
      emit(NoteOperationFailure(message: 'Sync failed: $e'));
    }
  }

  Future<String?> _getUserId() async {
    // First try to get userId from AuthBloc
    if (_authBloc.state is AuthAuthenticated) {
      final userId = (_authBloc.state as AuthAuthenticated).userId;
      print('Got userId from AuthBloc: $userId');
      return userId;
    }

    // If not available, get from SharedPreferences
    final userId = await SharedPreferencesService.getUserId();
    print('Got userId from SharedPreferences: $userId');
    return userId;
  }

  Future<String?> _getToken() async {
    // First try to get token from AuthBloc
    if (_authBloc.currentToken != null) {
      return _authBloc.currentToken;
    }

    // If not available, get from SharedPreferences
    return await SharedPreferencesService.getToken();
  }

  // Delete note from Railway API immediately (background operation)
  Future<void> _deleteFromRailwayApi(String userId, String apiId) async {
    try {
      final token = await _getToken();
      if (token == null) {
        print('No token available for immediate API deletion');
        return;
      }

      print('Deleting note $apiId from Railway API immediately');
      print('Using token: ${token.substring(0, 10)}...');

      await _apiServices.deleteNote(id: int.parse(apiId), token: token);
      print('Successfully deleted note $apiId from Railway API');

      // Verify deletion by checking if note still exists
      await Future.delayed(
        const Duration(seconds: 2),
      ); // Wait a bit for API to process
      try {
        final notes = await _apiServices.getNotes(token);
        final deletedNote = notes
            .where((note) => note['id'].toString() == apiId)
            .toList();
        if (deletedNote.isEmpty) {
          print('✅ Verification: Note $apiId successfully deleted from API');
        } else {
          print(
            '❌ Verification: Note $apiId still exists in API after deletion attempt',
          );
        }
      } catch (e) {
        print('Could not verify deletion: $e');
      }
    } catch (e) {
      print('Error deleting note $apiId from Railway API: $e');
      print('This means the note will be recreated on next sync');
    }
  }
}
