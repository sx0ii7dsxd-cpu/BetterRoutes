import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'place_search_service.dart';

class RouteCoordinate {
  const RouteCoordinate({required this.latitude, required this.longitude});

  final double latitude;
  final double longitude;
}

class OsrmRoute {
  const OsrmRoute({
    required this.geometry,
    required this.distanceMeters,
    required this.durationSeconds,
  });

  final List<RouteCoordinate> geometry;
  final double distanceMeters;
  final double durationSeconds;
}

class RoutePlanResult {
  const RoutePlanResult({
    required this.from,
    required this.to,
    required this.routes,
  });

  final PlaceSearchResult from;
  final PlaceSearchResult to;
  final List<OsrmRoute> routes;
}

class RouteCalculationException implements Exception {
  const RouteCalculationException(this.message);

  final String message;

  @override
  String toString() => message;
}

class RouteCalculationService {
  static const String _baseUrl = 'router.project-osrm.org';

  RouteCalculationService({http.Client? client})
    : _client = client ?? http.Client(),
      _ownsClient = client == null;

  final http.Client _client;
  final bool _ownsClient;

  Future<List<OsrmRoute>> calculate({
    required PlaceSearchResult from,
    required PlaceSearchResult to,
  }) async {
    _validateCoordinate(from.latitude, from.longitude);
    _validateCoordinate(to.latitude, to.longitude);

    final Uri uri = Uri.https(
      _baseUrl,
      '/route/v1/driving/'
      '${from.longitude},${from.latitude};${to.longitude},${to.latitude}',
      {
        'alternatives': 'true',
        'overview': 'full',
        'geometries': 'geojson',
        'steps': 'false',
      },
    );

    final http.Response response;
    try {
      response = await _client.get(uri).timeout(const Duration(seconds: 20));
    } on TimeoutException {
      throw const RouteCalculationException(
        'Route calculation timed out. Please try again.',
      );
    } on http.ClientException {
      throw const RouteCalculationException(
        'Could not connect to the routing service. Check your connection.',
      );
    } on SocketException {
      throw const RouteCalculationException(
        'Could not connect to the routing service. Check your connection.',
      );
    } on TlsException {
      throw const RouteCalculationException(
        'Could not establish a secure connection to the routing service.',
      );
    }

    if (response.statusCode != 200) {
      throw RouteCalculationException(
        'The routing service is unavailable (HTTP ${response.statusCode}).',
      );
    }

    final Object? decoded;
    try {
      decoded = jsonDecode(response.body);
    } on FormatException {
      throw const RouteCalculationException(
        'The routing service returned an unreadable response.',
      );
    }
    if (decoded is! Map<String, dynamic> || decoded['code'] is! String) {
      throw const RouteCalculationException(
        'The routing service returned an invalid response.',
      );
    }

    final String code = decoded['code'] as String;
    if (code == 'NoRoute') {
      throw const RouteCalculationException(
        'No drivable route was found between these locations.',
      );
    }
    if (code != 'Ok') {
      throw RouteCalculationException(
        'Route calculation failed${decoded['message'] is String ? ': ${decoded['message']}' : '.'}',
      );
    }

    final Object? routesValue = decoded['routes'];
    if (routesValue is! List || routesValue.isEmpty) {
      throw const RouteCalculationException(
        'The routing service did not return a route.',
      );
    }

    final List<OsrmRoute> routes = [];
    for (final Object? routeValue in routesValue) {
      final OsrmRoute? route = _parseRoute(routeValue);
      if (route == null) {
        throw const RouteCalculationException(
          'The routing service returned invalid route geometry.',
        );
      }
      routes.add(route);
    }
    return List<OsrmRoute>.unmodifiable(routes);
  }

  void dispose() {
    if (_ownsClient) _client.close();
  }

  static OsrmRoute? _parseRoute(Object? value) {
    if (value is! Map) return null;
    final Object? distanceValue = value['distance'];
    final Object? durationValue = value['duration'];
    final Object? geometryValue = value['geometry'];
    if (geometryValue is! Map ||
        geometryValue['type'] != 'LineString' ||
        geometryValue['coordinates'] is! List) {
      return null;
    }

    final double? distance = _asDouble(distanceValue);
    final double? duration = _asDouble(durationValue);
    if (distance == null ||
        duration == null ||
        !distance.isFinite ||
        !duration.isFinite ||
        distance < 0 ||
        duration < 0) {
      return null;
    }

    final List<RouteCoordinate> coordinates = [];
    for (final Object? coordinateValue
        in geometryValue['coordinates'] as List) {
      if (coordinateValue is! List || coordinateValue.length < 2) return null;
      final double? longitude = _asDouble(coordinateValue[0]);
      final double? latitude = _asDouble(coordinateValue[1]);
      if (latitude == null ||
          longitude == null ||
          !latitude.isFinite ||
          !longitude.isFinite ||
          latitude < -90 ||
          latitude > 90 ||
          longitude < -180 ||
          longitude > 180) {
        return null;
      }
      coordinates.add(
        RouteCoordinate(latitude: latitude, longitude: longitude),
      );
    }
    if (coordinates.length < 2) return null;

    return OsrmRoute(
      geometry: List<RouteCoordinate>.unmodifiable(coordinates),
      distanceMeters: distance,
      durationSeconds: duration,
    );
  }

  static double? _asDouble(Object? value) {
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }

  static void _validateCoordinate(double latitude, double longitude) {
    if (!latitude.isFinite ||
        !longitude.isFinite ||
        latitude < -90 ||
        latitude > 90 ||
        longitude < -180 ||
        longitude > 180) {
      throw const RouteCalculationException(
        'Choose valid starting and destination locations first.',
      );
    }
  }
}
