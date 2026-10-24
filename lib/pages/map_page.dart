import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

// Palette shared by this page and the rest of BetterRoutes, so the map and
// its permission screens stay visually consistent with HomePage and AuthScreen.
const Color background = Color(0xFF17131F);
const Color purple = Color(0xFFB39DDB);
const Color textColor = Color(0xFFF7F5FC);
const Color mutedColor = Color(0xFFB5AEC5);
const Color surface = Color(0xFF211C2B);
const Color borderColor = Color(0xFF383044);

/// Home of the OpenStreetMap experience.
///
/// Reached after authentication (destination still to be agreed). Focuses on
/// the two things that must work before any route feature can be built:
/// resolving the device position, and handling every permission outcome the
/// Android system dialog can produce.
class MapPage extends StatefulWidget {
  const MapPage({super.key});

  @override
  State<MapPage> createState() => _MapPageState();
}

enum _LocationState {
  checking,
  ready,
  serviceDisabled,
  denied,
  deniedForever,
}

class _MapPageState extends State<MapPage> {
  /// Official OpenStreetMap tiles: free, no API key, no account.
  ///
  /// OSMF's tile usage policy (operations.osmfoundation.org/policies/tiles)
  /// requires the exact URL below, an identifying User-Agent (passed via
  /// [TileLayer.userAgentPackageName]) and visible attribution
  /// (RichAttributionWidget below). Do not prefetch or bulk-download tiles.
  static const String _tileUrl =
      'https://tile.openstreetmap.org/{z}/{x}/{y}.png';

  final MapController _mapController = MapController();

  _LocationState _state = _LocationState.checking;
  Position? _position;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _resolveLocation();
  }

  @override
  void dispose() {
    _mapController.dispose();
    super.dispose();
  }

  Future<void> _resolveLocation() async {
    if (!mounted) return;
    setState(() {
      _state = _LocationState.checking;
      _busy = false;
    });

    final bool serviceEnabled;
    try {
      serviceEnabled = await Geolocator.isLocationServiceEnabled();
    } catch (_) {
      _setState(_LocationState.denied);
      return;
    }

    if (!serviceEnabled) {
      _setState(_LocationState.serviceDisabled);
      return;
    }

    LocationPermission permission;
    try {
      permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        // Triggers the system dialog: Precise / Approximate, then
        // "While using the app" / "Only this time" / "Don't allow".
        permission = await Geolocator.requestPermission();
      }
    } catch (_) {
      _setState(_LocationState.denied);
      return;
    }

    // UnableToDetermine is a real enum value, so test the outcomes we can
    // act on rather than switching exhaustively.
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.unableToDetermine) {
      _setState(_LocationState.denied);
      return;
    }

    if (permission == LocationPermission.deniedForever) {
      _setState(_LocationState.deniedForever);
      return;
    }

    if (permission != LocationPermission.whileInUse &&
        permission != LocationPermission.always) {
      _setState(_LocationState.denied);
      return;
    }

    try {
      final Position position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );
      if (!mounted) return;
      setState(() {
        _position = position;
        _state = _LocationState.ready;
      });
    } catch (_) {
      _setState(_LocationState.denied);
    }
  }

  void _setState(_LocationState next) {
    if (!mounted) return;
    setState(() => _state = next);
  }

  Future<void> _openAppSettings() async {
    setState(() => _busy = true);
    try {
      await Geolocator.openAppSettings();
    } catch (_) {
      // Nothing to do; the user can open Settings manually.
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _openLocationSettings() async {
    setState(() => _busy = true);
    try {
      await Geolocator.openLocationSettings();
    } catch (_) {
      if (mounted) {
        _setState(_LocationState.denied);
      }
      return;
    }
    if (mounted) setState(() => _busy = false);
    await _resolveLocation();
  }

  Future<void> _recenter() async {
    final Position? position = _position;
    if (position == null) return;
    _mapController.move(
      LatLng(position.latitude, position.longitude),
      16,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: background,
      body: SafeArea(child: _buildBody()),
      floatingActionButton: _state == _LocationState.ready
          ? FloatingActionButton(
              backgroundColor: purple,
              foregroundColor: background,
              onPressed: _recenter,
              child: const Icon(Icons.my_location),
            )
          : null,
    );
  }

  Widget _buildBody() {
    switch (_state) {
      case _LocationState.checking:
        return const Center(
          child: CircularProgressIndicator(color: purple),
        );

      case _LocationState.ready:
        return _buildMap();

      case _LocationState.serviceDisabled:
        return _MessagePane(
          icon: Icons.location_off_outlined,
          title: 'Location is turned off',
          body:
              'Turn on device location so BetterRoutes can find you on the map.',
          buttonLabel: 'Open location settings',
          busy: _busy,
          onPressed: _openLocationSettings,
        );

      case _LocationState.denied:
        return _MessagePane(
          icon: Icons.location_searching,
          title: 'Allow location access',
          body:
              'BetterRoutes uses your location to show where you are and to '
              'plan better routes around you.',
          buttonLabel: 'Try again',
          busy: _busy,
          onPressed: _resolveLocation,
        );

      case _LocationState.deniedForever:
        return _MessagePane(
          icon: Icons.location_disabled_outlined,
          title: 'Location permission blocked',
          body:
              'Location access was denied permanently. Enable it in Settings '
              'to use the map.',
          buttonLabel: 'Open app settings',
          busy: _busy,
          onPressed: _openAppSettings,
        );
    }
  }

  Widget _buildMap() {
    final Position? position = _position;
    if (position == null) {
      return const Center(child: CircularProgressIndicator(color: purple));
    }

    final LatLng here = LatLng(position.latitude, position.longitude);

    return Stack(
      children: [
        FlutterMap(
          mapController: _mapController,
          options: MapOptions(initialCenter: here, initialZoom: 16),
          children: [
            TileLayer(
              urlTemplate: _tileUrl,
              // OSM blocks generic library User-Agents; this package name is
              // the Android applicationId, so requests identify the app.
              userAgentPackageName: 'com.betterroutes.app',
            ),
            MarkerLayer(
              markers: [
                Marker(
                  point: here,
                  width: 48,
                  height: 48,
                  child: const Icon(
                    Icons.location_pin,
                    color: purple,
                    size: 48,
                  ),
                ),
              ],
            ),
            const RichAttributionWidget(
              attributions: [
                TextSourceAttribution('OpenStreetMap contributors'),
              ],
            ),
          ],
        ),
        Positioned(
          top: 12,
          left: 16,
          right: 16,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
            decoration: BoxDecoration(
              color: surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: borderColor),
            ),
            child: const Row(
              children: [
                Icon(Icons.map_outlined, color: purple, size: 20),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'BetterRoutes',
                    style: TextStyle(
                      color: textColor,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Shared presentation for every non-map outcome, so each state keeps the same
/// dark branding and only the icon, copy and action differ.
class _MessagePane extends StatelessWidget {
  const _MessagePane({
    required this.icon,
    required this.title,
    required this.body,
    required this.buttonLabel,
    required this.busy,
    required this.onPressed,
  });

  final IconData icon;
  final String title;
  final String body;
  final String buttonLabel;
  final bool busy;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: const BoxDecoration(
                color: surface,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: purple, size: 34),
            ),
            const SizedBox(height: 24),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: textColor,
                fontSize: 23,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              body,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: mutedColor,
                fontSize: 15,
                height: 1.6,
              ),
            ),
            const SizedBox(height: 30),
            SizedBox(
              width: double.infinity,
              height: 54,
              child: ElevatedButton(
                onPressed: busy ? null : onPressed,
                style: ElevatedButton.styleFrom(
                  backgroundColor: purple,
                  foregroundColor: background,
                  disabledBackgroundColor: purple.withValues(
                    alpha: 0.5,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: busy
                    ? const SizedBox(
                        width: 23,
                        height: 23,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(
                        buttonLabel,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
