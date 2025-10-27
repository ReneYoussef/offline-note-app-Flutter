import 'package:equatable/equatable.dart';

abstract class NoteEvent extends Equatable {
  const NoteEvent();
  @override
  List<Object> get props => [];
}

class LoadNotes extends NoteEvent {
  const LoadNotes();
  @override
  List<Object> get props => [];
}

class CreateNote extends NoteEvent {
  final String title;
  final String body;

  const CreateNote({required this.title, required this.body});
  @override
  List<Object> get props => [title, body];
}

class UpdateNote extends NoteEvent {
  final String id;
  final String title;
  final String body;

  const UpdateNote({required this.id, required this.title, required this.body});
  @override
  List<Object> get props => [id, title, body];
}

class DeleteNote extends NoteEvent {
  final String id;

  const DeleteNote({required this.id});
  @override
  List<Object> get props => [id];
}

class RefreshNotes extends NoteEvent {
  const RefreshNotes();
  @override
  List<Object> get props => [];
}

class SyncNotes extends NoteEvent {
  const SyncNotes();
  @override
  List<Object> get props => [];
}
