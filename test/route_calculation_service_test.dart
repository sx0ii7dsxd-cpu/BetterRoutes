import 'dart:convert';

import 'package:better_routes/pages/place_search_service.dart';
import 'package:better_routes/pages/route_calculation_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test(
    'requests driving alternatives in GeoJSON with lon,lat coordinates',
    () async {
      Uri? requestedUri;
      final MockClient client = MockClient((request) async {
        requestedUri = request.url;
        return http.Response(
          jsonEncode({
            'code': 'Ok',
            'routes': [
              _route(
                distance: 1200,
                duration: 180,
                coordinates: [
                  [75.7, 26.9],
                  [75.8, 27.0],
                ],
              ),
              _route(
                distance: 1600,
                duration: 240,
                coordinates: [
                  [75.7, 26.9],
                  [75.9, 27.1],
                ],
              ),
            ],
          }),
          200,
        );
      });
      final RouteCalculationService service = RouteCalculationService(
        client: client,
      );

      final List<OsrmRoute> routes = await service.calculate(
        from: _place(latitude: 26.9, longitude: 75.7),
        to: _place(latitude: 27.0, longitude: 75.8),
      );

      expect(requestedUri!.path, '/route/v1/driving/75.7,26.9;75.8,27.0');
      expect(requestedUri!.queryParameters['alternatives'], 'true');
      expect(requestedUri!.queryParameters['overview'], 'full');
      expect(requestedUri!.queryParameters['geometries'], 'geojson');
      expect(requestedUri!.queryParameters['steps'], 'false');
      expect(routes, hasLength(2));
      expect(routes.first.geometry.first.latitude, 26.9);
      expect(routes.first.geometry.first.longitude, 75.7);
      expect(routes.last.distanceMeters, 1600);

      client.close();
    },
  );

  test('reports when OSRM has no route', () async {
    final MockClient client = MockClient(
      (_) async => http.Response('{"code":"NoRoute","routes":[]}', 200),
    );
    final RouteCalculationService service = RouteCalculationService(
      client: client,
    );

    await expectLater(
      service.calculate(
        from: _place(latitude: 26.9, longitude: 75.7),
        to: _place(latitude: 27.0, longitude: 75.8),
      ),
      throwsA(
        isA<RouteCalculationException>().having(
          (error) => error.message,
          'message',
          contains('No drivable route'),
        ),
      ),
    );

    client.close();
  });

  test('rejects malformed or out-of-range route geometry', () async {
    for (final List<Object> coordinates in [
      <Object>[
        <num>[75.7, 26.9],
      ],
      <Object>[
        <num>[200, 26.9],
        <num>[75.8, 27.0],
      ],
    ]) {
      final MockClient client = MockClient(
        (_) async => http.Response(
          jsonEncode({
            'code': 'Ok',
            'routes': [
              _route(distance: 100, duration: 10, coordinates: coordinates),
            ],
          }),
          200,
        ),
      );
      final RouteCalculationService service = RouteCalculationService(
        client: client,
      );

      await expectLater(
        service.calculate(
          from: _place(latitude: 26.9, longitude: 75.7),
          to: _place(latitude: 27.0, longitude: 75.8),
        ),
        throwsA(isA<RouteCalculationException>()),
      );
      client.close();
    }
  });

  test('rejects invalid input coordinates before requesting OSRM', () async {
    var requestCount = 0;
    final MockClient client = MockClient((_) async {
      requestCount++;
      return http.Response('{}', 200);
    });
    final RouteCalculationService service = RouteCalculationService(
      client: client,
    );

    await expectLater(
      service.calculate(
        from: _place(latitude: 91, longitude: 75.7),
        to: _place(latitude: 27, longitude: 75.8),
      ),
      throwsA(isA<RouteCalculationException>()),
    );
    expect(requestCount, 0);

    client.close();
  });
}

Map<String, Object> _route({
  required num distance,
  required num duration,
  required List<Object> coordinates,
}) {
  return {
    'distance': distance,
    'duration': duration,
    'geometry': {'type': 'LineString', 'coordinates': coordinates},
  };
}

PlaceSearchResult _place({
  required double latitude,
  required double longitude,
}) {
  return PlaceSearchResult(
    name: 'Test location',
    displayName: 'Test location',
    latitude: latitude,
    longitude: longitude,
  );
}
