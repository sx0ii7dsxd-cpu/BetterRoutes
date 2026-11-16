import 'dart:io';

import 'package:better_routes/database/app_database.dart';
import 'package:better_routes/models/place_search_result.dart';
import 'package:better_routes/models/saved_place_model.dart';
import 'package:better_routes/models/recent_search_model.dart';
import 'package:better_routes/repositories/recent_search_repository.dart';
import 'package:better_routes/repositories/saved_place_repository.dart';
import 'package:better_routes/services/recent_search_service.dart';
import 'package:better_routes/services/saved_place_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late AppDatabase appDatabase;
  late SavedPlaceService savedPlaces;
  late RecentSearchService recentSearches;

  setUp(() {
    appDatabase = AppDatabase(path: inMemoryDatabasePath);
    savedPlaces = SavedPlaceService(
      SqliteSavedPlaceRepository(appDatabase),
    );
    recentSearches = RecentSearchService(
      SqliteRecentSearchRepository(appDatabase),
    );
  });

  tearDown(() async {
    await appDatabase.close();
  });

  test('saves, deduplicates, searches, and deletes places', () async {
    final PlaceSearchResult place = _place();

    expect(await savedPlaces.save(place), isTrue);
    expect(await savedPlaces.isSaved(place), isTrue);
    expect(await savedPlaces.save(_place(name: ' central station ')), isFalse);

    final List<SavedPlace> results = await savedPlaces.search('station');
    expect(results, hasLength(1));
    expect(results.single.name, 'Central Station');
    expect(results.single.latitude, 12.9716);

    await savedPlaces.delete(results.single.id);
    expect(await savedPlaces.getAll(), isEmpty);
    expect(await savedPlaces.isSaved(place), isFalse);
  });

  test('rejects invalid place names and coordinates', () async {
    await expectLater(
      savedPlaces.save(
        const PlaceSearchResult(
          name: ' ',
          displayName: 'No name',
          latitude: 12,
          longitude: 34,
        ),
      ),
      throwsFormatException,
    );
    await expectLater(
      savedPlaces.save(
        const PlaceSearchResult(
          name: 'Invalid',
          displayName: 'Invalid',
          latitude: 91,
          longitude: 34,
        ),
      ),
      throwsFormatException,
    );
    expect(await savedPlaces.getAll(), isEmpty);
  });

  test('upserts recent destinations, orders by recency, caps, and clears', () async {
    await recentSearches.recordPlace(_place(), query: 'Central');
    await Future<void>.delayed(const Duration(milliseconds: 2));
    await recentSearches.recordPlace(
      _place(name: 'Different Station', placeId: 'provider:2'),
      query: 'Different',
    );
    await Future<void>.delayed(const Duration(milliseconds: 2));
    await recentSearches.recordPlace(_place(), query: 'Station search');

    List<RecentSearch> searches = await recentSearches.getAll();
    expect(searches, hasLength(2));
    expect(searches.first.query, 'Station search');
    expect(searches.first.placeName, 'Central Station');

    for (int index = 0; index < 55; index++) {
      await recentSearches.record(
        query: 'query $index',
        placeName: 'Place $index',
      );
    }
    searches = await recentSearches.getAll();
    expect(searches, hasLength(RecentSearchService.maximumEntries));
    expect(searches.first.query, 'query 54');
    expect(searches.any((RecentSearch item) => item.query == 'query 0'), isFalse);

    await recentSearches.delete(searches.first.id);
    expect(await recentSearches.getAll(), hasLength(49));
    await recentSearches.clear();
    expect(await recentSearches.getAll(), isEmpty);
  });

  test('rejects incomplete or invalid recent-search coordinates', () async {
    await expectLater(
      recentSearches.record(query: 'bad', latitude: 12),
      throwsFormatException,
    );
    await expectLater(
      recentSearches.record(
        query: 'bad',
        latitude: 12,
        longitude: 181,
      ),
      throwsFormatException,
    );
    await expectLater(
      recentSearches.record(query: ' ', placeName: ' '),
      throwsFormatException,
    );
  });

  test('saved places and recents persist after reopening SQLite', () async {
    final Directory directory = await Directory.systemTemp.createTemp(
      'better-routes-places-',
    );
    final String path = '${directory.path}/places.db';
    final AppDatabase firstDatabase = AppDatabase(path: path);
    final SavedPlaceService firstSaved = SavedPlaceService(
      SqliteSavedPlaceRepository(firstDatabase),
    );
    final RecentSearchService firstRecent = RecentSearchService(
      SqliteRecentSearchRepository(firstDatabase),
    );
    try {
      await firstSaved.save(_place());
      await firstRecent.recordPlace(_place(), query: 'Central');
      await firstDatabase.close();

      final AppDatabase reopenedDatabase = AppDatabase(path: path);
      try {
        final List<SavedPlace> savedPlaces = await SavedPlaceService(
          SqliteSavedPlaceRepository(reopenedDatabase),
        ).getAll();
        final SavedPlace saved = savedPlaces.single;
        final List<RecentSearch> recent = await RecentSearchService(
          SqliteRecentSearchRepository(reopenedDatabase),
        ).getAll();
        expect(saved.latitude, 12.9716);
        expect(saved.longitude, 77.5946);
        expect(recent.single.toPlaceSearchResult()?.latitude, 12.9716);
      } finally {
        await reopenedDatabase.close();
      }
    } finally {
      await firstDatabase.close();
      await directory.delete(recursive: true);
    }
  });

  test('v2 to v3 migration preserves all prior records and relationships', () async {
    final Directory directory = await Directory.systemTemp.createTemp(
      'better-routes-migration-',
    );
    final String path = '${directory.path}/migration.db';
    final AppDatabase initialDatabase = AppDatabase(path: path);
    try {
      final Database database = await initialDatabase.database;
      await database.insert('warehouses', {
        'id': 'warehouse-v2',
        'warehouse_code': 'WH-000123',
        'name': 'Legacy Warehouse',
        'address': 'Old address',
        'contact_name': 'Legacy contact',
        'contact_number': '1234567890',
        'location_note': 'Legacy note',
        'latitude': 26.9124,
        'longitude': 75.7873,
        'created_at': '2024-01-01T00:00:00.000Z',
        'updated_at': '2024-01-02T00:00:00.000Z',
      });
      await database.insert('user_profiles', {
        'uid': 'user-v2',
        'display_name': 'Legacy User',
        'email': 'legacy@example.com',
        'photo_url': '',
        'provider_ids': '["password"]',
        'created_at': '2024-01-01T00:00:00.000Z',
        'updated_at': '2024-01-02T00:00:00.000Z',
      });
      await database.insert('businesses', {
        'id': 'business-v2',
        'owner_uid': 'user-v2',
        'name': 'Legacy Business',
        'created_at': '2024-01-01T00:00:00.000Z',
        'updated_at': '2024-01-02T00:00:00.000Z',
      });
      await database.insert('trucks', {
        'id': 'truck-v2',
        'registration_number': 'LEGACY-123',
        'truck_type': 'Box truck',
        'capacity': '10 tons',
        'details': '',
        'driver_name': 'Legacy Driver',
        'driver_contact_number': '1234567890',
        'warehouse_id': 'warehouse-v2',
        'business_id': 'business-v2',
        'approval_status': 'pending',
        'created_at': '2024-01-01T00:00:00.000Z',
        'updated_at': '2024-01-02T00:00:00.000Z',
      });
      await initialDatabase.close();

      final Database versionTwo = await openDatabase(
        path,
        version: AppDatabase.version,
      );
      await versionTwo.execute('DROP TABLE saved_places');
      await versionTwo.execute('DROP TABLE recent_searches');
      await versionTwo.execute('PRAGMA user_version = 2');
      await versionTwo.close();

      final AppDatabase upgradedDatabase = AppDatabase(path: path);
      try {
        final Database upgraded = await upgradedDatabase.database;
        expect(
          (await upgraded.rawQuery('PRAGMA user_version'))
              .single['user_version'],
          3,
        );
        expect((await upgraded.query('warehouses')).single['latitude'], 26.9124);
        expect((await upgraded.query('warehouses')).single['longitude'], 75.7873);
        expect((await upgraded.query('user_profiles')).single['uid'], 'user-v2');
        expect((await upgraded.query('businesses')).single['id'], 'business-v2');
        expect((await upgraded.query('trucks')).single['warehouse_id'], 'warehouse-v2');
        expect(await upgraded.query('saved_places'), isEmpty);
        expect(await upgraded.query('recent_searches'), isEmpty);
        expect(
          (await upgraded.rawQuery('PRAGMA foreign_keys'))
              .single['foreign_keys'],
          1,
        );
      } finally {
        await upgradedDatabase.close();
      }
    } finally {
      await initialDatabase.close();
      await directory.delete(recursive: true);
    }
  });
}

PlaceSearchResult _place({
  String name = 'Central Station',
  String? placeId,
}) => PlaceSearchResult(
  name: name,
  displayName: '$name, Bengaluru',
  address: 'Bengaluru',
  latitude: 12.9716,
  longitude: 77.5946,
  placeId: placeId,
);
