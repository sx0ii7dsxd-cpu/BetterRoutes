import 'package:sqflite/sqflite.dart';

import '../database/app_database.dart';
import '../models/business_model.dart';

abstract interface class BusinessRepository {
  Future<List<Business>> getForOwner(String ownerUid);
  Future<Business?> getByIdForOwner(String id, String ownerUid);
  Future<int> countTrucksForOwner(String id, String ownerUid);
  Future<void> insert(Business business);
  Future<void> update(Business business);
  Future<void> delete(String id, String ownerUid);
}

class SqliteBusinessRepository implements BusinessRepository {
  SqliteBusinessRepository(this._appDatabase);

  final AppDatabase _appDatabase;

  @override
  Future<List<Business>> getForOwner(String ownerUid) async {
    final Database database = await _appDatabase.database;
    final List<Map<String, Object?>> rows = await database.query(
      'businesses',
      where: 'owner_uid = ?',
      whereArgs: [ownerUid],
      orderBy: 'name COLLATE NOCASE',
    );
    return rows.map(Business.fromDatabaseMap).toList(growable: false);
  }

  @override
  Future<Business?> getByIdForOwner(String id, String ownerUid) async {
    final Database database = await _appDatabase.database;
    final List<Map<String, Object?>> rows = await database.query(
      'businesses',
      where: 'id = ? AND owner_uid = ?',
      whereArgs: [id, ownerUid],
      limit: 1,
    );
    return rows.isEmpty ? null : Business.fromDatabaseMap(rows.single);
  }

  @override
  Future<int> countTrucksForOwner(String id, String ownerUid) async {
    final Database database = await _appDatabase.database;
    final List<Map<String, Object?>> rows = await database.rawQuery(
      '''
      SELECT COUNT(*) AS truck_count
      FROM trucks
      INNER JOIN businesses ON businesses.id = trucks.business_id
      WHERE businesses.id = ? AND businesses.owner_uid = ?
      ''',
      [id, ownerUid],
    );
    return Sqflite.firstIntValue(rows) ?? 0;
  }

  @override
  Future<void> insert(Business business) async {
    final Database database = await _appDatabase.database;
    await database.insert(
      'businesses',
      business.toDatabaseMap(),
      conflictAlgorithm: ConflictAlgorithm.abort,
    );
  }

  @override
  Future<void> update(Business business) async {
    final Database database = await _appDatabase.database;
    final Map<String, Object?> values = business.toDatabaseMap()
      ..remove('id')
      ..remove('owner_uid')
      ..remove('created_at');
    final int updatedRows = await database.update(
      'businesses',
      values,
      where: 'id = ? AND owner_uid = ?',
      whereArgs: [business.id, business.ownerUid],
      conflictAlgorithm: ConflictAlgorithm.abort,
    );
    if (updatedRows == 0) {
      throw BusinessNotFoundException(business.id);
    }
  }

  @override
  Future<void> delete(String id, String ownerUid) async {
    final Database database = await _appDatabase.database;
    final int deletedRows = await database.delete(
      'businesses',
      where: 'id = ? AND owner_uid = ?',
      whereArgs: [id, ownerUid],
    );
    if (deletedRows == 0) throw BusinessNotFoundException(id);
  }
}

class BusinessNotFoundException implements Exception {
  const BusinessNotFoundException(this.id);

  final String id;

  @override
  String toString() => 'Business "$id" was not found for this account.';
}
