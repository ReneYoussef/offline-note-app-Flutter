import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:offline_note_app/pages/Notes/Bloc/note_event.dart';
import 'package:offline_note_app/pages/Notes/Bloc/note_state.dart';
import 'package:offline_note_app/services/api_services.dart';
import 'package:offline_note_app/pages/auth/Bloc/auth_bloc.dart';
import 'package:offline_note_app/services/shared_preferences_service.dart';

class NoteBloc extends Bloc<NoteEvent, NoteState> {
  final ApiServices _apiServices = ApiServices();
  final AuthBloc _authBloc;

  NoteBloc({required AuthBloc authBloc})
    : _authBloc = authBloc,
      super(const NoteInitial()) {
    on<LoadNotes>(_onLoadNotes);
    on<CreateNote>(_onCreateNote);
    on<UpdateNote>(_onUpdateNote);
    on<DeleteNote>(_onDeleteNote);
    on<RefreshNotes>(_onRefreshNotes);
  }

  Future<void> _onLoadNotes(LoadNotes event, Emitter<NoteState> emit) async {
    emit(const NoteLoading());

    try {
      final token = await _getToken();
      if (token == null) {
        emit(const NoteOperationFailure(message: 'User not authenticated'));
        return;
      }

      final notes = await _apiServices.getNotes(token);
      emit(NoteLoaded(notes: notes));
    } catch (e) {
      emit(NoteOperationFailure(message: e.toString()));
    }
  }

  Future<void> _onCreateNote(CreateNote event, Emitter<NoteState> emit) async {
    emit(const NoteCreating());

    try {
      final token = await _getToken();
      if (token == null) {
        emit(const NoteOperationFailure(message: 'User not authenticated'));
        return;
      }

      await _apiServices.createNote(
        title: event.title,
        body: event.body,
        token: token,
      );

      // Reload notes after creating
      final notes = await _apiServices.getNotes(token);
      emit(
        NoteOperationSuccess(
          message: 'Note created successfully',
          notes: notes,
        ),
      );
    } catch (e) {
      emit(NoteOperationFailure(message: e.toString()));
    }
  }

  Future<void> _onUpdateNote(UpdateNote event, Emitter<NoteState> emit) async {
    emit(const NoteUpdating());

    try {
      final token = await _getToken();
      if (token == null) {
        emit(const NoteOperationFailure(message: 'User not authenticated'));
        return;
      }

      await _apiServices.updateNote(
        id: event.id,
        title: event.title,
        body: event.body,
        token: token,
      );

      // Reload notes after updating
      final notes = await _apiServices.getNotes(token);
      emit(
        NoteOperationSuccess(
          message: 'Note updated successfully',
          notes: notes,
        ),
      );
    } catch (e) {
      emit(NoteOperationFailure(message: e.toString()));
    }
  }

  Future<void> _onDeleteNote(DeleteNote event, Emitter<NoteState> emit) async {
    emit(const NoteDeleting());

    try {
      final token = await _getToken();
      if (token == null) {
        emit(const NoteOperationFailure(message: 'User not authenticated'));
        return;
      }

      await _apiServices.deleteNote(id: event.id, token: token);

      // Reload notes after deleting
      final notes = await _apiServices.getNotes(token);
      emit(
        NoteOperationSuccess(
          message: 'Note deleted successfully',
          notes: notes,
        ),
      );
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

  Future<String?> _getToken() async {
    // First try to get token from AuthBloc
    if (_authBloc.currentToken != null) {
      return _authBloc.currentToken;
    }

    // If not available, get from SharedPreferences
    return await SharedPreferencesService.getToken();
  }
}
