import 'package:better_routes/pages/route_calculation_service.dart';
import 'package:better_routes/pages/route_navigation_progress.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const OsrmRoute route = OsrmRoute(
    geometry: [
      RouteCoordinate(latitude: 0, longitude: 0),
      RouteCoordinate(latitude: 0, longitude: 0.01),
    ],
    distanceMeters: 1112,
    durationSeconds: 600,
  );

  test('estimates remaining distance and time from route progress', () {
    final RouteNavigationProgress progress =
        RouteNavigationProgress.calculate(
          route: route,
          latitude: 0,
          longitude: 0.005,
        );

    expect(progress.remainingDistanceMeters, closeTo(556, 5));
    expect(progress.remainingDuration.inSeconds, closeTo(300, 3));
    expect(progress.isOffRoute, isFalse);
  });

  test('identifies positions away from the planned route', () {
    final RouteNavigationProgress progress =
        RouteNavigationProgress.calculate(
          route: route,
          latitude: 0.002,
          longitude: 0.005,
        );

    expect(progress.isOffRoute, isTrue);
    expect(progress.remainingDistanceMeters, closeTo(556, 5));
  });

  test('does not move the displayed progress backwards', () {
    final RouteNavigationProgress progress =
        RouteNavigationProgress.calculate(
          route: route,
          latitude: 0,
          longitude: 0.002,
          minimumProgressMeters: 800,
        );

    expect(progress.progressMeters, 800);
    expect(progress.remainingDistanceMeters, lessThan(400));
  });
}
