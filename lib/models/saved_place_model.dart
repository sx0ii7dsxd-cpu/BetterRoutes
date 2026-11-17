import 'package:cloud_firestore/cloud_firestore.dart';

import '../pages/place_search_service.dart';

class SavedPlaceModel {
  const SavedPlaceModel({
    required this.placeId,
    required this.name,
    required this.displayName,
    required this.latitude,
    required this.longitude,
    this.address,
    this.createdAt,
  });

  final String placeId;
  final String name;
  final String displayName;
  final String? address;
  final double latitude;
  final double longitude;
  final DateTime? createdAt;

  PlaceSearchResult toPlaceSearchResult() => PlaceSearchResult(
    name: name,
    displayName: displayName,
    address: address,
    latitude: latitude,
    longitude: longitude,
  );

  factory SavedPlaceModel.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> snapshot,
  ) {
    final data = snapshot.data();
    if (data == null) throw StateError('Saved place has no data.');
    final name = data['name'];
    final displayName = data['displayName'];
    final latitude = data['latitude'];
    final longitude = data['longitude'];
    if (name is! String ||
        name.trim().isEmpty ||
        displayName is! String ||
        displayName.trim().isEmpty ||
        latitude is! num ||
        longitude is! num) {
      throw StateError('Saved place ${snapshot.id} has invalid data.');
    }
    return SavedPlaceModel(
      placeId: snapshot.id,
      name: name,
      displayName: displayName,
      address: data['address'] is String ? data['address'] as String : null,
      latitude: latitude.toDouble(),
      longitude: longitude.toDouble(),
      createdAt: data['createdAt'] is Timestamp
          ? (data['createdAt'] as Timestamp).toDate()
          : null,
    );
  }
}
