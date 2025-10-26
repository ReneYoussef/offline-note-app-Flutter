import 'package:equatable/equatable.dart';

abstract class NoteState extends Equatable {
  const NoteState();
  @override
  List<Object> get props => [];
}

class NoteInitial extends NoteState {
  const NoteInitial();
}

class NoteLoading extends NoteState {
  const NoteLoading();
}

class NoteLoaded extends NoteState {
  final List<Map<String, dynamic>> notes;

  const NoteLoaded({required this.notes});
  @override
  List<Object> get props => [notes];
}

class NoteOperationSuccess extends NoteState {
  final String message;
  final List<Map<String, dynamic>> notes;

  const NoteOperationSuccess({
    required this.message,
    required this.notes,
  });
  @override
  List<Object> get props => [message, notes];
}

class NoteOperationFailure extends NoteState {
  final String message;

  const NoteOperationFailure({required this.message});
  @override
  List<Object> get props => [message];
}

class NoteCreating extends NoteState {
  const NoteCreating();
}

class NoteUpdating extends NoteState {
  const NoteUpdating();
}

class NoteDeleting extends NoteState {
  const NoteDeleting();
}