import 'package:drift/drift.dart';
import 'package:drift/native.dart'; // contains NativeDatabase
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'package:offline_note_app/Database/Note_tables.dart';
import 'package:offline_note_app/Database/users_table.dart';

part 'app_database.g.dart'; // Drift will generate this file

@DriftDatabase(tables: [Notes, Users])
class AppDatabase extends _$AppDatabase {
  // Singleton instance
  static AppDatabase? _instance;

  // Private constructor opens the database
  AppDatabase._internal() : super(_openConnection());

  // Factory constructor that returns the singleton instance
  factory AppDatabase() {
    _instance ??= AppDatabase._internal();
    return _instance!;
  }

  // Increment schema version when tables change
  @override
  int get schemaVersion => 3;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (Migrator m) async {
      await m.createAll();
    },
    onUpgrade: (Migrator m, int from, int to) async {
      if (from < 2) {
        // Add Users table
        await m.createTable(users);
      }
      if (from < 3) {
        // Add userId column to notes table
        // Use try-catch to handle case where column already exists
        try {
          await m.addColumn(notes, notes.userId);
        } catch (e) {
          // Column might already exist, this is okay
          print('Column user_id might already exist, continuing...');
        }
      }
    },
  );

  // CRUD helper functions

  // Add a note for a specific user
  Future<int> addNote(NotesCompanion note) => into(notes).insert(note);

  // Get all notes for a specific user
  Future<List<Note>> getNotesForUser(int userId) =>
      (select(notes)..where((t) => t.userId.equals(userId))).get();

  // Get all notes (for admin purposes)
  Future<List<Note>> getAllNotes() => select(notes).get();
  // Update note
  Future updateNote(Note note) => update(notes).replace(note);
  // Delete note by ID
  Future deleteNoteById(int id) =>
      (delete(notes)..where((t) => t.id.equals(id))).go();

  // Debug method to print all notes
  Future<void> debugPrintAllNotes() async {
    final allNotes = await getAllNotes();
    print('=== DATABASE DEBUG ===');
    print('Total notes: ${allNotes.length}');
    for (final note in allNotes) {
      print('ID: ${note.id}, Title: ${note.title}, Content: ${note.content}');
    }
    print('=====================');
  }

  // Debug method to print all users
  Future<void> debugPrintAllUsers() async {
    final allUsers = await getAllUsers();
    print('=== DATABASE DEBUG ===');
    print('Total users: ${allUsers.length}');
    for (final user in allUsers) {
      print('ID: ${user.id}, Name: ${user.name}, Email: ${user.email}');
    }
  }

  /////////////////////////////////////users/////////////////////////////////////

  ///// Add a new user
  Future<int> addUser(UsersCompanion user) => into(users).insert(user);

  // Get all users
  Future<List<User>> getAllUsers() => select(users).get();

  // Update a user
  Future updateUser(User user) => update(users).replace(user);

  // Delete user by ID
  Future deleteUserById(int id) =>
      (delete(users)..where((t) => t.id.equals(id))).go();

  // Get user by email
  Future<List<User>> getUserByEmail(String email) =>
      (select(users)..where((t) => t.email.equals(email))).get();

  // Helper method to reset database (for development purposes)
  static Future<void> resetDatabase() async {
    final dbFolder = await getApplicationDocumentsDirectory();
    final file = File('${dbFolder.path}/notes.db');
    if (await file.exists()) {
      await file.delete();
      print('Database file deleted. App will recreate it on next run.');
    }
  }

  // Helper method to check and fix database permissions
  static Future<bool> checkDatabasePermissions() async {
    try {
      final dbFolder = await getApplicationDocumentsDirectory();
      final file = File('${dbFolder.path}/notes.db');

      // Test if we can write to the directory
      final testFile = File('${dbFolder.path}/test_write.tmp');
      await testFile.writeAsString('test');
      await testFile.delete();

      return true;
    } catch (e) {
      print('Database permission error: $e');
      return false;
    }
  }
}

// Open database connection
LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dbFolder = await getApplicationDocumentsDirectory();
    final file = File('${dbFolder.path}/notes.db');

    // Ensure the directory exists
    await dbFolder.create(recursive: true);

    // Create the database file if it doesn't exist
    if (!await file.exists()) {
      await file.create(recursive: true);
    }

    // Use a more robust database creation approach
    try {
      return NativeDatabase.createInBackground(file);
    } catch (e) {
      // If there's an issue with the existing file, delete and recreate
      print('Database connection error: $e');
      print('Attempting to recreate database...');

      if (await file.exists()) {
        await file.delete();
      }

      // Create a fresh database file
      await file.create(recursive: true);
      return NativeDatabase.createInBackground(file);
    }
  });
}
