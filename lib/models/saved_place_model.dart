import 'place_search_result.dart';
import 'database_timestamp.dart';

class SavedPlace {
  const SavedPlace({
    required this.id,
    required this.placeKey,
    required this.name,
    required this.displayName,
    required this.latitude,
    required this.longitude,
    required this.savedAt,
    this.address,
    this.placeId,
  });

  final String id;
  final String placeKey;
  final String name;
  final String displayName;
  final String? address;
  final double latitude;
  final double longitude;
  final String? placeId;
  final DateTime savedAt;

  PlaceSearchResult toPlaceSearchResult() => PlaceSearchResult(
    name: name,
    displayName: displayName,
    address: address,
    latitude: latitude,
    longitude: longitude,
    placeId: placeId,
  );

  Map<String, Object?> toDatabaseMap() => {
    'id': id,
    'place_key': placeKey,
    'name': name,
    'display_name': displayName,
    'address': address,
    'latitude': latitude,
    'longitude': longitude,
    'provider_place_id': placeId,
    'saved_at': formatDatabaseTimestamp(savedAt),
  };

  factory SavedPlace.fromDatabaseMap(Map<String, Object?> row) => SavedPlace(
    id: row['id']! as String,
    placeKey: row['place_key']! as String,
    name: row['name']! as String,
    displayName: row['display_name']! as String,
    address: row['address'] as String?,
    latitude: (row['latitude']! as num).toDouble(),
    longitude: (row['longitude']! as num).toDouble(),
    placeId: row['provider_place_id'] as String?,
    savedAt: DateTime.parse(row['saved_at']! as String).toUtc(),
  );
}
