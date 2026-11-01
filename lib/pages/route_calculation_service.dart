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
    this.weightName,
    this.roadSummary,
  });

  final List<RouteCoordinate> geometry;
  final double distanceMeters;
  final double durationSeconds;
  final String? weightName;
  final String? roadSummary;
}

class RoutePlanResult {
  const RoutePlanResult({
    required this.from,
    required this.to,
    required this.routes,
    this.viaStops = const [],
  });

  final PlaceSearchResult from;
  final PlaceSearchResult to;
  final List<PlaceSearchResult> viaStops;
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
    List<PlaceSearchResult> viaStops = const [],
  }) async {
    final List<PlaceSearchResult> waypoints = [from, ...viaStops, to];
    for (final PlaceSearchResult waypoint in waypoints) {
      _validateCoordinate(waypoint.latitude, waypoint.longitude);
    }
    final String coordinates = waypoints
        .map((waypoint) => '${waypoint.longitude},${waypoint.latitude}')
        .join(';');

    final Uri uri = Uri.https(
      _baseUrl,
      '/route/v1/driving/$coordinates',
      {
        'alternatives': viaStops.isEmpty ? 'true' : 'false',
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
      if (route != null) routes.add(route);
    }
    if (routes.isEmpty) {
      throw const RouteCalculationException(
        'The routing service returned no valid route geometry.',
      );
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
    final Object? weightNameValue = value['weight_name'];
    final Object? legsValue = value['legs'];
    final List<String> summaries = [];
    if (legsValue is List) {
      for (final Object? leg in legsValue) {
        if (leg is Map && leg['summary'] is String) {
          final String summary = (leg['summary'] as String).trim();
          if (summary.isNotEmpty && !summaries.contains(summary)) {
            summaries.add(summary);
          }
        }
      }
    }

    return OsrmRoute(
      geometry: List<RouteCoordinate>.unmodifiable(coordinates),
      distanceMeters: distance,
      durationSeconds: duration,
      weightName: weightNameValue is String && weightNameValue.trim().isNotEmpty
          ? weightNameValue.trim()
          : null,
      roadSummary: summaries.isEmpty ? null : summaries.join(' · '),
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
