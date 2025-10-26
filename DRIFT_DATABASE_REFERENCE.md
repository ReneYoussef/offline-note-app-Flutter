# 📚 **Drift Database Reference Guide**
## Complete Guide to Using Drift Offline Database in Flutter

---

## 🗂️ **File Structure Overview**
```
lib/
├── Database/
│   ├── app_database.dart      # Main database configuration
│   └── Note_tables.dart       # Table definitions
├── pages/
│   ├── Addnote.dart          # CREATE operations
│   ├── NotesPage.dart        # READ operations  
│   └── ViewNotes.dart        # UPDATE operations
└── services/
    └── auth_service.dart     # User authentication
```

---

## 🏗️ **1. DATABASE SETUP (app_database.dart)**

### **🔧 Singleton Pattern Implementation**
```dart
class AppDatabase extends _$AppDatabase {
  static AppDatabase? _instance;
  AppDatabase._internal() : super(_openConnection());
  
  factory AppDatabase() {
    _instance ??= AppDatabase._internal();
    return _instance!;
  }
}
```
**📝 Notes:**
- **Singleton ensures single database instance** across the app
- **Prevents multiple database connections** that could cause corruption
- **Use `AppDatabase()` to get the instance anywhere in the app**

### **🔗 Database Connection**
```dart
LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dbFolder = await getApplicationDocumentsDirectory();
    final file = File('${dbFolder.path}/notes.db');
    
    await dbFolder.create(recursive: true);
    if (!await file.exists()) {
      await file.create(recursive: true);
    }
    
    return NativeDatabase.createInBackground(file);
  });
}
```
**📝 Notes:**
- **LazyDatabase** delays connection until first use
- **NativeDatabase** provides better performance than WebDatabase
- **File path** stores database in app's documents directory
- **Error handling** includes database recreation on failure

---

## ➕ **2. CREATE OPERATIONS (Addnote.dart)**

### **🎯 Key Function: `saveNote()`**
```dart
Future<void> saveNote() async {
  if (title.isNotEmpty && content.isNotEmpty) {
    final currentUserId = AuthService.getCurrentUserId();
    if (currentUserId != null) {
      try {
        await db.addNote(
          NotesCompanion.insert(
            userId: currentUserId,
            title: title,
            content: content,
          ),
        );
      } catch (e) {
        // Error handling with database reset option
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error saving note: ${e.toString()}'),
            action: SnackBarAction(
              label: 'Reset DB',
              onPressed: () async {
                await AppDatabase.resetDatabase();
              },
            ),
          ),
        );
      }
    }
  }
}
```

**📝 Key Concepts:**
- **`NotesCompanion.insert()`** - Drift's way to insert new records
- **User authentication check** - Ensures user is logged in
- **Error handling** - Provides database reset option on failure
- **Validation** - Checks for non-empty title and content

**🔍 What to Remember:**
- Always wrap database operations in try-catch
- Use `NotesCompanion.insert()` for new records
- Include user ID for data ownership
- Provide user feedback on success/failure

---

## 📖 **3. READ OPERATIONS (NotesPage.dart)**

### **🎯 Key Function: `loadNotes()`**
```dart
Future<void> loadNotes() async {
  final currentUserId = AuthService.getCurrentUserId();
  if (currentUserId != null) {
    final userNotes = await db.getNotesForUser(currentUserId);
    setState(() => notes = userNotes);
  } else {
    setState(() => notes = []);
  }
}
```

**📝 Key Concepts:**
- **`getNotesForUser(userId)`** - Fetches notes for specific user
- **setState()** - Updates UI with new data
- **User filtering** - Only shows notes belonging to current user
- **Empty state handling** - Shows empty list if no user

### **🎯 Key Function: `addNote()` (Test Function)**
```dart
Future<void> addNote() async {
  final currentUserId = AuthService.getCurrentUserId();
  if (currentUserId != null) {
    await db.addNote(
      NotesCompanion.insert(
        userId: currentUserId,
        title: 'New Note',
        content: 'This is a test note',
      ),
    );
    await loadNotes(); // Refresh the list
  }
}
```

**📝 Key Concepts:**
- **Immediate refresh** - Calls `loadNotes()` after insert
- **User association** - Links note to current user
- **Simple test data** - Creates basic note for testing

### **🎯 Key Function: `deleteNote()`**
```dart
Future<void> deleteNote(Note note) async {
  await db.deleteNoteById(note.id);
  await loadNotes(); // Refresh the list
}
```

**📝 Key Concepts:**
- **`deleteNoteById(id)`** - Removes note by ID
- **Immediate refresh** - Updates UI after deletion
- **ID-based deletion** - Uses primary key for efficiency

---

## ✏️ **4. UPDATE OPERATIONS (ViewNotes.dart)**

### **🎯 Key Function: `_saveChanges()`**
```dart
Future<void> _saveChanges() async {
  if (_currentNote == null) return;
  
  final updatedNote = _currentNote!.copyWith(
    title: _titleController!.text.trim(),
    content: _contentController!.text.trim(),
    updatedAt: DateTime.now(),
  );
  
  await db.updateNote(updatedNote);
  
  setState(() {
    _isEditing = false;
    _currentNote = updatedNote; // Update local state
  });
}
```

**📝 Key Concepts:**
- **`copyWith()`** - Creates new Note object with updated fields
- **`updateNote(note)`** - Updates existing record in database
- **Local state update** - Updates `_currentNote` for immediate UI refresh
- **Timestamp update** - Sets `updatedAt` to current time

### **🎯 Key Function: `_deleteNote()`**
```dart
Future<void> _deleteNote() async {
  final confirmed = await showDialog<bool>(...);
  
  if (confirmed == true) {
    try {
      await db.deleteNoteById(_currentNote!.id);
      if (mounted) {
        Navigator.pop(context); // Return to notes list
      }
    } catch (e) {
      // Error handling
    }
  }
}
```

**📝 Key Concepts:**
- **Confirmation dialog** - Asks user before deletion
- **Navigation after delete** - Returns to previous page
- **Error handling** - Catches and displays errors
- **Mounted check** - Ensures widget is still active

---

## 🔧 **5. DATABASE UTILITY FUNCTIONS**

### **🐛 Debug Functions**
```dart
Future<void> debugDatabase() async {
  await db.debugPrintAllNotes();
  await db.debugPrintAllUsers();
}
```

### **🔄 Reset Function**
```dart
Future<void> resetDatabase() async {
  await AppDatabase.resetDatabase();
  // Show user feedback
}
```

### **🏥 Health Check**
```dart
Future<void> checkDatabaseHealth() async {
  final hasPermissions = await AppDatabase.checkDatabasePermissions();
  // Show appropriate message
}
```

---

## 📋 **6. COMMON PATTERNS & BEST PRACTICES**

### **✅ Always Do:**
```dart
// 1. Check user authentication
final currentUserId = AuthService.getCurrentUserId();
if (currentUserId == null) return;

// 2. Wrap in try-catch
try {
  await db.someOperation();
} catch (e) {
  // Handle error
}

// 3. Update UI after database changes
setState(() {
  // Update local state
});

// 4. Check if widget is mounted
if (mounted) {
  Navigator.pop(context);
}
```

### **❌ Never Do:**
```dart
// Don't create multiple database instances
final db1 = AppDatabase();
final db2 = AppDatabase(); // Wrong!

// Don't forget error handling
await db.addNote(...); // Could throw exception

// Don't update UI without setState
notes = newNotes; // UI won't update
```

---

## 🎯 **7. CRUD OPERATIONS SUMMARY**

| Operation | Method | Usage | Example |
|-----------|--------|-------|---------|
| **CREATE** | `db.addNote()` | Add new record | `NotesCompanion.insert()` |
| **READ** | `db.getNotesForUser()` | Fetch records | `await db.getNotesForUser(userId)` |
| **UPDATE** | `db.updateNote()` | Modify existing | `note.copyWith(title: newTitle)` |
| **DELETE** | `db.deleteNoteById()` | Remove record | `await db.deleteNoteById(noteId)` |

---

## 🚀 **8. QUICK REFERENCE**

### **Database Instance:**
```dart
final AppDatabase db = AppDatabase(); // Singleton
```

### **Insert New Record:**
```dart
await db.addNote(NotesCompanion.insert(
  userId: userId,
  title: title,
  content: content,
));
```

### **Update Existing Record:**
```dart
final updatedNote = note.copyWith(
  title: newTitle,
  updatedAt: DateTime.now(),
);
await db.updateNote(updatedNote);
```

### **Delete Record:**
```dart
await db.deleteNoteById(noteId);
```

### **Fetch Records:**
```dart
final notes = await db.getNotesForUser(userId);
```

---

## 💡 **9. TROUBLESHOOTING TIPS**

### **Common Issues:**
1. **Database locked errors** → Use singleton pattern
2. **Migration errors** → Reset database in development
3. **Permission errors** → Check file system permissions
4. **Null reference errors** → Always check for null values

### **Debug Commands:**
```dart
// Print all notes
await db.debugPrintAllNotes();

// Check database health
await AppDatabase.checkDatabasePermissions();

// Reset database (development only)
await AppDatabase.resetDatabase();
```

---

## 📚 **10. LEARNING RESOURCES**

- **Drift Documentation:** https://drift.simonbinder.eu/
- **Flutter Database Guide:** https://docs.flutter.dev/cookbook/persistence/sqlite
- **Singleton Pattern:** https://flutter.dev/docs/development/data-and-backend/state-mgmt/simple

---

**🎉 Happy Coding with Drift Database!** 🎉
