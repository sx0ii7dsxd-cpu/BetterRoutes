import '../database/app_database.dart';
import '../models/place_identity.dart';
import '../models/place_search_result.dart';
import '../models/saved_place_model.dart';
import '../repositories/saved_place_repository.dart';
import 'database_id_generator.dart';

class SavedPlaceService {
  SavedPlaceService(this._repository);

  factory SavedPlaceService.local() =>
      SavedPlaceService(SqliteSavedPlaceRepository(AppDatabase.instance));

  final SavedPlaceRepository _repository;

  Future<List<SavedPlace>> getAll() => _repository.getAll();

  Future<List<SavedPlace>> search(String query) => _repository.search(query);

  Future<SavedPlace?> getById(String id) => _repository.getById(id);

  Future<bool> isSaved(PlaceSearchResult place) {
    _validate(place);
    return _repository.contains(_keyFor(place));
  }

  Future<bool> save(PlaceSearchResult place) async {
    _validate(place);
    final DateTime now = DateTime.now().toUtc();
    return _repository.insert(
      SavedPlace(
        id: DatabaseIdGenerator.generate(),
        placeKey: _keyFor(place),
        name: place.name.trim(),
        displayName: place.displayName.trim(),
        address: _optional(place.address),
        latitude: place.latitude,
        longitude: place.longitude,
        placeId: _optional(place.placeId),
        savedAt: now,
      ),
    );
  }

  Future<void> delete(String id) => _repository.delete(id);

  static String _keyFor(PlaceSearchResult place) => placeIdentityKey(
    name: place.name,
    placeId: place.placeId,
    latitude: place.latitude,
    longitude: place.longitude,
  );

  static void _validate(PlaceSearchResult place) {
    if (place.name.trim().isEmpty || place.displayName.trim().isEmpty) {
      throw const FormatException('A place name is required.');
    }
    if (!place.latitude.isFinite ||
        !place.longitude.isFinite ||
        place.latitude < -90 ||
        place.latitude > 90 ||
        place.longitude < -180 ||
        place.longitude > 180) {
      throw const FormatException('The place has invalid coordinates.');
    }
  }

  static String? _optional(String? value) {
    final String? trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }
}
