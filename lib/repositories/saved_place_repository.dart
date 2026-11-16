import 'package:sqflite/sqflite.dart';

import '../database/app_database.dart';
import '../models/saved_place_model.dart';

abstract interface class SavedPlaceRepository {
  Future<List<SavedPlace>> getAll();
  Future<List<SavedPlace>> search(String query);
  Future<SavedPlace?> getById(String id);
  Future<bool> contains(String placeKey);
  Future<bool> insert(SavedPlace place);
  Future<void> delete(String id);
}

class SqliteSavedPlaceRepository implements SavedPlaceRepository {
  SqliteSavedPlaceRepository(this._appDatabase);

  final AppDatabase _appDatabase;

  @override
  Future<List<SavedPlace>> getAll() async {
    final Database database = await _appDatabase.database;
    final List<Map<String, Object?>> rows = await database.query(
      'saved_places',
      orderBy: 'saved_at DESC, name COLLATE NOCASE',
    );
    return rows.map(SavedPlace.fromDatabaseMap).toList(growable: false);
  }

  @override
  Future<List<SavedPlace>> search(String query) async {
    final String term = query.trim();
    if (term.isEmpty) return getAll();
    final Database database = await _appDatabase.database;
    final String pattern = '%$term%';
    final List<Map<String, Object?>> rows = await database.query(
      'saved_places',
      where: 'name LIKE ? COLLATE NOCASE OR '
          'display_name LIKE ? COLLATE NOCASE OR '
          'address LIKE ? COLLATE NOCASE',
      whereArgs: [pattern, pattern, pattern],
      orderBy: 'saved_at DESC, name COLLATE NOCASE',
    );
    return rows.map(SavedPlace.fromDatabaseMap).toList(growable: false);
  }

  @override
  Future<SavedPlace?> getById(String id) async {
    final Database database = await _appDatabase.database;
    final List<Map<String, Object?>> rows = await database.query(
      'saved_places',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isEmpty ? null : SavedPlace.fromDatabaseMap(rows.single);
  }

  @override
  Future<bool> contains(String placeKey) async {
    final Database database = await _appDatabase.database;
    final List<Map<String, Object?>> rows = await database.query(
      'saved_places',
      columns: ['id'],
      where: 'place_key = ?',
      whereArgs: [placeKey],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  @override
  Future<bool> insert(SavedPlace place) async {
    final Database database = await _appDatabase.database;
    final int inserted = await database.insert(
      'saved_places',
      place.toDatabaseMap(),
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
    return inserted != 0;
  }

  @override
  Future<void> delete(String id) async {
    final Database database = await _appDatabase.database;
    final int deleted = await database.delete(
      'saved_places',
      where: 'id = ?',
      whereArgs: [id],
    );
    if (deleted == 0) throw SavedPlaceNotFoundException(id);
  }
}

class SavedPlaceNotFoundException implements Exception {
  const SavedPlaceNotFoundException(this.id);

  final String id;

  @override
  String toString() => 'Saved place "$id" was not found.';
}
