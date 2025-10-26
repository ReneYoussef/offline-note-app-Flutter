import 'package:drift/drift.dart';
import 'package:offline_note_app/Database/users_table.dart';

// DataClassName tells Drift to generate a Dart class called 'Note'
@DataClassName('Note')
class Notes extends Table {
  IntColumn get id => integer().autoIncrement()(); // primary key
  IntColumn get userId =>
      integer().references(Users, #id)(); // foreign key to users
  TextColumn get title => text().withLength(min: 1, max: 100)(); // note title
  TextColumn get content => text().named('body')(); // note content
  DateTimeColumn get updatedAt =>
      dateTime().withDefault(currentDateAndTime)(); // last update
  BoolColumn get isSynced =>
      boolean().withDefault(const Constant(false))(); // used later for sync
}
