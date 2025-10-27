import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:offline_note_app/pages/Notes/Bloc/note_event.dart';
import 'package:offline_note_app/pages/Notes/Bloc/note_state.dart';
import 'package:offline_note_app/services/firestore_service.dart';
import 'package:offline_note_app/services/sync_service.dart';
import 'package:offline_note_app/pages/auth/Bloc/auth_bloc.dart';
import 'package:offline_note_app/pages/auth/Bloc/auth_state.dart';
import 'package:offline_note_app/services/shared_preferences_service.dart';
import 'dart:async';

class NoteBloc extends Bloc<NoteEvent, NoteState> {
  final AuthBloc _authBloc;
  StreamSubscription<List<Map<String, dynamic>>>? _notesSubscription;
  StreamSubscription<bool>? _connectivitySubscription;
  String? _currentUserId;

  NoteBloc({required AuthBloc authBloc})
    : _authBloc = authBloc,
      super(const NoteInitial()) {
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
      if (isOnline && _currentUserId != null) {
        // When coming online, trigger sync
        add(SyncNotes());
      }
    });
  }

  @override
  Future<void> close() {
    _notesSubscription?.cancel();
    _connectivitySubscription?.cancel();
    return super.close();
  }

  Future<void> _onLoadNotes(LoadNotes event, Emitter<NoteState> emit) async {
    emit(const NoteLoading());

    try {
      final userId = await _getUserId();
      if (userId == null) {
        emit(const NoteOperationFailure(message: 'User not authenticated'));
        return;
      }

      _currentUserId = userId;

      // Listen to Firestore notes stream (works offline)
      _notesSubscription?.cancel();
      _notesSubscription = FirestoreService.getNotesStream(userId).listen(
        (notes) {
          if (!emit.isDone) {
            emit(NoteLoaded(notes: notes));
          }
        },
        onError: (error) {
          if (!emit.isDone) {
            emit(NoteOperationFailure(message: error.toString()));
          }
        },
      );

      // Background sync when online (non-blocking)
      if (FirestoreService.isOnline) {
        _backgroundSync(userId);
      }
    } catch (e) {
      emit(NoteOperationFailure(message: e.toString()));
    }
  }

  // Background sync that doesn't block the UI
  Future<void> _backgroundSync(String userId) async {
    try {
      final token = await _getToken();
      if (token != null) {
        // Sync in background without affecting UI
        SyncService.syncFromApiToFirestore(userId, token);
        SyncService.syncFromFirestoreToApi(userId, token);
      }
    } catch (e) {
      print('Background sync error: $e');
      // Don't emit errors for background sync
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
        'createdAt': DateTime.now(),
        'updatedAt': DateTime.now(),
        'needsSync':
            true, // Always mark as needing sync for offline-first approach
      });

      // Note added successfully - the Firestore stream will update the UI
      // Background sync will handle API upload when online
      print('Note created offline and stored in Firestore');
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
        'updatedAt': DateTime.now(),
        'needsSync':
            true, // Always mark as needing sync for offline-first approach
      });

      // Note updated successfully - the Firestore stream will update the UI
      // Background sync will handle API upload when online
      print('Note updated offline and stored in Firestore');
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

      // Delete note from Firestore (works completely offline)
      await FirestoreService.deleteNote(userId, event.id);

      // Note deleted successfully - the Firestore stream will update the UI
      // Background sync will handle API deletion when online
      print('Note deleted offline from Firestore');
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
        return;
      }

      // Perform full bidirectional sync
      await SyncService.fullSync(userId, token);
    } catch (e) {
      print('Error during sync: $e');
    }
  }

  Future<String?> _getToken() async {
    // First try to get token from AuthBloc
    if (_authBloc.currentToken != null) {
      return _authBloc.currentToken;
    }

    // If not available, get from SharedPreferences
    return await SharedPreferencesService.getToken();
  }

  Future<String?> _getUserId() async {
    // First try to get userId from AuthBloc
    if (_authBloc.state is AuthAuthenticated) {
      return (_authBloc.state as AuthAuthenticated).userId;
    }

    // If not available, get from SharedPreferences
    return await SharedPreferencesService.getUserId();
  }
}
