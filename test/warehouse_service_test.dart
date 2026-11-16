import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:better_routes/database/app_database.dart';
import 'package:better_routes/models/warehouse_model.dart';
import 'package:better_routes/repositories/warehouse_repository.dart';
import 'package:better_routes/services/warehouse_service.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late AppDatabase appDatabase;
  late WarehouseService service;

  setUp(() {
    appDatabase = AppDatabase(path: inMemoryDatabasePath);
    service = WarehouseService(SqliteWarehouseRepository(appDatabase));
  });

  tearDown(() async {
    await appDatabase.close();
  });

  test('creates, reads, searches, updates, and deletes warehouses', () async {
    final warehouse = await _createWarehouse(service);

    expect(warehouse.id, isNotEmpty);
    expect(warehouse.code, matches(RegExp(r'^WH-\d{6}$')));
    expect(warehouse.createdAt, warehouse.updatedAt);
    expect((await service.getAll()).single.id, warehouse.id);
    expect((await service.getById(warehouse.id))?.latitude, 26.9124);
    expect((await service.search('jaipur')).single.id, warehouse.id);
    expect((await service.search('no match')), isEmpty);

    final updated = await service.update(
      existing: warehouse,
      name: 'South Hub',
      address: 'New address',
      contactName: 'Alex',
      contactNumber: '+1 555 123 4567',
      locationNote: 'Updated landmark',
      latitude: 27.1,
      longitude: 75.9,
    );
    expect(updated.id, warehouse.id);
    expect(updated.code, warehouse.code);
    expect(updated.createdAt, warehouse.createdAt);
    expect(updated.updatedAt.isAfter(warehouse.updatedAt), isTrue);
    expect((await service.getById(warehouse.id))?.longitude, 75.9);
    expect((await service.search('updated landmark')).single.id, warehouse.id);

    await service.delete(warehouse.id);
    expect(await service.getAll(), isEmpty);
    await expectLater(
      service.delete(warehouse.id),
      throwsA(isA<WarehouseNotFoundException>()),
    );
  });

  test('rejects invalid required fields and coordinates', () async {
    await expectLater(
      service.create(
        name: '  ',
        address: 'Address',
        contactName: 'Contact',
        contactNumber: '1234567',
        latitude: 26.9,
        longitude: 75.7,
      ),
      throwsFormatException,
    );
    await expectLater(
      service.create(
        name: 'Warehouse',
        address: 'Address',
        contactName: 'Contact',
        contactNumber: '1234567',
        latitude: 91,
        longitude: 75.7,
      ),
      throwsFormatException,
    );
    expect(await service.getAll(), isEmpty);
  });

  test(
    'enables foreign keys and prevents deletion of referenced warehouses',
    () async {
      final warehouse = await _createWarehouse(service);
      final Database database = await appDatabase.database;
      final List<Map<String, Object?>> pragma = await database.rawQuery(
        'PRAGMA foreign_keys',
      );
      expect(pragma.single['foreign_keys'], 1);

      await database.execute('''
      CREATE TABLE warehouse_references (
        warehouse_id TEXT NOT NULL REFERENCES warehouses(id)
      )
    ''');
      await database.insert('warehouse_references', {
        'warehouse_id': warehouse.id,
      });

      await expectLater(
        service.delete(warehouse.id),
        throwsA(isA<DatabaseException>()),
      );
      expect(await service.getById(warehouse.id), isNotNull);
    },
  );

  test(
    'warehouse coordinates persist after closing and reopening SQLite',
    () async {
      final Directory directory = await Directory.systemTemp.createTemp(
        'better-routes-sqlite-',
      );
      final String path = '${directory.path}/warehouse-test.db';
      final AppDatabase firstDatabase = AppDatabase(path: path);
      final WarehouseService firstService = WarehouseService(
        SqliteWarehouseRepository(firstDatabase),
      );

      try {
        final warehouse = await _createWarehouse(firstService);
        await firstDatabase.close();

        final AppDatabase reopenedDatabase = AppDatabase(path: path);
        try {
          final Warehouse? loaded = await WarehouseService(
            SqliteWarehouseRepository(reopenedDatabase),
          ).getById(warehouse.id);
          expect(loaded?.latitude, 26.9124);
          expect(loaded?.longitude, 75.7873);
        } finally {
          await reopenedDatabase.close();
        }
      } finally {
        await firstDatabase.close();
        await directory.delete(recursive: true);
      }
    },
  );
}

Future<Warehouse> _createWarehouse(WarehouseService service) {
  return service.create(
    name: 'North Hub',
    address: 'Jaipur, Rajasthan',
    contactName: 'Alex',
    contactNumber: '+1 555 123 4567',
    locationNote: 'Near the central station',
    latitude: 26.9124,
    longitude: 75.7873,
  );
}
