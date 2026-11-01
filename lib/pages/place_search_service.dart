import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

class PlaceSearchResult {
  const PlaceSearchResult({
    required this.name,
    required this.displayName,
    required this.latitude,
    required this.longitude,
    this.address,
  });

  final String name;
  final String displayName;
  final String? address;
  final double latitude;
  final double longitude;
}

class PlaceSearchException implements Exception {
  const PlaceSearchException(this.message);

  final String message;

  @override
  String toString() => message;
}

class PlaceSearchService {
  static const String configuredApiKey = String.fromEnvironment(
    'MAPTILER_API_KEY',
  );

  PlaceSearchService({required this.apiKey, http.Client? client})
    : _client = client ?? http.Client(),
      _ownsClient = client == null;

  final String apiKey;
  final http.Client _client;
  final bool _ownsClient;

  Future<List<PlaceSearchResult>> search(
    String rawQuery, {
    double? proximityLatitude,
    double? proximityLongitude,
  }) async {
    final String query = rawQuery.trim();
    if (query.length < 2) return [];
    if (apiKey.trim().isEmpty || apiKey.trim() == 'YOUR_MAPTILER_API_KEY') {
      throw const PlaceSearchException(
        'Place suggestions require a MapTiler API key.',
      );
    }

    final Uri uri = Uri.https(
      'api.maptiler.com',
      '/geocoding/${Uri.encodeComponent(query)}.json',
      {
        'key': apiKey.trim(),
        'autocomplete': 'true',
        'limit': '10',
        'language': 'en',
        'country': 'in',
        if (proximityLatitude != null && proximityLongitude != null)
          'proximity': '$proximityLongitude,$proximityLatitude',
      },
    );

    final http.Response response = await _client
        .get(uri)
        .timeout(const Duration(seconds: 8));
    if (response.statusCode != 200) {
      throw PlaceSearchException(
        'Place suggestions are unavailable (HTTP ${response.statusCode}).',
      );
    }

    final Object? decoded = jsonDecode(response.body);
    if (decoded is! Map || decoded['features'] is! List) {
      throw const FormatException('Place search returned invalid results.');
    }

    final List<PlaceSearchResult> results = [];
    for (final Object? feature in decoded['features'] as List) {
      if (feature is! Map) continue;

      final Object? centerValue = feature['center'];
      final Object? placeNameValue = feature['place_name'];
      if (centerValue is! List ||
          centerValue.length < 2 ||
          placeNameValue is! String) {
        continue;
      }

      final double? longitude = _asDouble(centerValue[0]);
      final double? latitude = _asDouble(centerValue[1]);
      if (latitude == null ||
          longitude == null ||
          !latitude.isFinite ||
          !longitude.isFinite ||
          latitude < -90 ||
          latitude > 90 ||
          longitude < -180 ||
          longitude > 180) {
        continue;
      }

      final String displayName = placeNameValue.trim();
      if (displayName.isEmpty) continue;

      final Object? textValue = feature['text'];
      final String? featureName = textValue is String ? textValue.trim() : null;
      final String name = featureName?.isNotEmpty == true
          ? featureName!
          : displayName.split(',').first.trim();
      final String namePrefix = '$name,';
      final String? address =
          displayName.toLowerCase().startsWith(namePrefix.toLowerCase())
          ? displayName.substring(namePrefix.length).trim()
          : displayName == name
          ? null
          : displayName;

      results.add(
        PlaceSearchResult(
          name: name,
          displayName: displayName,
          address: address?.isEmpty == true ? null : address,
          latitude: latitude,
          longitude: longitude,
        ),
      );
    }

    return results;
  }

  void dispose() {
    if (_ownsClient) _client.close();
  }

  static double? _asDouble(Object? value) {
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }
}
