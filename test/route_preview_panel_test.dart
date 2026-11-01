import 'package:better_routes/pages/place_search_service.dart';
import 'package:better_routes/pages/route_calculation_service.dart';
import 'package:better_routes/pages/route_preview_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const RoutePlanResult plan = RoutePlanResult(
    from: PlaceSearchResult(
      name: 'Start',
      displayName: 'Start location',
      latitude: 26.9,
      longitude: 75.7,
    ),
    to: PlaceSearchResult(
      name: 'Destination',
      displayName: 'Destination location',
      latitude: 27,
      longitude: 75.8,
    ),
    routes: [
      OsrmRoute(
        geometry: [
          RouteCoordinate(latitude: 26.9, longitude: 75.7),
          RouteCoordinate(latitude: 27, longitude: 75.8),
        ],
        distanceMeters: 12000,
        durationSeconds: 1800,
      ),
      OsrmRoute(
        geometry: [
          RouteCoordinate(latitude: 26.9, longitude: 75.7),
          RouteCoordinate(latitude: 27.01, longitude: 75.79),
        ],
        distanceMeters: 14500,
        durationSeconds: 2100,
        roadSummary: 'Ring road',
      ),
    ],
  );

  testWidgets('exposes alternative selection and working route actions', (
    tester,
  ) async {
    int? selectedRoute;
    int starts = 0;
    int edits = 0;
    int clears = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 800,
            child: RoutePreviewPanel(
              scrollController: ScrollController(),
              plan: plan,
              selectedRouteIndex: 0,
              isNavigating: false,
              onSelectRoute: (index) => selectedRoute = index,
              onStartNavigation: () => starts++,
              onExitNavigation: () {},
              onEditStops: () => edits++,
              onClearRoute: () => clears++,
              remainingDistanceMeters: null,
              remainingDuration: null,
              isOffRoute: false,
              isLocationUnavailable: false,
            ),
          ),
        ),
      ),
    );

    expect(find.text('2 routes'), findsOneWidget);
    expect(find.textContaining('12 km'), findsOneWidget);
    expect(find.text('Alternative 1'), findsOneWidget);
    await tester.tap(find.text('Alternative 1'));
    expect(selectedRoute, 1);
    await tester.tap(find.text('Start'));
    await tester.tap(find.text('Edit stops'));
    await tester.tap(find.text('Clear'));
    expect(starts, 1);
    expect(edits, 1);
    expect(clears, 1);
  });

  testWidgets('displays live progress and can exit without clearing route', (
    tester,
  ) async {
    var exited = false;
    var cleared = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 800,
            child: RoutePreviewPanel(
              scrollController: ScrollController(),
              plan: plan,
              selectedRouteIndex: 0,
              isNavigating: true,
              onSelectRoute: (_) {},
              onStartNavigation: () {},
              onExitNavigation: () => exited = true,
              onEditStops: () {},
              onClearRoute: () => cleared = true,
              remainingDistanceMeters: 6500,
              remainingDuration: const Duration(minutes: 17),
              isOffRoute: false,
              isLocationUnavailable: false,
            ),
          ),
        ),
      ),
    );

    expect(find.text('Navigation active'), findsOneWidget);
    expect(find.text('6.5 km remaining  ·  17 min'), findsOneWidget);
    await tester.tap(find.text('Exit navigation'));
    expect(exited, isTrue);
    expect(cleared, isFalse);
  });

  testWidgets('shows route summary in route details without inventing steps', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 800,
            child: RoutePreviewPanel(
              scrollController: ScrollController(),
              plan: plan,
              selectedRouteIndex: 1,
              isNavigating: false,
              onSelectRoute: (_) {},
              onStartNavigation: () {},
              onExitNavigation: () {},
              onEditStops: () {},
              onClearRoute: () {},
              remainingDistanceMeters: null,
              remainingDuration: null,
              isOffRoute: false,
              isLocationUnavailable: false,
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Route details'));
    await tester.pumpAndSettle();
    expect(find.text('Road overview'), findsOneWidget);
    expect(find.text('Ring road'), findsOneWidget);
    expect(find.textContaining('coordinates from OSRM'), findsOneWidget);
    expect(find.textContaining('Turn left'), findsNothing);
  });
}
