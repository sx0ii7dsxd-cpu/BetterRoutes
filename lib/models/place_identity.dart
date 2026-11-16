import 'dart:convert';

String placeIdentityKey({
  required String name,
  String? placeId,
  double? latitude,
  double? longitude,
  String? fallbackQuery,
}) {
  final String normalizedPlaceId = placeId?.trim() ?? '';
  if (normalizedPlaceId.isNotEmpty) {
    return jsonEncode(['provider', normalizedPlaceId]);
  }

  if (latitude != null && longitude != null) {
    return jsonEncode([
      'coordinates',
      latitude.toStringAsFixed(5),
      longitude.toStringAsFixed(5),
      _normalize(name),
    ]);
  }

  return jsonEncode(['query', _normalize(fallbackQuery ?? name)]);
}

String _normalize(String value) =>
    value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
