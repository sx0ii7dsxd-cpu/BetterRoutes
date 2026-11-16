import 'package:sqflite/sqflite.dart';

import '../database/app_database.dart';
import '../models/warehouse_model.dart';

abstract interface class WarehouseRepository {
  Future<List<Warehouse>> getAll();
  Future<Warehouse?> getById(String id);
  Future<List<Warehouse>> search(String query);
  Future<void> insert(Warehouse warehouse);
  Future<void> update(Warehouse warehouse);
  Future<void> delete(String id);
}

class SqliteWarehouseRepository implements WarehouseRepository {
  SqliteWarehouseRepository(this._appDatabase);

  final AppDatabase _appDatabase;

  @override
  Future<List<Warehouse>> getAll() async {
    final Database database = await _appDatabase.database;
    final List<Map<String, Object?>> rows = await database.query(
      'warehouses',
      orderBy: 'name COLLATE NOCASE',
    );
    return rows.map(Warehouse.fromDatabaseMap).toList(growable: false);
  }

  @override
  Future<Warehouse?> getById(String id) async {
    final Database database = await _appDatabase.database;
    final List<Map<String, Object?>> rows = await database.query(
      'warehouses',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isEmpty ? null : Warehouse.fromDatabaseMap(rows.single);
  }

  @override
  Future<List<Warehouse>> search(String query) async {
    final String term = query.trim();
    if (term.isEmpty) return getAll();

    final Database database = await _appDatabase.database;
    final String pattern = '%$term%';
    final List<Map<String, Object?>> rows = await database.query(
      'warehouses',
      where: '''
        name LIKE ? COLLATE NOCASE OR
        warehouse_code LIKE ? COLLATE NOCASE OR
        address LIKE ? COLLATE NOCASE OR
        contact_name LIKE ? COLLATE NOCASE OR
        contact_number LIKE ? COLLATE NOCASE OR
        location_note LIKE ? COLLATE NOCASE
      ''',
      whereArgs: List<String>.filled(6, pattern),
      orderBy: 'name COLLATE NOCASE',
    );
    return rows.map(Warehouse.fromDatabaseMap).toList(growable: false);
  }

  @override
  Future<void> insert(Warehouse warehouse) async {
    final Database database = await _appDatabase.database;
    await database.insert(
      'warehouses',
      warehouse.toDatabaseMap(),
      conflictAlgorithm: ConflictAlgorithm.abort,
    );
  }

  @override
  Future<void> update(Warehouse warehouse) async {
    final Database database = await _appDatabase.database;
    final int changedRows = await database.update(
      'warehouses',
      warehouse.toDatabaseMap()..remove('id'),
      where: 'id = ?',
      whereArgs: [warehouse.id],
      conflictAlgorithm: ConflictAlgorithm.abort,
    );
    if (changedRows == 0) {
      throw WarehouseNotFoundException(warehouse.id);
    }
  }

  @override
  Future<void> delete(String id) async {
    final Database database = await _appDatabase.database;
    final int deletedRows = await database.delete(
      'warehouses',
      where: 'id = ?',
      whereArgs: [id],
    );
    if (deletedRows == 0) {
      throw WarehouseNotFoundException(id);
    }
  }
}

class WarehouseNotFoundException implements Exception {
  const WarehouseNotFoundException(this.id);

  final String id;

  @override
  String toString() => 'Warehouse "$id" was not found.';
}
