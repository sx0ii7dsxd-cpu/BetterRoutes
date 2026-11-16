import 'package:sqflite/sqflite.dart';

import '../database/app_database.dart';
import '../models/truck_model.dart';

abstract interface class TruckRepository {
  Future<List<Truck>> getForOwner(
    String ownerUid, {
    String? approvalStatus,
    String? businessId,
    String? warehouseId,
  });
  Future<List<Truck>> searchForOwner(
    String ownerUid,
    String query, {
    String? approvalStatus,
    String? businessId,
    String? warehouseId,
  });
  Future<Truck?> getByIdForOwner(String id, String ownerUid);
  Future<void> insert(Truck truck);
  Future<void> update(Truck truck);
  Future<void> delete(String id);
}

class SqliteTruckRepository implements TruckRepository {
  SqliteTruckRepository(this._appDatabase);

  final AppDatabase _appDatabase;

  static const String _joinedColumns = '''
    SELECT trucks.*,
      warehouses.name AS warehouse_name,
      warehouses.warehouse_code AS warehouse_code,
      businesses.name AS business_name
    FROM trucks
    INNER JOIN warehouses ON warehouses.id = trucks.warehouse_id
    INNER JOIN businesses ON businesses.id = trucks.business_id
  ''';

  @override
  Future<List<Truck>> getForOwner(
    String ownerUid, {
    String? approvalStatus,
    String? businessId,
    String? warehouseId,
  }) async {
    final Database database = await _appDatabase.database;
    final List<String> conditions = ['businesses.owner_uid = ?'];
    final List<Object?> arguments = [ownerUid];
    if (approvalStatus != null) {
      conditions.add('trucks.approval_status = ?');
      arguments.add(approvalStatus);
    }
    if (businessId != null) {
      conditions.add('trucks.business_id = ?');
      arguments.add(businessId);
    }
    if (warehouseId != null) {
      conditions.add('trucks.warehouse_id = ?');
      arguments.add(warehouseId);
    }
    final List<Map<String, Object?>> rows = await database.rawQuery(
      '$_joinedColumns WHERE ${conditions.join(' AND ')} '
      'ORDER BY trucks.registration_number COLLATE NOCASE',
      arguments,
    );
    return rows.map(Truck.fromDatabaseMap).toList(growable: false);
  }

  @override
  Future<List<Truck>> searchForOwner(
    String ownerUid,
    String query, {
    String? approvalStatus,
    String? businessId,
    String? warehouseId,
  }) async {
    final String term = query.trim();
    if (term.isEmpty) {
      return getForOwner(
        ownerUid,
        approvalStatus: approvalStatus,
        businessId: businessId,
        warehouseId: warehouseId,
      );
    }

    final Database database = await _appDatabase.database;
    final String pattern = '%$term%';
    final List<String> conditions = ['businesses.owner_uid = ?'];
    final List<Object?> arguments = [ownerUid];
    if (approvalStatus != null) {
      conditions.add('trucks.approval_status = ?');
      arguments.add(approvalStatus);
    }
    if (businessId != null) {
      conditions.add('trucks.business_id = ?');
      arguments.add(businessId);
    }
    if (warehouseId != null) {
      conditions.add('trucks.warehouse_id = ?');
      arguments.add(warehouseId);
    }
    conditions.add('''
      (
        trucks.registration_number LIKE ? COLLATE NOCASE OR
        trucks.truck_type LIKE ? COLLATE NOCASE OR
        trucks.capacity LIKE ? COLLATE NOCASE OR
        trucks.details LIKE ? COLLATE NOCASE OR
        trucks.driver_name LIKE ? COLLATE NOCASE OR
        trucks.driver_contact_number LIKE ? COLLATE NOCASE OR
        warehouses.name LIKE ? COLLATE NOCASE OR
        warehouses.warehouse_code LIKE ? COLLATE NOCASE OR
        businesses.name LIKE ? COLLATE NOCASE
      )
    ''');
    arguments.addAll(List<String>.filled(9, pattern));
    final List<Map<String, Object?>> rows = await database.rawQuery('''
      $_joinedColumns
      WHERE ${conditions.join(' AND ')}
      ORDER BY trucks.registration_number COLLATE NOCASE
      ''', arguments);
    return rows.map(Truck.fromDatabaseMap).toList(growable: false);
  }

  @override
  Future<Truck?> getByIdForOwner(String id, String ownerUid) async {
    final Database database = await _appDatabase.database;
    final List<Map<String, Object?>> rows = await database.rawQuery(
      '$_joinedColumns '
      'WHERE trucks.id = ? AND businesses.owner_uid = ? LIMIT 1',
      [id, ownerUid],
    );
    return rows.isEmpty ? null : Truck.fromDatabaseMap(rows.single);
  }

  @override
  Future<void> insert(Truck truck) async {
    final Database database = await _appDatabase.database;
    await database.insert(
      'trucks',
      truck.toDatabaseMap(),
      conflictAlgorithm: ConflictAlgorithm.abort,
    );
  }

  @override
  Future<void> update(Truck truck) async {
    final Database database = await _appDatabase.database;
    final Map<String, Object?> values = truck.toDatabaseMap()
      ..remove('id')
      ..remove('created_at');
    final int updatedRows = await database.update(
      'trucks',
      values,
      where: 'id = ?',
      whereArgs: [truck.id],
      conflictAlgorithm: ConflictAlgorithm.abort,
    );
    if (updatedRows == 0) throw TruckNotFoundException(truck.id);
  }

  @override
  Future<void> delete(String id) async {
    final Database database = await _appDatabase.database;
    final int deletedRows = await database.delete(
      'trucks',
      where: 'id = ?',
      whereArgs: [id],
    );
    if (deletedRows == 0) throw TruckNotFoundException(id);
  }
}

class TruckNotFoundException implements Exception {
  const TruckNotFoundException(this.id);

  final String id;

  @override
  String toString() => 'Truck "$id" was not found.';
}
