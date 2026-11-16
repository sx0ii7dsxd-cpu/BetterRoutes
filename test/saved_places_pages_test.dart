import 'package:better_routes/models/recent_search_model.dart';
import 'package:better_routes/models/saved_place_model.dart';
import 'package:better_routes/pages/recent_searches_page.dart';
import 'package:better_routes/pages/saved_places_page.dart';
import 'package:better_routes/repositories/recent_search_repository.dart';
import 'package:better_routes/repositories/saved_place_repository.dart';
import 'package:better_routes/services/recent_search_service.dart';
import 'package:better_routes/services/saved_place_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('saved place selection returns its stored coordinates', (
    WidgetTester tester,
  ) async {
    final SavedPlaceService service = SavedPlaceService(
      _FakeSavedPlaceRepository([
        SavedPlace(
          id: 'saved-1',
          placeKey: 'key-1',
          name: 'Central Station',
          displayName: 'Central Station, Bengaluru',
          address: 'Bengaluru',
          latitude: 12.9716,
          longitude: 77.5946,
          savedAt: DateTime.utc(2025),
        ),
      ]),
    );
    SavedPlace? selected;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (BuildContext context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                selected = await Navigator.of(context).push<SavedPlace>(
                  MaterialPageRoute<SavedPlace>(
                    builder: (_) => SavedPlacesPage(service: service),
                  ),
                );
              },
              child: const Text('Open saved'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open saved'));
    await tester.pumpAndSettle();
    expect(find.text('Central Station'), findsOneWidget);
    await tester.tap(find.text('Central Station'));
    await tester.pumpAndSettle();

    expect(selected?.latitude, 12.9716);
    expect(selected?.longitude, 77.5946);
  });

  testWidgets('recent search selection returns and clear-all empties history', (
    WidgetTester tester,
  ) async {
    final RecentSearchService service = RecentSearchService(
      _FakeRecentSearchRepository([
        RecentSearch(
          id: 'recent-1',
          destinationKey: 'key-1',
          query: 'Central',
          placeName: 'Central Station',
          latitude: 12.9716,
          longitude: 77.5946,
          searchedAt: DateTime.utc(2025),
        ),
      ]),
    );
    RecentSearch? selected;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (BuildContext context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                selected = await Navigator.of(context).push<RecentSearch>(
                  MaterialPageRoute<RecentSearch>(
                    builder: (_) => RecentSearchesPage(service: service),
                  ),
                );
              },
              child: const Text('Open recents'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open recents'));
    await tester.pumpAndSettle();
    expect(find.text('Central Station'), findsOneWidget);
    await tester.tap(find.text('Central Station'));
    await tester.pumpAndSettle();
    expect(selected?.toPlaceSearchResult()?.longitude, 77.5946);

    await tester.tap(find.text('Open recents'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Clear all'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Clear all').last);
    await tester.pumpAndSettle();
    expect(await service.getAll(), isEmpty);
    expect(find.text('No recent searches'), findsOneWidget);
  });
}

class _FakeSavedPlaceRepository implements SavedPlaceRepository {
  _FakeSavedPlaceRepository(this.places);

  final List<SavedPlace> places;

  @override
  Future<bool> contains(String placeKey) async =>
      places.any((SavedPlace place) => place.placeKey == placeKey);

  @override
  Future<void> delete(String id) async =>
      places.removeWhere((SavedPlace place) => place.id == id);

  @override
  Future<SavedPlace?> getById(String id) async {
    for (final SavedPlace place in places) {
      if (place.id == id) return place;
    }
    return null;
  }

  @override
  Future<List<SavedPlace>> getAll() async => List.of(places);

  @override
  Future<bool> insert(SavedPlace place) async {
    if (await contains(place.placeKey)) return false;
    places.add(place);
    return true;
  }

  @override
  Future<List<SavedPlace>> search(String query) async {
    final String normalized = query.toLowerCase();
    return places
        .where(
          (SavedPlace place) =>
              place.name.toLowerCase().contains(normalized) ||
              (place.address?.toLowerCase().contains(normalized) ?? false),
        )
        .toList();
  }
}

class _FakeRecentSearchRepository implements RecentSearchRepository {
  _FakeRecentSearchRepository(this.searches);

  final List<RecentSearch> searches;

  @override
  Future<void> clear() async => searches.clear();

  @override
  Future<void> delete(String id) async =>
      searches.removeWhere((RecentSearch search) => search.id == id);

  @override
  Future<List<RecentSearch>> getAll() async => List.of(searches);

  @override
  Future<void> record(
    RecentSearch search, {
    required int maximumEntries,
  }) async {
    searches.removeWhere(
      (RecentSearch existing) =>
          existing.destinationKey == search.destinationKey,
    );
    searches.insert(0, search);
    if (searches.length > maximumEntries) {
      searches.removeRange(maximumEntries, searches.length);
    }
  }
}
