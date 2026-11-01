import 'package:flutter/material.dart';

import 'route_calculation_service.dart';

const Color _panelBackground = Color(0xFF17131F);
const Color _panelSurface = Color(0xFF211C2B);
const Color _panelSurfaceRaised = Color(0xFF292334);
const Color _panelAmethyst = Color(0xFFB39DDB);
const Color _panelText = Color(0xFFF7F5FC);
const Color _panelMuted = Color(0xFFB5AEC5);
const Color _panelBorder = Color(0xFF383044);
const Color _panelGreen = Color(0xFF5CC6A3);

class RoutePreviewPanel extends StatelessWidget {
  const RoutePreviewPanel({
    required this.scrollController,
    required this.plan,
    required this.selectedRouteIndex,
    required this.isNavigating,
    required this.onSelectRoute,
    required this.onStartNavigation,
    required this.onExitNavigation,
    required this.onEditStops,
    required this.onClearRoute,
    required this.remainingDistanceMeters,
    required this.remainingDuration,
    required this.isOffRoute,
    required this.isLocationUnavailable,
    super.key,
  });

  final ScrollController scrollController;
  final RoutePlanResult plan;
  final int selectedRouteIndex;
  final bool isNavigating;
  final ValueChanged<int> onSelectRoute;
  final VoidCallback onStartNavigation;
  final VoidCallback onExitNavigation;
  final VoidCallback onEditStops;
  final VoidCallback onClearRoute;
  final double? remainingDistanceMeters;
  final Duration? remainingDuration;
  final bool isOffRoute;
  final bool isLocationUnavailable;

  @override
  Widget build(BuildContext context) {
    final OsrmRoute selectedRoute = plan.routes[selectedRouteIndex];
    return DecoratedBox(
      decoration: BoxDecoration(
        color: _panelBackground.withValues(alpha: 0.99),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        border: Border.all(color: _panelBorder),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.34),
            blurRadius: 22,
            offset: const Offset(0, -6),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        child: CustomScrollView(
          controller: scrollController,
          physics: const BouncingScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 30),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 42,
                        height: 5,
                        decoration: BoxDecoration(
                          color: _panelBorder,
                          borderRadius: BorderRadius.circular(5),
                        ),
                      ),
                    ),
                    const SizedBox(height: 17),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            isNavigating ? 'Navigation' : 'Route preview',
                            style: const TextStyle(
                              color: _panelText,
                              fontSize: 22,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        TextButton.icon(
                          onPressed: onClearRoute,
                          icon: const Icon(Icons.delete_outline_rounded),
                          label: const Text('Clear'),
                          style: TextButton.styleFrom(
                            foregroundColor: _panelMuted,
                            visualDensity: VisualDensity.compact,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    _stopRow(
                      icon: Icons.trip_origin_rounded,
                      color: _panelGreen,
                      label: plan.from.displayName,
                    ),
                    for (final stop in plan.viaStops) ...[
                      const Padding(
                        padding: EdgeInsets.only(left: 11),
                        child: SizedBox(
                          height: 16,
                          child: VerticalDivider(
                            color: _panelBorder,
                            thickness: 1.5,
                          ),
                        ),
                      ),
                      _stopRow(
                        icon: Icons.stop_circle_rounded,
                        color: _panelAmethyst,
                        label: stop.displayName,
                      ),
                    ],
                    const Padding(
                      padding: EdgeInsets.only(left: 11),
                      child: SizedBox(
                        height: 16,
                        child: VerticalDivider(
                          color: _panelBorder,
                          thickness: 1.5,
                        ),
                      ),
                    ),
                    _stopRow(
                      icon: Icons.location_on_rounded,
                      color: _panelAmethyst,
                      label: plan.to.displayName,
                    ),
                    if (isNavigating) ...[
                      const SizedBox(height: 16),
                      _navigationStatus(),
                    ] else ...[
                      const SizedBox(height: 19),
                      Text(
                        '${plan.routes.length} route${plan.routes.length == 1 ? '' : 's'}',
                        style: const TextStyle(
                          color: _panelMuted,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.8,
                        ),
                      ),
                      const SizedBox(height: 10),
                      for (final (index, route) in plan.routes.indexed)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 9),
                          child: _routeCard(
                            context,
                            route: route,
                            index: index,
                            selected: selectedRouteIndex == index,
                          ),
                        ),
                      const SizedBox(height: 5),
                      _primaryButton(
                        label: 'Start',
                        icon: Icons.navigation_rounded,
                        onPressed: onStartNavigation,
                      ),
                    ],
                    if (isNavigating) ...[
                      const SizedBox(height: 14),
                      _primaryButton(
                        label: 'Exit navigation',
                        icon: Icons.pause_circle_outline_rounded,
                        onPressed: onExitNavigation,
                      ),
                    ],
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: _secondaryButton(
                            icon: Icons.subject_rounded,
                            label: 'Route details',
                            onPressed: () => _showRouteDetails(
                              context,
                              plan: plan,
                              route: selectedRoute,
                              index: selectedRouteIndex,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _secondaryButton(
                            icon: Icons.edit_road_rounded,
                            label: 'Edit stops',
                            onPressed: onEditStops,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _stopRow({
    required IconData icon,
    required Color color,
    required String label,
  }) {
    return Row(
      children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(width: 11),
        Expanded(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: _panelText, fontSize: 14),
          ),
        ),
      ],
    );
  }

  Widget _routeCard(
    BuildContext context, {
    required OsrmRoute route,
    required int index,
    required bool selected,
  }) {
    final Color accent = selected ? _panelAmethyst : _panelMuted;
    return Material(
      color: selected ? _panelSurfaceRaised : _panelSurface,
      borderRadius: BorderRadius.circular(17),
      child: InkWell(
        onTap: () => onSelectRoute(index),
        borderRadius: BorderRadius.circular(17),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(17),
            border: Border.all(
              color: selected ? _panelAmethyst : _panelBorder,
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Row(
            children: [
              Icon(
                selected ? Icons.radio_button_checked : Icons.route_rounded,
                color: accent,
                size: 20,
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      index == 0 ? 'Route 1 · Primary' : 'Alternative $index',
                      style: TextStyle(
                        color: selected ? _panelText : _panelMuted,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${formatRouteDistance(route.distanceMeters)}  ·  '
                      '${formatRouteDuration(Duration(seconds: route.durationSeconds.round()))}',
                      style: const TextStyle(color: _panelMuted, fontSize: 12),
                    ),
                  ],
                ),
              ),
              if (selected)
                IconButton(
                  tooltip: 'View route details',
                  onPressed: () => _showRouteDetails(
                    context,
                    plan: plan,
                    route: route,
                    index: index,
                  ),
                  icon: const Icon(Icons.info_outline_rounded),
                  color: _panelAmethyst,
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _navigationStatus() {
    final double? distance = remainingDistanceMeters;
    final Duration? duration = remainingDuration;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: _panelSurface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isOffRoute ? const Color(0xFFE0A85C) : _panelBorder,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                isOffRoute
                    ? Icons.warning_amber_rounded
                    : Icons.navigation_rounded,
                color: isOffRoute ? const Color(0xFFE0A85C) : _panelAmethyst,
                size: 20,
              ),
              const SizedBox(width: 9),
              Text(
                isOffRoute ? 'Away from planned route' : 'Navigation active',
                style: const TextStyle(
                  color: _panelText,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 13),
          if (distance != null && duration != null)
            Text(
              '${formatRouteDistance(distance)} remaining  ·  '
              '${formatRouteDuration(duration)}',
              style: const TextStyle(
                color: _panelAmethyst,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            )
          else
            const Text(
              'Waiting for a GPS position to estimate progress.',
              style: TextStyle(color: _panelMuted, fontSize: 13),
            ),
          if (isLocationUnavailable) ...[
            const SizedBox(height: 8),
            const Text(
              'GPS is temporarily unavailable. The route remains active.',
              style: TextStyle(color: _panelMuted, fontSize: 12, height: 1.4),
            ),
          ],
          if (isOffRoute) ...[
            const SizedBox(height: 8),
            const Text(
              'This route is not being recalculated automatically.',
              style: TextStyle(color: _panelMuted, fontSize: 12, height: 1.4),
            ),
          ],
        ],
      ),
    );
  }

  Widget _primaryButton({
    required String label,
    required IconData icon,
    required VoidCallback onPressed,
  }) {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: FilledButton.icon(
        onPressed: onPressed,
        icon: Icon(icon),
        label: Text(label),
        style: FilledButton.styleFrom(
          backgroundColor: _panelAmethyst,
          foregroundColor: _panelBackground,
          textStyle: const TextStyle(fontWeight: FontWeight.w800),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(17),
          ),
        ),
      ),
    );
  }

  Widget _secondaryButton({
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
  }) {
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 18),
      label: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
      style: OutlinedButton.styleFrom(
        foregroundColor: _panelMuted,
        side: const BorderSide(color: _panelBorder),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 8),
        textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
      ),
    );
  }
}

void _showRouteDetails(
  BuildContext context, {
  required RoutePlanResult plan,
  required OsrmRoute route,
  required int index,
}) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) => SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(22, 14, 22, 28),
        decoration: const BoxDecoration(
          color: _panelBackground,
          borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
          border: Border(top: BorderSide(color: _panelBorder)),
        ),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Center(
                child: Container(
                  width: 42,
                  height: 5,
                  decoration: BoxDecoration(
                    color: _panelBorder,
                    borderRadius: BorderRadius.circular(5),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                index == 0 ? 'Primary route' : 'Alternative $index',
                style: const TextStyle(
                  color: _panelText,
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 18),
              _detailRow(
                Icons.trip_origin_rounded,
                'From',
                plan.from.displayName,
              ),
              for (final (stopIndex, stop) in plan.viaStops.indexed) ...[
                const SizedBox(height: 13),
                _detailRow(
                  Icons.stop_circle_rounded,
                  'Stop ${stopIndex + 1}',
                  stop.displayName,
                ),
              ],
              const SizedBox(height: 13),
              _detailRow(Icons.location_on_rounded, 'To', plan.to.displayName),
              const SizedBox(height: 13),
              _detailRow(
                Icons.straighten_rounded,
                'Distance',
                formatRouteDistance(route.distanceMeters),
              ),
              const SizedBox(height: 13),
              _detailRow(
                Icons.schedule_rounded,
                'Estimated duration',
                formatRouteDuration(
                  Duration(seconds: route.durationSeconds.round()),
                ),
              ),
              if (route.roadSummary case final String summary) ...[
                const SizedBox(height: 13),
                _detailRow(Icons.alt_route_rounded, 'Road overview', summary),
              ],
              if (route.weightName case final String weightName) ...[
                const SizedBox(height: 13),
                _detailRow(Icons.tune_rounded, 'OSRM profile', weightName),
              ],
              const SizedBox(height: 13),
              _detailRow(
                Icons.polyline_rounded,
                'Route geometry',
                '${route.geometry.length} coordinates from OSRM',
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

Widget _detailRow(IconData icon, String label, String value) {
  return Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Icon(icon, color: _panelAmethyst, size: 20),
      const SizedBox(width: 12),
      SizedBox(
        width: 115,
        child: Text(label, style: const TextStyle(color: _panelMuted)),
      ),
      Expanded(
        child: Text(
          value,
          style: const TextStyle(color: _panelText, height: 1.35),
        ),
      ),
    ],
  );
}

String formatRouteDistance(double meters) {
  if (meters >= 10000) return '${(meters / 1000).round()} km';
  if (meters >= 1000) return '${(meters / 1000).toStringAsFixed(1)} km';
  return '${meters.round()} m';
}

String formatRouteDuration(Duration duration) {
  final int minutes = duration.inMinutes;
  if (minutes < 1) return 'Less than 1 min';
  final int hours = minutes ~/ 60;
  final int remainingMinutes = minutes % 60;
  if (hours == 0) return '$remainingMinutes min';
  if (remainingMinutes == 0) return '$hours hr';
  return '$hours hr $remainingMinutes min';
}
