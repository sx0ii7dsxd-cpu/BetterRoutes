class PlaceSearchResult {
  const PlaceSearchResult({
    required this.name,
    required this.displayName,
    required this.latitude,
    required this.longitude,
    this.address,
    this.placeId,
  });

  final String name;
  final String displayName;
  final String? address;
  final double latitude;
  final double longitude;
  final String? placeId;
}
