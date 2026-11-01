import 'dart:math' as math;

import 'route_calculation_service.dart';

class RouteNavigationProgress {
  const RouteNavigationProgress({
    required this.remainingDistanceMeters,
    required this.remainingDuration,
    required this.distanceFromRouteMeters,
    required this.progressMeters,
  });

  final double remainingDistanceMeters;
  final Duration remainingDuration;
  final double distanceFromRouteMeters;
  final double progressMeters;

  bool get isOffRoute => distanceFromRouteMeters > 100;

  static RouteNavigationProgress calculate({
    required OsrmRoute route,
    required double latitude,
    required double longitude,
    double minimumProgressMeters = 0,
  }) {
    final List<RouteCoordinate> points = route.geometry;
    if (points.length < 2) {
      return RouteNavigationProgress(
        remainingDistanceMeters: route.distanceMeters,
        remainingDuration: Duration(
          seconds: route.durationSeconds.round(),
        ),
        distanceFromRouteMeters: double.infinity,
        progressMeters: 0,
      );
    }

    double geometryLength = 0;
    double distanceAlongRoute = 0;
    double closestDistance = double.infinity;
    double progressAtClosestPoint = 0;

    for (int index = 0; index < points.length - 1; index++) {
      final RouteCoordinate start = points[index];
      final RouteCoordinate end = points[index + 1];
      final double segmentLength = _distanceBetween(start, end);
      geometryLength += segmentLength;

      final double latitudeScale = 111320;
      final double longitudeScale =
          111320 * math.cos(latitude * math.pi / 180);
      final double startX = (start.longitude - longitude) * longitudeScale;
      final double startY = (start.latitude - latitude) * latitudeScale;
      final double endX = (end.longitude - longitude) * longitudeScale;
      final double endY = (end.latitude - latitude) * latitudeScale;
      final double segmentX = endX - startX;
      final double segmentY = endY - startY;
      final double segmentSquared = segmentX * segmentX + segmentY * segmentY;
      final double fraction = segmentSquared == 0
          ? 0
          : (-(startX * segmentX + startY * segmentY) / segmentSquared)
                .clamp(0, 1)
                .toDouble();
      final double closestX = startX + segmentX * fraction;
      final double closestY = startY + segmentY * fraction;
      final double distance = math.sqrt(
        closestX * closestX + closestY * closestY,
      );

      if (distance < closestDistance) {
        closestDistance = distance;
        progressAtClosestPoint = distanceAlongRoute + segmentLength * fraction;
      }
      distanceAlongRoute += segmentLength;
    }

    final double monotonicProgress = math
        .max(progressAtClosestPoint, minimumProgressMeters)
        .clamp(0, geometryLength)
        .toDouble();
    final double progressFraction = geometryLength == 0
        ? 0
        : (monotonicProgress / geometryLength).clamp(0, 1).toDouble();
    return RouteNavigationProgress(
      remainingDistanceMeters:
          route.distanceMeters * (1 - progressFraction),
      remainingDuration: Duration(
        seconds: (route.durationSeconds * (1 - progressFraction)).round(),
      ),
      distanceFromRouteMeters: closestDistance,
      progressMeters: monotonicProgress,
    );
  }

  static double _distanceBetween(RouteCoordinate first, RouteCoordinate second) {
    const double earthRadiusMeters = 6371000;
    final double firstLatitude = first.latitude * math.pi / 180;
    final double secondLatitude = second.latitude * math.pi / 180;
    final double latitudeDifference = secondLatitude - firstLatitude;
    final double longitudeDifference =
        (second.longitude - first.longitude) * math.pi / 180;
    final double haversine =
        math.sin(latitudeDifference / 2) * math.sin(latitudeDifference / 2) +
        math.cos(firstLatitude) *
            math.cos(secondLatitude) *
            math.sin(longitudeDifference / 2) *
            math.sin(longitudeDifference / 2);
    return earthRadiusMeters *
        2 *
        math.atan2(math.sqrt(haversine), math.sqrt(1 - haversine));
  }
}
