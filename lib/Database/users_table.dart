import 'package:drift/drift.dart';

@DataClassName('User')
class Users extends Table {
  IntColumn get id => integer().autoIncrement()(); // primary key
  TextColumn get name => text().withLength(min: 1, max: 100)(); // user name
  TextColumn get email =>
      text().withLength(min: 1, max: 100).unique()(); // user email
  TextColumn get password =>
      text().withLength(min: 1, max: 100)(); // user password
}
