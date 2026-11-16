import '../database/app_database.dart';
import '../models/place_identity.dart';
import '../models/recent_search_model.dart';
import '../models/place_search_result.dart';
import '../repositories/recent_search_repository.dart';
import 'database_id_generator.dart';

class RecentSearchService {
  RecentSearchService(this._repository);

  factory RecentSearchService.local() =>
      RecentSearchService(SqliteRecentSearchRepository(AppDatabase.instance));

  static const int maximumEntries = 50;

  final RecentSearchRepository _repository;

  Future<List<RecentSearch>> getAll() => _repository.getAll();

  Future<RecentSearch> record({
    required String query,
    String? placeName,
    String? address,
    double? latitude,
    double? longitude,
    String? placeId,
  }) async {
    final String normalizedQuery = query.trim();
    final String? normalizedName = _optional(placeName);
    if (normalizedQuery.isEmpty && normalizedName == null) {
      throw const FormatException('A search query or place name is required.');
    }
    if ((latitude == null) != (longitude == null)) {
      throw const FormatException('Both place coordinates must be provided.');
    }
    if (latitude != null &&
        longitude != null &&
        (!latitude.isFinite ||
            !longitude.isFinite ||
            latitude < -90 ||
            latitude > 90 ||
            longitude < -180 ||
            longitude > 180)) {
      throw const FormatException('The place has invalid coordinates.');
    }

    final DateTime searchedAt = DateTime.now().toUtc();
    final RecentSearch search = RecentSearch(
      id: DatabaseIdGenerator.generate(),
      destinationKey: placeIdentityKey(
        name: normalizedName ?? normalizedQuery,
        placeId: placeId,
        latitude: latitude,
        longitude: longitude,
        fallbackQuery: normalizedQuery,
      ),
      query: normalizedQuery.isEmpty ? normalizedName! : normalizedQuery,
      placeName: normalizedName,
      address: _optional(address),
      latitude: latitude,
      longitude: longitude,
      placeId: _optional(placeId),
      searchedAt: searchedAt,
    );
    await _repository.record(search, maximumEntries: maximumEntries);
    return search;
  }

  Future<RecentSearch> recordPlace(
    PlaceSearchResult place, {
    required String query,
  }) => record(
    query: query,
    placeName: place.name,
    address: place.address,
    latitude: place.latitude,
    longitude: place.longitude,
    placeId: place.placeId,
  );

  Future<void> delete(String id) => _repository.delete(id);

  Future<void> clear() => _repository.clear();

  static String? _optional(String? value) {
    final String? trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }
}
