import 'package:better_routes/database/app_database.dart';
import 'package:better_routes/models/business_model.dart';
import 'package:better_routes/repositories/business_repository.dart';
import 'package:better_routes/services/business_service.dart';
import 'package:better_routes/pages/business_management_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Business business;
  late _FakeBusinessService service;

  setUp(() {
    business = Business(
      id: 'business-1',
      ownerUid: 'user-1',
      name: 'Demo Logistics',
      createdAt: DateTime.utc(2025),
      updatedAt: DateTime.utc(2025),
    );
    service = _FakeBusinessService(business);
  });

  testWidgets(
    'explains blocked business deletion and opens associated truck management',
    (WidgetTester tester) async {
      service.truckCounts[business.id] = 1;
      await tester.pumpWidget(
        MaterialApp(
          home: BusinessManagementPage(
            ownerUid: 'user-1',
            service: service,
            truckManagementPageBuilder: (_) => Scaffold(
              appBar: AppBar(),
              body: const Text('Filtered truck management'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Delete business'));
      await tester.pumpAndSettle();

      expect(find.text('Business cannot be deleted'), findsOneWidget);
      expect(find.textContaining('has 1 associated truck'), findsOneWidget);
      expect(find.textContaining('FOREIGN KEY'), findsNothing);

      await tester.tap(find.text('Manage trucks'));
      await tester.pumpAndSettle();
      expect(find.text('Filtered truck management'), findsOneWidget);
      service.truckCounts[business.id] = 0;
      await tester.pageBack();
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Delete business'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Delete'));
      await tester.pumpAndSettle();

      expect(find.text('Demo Logistics'), findsNothing);
      expect(find.text('Business profile deleted.'), findsOneWidget);
      expect(service.businesses, isEmpty);
    },
  );

  testWidgets('deletes a business after confirmation when it has no trucks', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: BusinessManagementPage(ownerUid: 'user-1', service: service),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Delete business'));
    await tester.pumpAndSettle();
    expect(find.text('Delete business?'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, 'Delete'));
    await tester.pumpAndSettle();

    expect(find.text('Demo Logistics'), findsNothing);
    expect(find.text('Business profile deleted.'), findsOneWidget);
    expect(service.businesses, isEmpty);
  });
}

class _FakeBusinessService extends BusinessService {
  _FakeBusinessService(Business business)
    : businesses = [business],
      super(SqliteBusinessRepository(AppDatabase(path: 'unused.db')));

  List<Business> businesses;
  final Map<String, int> truckCounts = {};

  @override
  Future<List<Business>> getForOwner(String ownerUid) async => businesses
      .where((Business business) => business.ownerUid == ownerUid)
      .toList(growable: false);

  @override
  Future<int> getTruckCountForOwner(String id, String ownerUid) async {
    final Business? business = businesses
        .where(
          (Business business) =>
              business.id == id && business.ownerUid == ownerUid,
        )
        .firstOrNull;
    if (business == null) throw BusinessNotFoundException(id);
    return truckCounts[id] ?? 0;
  }

  @override
  Future<void> delete(String id, String ownerUid) async {
    final int count = await getTruckCountForOwner(id, ownerUid);
    if (count > 0) throw BusinessHasTrucksException(count);
    businesses = businesses
        .where((Business business) => business.id != id)
        .toList(growable: false);
  }
}
