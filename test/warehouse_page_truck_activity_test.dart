import 'package:better_routes/database/app_database.dart';
import 'package:better_routes/models/business_model.dart';
import 'package:better_routes/models/truck_model.dart';
import 'package:better_routes/models/warehouse_model.dart';
import 'package:better_routes/pages/warehouse_page.dart';
import 'package:better_routes/repositories/business_repository.dart';
import 'package:better_routes/repositories/truck_repository.dart';
import 'package:better_routes/repositories/warehouse_repository.dart';
import 'package:better_routes/services/truck_service.dart';
import 'package:better_routes/services/warehouse_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase appDatabase;
  late _FakeTruckService truckService;
  late _FakeWarehouseService warehouseService;
  late Business business;
  late Warehouse firstWarehouse;
  late Warehouse secondWarehouse;

  setUp(() {
    appDatabase = AppDatabase(path: 'unused.db');
    final SqliteBusinessRepository businessRepository =
        SqliteBusinessRepository(appDatabase);
    final SqliteWarehouseRepository warehouseRepository =
        SqliteWarehouseRepository(appDatabase);
    final SqliteTruckRepository truckRepository = SqliteTruckRepository(
      appDatabase,
    );
    business = Business(
      id: 'business-1',
      ownerUid: 'user-1',
      name: 'Demo Logistics',
      createdAt: DateTime.utc(2025),
      updatedAt: DateTime.utc(2025),
    );
    firstWarehouse = _warehouse(id: 'warehouse-1', name: 'North Hub');
    secondWarehouse = _warehouse(id: 'warehouse-2', name: 'South Hub');
    warehouseService = _FakeWarehouseService(
      repository: warehouseRepository,
      warehouses: [firstWarehouse, secondWarehouse],
    );
    truckService = _FakeTruckService(
      truckRepository: truckRepository,
      businessRepository: businessRepository,
      warehouseRepository: warehouseRepository,
    );
  });

  testWidgets(
    'warehouse activity shows associated trucks and refreshes after reassignment',
    (WidgetTester tester) async {
      final Truck truck = _truck(business: business, warehouse: firstWarehouse);
      truckService.trucks = [truck];
      await tester.pumpWidget(
        MaterialApp(
          home: WarehousePage(
            service: warehouseService,
            truckService: truckService,
            ownerUid: 'user-1',
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Truck activity · 1'), findsOneWidget);
      expect(find.text(truck.registrationNumber), findsOneWidget);
      expect(
        find.textContaining('Mini truck · Demo Logistics'),
        findsOneWidget,
      );
      expect(find.text('PENDING'), findsOneWidget);

      await tester.ensureVisible(find.text(truck.registrationNumber));
      await tester.tap(find.text(truck.registrationNumber));
      await tester.pumpAndSettle();
      expect(find.text('Truck details'), findsOneWidget);
      expect(find.text('Demo Logistics'), findsOneWidget);
      expect(find.text('North Hub'), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();

      truckService.trucks = [
        truck.copyWith(
          warehouseId: secondWarehouse.id,
          updatedAt: DateTime.utc(2026),
        ),
      ];
      await tester.enterText(find.byType(TextField), 'North');
      await tester.pumpAndSettle();
      expect(find.text('Truck activity · 0'), findsOneWidget);
      expect(
        find.text('No trucks are currently assigned to this warehouse.'),
        findsOneWidget,
      );

      await tester.enterText(find.byType(TextField), '');
      await tester.pumpAndSettle();
      expect(find.text('Truck activity · 1'), findsOneWidget);
      expect(find.text(truck.registrationNumber), findsOneWidget);
    },
  );

  testWidgets('notifies the map after a warehouse is successfully updated', (
    WidgetTester tester,
  ) async {
    int warehouseChangeCount = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: WarehousePage(
          service: warehouseService,
          truckService: truckService,
          ownerUid: 'user-1',
          onWarehousesChanged: () => warehouseChangeCount++,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Edit').first);
    await tester.tap(find.text('Edit').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save Changes'));
    await tester.pumpAndSettle();

    expect(warehouseChangeCount, 1);
  });
}

class _FakeWarehouseService extends WarehouseService {
  _FakeWarehouseService({
    required WarehouseRepository repository,
    required this.warehouses,
  }) : super(repository);

  List<Warehouse> warehouses;

  @override
  Future<List<Warehouse>> getAll() async => warehouses;

  @override
  Future<List<Warehouse>> search(String query) async {
    final String term = query.toLowerCase();
    return warehouses
        .where(
          (Warehouse warehouse) =>
              warehouse.name.toLowerCase().contains(term) ||
              warehouse.code.toLowerCase().contains(term),
        )
        .toList(growable: false);
  }

  @override
  Future<Warehouse> update({
    required Warehouse existing,
    required String name,
    required String address,
    required String contactName,
    required String contactNumber,
    String locationNote = '',
    required double latitude,
    required double longitude,
  }) async {
    final Warehouse updated = existing.copyWith(
      name: name,
      address: address,
      contactName: contactName,
      contactNumber: contactNumber,
      locationNote: locationNote,
      latitude: latitude,
      longitude: longitude,
      updatedAt: DateTime.utc(2026),
    );
    warehouses = [
      for (final Warehouse warehouse in warehouses)
        if (warehouse.id == existing.id) updated else warehouse,
    ];
    return updated;
  }
}

class _FakeTruckService extends TruckService {
  _FakeTruckService({
    required TruckRepository truckRepository,
    required BusinessRepository businessRepository,
    required WarehouseRepository warehouseRepository,
  }) : super(truckRepository, businessRepository, warehouseRepository);

  List<Truck> trucks = [];

  @override
  Future<List<Truck>> getForOwner(
    String ownerUid, {
    String? approvalStatus,
    String? businessId,
    String? warehouseId,
  }) async => trucks;
}

Warehouse _warehouse({required String id, required String name}) => Warehouse(
  id: id,
  code: id == 'warehouse-1' ? 'WH-000001' : 'WH-000002',
  name: name,
  address: 'Jaipur',
  contactName: 'Alex',
  contactNumber: '1234567890',
  locationNote: '',
  latitude: 26.9124,
  longitude: 75.7873,
  createdAt: DateTime.utc(2025),
  updatedAt: DateTime.utc(2025),
);

Truck _truck({required Business business, required Warehouse warehouse}) =>
    Truck(
      id: 'truck-1',
      registrationNumber: 'TN 01 AB 1234',
      truckType: 'Mini truck',
      capacity: '5 tonnes',
      details: '',
      driverName: 'Demo Driver',
      driverContactNumber: '1234567890',
      warehouseId: warehouse.id,
      businessId: business.id,
      approvalStatus: 'pending',
      createdAt: DateTime.utc(2025),
      updatedAt: DateTime.utc(2025),
      warehouseName: warehouse.name,
      warehouseCode: warehouse.code,
      businessName: business.name,
    );
