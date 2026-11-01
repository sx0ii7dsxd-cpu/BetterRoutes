import 'dart:convert';

import 'package:better_routes/pages/place_search_service.dart';
import 'package:better_routes/pages/route_calculation_service.dart';
import 'package:better_routes/pages/route_planning_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  testWidgets('Find Route returns the calculated route set to its caller', (
    WidgetTester tester,
  ) async {
    final MockClient client = MockClient((request) async {
      expect(request.url.path, contains('/route/v1/driving/75.7,26.9;75.8,27'));
      return http.Response(
        jsonEncode({
          'code': 'Ok',
          'routes': [
            {
              'distance': 1000,
              'duration': 120,
              'geometry': {
                'type': 'LineString',
                'coordinates': [
                  [75.7, 26.9],
                  [75.8, 27.0],
                ],
              },
            },
          ],
        }),
        200,
      );
    });
    final RouteCalculationService routeService = RouteCalculationService(
      client: client,
    );
    RoutePlanResult? calculatedPlan;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                calculatedPlan = await Navigator.of(context)
                    .push<RoutePlanResult>(
                      MaterialPageRoute<RoutePlanResult>(
                        builder: (_) => RoutePlanningPage(
                          startingLocation: _place(
                            name: 'Start',
                            latitude: 26.9,
                            longitude: 75.7,
                          ),
                          destination: _place(
                            name: 'End',
                            latitude: 27,
                            longitude: 75.8,
                          ),
                          routeCalculationService: routeService,
                        ),
                      ),
                    );
              },
              child: const Text('Open planner'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open planner'));
    await tester.pumpAndSettle();

    expect(find.text('SETUP'), findsNothing);
    await tester.drag(find.byType(ListView).last, const Offset(0, -700));
    await tester.pumpAndSettle();
    expect(find.text('Find Route'), findsOneWidget);
    final Finder findRouteButton = find.widgetWithText(
      FilledButton,
      'Find Route',
    );
    await tester.ensureVisible(findRouteButton);
    await tester.pumpAndSettle();
    await tester.tap(findRouteButton);
    await tester.pumpAndSettle();

    expect(calculatedPlan, isNotNull);
    expect(calculatedPlan!.routes, hasLength(1));
    expect(calculatedPlan!.from.latitude, 26.9);
    expect(calculatedPlan!.to.longitude, 75.8);

    await tester.pumpWidget(const SizedBox.shrink());
    client.close();
  });

  testWidgets('supports suggestions for both fields and swaps locations', (
    WidgetTester tester,
  ) async {
    final List<Uri> requests = [];
    final MockClient client = MockClient((request) async {
      requests.add(request.url);
      return http.Response(
        jsonEncode({
          'features': [
            {
              'text': 'Mysuru',
              'place_name': 'Mysuru, Karnataka, India',
              'center': [76.6394, 12.2958],
            },
          ],
        }),
        200,
      );
    });
    final PlaceSearchService searchService = PlaceSearchService(
      apiKey: 'test-key',
      client: client,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: RoutePlanningPage(
          startingLocation: _place(
            name: 'Current location',
            latitude: 26.9124,
            longitude: 75.7873,
          ),
          destination: _place(
            name: 'Central Station',
            address: '1 Station Road',
            latitude: 26.9201,
            longitude: 75.7902,
          ),
          placeSearchService: searchService,
        ),
      ),
    );

    Finder fields = find.byType(TextField);
    TextField fieldAt(int index) => tester.widget<TextField>(fields.at(index));
    expect(fieldAt(0).controller!.text, 'Current location');
    expect(fieldAt(1).controller!.text, 'Central Station');
    expect(find.text('1 Station Road'), findsOneWidget);

    await tester.tap(find.byTooltip('Clear from location'));
    await tester.pump();
    await tester.enterText(fields.at(0), 'Mysuru');
    await tester.pump(const Duration(milliseconds: 450));
    await tester.pump();

    expect(find.widgetWithText(ListTile, 'Mysuru'), findsOneWidget);
    expect(find.text('Karnataka, India'), findsOneWidget);
    expect(requests, hasLength(1));
    expect(requests.single.queryParameters['country'], 'in');
    expect(requests.single.queryParameters['proximity'], '75.7873,26.9124');

    await tester.tap(find.widgetWithText(ListTile, 'Mysuru'));
    await tester.pumpAndSettle();
    expect(fieldAt(0).controller!.text, 'Mysuru, Karnataka, India');

    await tester.tap(find.byTooltip('Swap starting point and destination'));
    await tester.pump();
    expect(fieldAt(0).controller!.text, 'Central Station');
    expect(fieldAt(1).controller!.text, 'Mysuru, Karnataka, India');
    expect(find.text('Karnataka, India'), findsOneWidget);

    await tester.enterText(fields.at(1), 'Pune');
    await tester.pump(const Duration(milliseconds: 450));
    await tester.pump();
    expect(requests, hasLength(2));
    expect(requests[1].queryParameters['proximity'], '75.7873,26.9124');
    expect(find.widgetWithText(ListTile, 'Mysuru'), findsOneWidget);
    await tester.tap(find.widgetWithText(ListTile, 'Mysuru'));
    await tester.pumpAndSettle();
    expect(fieldAt(1).controller!.text, 'Mysuru, Karnataka, India');

    await tester.pumpWidget(const SizedBox.shrink());
    client.close();
  });

  testWidgets('adds a searchable stop and includes it in OSRM routing', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(430, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final MockClient searchClient = MockClient((request) async {
      return http.Response(
        jsonEncode({
          'features': [
            {
              'text': 'Mysuru Palace',
              'place_name': 'Mysuru Palace, Mysuru, India',
              'center': [75.75, 26.95],
            },
          ],
        }),
        200,
      );
    });
    final PlaceSearchService searchService = PlaceSearchService(
      apiKey: 'test-key',
      client: searchClient,
    );
    Uri? routeUri;
    final MockClient routeClient = MockClient((request) async {
      routeUri = request.url;
      return http.Response(
        jsonEncode({
          'code': 'Ok',
          'routes': [
            {
              'distance': 2400,
              'duration': 360,
              'geometry': {
                'type': 'LineString',
                'coordinates': [
                  [75.7, 26.9],
                  [75.75, 26.95],
                  [75.8, 27.0],
                ],
              },
            },
          ],
        }),
        200,
      );
    });
    final RouteCalculationService routeService = RouteCalculationService(
      client: routeClient,
    );
    RoutePlanResult? calculatedPlan;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                calculatedPlan = await Navigator.of(context)
                    .push<RoutePlanResult>(
                      MaterialPageRoute<RoutePlanResult>(
                        builder: (_) => RoutePlanningPage(
                          startingLocation: _place(
                            name: 'Start',
                            latitude: 26.9,
                            longitude: 75.7,
                          ),
                          destination: _place(
                            name: 'End',
                            latitude: 27,
                            longitude: 75.8,
                          ),
                          placeSearchService: searchService,
                          routeCalculationService: routeService,
                        ),
                      ),
                    );
              },
              child: const Text('Open planner'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open planner'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Add new stop'));
    await tester.pumpAndSettle();
    expect(find.text('STOP 1'), findsOneWidget);
    final Finder stopField = find.byType(TextField).at(1);
    await tester.ensureVisible(stopField);
    await tester.pumpAndSettle();
    await tester.enterText(stopField, 'Mysuru Palace');
    await tester.pump(const Duration(milliseconds: 450));
    await tester.pumpAndSettle();
    expect(find.text('Mysuru Palace'), findsWidgets);
    final Finder suggestion = find.widgetWithText(ListTile, 'Mysuru Palace');
    await tester.ensureVisible(suggestion);
    await tester.pumpAndSettle();
    await tester.tap(suggestion);
    await tester.pumpAndSettle();
    expect(find.text('Mysuru Palace, Mysuru, India'), findsOneWidget);

    final Finder findRouteButton = find.widgetWithText(
      FilledButton,
      'Find Route',
    );
    await tester.ensureVisible(findRouteButton);
    await tester.pumpAndSettle();
    await tester.tap(findRouteButton);
    await tester.pumpAndSettle();

    expect(routeUri!.path, '/route/v1/driving/75.7,26.9;75.75,26.95;75.8,27.0');
    expect(routeUri!.queryParameters['alternatives'], 'false');
    expect(calculatedPlan!.viaStops, hasLength(1));
    expect(
      calculatedPlan!.viaStops.single.displayName,
      'Mysuru Palace, Mysuru, India',
    );

    await tester.pumpWidget(const SizedBox.shrink());
    searchClient.close();
    routeClient.close();
  });

  testWidgets('shows an empty-results message and reports search failures', (
    WidgetTester tester,
  ) async {
    final MockClient client = MockClient((request) async {
      if (request.url.path.contains('failure')) {
        throw http.ClientException('offline', request.url);
      }
      return http.Response('{"features":[]}', 200);
    });
    final PlaceSearchService searchService = PlaceSearchService(
      apiKey: 'test-key',
      client: client,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: RoutePlanningPage(
          startingLocation: null,
          destination: _place(
            name: 'Central Station',
            latitude: 26.9201,
            longitude: 75.7902,
          ),
          placeSearchService: searchService,
        ),
      ),
    );

    final Finder fromField = find.byType(TextField).first;
    await tester.enterText(fromField, 'unknown');
    await tester.pump(const Duration(milliseconds: 450));
    await tester.pump();
    expect(find.text('No places found.'), findsOneWidget);

    await tester.enterText(fromField, 'failure');
    await tester.pump(const Duration(milliseconds: 450));
    await tester.pump();
    expect(
      find.text('Could not connect to place search. Check your connection.'),
      findsOneWidget,
    );

    await tester.pumpWidget(const SizedBox.shrink());
    client.close();
  });

  testWidgets('leaves From empty when current location is unavailable', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: RoutePlanningPage(
          startingLocation: null,
          destination: _place(
            name: 'Central Station',
            latitude: 26.9201,
            longitude: 75.7902,
          ),
        ),
      ),
    );

    final Finder fields = find.byType(TextField);
    expect(tester.widget<TextField>(fields.first).controller!.text, isEmpty);
    expect(
      tester.widget<TextField>(fields.last).controller!.text,
      'Central Station',
    );
    expect(find.byTooltip('Clear from location'), findsNothing);
  });

  test(
    'parses selected MapTiler coordinates without inventing a location',
    () async {
      final MockClient client = MockClient(
        (_) async => http.Response(
          jsonEncode({
            'features': [
              {
                'text': 'Mysuru',
                'place_name': 'Mysuru, Karnataka, India',
                'center': [76.6394, 12.2958],
              },
              {
                'text': 'Invalid result',
                'place_name': 'Invalid result, India',
                'center': [],
              },
            ],
          }),
          200,
        ),
      );
      final PlaceSearchService searchService = PlaceSearchService(
        apiKey: 'test-key',
        client: client,
      );

      final List<PlaceSearchResult> results = await searchService.search(
        'Mysuru',
      );

      expect(results, hasLength(1));
      expect(results.single.name, 'Mysuru');
      expect(results.single.displayName, 'Mysuru, Karnataka, India');
      expect(results.single.address, 'Karnataka, India');
      expect(results.single.latitude, 12.2958);
      expect(results.single.longitude, 76.6394);

      client.close();
    },
  );
}

PlaceSearchResult _place({
  required String name,
  required double latitude,
  required double longitude,
  String? address,
}) {
  return PlaceSearchResult(
    name: name,
    displayName: name,
    address: address,
    latitude: latitude,
    longitude: longitude,
  );
}
