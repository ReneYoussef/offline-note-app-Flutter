import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:offline_note_app/pages/Notes/Bloc/note_bloc.dart';
import 'package:offline_note_app/pages/Notes/Bloc/note_event.dart';
import 'package:offline_note_app/pages/Notes/Bloc/note_state.dart';
import 'package:intl/intl.dart';

class ViewNotes extends StatefulWidget {
  final Map<String, dynamic> note;
  const ViewNotes({super.key, required this.note});

  @override
  State<ViewNotes> createState() => _ViewNotesState();
}

class _ViewNotesState extends State<ViewNotes> {
  // final AppDatabase db = AppDatabase(); // Commented out for future offline sync
  bool _isEditing = false;
  TextEditingController? _titleController;
  TextEditingController? _contentController;
  Map<String, dynamic>? _currentNote;

  @override
  void initState() {
    super.initState();
    _currentNote = widget.note;
    _titleController = TextEditingController(
      text: _currentNote?['title'] ?? '',
    );
    _contentController = TextEditingController(
      text: _currentNote?['content'] ?? '',
    );
  }

  @override
  void dispose() {
    _titleController?.dispose();
    _contentController?.dispose();
    super.dispose();
  }

  void _saveChanges() {
    if (_titleController == null || _contentController == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Controllers not initialized'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    if (_titleController!.text.trim().isEmpty ||
        _contentController!.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Title and content cannot be empty'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    if (_currentNote == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Note data not available'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    // Dispatch UpdateNote event to BLoC
    context.read<NoteBloc>().add(
      UpdateNote(
        id: _currentNote!['id'].toString(),
        title: _titleController!.text.trim(),
        body: _contentController!.text.trim(),
      ),
    );
  }

  // Future<void> _deleteNote() async {
  //   final confirmed = await showDialog<bool>(
  //     context: context,
  //     builder: (context) => AlertDialog(
  //       shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
  //       title: const Text('Delete Note'),
  //       content: const Text(
  //         'Are you sure you want to delete this note? This action cannot be undone.',
  //       ),
  //       actions: [
  //         TextButton(
  //           onPressed: () => Navigator.pop(context, false),
  //           child: const Text('Cancel'),
  //         ),
  //         ElevatedButton(
  //           onPressed: () => Navigator.pop(context, true),
  //           style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
  //           child: const Text('Delete'),
  //         ),
  //       ],
  //     ),
  //   );

  //   if (confirmed == true) {
  //     try {
  //       await db.deleteNoteById(_currentNote?.id ?? 0);
  //       if (mounted) {
  //         Navigator.pop(context);
  //         ScaffoldMessenger.of(context).showSnackBar(
  //           const SnackBar(
  //             content: Text('Note deleted successfully'),
  //             backgroundColor: Colors.orange,
  //           ),
  //         );
  //       }
  //     } catch (e) {
  //       ScaffoldMessenger.of(context).showSnackBar(
  //         SnackBar(
  //           content: Text('Error deleting note: ${e.toString()}'),
  //           backgroundColor: Colors.red,
  //         ),
  //       );
  //     }
  //   }
  // }

  @override
  Widget build(BuildContext context) {
    return BlocListener<NoteBloc, NoteState>(
      listener: (context, state) {
        if (state is NoteOperationSuccess) {
          // Update the current note with the new data
          setState(() {
            _isEditing = false;
            _currentNote?['title'] =
                _titleController?.text.trim() ?? _currentNote!['title'];
            _currentNote?['content'] =
                _contentController?.text.trim() ?? _currentNote!['content'];
            _currentNote?['updatedAt'] = DateTime.now();
          });
        } else if (state is NoteOperationFailure) {
          // Show error message
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(state.message), backgroundColor: Colors.red),
          );
        }
      },
      child: BlocBuilder<NoteBloc, NoteState>(
        builder: (context, state) {
          final isLoading = state is NoteUpdating;

          return Scaffold(
            backgroundColor: Colors.grey[50],
            appBar: AppBar(
              elevation: 0,
              backgroundColor: Colors.white,
              foregroundColor: Colors.black87,
              leading: IconButton(
                icon: const Icon(Icons.arrow_back_ios),
                onPressed: () => Navigator.pop(context),
              ),
              title: Text(
                _isEditing ? 'Edit Note' : 'View Note',
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 20,
                ),
              ),
              actions: [
                if (_isEditing) ...[
                  IconButton(
                    onPressed: () {
                      setState(() {
                        _isEditing = false;
                        _titleController?.text = _currentNote?['title'] ?? '';
                        _contentController?.text =
                            _currentNote?['content'] ?? '';
                      });
                    },
                    icon: const Icon(Icons.close),
                    tooltip: 'Cancel',
                  ),
                  IconButton(
                    onPressed: isLoading ? null : _saveChanges,
                    icon: isLoading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                Colors.white,
                              ),
                            ),
                          )
                        : const Icon(Icons.check),
                    tooltip: isLoading ? 'Saving...' : 'Save',
                  ),
                ] else ...[
                  IconButton(
                    onPressed: () {
                      setState(() {
                        _isEditing = true;
                      });
                    },
                    icon: const Icon(Icons.edit),
                    tooltip: 'Edit',
                  ),
                  PopupMenuButton<String>(
                    onSelected: (value) {
                      switch (value) {
                        case 'delete':
                          // Use BLoC for delete instead of local DB
                          context.read<NoteBloc>().add(
                            DeleteNote(
                              id: _currentNote?['id'].toString() ?? '',
                            ),
                          );
                          Navigator.pop(context); // Close the view after delete
                          break;
                        case 'share':
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Share functionality coming soon!'),
                            ),
                          );
                          break;
                      }
                    },
                    itemBuilder: (context) => [
                      const PopupMenuItem(
                        value: 'share',
                        child: Row(
                          children: [
                            Icon(Icons.share, size: 20),
                            SizedBox(width: 8),
                            Text('Share'),
                          ],
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'delete',
                        child: Row(
                          children: [
                            Icon(Icons.delete, color: Colors.red, size: 20),
                            SizedBox(width: 8),
                            Text('Delete'),
                          ],
                        ),
                      ),
                    ],
                    icon: const Icon(Icons.more_vert),
                  ),
                ],
              ],
            ),
            body: _buildNoteContent(),
          );
        },
      ),
    );
  }

  Widget _buildNoteContent() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Note Header Card
          Card(
            elevation: 2,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                gradient: LinearGradient(
                  colors: [Colors.blue[50]!, Colors.blue[100]!],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.blue[600],
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(
                          Icons.note_alt,
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Note Details',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: Colors.blue[800],
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    DateFormat('EEEE, MMMM dd, yyyy').format(
                      _currentNote?['updatedAt'] is DateTime
                          ? _currentNote!['updatedAt']
                          : DateTime.parse(
                              _currentNote?['updatedAt'].toString() ??
                                  DateTime.now().toIso8601String(),
                            ),
                    ),
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.blue[700],
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    DateFormat('h:mm a').format(
                      _currentNote?['updatedAt'] is DateTime
                          ? _currentNote!['updatedAt']
                          : DateTime.parse(
                              _currentNote?['updatedAt'].toString() ??
                                  DateTime.now().toIso8601String(),
                            ),
                    ),
                    style: TextStyle(fontSize: 12, color: Colors.blue[600]),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),

          // Title Section
          _buildSection(
            'Title',
            _isEditing
                ? TextFormField(
                    controller: _titleController,
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                    decoration: InputDecoration(
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      filled: true,
                      fillColor: Colors.white,
                    ),
                  )
                : Text(
                    _currentNote?['title'] ?? '',
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                  ),
          ),
          const SizedBox(height: 24),

          // Content Section
          _buildSection(
            'Content',
            _isEditing
                ? TextFormField(
                    controller: _contentController,
                    maxLines: null,
                    style: const TextStyle(fontSize: 16, height: 1.6),
                    decoration: InputDecoration(
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      filled: true,
                      fillColor: Colors.white,
                      hintText: 'Write your note content here...',
                    ),
                  )
                : Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey[200]!),
                    ),
                    child: Text(
                      _currentNote?['content'] ?? '',
                      style: const TextStyle(
                        fontSize: 16,
                        height: 1.6,
                        color: Colors.black87,
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildSection(String label, Widget child) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: Colors.grey[600],
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 8),
        child,
      ],
    );
  }
}
