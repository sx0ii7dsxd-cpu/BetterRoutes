import 'dart:io';

import 'package:better_routes/database/app_database.dart';
import 'package:better_routes/models/business_model.dart';
import 'package:better_routes/models/truck_model.dart';
import 'package:better_routes/models/warehouse_model.dart';
import 'package:better_routes/repositories/business_repository.dart';
import 'package:better_routes/repositories/truck_repository.dart';
import 'package:better_routes/repositories/user_profile_repository.dart';
import 'package:better_routes/repositories/warehouse_repository.dart';
import 'package:better_routes/services/business_service.dart';
import 'package:better_routes/services/truck_service.dart';
import 'package:better_routes/services/user_profile_service.dart';
import 'package:better_routes/services/warehouse_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late AppDatabase appDatabase;
  late BusinessService businessService;
  late TruckService truckService;
  late UserProfileService profileService;
  late WarehouseService warehouseService;
  late Business business;
  late Warehouse warehouse;

  setUp(() async {
    appDatabase = AppDatabase(path: inMemoryDatabasePath);
    businessService = BusinessService(SqliteBusinessRepository(appDatabase));
    truckService = TruckService(
      SqliteTruckRepository(appDatabase),
      SqliteBusinessRepository(appDatabase),
      SqliteWarehouseRepository(appDatabase),
    );
    profileService = UserProfileService(
      SqliteUserProfileRepository(appDatabase),
    );
    warehouseService = WarehouseService(SqliteWarehouseRepository(appDatabase));
    await profileService.saveFromAuthentication(
      uid: 'user-1',
      displayName: 'Demo User',
      email: 'demo@example.com',
      photoUrl: null,
      providerIds: ['password'],
    );
    business = await businessService.create(
      ownerUid: 'user-1',
      name: 'Demo Logistics',
    );
    warehouse = await _createWarehouse(warehouseService);
  });

  tearDown(() async {
    await appDatabase.close();
  });

  test(
    'creates, retrieves, searches, filters, updates, and deletes trucks',
    () async {
      final Truck created = await _createTruck(
        truckService,
        business: business,
        warehouse: warehouse,
      );

      expect(created.id, isNotEmpty);
      expect(created.registrationNumber, 'TN 01 AB 1234');
      expect(created.approvalStatus, 'pending');
      expect(created.createdAt, created.updatedAt);
      expect(
        (await truckService.getByIdForOwner(created.id, 'user-1'))?.warehouseId,
        warehouse.id,
      );
      expect(
        (await truckService.getByIdForOwner(created.id, 'user-1'))?.businessId,
        business.id,
      );
      expect(
        await truckService.getByIdForOwner(created.id, 'other-user'),
        isNull,
      );
      expect((await truckService.getForOwner('user-1')).single.id, created.id);
      expect(
        (await truckService.searchForOwner('user-1', 'driver')).single.id,
        created.id,
      );
      expect(
        (await truckService.searchForOwner('user-1', 'North Hub')).single.id,
        created.id,
      );
      expect(
        (await truckService.searchForOwner('user-1', warehouse.code)).single.id,
        created.id,
      );
      expect(
        (await truckService.searchForOwner('user-1', 'Mini truck')).single.id,
        created.id,
      );
      expect(
        (await truckService.searchForOwner(
          'user-1',
          'Demo Logistics',
        )).single.id,
        created.id,
      );
      expect(
        (await truckService.getForOwner(
          'user-1',
          businessId: business.id,
        )).single.id,
        created.id,
      );
      expect(
        (await truckService.getForOwner(
          'user-1',
          warehouseId: warehouse.id,
        )).single.id,
        created.id,
      );
      expect(
        (await truckService.searchForOwner(
          'user-1',
          'TN 01',
          approvalStatus: 'pending',
        )).single.id,
        created.id,
      );
      expect(
        await truckService.getForOwner('user-1', approvalStatus: 'approved'),
        isEmpty,
      );
      expect(
        (await truckService.searchForOwner('user-1', 'no match')),
        isEmpty,
      );
      expect(
        () => truckService.getForOwner('user-1', approvalStatus: 'unknown'),
        throwsFormatException,
      );

      final Business reassignedBusiness = await businessService.create(
        ownerUid: 'user-1',
        name: 'Reassigned Logistics',
      );
      final Warehouse reassignedWarehouse = await _createWarehouse(
        warehouseService,
        name: 'South Hub',
      );
      await Future<void>.delayed(const Duration(milliseconds: 2));
      final Truck updated = await truckService.update(
        ownerUid: 'user-1',
        existing: created,
        registrationNumber: ' tn 02 xy 9876 ',
        truckType: 'Box truck',
        capacity: '8 tonnes',
        details: 'Lift gate',
        driverName: 'Jordan Driver',
        driverContactNumber: '+1 555 987 6543',
        warehouseId: reassignedWarehouse.id,
        businessId: reassignedBusiness.id,
      );
      expect(updated.id, created.id);
      expect(updated.registrationNumber, 'TN 02 XY 9876');
      expect(updated.approvalStatus, 'pending');
      expect(updated.createdAt, created.createdAt);
      expect(updated.updatedAt.isAfter(created.updatedAt), isTrue);
      final Truck loaded = (await truckService.getByIdForOwner(
        created.id,
        'user-1',
      ))!;
      expect(loaded.details, 'Lift gate');
      expect(loaded.warehouseName, reassignedWarehouse.name);
      expect(loaded.businessName, reassignedBusiness.name);
      expect(
        await truckService.getForOwner('user-1', warehouseId: warehouse.id),
        isEmpty,
      );
      expect(
        (await truckService.getForOwner(
          'user-1',
          warehouseId: reassignedWarehouse.id,
        )).single.id,
        created.id,
      );
      expect(
        await truckService.getForOwner('user-1', businessId: business.id),
        isEmpty,
      );

      await truckService.delete(created.id, 'user-1');
      expect(await truckService.getForOwner('user-1'), isEmpty);
      await expectLater(
        truckService.delete(created.id, 'user-1'),
        throwsA(isA<TruckNotFoundException>()),
      );
    },
  );

  test(
    'validates truck inputs and ownership of business association',
    () async {
      await expectLater(
        truckService.create(
          ownerUid: 'user-1',
          registrationNumber: ' ',
          truckType: 'Mini truck',
          capacity: '5 tonnes',
          driverName: 'Driver',
          driverContactNumber: '1234567',
          warehouseId: warehouse.id,
          businessId: business.id,
        ),
        throwsFormatException,
      );
      await expectLater(
        truckService.create(
          ownerUid: 'user-1',
          registrationNumber: 'TN 01 AB 1234',
          truckType: 'Unknown truck',
          capacity: '5 tonnes',
          driverName: 'Driver',
          driverContactNumber: '1234567',
          warehouseId: warehouse.id,
          businessId: business.id,
        ),
        throwsFormatException,
      );
      await expectLater(
        truckService.create(
          ownerUid: 'user-1',
          registrationNumber: 'TN 01 AB 1234',
          truckType: 'Mini truck',
          capacity: '5 tonnes',
          driverName: 'Driver',
          driverContactNumber: '123',
          warehouseId: warehouse.id,
          businessId: business.id,
        ),
        throwsFormatException,
      );
      await expectLater(
        truckService.create(
          ownerUid: 'other-user',
          registrationNumber: 'TN 01 AB 1234',
          truckType: 'Mini truck',
          capacity: '5 tonnes',
          driverName: 'Driver',
          driverContactNumber: '1234567',
          warehouseId: warehouse.id,
          businessId: business.id,
        ),
        throwsFormatException,
      );
      expect(await truckService.getForOwner('user-1'), isEmpty);
    },
  );

  test(
    'business CRUD is owner-scoped and deletion respects truck references',
    () async {
      final List<Business> owned = await businessService.getForOwner('user-1');
      expect(owned.map((Business value) => value.id), contains(business.id));
      expect(await businessService.getForOwner('other-user'), isEmpty);
      expect(
        await businessService.getByIdForOwner(business.id, 'other-user'),
        isNull,
      );
      await expectLater(
        businessService.getTruckCountForOwner(business.id, 'other-user'),
        throwsA(isA<BusinessNotFoundException>()),
      );
      await expectLater(
        businessService.delete(business.id, 'other-user'),
        throwsA(isA<BusinessNotFoundException>()),
      );
      expect(
        await businessService.getByIdForOwner(business.id, 'user-1'),
        isNotNull,
      );

      final Business updated = await businessService.update(
        ownerUid: 'user-1',
        existing: business,
        name: 'Updated Logistics',
      );
      expect(updated.id, business.id);
      expect(updated.ownerUid, 'user-1');
      expect(updated.name, 'Updated Logistics');
      expect(updated.createdAt, business.createdAt);
      expect(updated.updatedAt.isAfter(business.updatedAt), isTrue);
      expect(
        await businessService.getTruckCountForOwner(updated.id, 'user-1'),
        0,
      );

      final Truck truck = await _createTruck(
        truckService,
        business: updated,
        warehouse: warehouse,
      );
      final Database database = await appDatabase.database;
      expect(
        (await database.rawQuery('PRAGMA foreign_keys')).single['foreign_keys'],
        1,
      );
      final Map<String, Object?> invalidWarehouseTruck = truck.toDatabaseMap()
        ..['id'] = 'invalid-warehouse-truck'
        ..['registration_number'] = 'INVALID-WAREHOUSE'
        ..['warehouse_id'] = 'missing-warehouse';
      await expectLater(
        database.insert('trucks', invalidWarehouseTruck),
        throwsA(isA<DatabaseException>()),
      );
      final Map<String, Object?> invalidBusinessTruck = truck.toDatabaseMap()
        ..['id'] = 'invalid-business-truck'
        ..['registration_number'] = 'INVALID-BUSINESS'
        ..['business_id'] = 'missing-business';
      await expectLater(
        database.insert('trucks', invalidBusinessTruck),
        throwsA(isA<DatabaseException>()),
      );
      expect(
        await businessService.getTruckCountForOwner(updated.id, 'user-1'),
        1,
      );
      await expectLater(
        businessService.delete(updated.id, 'user-1'),
        throwsA(
          isA<BusinessHasTrucksException>().having(
            (BusinessHasTrucksException error) => error.truckCount,
            'truckCount',
            1,
          ),
        ),
      );
      await expectLater(
        warehouseService.delete(warehouse.id),
        throwsA(isA<DatabaseException>()),
      );

      await truckService.delete(truck.id, 'user-1');
      expect(
        await businessService.getTruckCountForOwner(updated.id, 'user-1'),
        0,
      );
      await businessService.delete(updated.id, 'user-1');
      await warehouseService.delete(warehouse.id);
      expect(await businessService.getForOwner('user-1'), isEmpty);
      expect(await warehouseService.getAll(), isEmpty);
    },
  );

  test(
    'profile upsert preserves referenced businesses and updates fields',
    () async {
      final UserProfileService profiles = profileService;
      final profileBefore = await profiles.getByUid('user-1');
      await profiles.saveFromAuthentication(
        uid: 'user-1',
        displayName: 'Updated Name',
        email: 'updated@example.com',
        photoUrl: 'https://example.com/avatar.png',
        providerIds: ['google.com'],
      );
      final profileAfter = await profiles.getByUid('user-1');

      expect(profileAfter?.displayName, 'Updated Name');
      expect(profileAfter?.email, 'updated@example.com');
      expect(profileAfter?.providerIds, ['google.com']);
      expect(profileAfter?.createdAt, profileBefore?.createdAt);
      expect(
        (await businessService.getForOwner('user-1')).single.id,
        business.id,
      );
      final Database database = await appDatabase.database;
      final List<Map<String, Object?>> profileRows = await database.query(
        'user_profiles',
        where: 'uid = ?',
        whereArgs: ['user-1'],
      );
      expect(profileRows, hasLength(1));
    },
  );

  test(
    'version 1 to 2 migration keeps warehouse rows and coordinates',
    () async {
      final Directory directory = await Directory.systemTemp.createTemp(
        'better-routes-migration-',
      );
      final String path = '${directory.path}/better-routes.db';
      final Database versionOne = await openDatabase(
        path,
        version: 1,
        onCreate: (Database database, int version) async {
          await database.execute('''
          CREATE TABLE warehouses (
            id TEXT PRIMARY KEY NOT NULL,
            warehouse_code TEXT NOT NULL UNIQUE,
            name TEXT NOT NULL,
            address TEXT NOT NULL,
            contact_name TEXT NOT NULL,
            contact_number TEXT NOT NULL,
            location_note TEXT NOT NULL DEFAULT '',
            latitude REAL,
            longitude REAL,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL
          )
        ''');
        },
      );
      await versionOne.insert('warehouses', {
        'id': 'warehouse-v1',
        'warehouse_code': 'WH-000123',
        'name': 'Legacy Warehouse',
        'address': 'Old address',
        'contact_name': 'Legacy Contact',
        'contact_number': '1234567890',
        'location_note': 'Legacy note',
        'latitude': 26.9124,
        'longitude': 75.7873,
        'created_at': '2024-01-01T00:00:00.000Z',
        'updated_at': '2024-01-02T00:00:00.000Z',
      });
      await versionOne.close();

      final AppDatabase upgradedDatabase = AppDatabase(path: path);
      try {
        final Database database = await upgradedDatabase.database;
        final List<Map<String, Object?>> rows = await database.query(
          'warehouses',
          where: 'id = ?',
          whereArgs: ['warehouse-v1'],
        );
        expect(rows, hasLength(1));
        expect(rows.single['latitude'], 26.9124);
        expect(rows.single['longitude'], 75.7873);
        expect(await database.query('user_profiles'), isEmpty);
        expect(await database.query('businesses'), isEmpty);
        expect(await database.query('trucks'), isEmpty);
        expect(
          (await database.rawQuery('PRAGMA user_version'))
              .single['user_version'],
          AppDatabase.version,
        );
        expect(
          (await database.rawQuery('PRAGMA foreign_keys'))
              .single['foreign_keys'],
          1,
        );
      } finally {
        await upgradedDatabase.close();
        await directory.delete(recursive: true);
      }
    },
  );

  test(
    'profile, business, and truck records persist after database reopen',
    () async {
      final Directory directory = await Directory.systemTemp.createTemp(
        'better-routes-trucks-',
      );
      final String path = '${directory.path}/truck-test.db';
      final AppDatabase firstDatabase = AppDatabase(path: path);
      final UserProfileService firstProfiles = UserProfileService(
        SqliteUserProfileRepository(firstDatabase),
      );
      final BusinessService firstBusinesses = BusinessService(
        SqliteBusinessRepository(firstDatabase),
      );
      final WarehouseService firstWarehouses = WarehouseService(
        SqliteWarehouseRepository(firstDatabase),
      );
      final TruckService firstTrucks = TruckService(
        SqliteTruckRepository(firstDatabase),
        SqliteBusinessRepository(firstDatabase),
        SqliteWarehouseRepository(firstDatabase),
      );

      try {
        await firstProfiles.saveFromAuthentication(
          uid: 'persistent-user',
          displayName: 'Persistent User',
          email: 'persist@example.com',
          photoUrl: null,
          providerIds: ['password'],
        );
        final Business persistedBusiness = await firstBusinesses.create(
          ownerUid: 'persistent-user',
          name: 'Persistent Company',
        );
        final Warehouse persistedWarehouse = await _createWarehouse(
          firstWarehouses,
        );
        final Truck persistedTruck = await _createTruck(
          firstTrucks,
          business: persistedBusiness,
          warehouse: persistedWarehouse,
          ownerUid: 'persistent-user',
        );
        await firstDatabase.close();

        final AppDatabase reopenedDatabase = AppDatabase(path: path);
        try {
          final List<Truck> reopenedTrucks = await TruckService(
            SqliteTruckRepository(reopenedDatabase),
            SqliteBusinessRepository(reopenedDatabase),
            SqliteWarehouseRepository(reopenedDatabase),
          ).getForOwner('persistent-user');
          expect(reopenedTrucks.single.id, persistedTruck.id);
          expect(reopenedTrucks.single.warehouseId, persistedWarehouse.id);
          expect(reopenedTrucks.single.businessId, persistedBusiness.id);
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

Future<Warehouse> _createWarehouse(
  WarehouseService service, {
  String name = 'North Hub',
}) {
  return service.create(
    name: name,
    address: 'Jaipur, Rajasthan',
    contactName: 'Alex',
    contactNumber: '+1 555 123 4567',
    locationNote: 'Near the central station',
    latitude: 26.9124,
    longitude: 75.7873,
  );
}

Future<Truck> _createTruck(
  TruckService service, {
  required Business business,
  required Warehouse warehouse,
  String ownerUid = 'user-1',
}) {
  return service.create(
    ownerUid: ownerUid,
    registrationNumber: 'TN 01 AB 1234',
    truckType: 'Mini truck',
    capacity: '5 tonnes',
    details: 'Closed body',
    driverName: 'Jordan Driver',
    driverContactNumber: '+1 555 123 4567',
    warehouseId: warehouse.id,
    businessId: business.id,
  );
}
