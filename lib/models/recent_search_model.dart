import 'place_search_result.dart';
import 'database_timestamp.dart';

class RecentSearch {
  const RecentSearch({
    required this.id,
    required this.destinationKey,
    required this.query,
    required this.searchedAt,
    this.placeName,
    this.address,
    this.latitude,
    this.longitude,
    this.placeId,
  });

  final String id;
  final String destinationKey;
  final String query;
  final String? placeName;
  final String? address;
  final double? latitude;
  final double? longitude;
  final String? placeId;
  final DateTime searchedAt;

  PlaceSearchResult? toPlaceSearchResult() {
    final double? resultLatitude = latitude;
    final double? resultLongitude = longitude;
    if (resultLatitude == null || resultLongitude == null) return null;
    final String name = placeName ?? query;
    return PlaceSearchResult(
      name: name,
      displayName: name,
      address: address,
      latitude: resultLatitude,
      longitude: resultLongitude,
      placeId: placeId,
    );
  }

  Map<String, Object?> toDatabaseMap() => {
    'id': id,
    'destination_key': destinationKey,
    'query': query,
    'place_name': placeName,
    'address': address,
    'latitude': latitude,
    'longitude': longitude,
    'provider_place_id': placeId,
    'searched_at': formatDatabaseTimestamp(searchedAt),
  };

  factory RecentSearch.fromDatabaseMap(Map<String, Object?> row) =>
      RecentSearch(
        id: row['id']! as String,
        destinationKey: row['destination_key']! as String,
        query: row['query']! as String,
        placeName: row['place_name'] as String?,
        address: row['address'] as String?,
        latitude: (row['latitude'] as num?)?.toDouble(),
        longitude: (row['longitude'] as num?)?.toDouble(),
        placeId: row['provider_place_id'] as String?,
        searchedAt: DateTime.parse(row['searched_at']! as String).toUtc(),
      );
}
