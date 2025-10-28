import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:offline_note_app/pages/Notes/Addnote.dart';
import 'package:offline_note_app/services/shared_preferences_service.dart';
import 'package:offline_note_app/pages/auth/login.dart';
import 'package:offline_note_app/pages/auth/Bloc/auth_bloc.dart';
import 'package:offline_note_app/pages/auth/Bloc/auth_event.dart';
import 'package:offline_note_app/pages/auth/Bloc/auth_state.dart';
import 'package:offline_note_app/pages/Notes/ViewNotes.dart';
import 'package:offline_note_app/pages/Notes/Bloc/note_bloc.dart';
import 'package:offline_note_app/pages/Notes/Bloc/note_event.dart';
import 'package:offline_note_app/pages/Notes/Bloc/note_state.dart';
import 'package:offline_note_app/widgets/note_shimmer.dart';
import 'package:offline_note_app/services/firestore_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

class NotesPage extends StatefulWidget {
  const NotesPage({super.key});

  @override
  State<NotesPage> createState() => _NotesPageState();
}

class _NotesPageState extends State<NotesPage> {
  List<Map<String, dynamic>> notes = [];
  String? userName;
  bool isOnline = true;

  @override
  void initState() {
    super.initState();
    print('NotesPage initState called');
    // Load notes using BLoC only if not already loaded
    final currentState = context.read<NoteBloc>().state;
    print('Current BLoC state: ${currentState.runtimeType}');
    if (currentState is NoteInitial) {
      print('Triggering LoadNotes because state is NoteInitial');
      context.read<NoteBloc>().add(const LoadNotes());
    } else {
      print('Skipping LoadNotes because state is not NoteInitial');
    }
    _loadUserName();
    _listenToConnectivity();
  }

  void _listenToConnectivity() {
    FirestoreService.connectivityStream.listen((online) {
      if (mounted) {
        setState(() {
          isOnline = online;
        });
      }
    });
  }

  Future<void> _loadUserName() async {
    final name = await SharedPreferencesService.getUserName();
    if (mounted) {
      setState(() {
        userName = name;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return MultiBlocListener(
      listeners: [
        BlocListener<NoteBloc, NoteState>(
          listener: (context, state) {
            if (state is NoteLoaded) {
              setState(() {
                notes = state.notes;
              });
            } else if (state is NoteOperationSuccess) {
              setState(() {
                notes = state.notes;
              });
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(state.message),
                  backgroundColor: Colors.green,
                ),
              );
            } else if (state is NoteOperationFailure) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(state.message),
                  backgroundColor: Colors.red,
                ),
              );
            }
          },
        ),
        BlocListener<AuthBloc, AuthState>(
          listener: (context, state) {
            if (state is AuthUnauthenticated) {
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (context) => const Login()),
              );
            }
          },
        ),
      ],
      child: BlocBuilder<NoteBloc, NoteState>(
        builder: (context, state) {
          print('NotesPage received state: ${state.runtimeType}');
          if (state is NoteLoaded) {
            print('NotesPage has ${state.notes.length} notes');
          } else if (state is NoteLoading) {
            print('NotesPage is in loading state');
          }
          return Scaffold(
            backgroundColor: Colors.grey[50],
            appBar: AppBar(
              automaticallyImplyLeading: false,
              elevation: 0,
              backgroundColor: Colors.white,
              foregroundColor: Colors.black87,
              title: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        'Welcome, ${userName ?? 'User'}!',
                        style: const TextStyle(
                          fontWeight: FontWeight.w500,
                          fontSize: 16,
                          color: Colors.grey,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: isOnline ? Colors.green : Colors.orange,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          isOnline ? 'Online' : 'Offline',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  const Text(
                    'My Notes',
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 24),
                  ),
                ],
              ),
              actions: [
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert),
                  onSelected: (value) {
                    switch (value) {
                      case 'sync':
                        context.read<NoteBloc>().add(const SyncNotes());
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Syncing notes to cloud...'),
                            duration: Duration(seconds: 2),
                          ),
                        );
                        break;
                      case 'logout':
                        context.read<AuthBloc>().add(
                          const AuthLogoutRequested(),
                        );
                        break;
                    }
                  },
                  itemBuilder: (context) => [
                    const PopupMenuItem(
                      value: 'sync',
                      child: Row(
                        children: [
                          Icon(Icons.sync, size: 20),
                          SizedBox(width: 8),
                          Text('Sync to Cloud'),
                        ],
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'logout',
                      child: Row(
                        children: [
                          Icon(Icons.logout, size: 20),
                          SizedBox(width: 8),
                          Text('Logout'),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
            body: _buildBody(state),
            floatingActionButton: FloatingActionButton.extended(
              onPressed: () async {
                await showDialog(
                  context: context,
                  builder: (context) => const AddNote(),
                );
                context.read<NoteBloc>().add(const RefreshNotes());
              },
              backgroundColor: Colors.blue[600],
              foregroundColor: Colors.white,
              icon: const Icon(Icons.add),
              label: const Text('New Note'),
              elevation: 4,
            ),
          );
        },
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.blue[50],
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.note_add, size: 64, color: Colors.blue[400]),
          ),
          const SizedBox(height: 24),
          Text(
            'No notes yet',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w600,
              color: Colors.grey[700],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Tap the + button to create your first note',
            style: TextStyle(fontSize: 16, color: Colors.grey[500]),
          ),
        ],
      ),
    );
  }

  Widget _buildBody(NoteState state) {
    // Show shimmer loading when notes are being loaded
    if (state is NoteLoading) {
      return const NoteShimmer();
    }

    // Show notes based on state
    if (state is NoteLoaded) {
      if (state.notes.isEmpty) {
        return _buildEmptyState();
      }
      return _buildNoteListView(state.notes);
    }

    // Show empty state if no notes or other states
    if (notes.isEmpty) {
      return _buildEmptyState();
    }

    // Show notes list
    return _buildNoteListView();
  }

  Widget _buildNoteListView([List<Map<String, dynamic>>? notesList]) {
    final notesToShow = notesList ?? notes;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: GridView.builder(
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          childAspectRatio: 0.8,
          crossAxisSpacing: 16,
          mainAxisSpacing: 16,
        ),
        itemCount: notesToShow.length,
        itemBuilder: (context, index) {
          final note = notesToShow[index];
          return _buildNoteCard(note, context);
        },
      ),
    );
  }

  Widget _buildNoteCard(Map<String, dynamic> note, BuildContext context) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () async {
          // Navigate to ViewNotes with the note data
          await Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => ViewNotes(note: note)),
          );
          context.read<NoteBloc>().add(const RefreshNotes());
        },
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      note['title'] ?? 'Untitled',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  PopupMenuButton<String>(
                    onSelected: (value) async {
                      if (value == 'delete') {
                        context.read<NoteBloc>().add(
                          DeleteNote(id: note['id'].toString()),
                        );
                      }
                    },
                    itemBuilder: (context) => [
                      const PopupMenuItem(
                        value: 'delete',
                        child: Row(
                          children: [
                            Icon(Icons.delete, color: Colors.red),
                            SizedBox(width: 8),
                            Text('Delete'),
                          ],
                        ),
                      ),
                    ],
                    child: const Icon(
                      Icons.more_vert,
                      size: 20,
                      color: Colors.grey,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Expanded(
                child: Text(
                  note['body'] ?? note['content'] ?? 'No content',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey[600],
                    height: 1.4,
                  ),
                  maxLines: 6,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    note['createdAt'] != null
                        ? DateFormat(
                            'MMM dd, yyyy',
                          ).format(_parseDateTime(note['createdAt']))
                        : 'No date',
                    style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                  ),
                  _buildSyncStatus(note),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSyncStatus(Map<String, dynamic> note) {
    final isLocal = note['isLocal'] == true;
    final hasApiId = note['apiId'] != null;

    if (isLocal) {
      // Note is local only (not synced to Firestore yet)
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.cloud_off, size: 14, color: Colors.orange[600]),
          const SizedBox(width: 4),
          Text(
            'Local',
            style: TextStyle(
              fontSize: 10,
              color: Colors.orange[600],
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      );
    } else if (hasApiId) {
      // Note is synced to both Firestore and API
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.cloud_done, size: 14, color: Colors.green[600]),
          const SizedBox(width: 4),
          Text(
            'Synced',
            style: TextStyle(
              fontSize: 10,
              color: Colors.green[600],
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      );
    } else {
      // Note is in Firestore but not synced to API yet
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.cloud_upload, size: 14, color: Colors.blue[600]),
          const SizedBox(width: 4),
          Text(
            'Pending',
            style: TextStyle(
              fontSize: 10,
              color: Colors.blue[600],
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      );
    }
  }

  DateTime _parseDateTime(dynamic dateValue) {
    try {
      if (dateValue == null) return DateTime.now();

      if (dateValue is DateTime) {
        return dateValue;
      }

      if (dateValue is Timestamp) {
        return dateValue.toDate();
      }

      if (dateValue is String) {
        return DateTime.parse(dateValue);
      }

      return DateTime.now();
    } catch (e) {
      print('Error parsing date: $e');
      return DateTime.now();
    }
  }
}
