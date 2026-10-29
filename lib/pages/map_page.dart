import 'dart:async';
import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart' as legacy;
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart' as latlong;
import 'package:maplibre_gl/maplibre_gl.dart' as maplibre;

import 'track_shipment_page.dart';
import 'truck_registration_page.dart';
import 'warehouse_page.dart';
import 'profile_menu.dart';

const Color background = Color(0xFF17131F);
const Color purple = Color(0xFFB39DDB);
const Color textColor = Color(0xFFF7F5FC);
const Color mutedColor = Color(0xFFB5AEC5);
const Color surface = Color(0xFF211C2B);
const Color borderColor = Color(0xFF383044);

class MapPage extends StatefulWidget {
  const MapPage({super.key});

  @override
  State<MapPage> createState() => _MapPageState();
}

enum _LocationState { checking, ready, serviceDisabled, denied, deniedForever }

class _MapPageState extends State<MapPage> {
  static const String _tileUrl =
      'https://tile.openstreetmap.org/{z}/{x}/{y}.png';
  static const String _mapTilerApiKey = String.fromEnvironment(
    'MAPTILER_API_KEY',
  );
  static const String _mapTilerStyleId = String.fromEnvironment(
    'MAPTILER_STYLE_ID',
    defaultValue: '01a17d04-02f5-792b-8055-66c8af6dad5f',
  );
  static const Duration _mapLibreLoadTimeout = Duration(seconds: 30);

  final legacy.MapController _legacyMapController = legacy.MapController();
  final TextEditingController _searchController = TextEditingController();
  final http.Client _httpClient = http.Client();

  maplibre.MapLibreMapController? _mapLibreController;
  _LocationState _state = _LocationState.checking;
  Position? _position;
  maplibre.LatLng? _searchedLocation;
  String? _searchedName;
  DateTime? _lastSearchTime;
  bool _busy = false;
  bool _isSearching = false;
  bool _mapStyleLoaded = false;
  bool _isMapLibreActive = false;
  Timer? _mapLibreLoadTimer;

  bool get _hasMapTilerConfig =>
      _mapTilerApiKey.trim().isNotEmpty &&
      _mapTilerApiKey.trim() != 'YOUR_MAPTILER_API_KEY' &&
      _mapTilerStyleId.trim().isNotEmpty;

  String get _mapTilerStyleUrl => Uri.https(
    'api.maptiler.com',
    '/maps/${_mapTilerStyleId.trim()}/style.json',
    {'key': _mapTilerApiKey.trim()},
  ).toString();
  bool _isDarkMode = true;

  @override
  void initState() {
    super.initState();
    _resolveLocation();
  }

  @override
  void dispose() {
    _mapLibreLoadTimer?.cancel();
    _legacyMapController.dispose();
    _searchController.dispose();
    _httpClient.close();
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
        permission = await Geolocator.requestPermission();
      }
    } catch (_) {
      _setState(_LocationState.denied);
      return;
    }

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
        _isMapLibreActive = _hasMapTilerConfig;
      });
      if (_isMapLibreActive) _startMapLibreLoadTimer();
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
      // The user can still open Settings manually.
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _openLocationSettings() async {
    setState(() => _busy = true);
    try {
      await Geolocator.openLocationSettings();
    } catch (_) {
      if (mounted) _setState(_LocationState.denied);
      return;
    }
    if (mounted) setState(() => _busy = false);
    await _resolveLocation();
  }

  Future<void> _recenter() async {
    final Position? position = _position;
    if (position == null) return;
    final maplibre.LatLng here = maplibre.LatLng(
      position.latitude,
      position.longitude,
    );
    if (_isMapLibreActive) {
      await _moveMapLibreCamera(here, 16);
    } else {
      _legacyMapController.move(
        latlong.LatLng(position.latitude, position.longitude),
        16,
      );
    }
    if (_searchedLocation != null) {
      setState(() {
        _searchedLocation = null;
        _searchedName = null;
      });
    }
  }

  Future<void> _searchPlace(String rawQuery) async {
    final String query = rawQuery.trim();
    if (query.isEmpty || _isSearching) return;

    setState(() => _isSearching = true);
    try {
      final DateTime now = DateTime.now();
      final DateTime? previousSearch = _lastSearchTime;
      if (previousSearch != null) {
        final Duration elapsed = now.difference(previousSearch);
        if (elapsed < const Duration(seconds: 1)) {
          await Future<void>.delayed(const Duration(seconds: 1) - elapsed);
        }
      }
      if (!mounted) return;
      _lastSearchTime = DateTime.now();

      final Uri uri = Uri.https('nominatim.openstreetmap.org', '/search', {
        'format': 'jsonv2',
        'limit': '1',
        'q': query,
      });
      final http.Response response = await _httpClient
          .get(
            uri,
            headers: const {
              'User-Agent': 'BetterRoutes/1.0.0 (com.betterroutes.app)',
            },
          )
          .timeout(const Duration(seconds: 12));

      if (response.statusCode != 200) {
        _showMessage('Place search is temporarily unavailable.');
        return;
      }

      final Object? decoded = jsonDecode(response.body);
      if (decoded is! List || decoded.isEmpty || decoded.first is! Map) {
        _showMessage('No places found. Try a different search.');
        return;
      }

      final Map<String, dynamic> result = Map<String, dynamic>.from(
        decoded.first as Map,
      );
      final double? latitude = double.tryParse('${result['lat']}');
      final double? longitude = double.tryParse('${result['lon']}');
      if (latitude == null || longitude == null) {
        _showMessage('The place search returned an invalid location.');
        return;
      }

      final maplibre.LatLng place = maplibre.LatLng(latitude, longitude);
      final String name = result['display_name'] as String? ?? query;
      if (!mounted) return;
      setState(() {
        _searchedLocation = place;
        _searchedName = name;
      });
      if (_isMapLibreActive) {
        await _moveMapLibreCamera(place, 15);
        await _refreshMapAnnotations();
      } else {
        _legacyMapController.move(
          latlong.LatLng(place.latitude, place.longitude),
          15,
        );
      }
      if (!mounted) return;
      FocusScope.of(context).unfocus();
    } on TimeoutException {
      _showMessage('Place search took too long. Please try again.');
    } on http.ClientException {
      _showMessage('Could not connect to place search. Check your connection.');
    } on FormatException {
      _showMessage('Place search returned an unreadable response.');
    } finally {
      if (mounted) setState(() => _isSearching = false);
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        backgroundColor: surface,
      ),
    );
  }

  Future<void> _moveMapLibreCamera(maplibre.LatLng target, double zoom) async {
    final maplibre.MapLibreMapController? controller = _mapLibreController;
    if (controller == null || !_mapStyleLoaded) return;
    try {
      await controller.animateCamera(
        maplibre.CameraUpdate.newLatLngZoom(target, zoom),
      );
    } on PlatformException {
      _fallbackToLegacyMap(
        'The custom map could not be controlled. Showing the standard map.',
      );
    }
  }

  void _onMapLibreCreated(maplibre.MapLibreMapController controller) {
    _mapLibreController = controller;
    _startMapLibreLoadTimer();
  }

  void _onMapLibreStyleLoaded() {
    _mapLibreLoadTimer?.cancel();
    _mapStyleLoaded = true;
    unawaited(_refreshMapAnnotations());
    final maplibre.LatLng? searchedLocation = _searchedLocation;
    if (searchedLocation != null) {
      unawaited(_moveMapLibreCamera(searchedLocation, 15));
    }
  }

  void _startMapLibreLoadTimer() {
    _mapLibreLoadTimer?.cancel();
    _mapLibreLoadTimer = Timer(_mapLibreLoadTimeout, () {
      if (_isMapLibreActive && !_mapStyleLoaded) {
        _fallbackToLegacyMap(
          'The custom map did not finish loading. Showing the standard map.',
        );
      }
    });
  }

  void _fallbackToLegacyMap(String message) {
    if (!mounted || !_isMapLibreActive) return;
    _mapLibreLoadTimer?.cancel();
    setState(() {
      _isMapLibreActive = false;
      _mapStyleLoaded = false;
      _mapLibreController = null;
    });
    _showMessage(message);
  }

  Future<void> _refreshMapAnnotations() async {
    if (!_mapStyleLoaded) return;
    final maplibre.MapLibreMapController? controller = _mapLibreController;
    if (controller == null) return;

    try {
      await controller.clearCircles();
      final List<maplibre.CircleOptions> circles = [];
      final Position? position = _position;
      if (position != null) {
        circles.add(
          maplibre.CircleOptions(
            geometry: maplibre.LatLng(position.latitude, position.longitude),
            circleRadius: 9,
            circleColor: '#5CC6A3',
            circleStrokeWidth: 3,
            circleStrokeColor: '#FFFFFF',
          ),
        );
      }
      final maplibre.LatLng? searchedLocation = _searchedLocation;
      if (searchedLocation != null) {
        circles.add(
          maplibre.CircleOptions(
            geometry: searchedLocation,
            circleRadius: 8,
            circleColor: '#B39DDB',
            circleStrokeWidth: 2,
            circleStrokeColor: '#FFFFFF',
          ),
        );
      }
      if (circles.isNotEmpty) {
        await controller.addCircles(circles);
      }
    } on PlatformException {
      _fallbackToLegacyMap(
        'The custom map could not update its markers. Showing the standard map.',
      );
    }
  }

  void _openMenu() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      sheetAnimationStyle: const AnimationStyle(
        duration: Duration(milliseconds: 420),
        reverseDuration: Duration(milliseconds: 320),
      ),
      builder: (sheetContext) => _MapMenuSheet(
        onWarehouse: () => _closeMenuWithPage(
          sheetContext,
          const WarehousePage(),
        ),
        onTruckRegistration: () => _closeMenuWithPage(
          sheetContext,
          const TruckRegistrationPage(),
        ),
        onTrackShipment: () => _closeMenuWithPage(
          sheetContext,
          const TrackShipmentPage(),
        ),
        onAbout: () => _closeMenuWithAction(sheetContext, _showAbout),
      ),
    );
  }

  void _openProfile() {
    Navigator.of(context)
        .push(MaterialPageRoute<void>(builder: (_) => const ProfileMenu()));
  }

  void _closeMenuWithPage(BuildContext sheetContext, Widget page) {
    Navigator.pop(sheetContext);
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => page),
    );
  }

  void _closeMenuWithAction(BuildContext sheetContext, VoidCallback action) {
    Navigator.pop(sheetContext);
    action();
  }

  void _showAbout() {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: surface,
        icon: const Icon(Icons.route_rounded, color: purple, size: 32),
        title: const Text(
          'BetterRoutes',
          style: TextStyle(color: textColor, fontWeight: FontWeight.w700),
        ),
        content: const Text(
          'Explore your surroundings and make every journey better. '
          'Map data © OpenStreetMap contributors.',
          style: TextStyle(color: mutedColor, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Done', style: TextStyle(color: purple)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: background,
      body: SafeArea(child: _buildBody()),
    );
  }

  Widget _buildBody() {
    switch (_state) {
      case _LocationState.checking:
        return const Center(child: CircularProgressIndicator(color: purple));
      case _LocationState.ready:
        return _buildMap();
      case _LocationState.serviceDisabled:
        return _MessagePane(
          icon: Icons.location_off_outlined,
          title: 'Location is turned off',
          body: 'Turn on device location so BetterRoutes can find you on the map.',
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

    return Stack(
      children: [
        Positioned.fill(
          child: _isMapLibreActive
              ? maplibre.MapLibreMap(
                  styleString: _mapTilerStyleUrl,
                  initialCameraPosition: maplibre.CameraPosition(
                    target: maplibre.LatLng(
                      position.latitude,
                      position.longitude,
                    ),
                    zoom: 16,
                  ),
                  onMapCreated: _onMapLibreCreated,
                  onStyleLoadedCallback: _onMapLibreStyleLoaded,
                  attributionButtonPosition:
                      maplibre.AttributionButtonPosition.bottomLeft,
                  logoEnabled: false,
                )
              : _buildLegacyMap(position),
        ),
        Positioned(
          top: 12,
          left: 16,
          right: 16,
          child: _SearchProfileBar(
            controller: _searchController,
            isSearching: _isSearching,
            onSearch: _searchPlace,
            isDarkMode: _isDarkMode,
            onThemeToggle: () {
              setState(() => _isDarkMode = !_isDarkMode);
            },
            onProfileTap: _openProfile,
          ),
        ),
        DraggableScrollableSheet(
          initialChildSize: 0.3,
          minChildSize: 0.12,
          maxChildSize: 0.6,
          snap: true,
          snapSizes: const [0.3, 0.6],
          builder: (context, scrollController) {
            return _ProjectPanel(
              scrollController: scrollController,
              onAction: _showMessage,
            );
          },
        ),
        if (_searchedName case final String name)
          Positioned(
            left: 16,
            right: 88,
            bottom: 24,
            child: _PlaceCard(
              name: name,
              onDismiss: () => setState(() {
                _searchedLocation = null;
                _searchedName = null;
              }),
            ),
          ),
        Positioned(
          right: 18,
          bottom: 24,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _FloatingMapButton(
                icon: Icons.menu_rounded,
                tooltip: 'Open map menu',
                onPressed: _openMenu,
                backgroundColor: const Color(0xFF6F5A9B),
              ),
              const SizedBox(height: 12),
              _FloatingMapButton(
                icon: Icons.my_location_rounded,
                tooltip: 'Center on my location',
                onPressed: _recenter,
                prominent: true,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildLegacyMap(Position position) {
    final latlong.LatLng here = latlong.LatLng(
      position.latitude,
      position.longitude,
    );

    return legacy.FlutterMap(
      mapController: _legacyMapController,
      options: legacy.MapOptions(initialCenter: here, initialZoom: 16),
      children: [
        legacy.TileLayer(
          urlTemplate: _tileUrl,
          userAgentPackageName: 'com.betterroutes.app',
        ),
        legacy.MarkerLayer(
          markers: [
            legacy.Marker(
              point: here,
              width: 54,
              height: 54,
              child: const _LocationMarker(),
            ),
            if (_searchedLocation case final maplibre.LatLng place)
              legacy.Marker(
                point: latlong.LatLng(place.latitude, place.longitude),
                width: 48,
                height: 54,
                child: const Icon(Icons.location_pin, color: purple, size: 48),
              ),
          ],
        ),
        const legacy.RichAttributionWidget(
          attributions: [
            legacy.TextSourceAttribution('© OpenStreetMap contributors'),
          ],
        ),
      ],
    );
  }
}

class _SearchProfileBar extends StatelessWidget {
  const _SearchProfileBar({
    required this.controller,
    required this.isSearching,
    required this.onSearch,
    required this.isDarkMode,
    required this.onThemeToggle,
    required this.onProfileTap,
  });

  final TextEditingController controller;
  final bool isSearching;
  final ValueChanged<String> onSearch;
  final bool isDarkMode;
  final VoidCallback onThemeToggle;
  final VoidCallback onProfileTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 64,
      padding: const EdgeInsets.fromLTRB(17, 7, 8, 7),
      decoration: BoxDecoration(
        color: surface.withValues(alpha: 0.97),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: borderColor.withValues(alpha: 0.9)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.24),
            blurRadius: 24,
            offset: const Offset(0, 9),
          ),
        ],
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.asset(
              'assets/images/BetterRoutes.png',
              width: 40,
              height: 60,
              fit: BoxFit.contain,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: controller,
              textInputAction: TextInputAction.search,
              onSubmitted: onSearch,
              style: const TextStyle(
                color: textColor,
                fontSize: 15,
                fontWeight: FontWeight.w500,
              ),
              cursorColor: purple,
              decoration: const InputDecoration(
                hintText: 'Search here ',
                hintStyle: TextStyle(color: mutedColor, fontSize: 18),
                border: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ),
          if (isSearching)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 9),
              child: SizedBox(
                width: 19,
                height: 19,
                child: CircularProgressIndicator(strokeWidth: 2, color: purple),
              ),
            )
          else
            Container(
              width: 1,
              height: 25,
              color: borderColor,
              margin: const EdgeInsets.symmetric(horizontal: 5),
            ),
          IconButton(
            onPressed: onThemeToggle,
            tooltip: isDarkMode
                ? 'Switch to bright mode'
                : 'Switch to dark mode',
            visualDensity: VisualDensity.compact,
            icon: Icon(
              isDarkMode ? Icons.dark_mode_rounded : Icons.light_mode_rounded,
              color: textColor,
              size: 28,
            ),
          ),
          Semantics(
            button: true,
            label: 'Open profile',
            child: GestureDetector(
              onTap: onProfileTap,
              child: ProfileAvatar(
                user: FirebaseAuth.instance.currentUser,
                radius: 22,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LocationMarker extends StatelessWidget {
  const _LocationMarker();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 15,
        height: 15,
        decoration: BoxDecoration(
          color: const Color(0xFF5CC6A3),
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 2),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF5CC6A3).withValues(alpha: 0.45),
              blurRadius: 14,
              spreadRadius: 3,
            ),
          ],
        ),
      ),
    );
  }
}

class _FloatingMapButton extends StatelessWidget {
  const _FloatingMapButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.prominent = false,
    this.backgroundColor,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;
  final bool prominent;
  final Color? backgroundColor;

  @override
  Widget build(BuildContext context) {
    return Material(
      color:
          backgroundColor ??
          (prominent ? purple : surface.withValues(alpha: 0.97)),
      shape: const CircleBorder(),
      elevation: 7,
      shadowColor: Colors.black.withValues(alpha: 0.3),
      child: IconButton(
        onPressed: onPressed,
        tooltip: tooltip,
        icon: Icon(icon, color: prominent ? background : textColor, size: 23),
        style: IconButton.styleFrom(
          fixedSize: const Size(54, 54),
          shape: const CircleBorder(),
          side: prominent ? null : const BorderSide(color: borderColor),
        ),
      ),
    );
  }
}

class _PlaceCard extends StatelessWidget {
  const _PlaceCard({required this.name, required this.onDismiss});

  final String name;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
      decoration: BoxDecoration(
        color: surface.withValues(alpha: 0.97),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: borderColor),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.22),
            blurRadius: 18,
            offset: const Offset(0, 7),
          ),
        ],
      ),
      child: Row(
        children: [
          const Icon(Icons.place_rounded, color: purple, size: 23),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'SEARCH RESULT',
                  style: TextStyle(
                    color: purple,
                    fontSize: 9,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: textColor,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: onDismiss,
            tooltip: 'Dismiss search result',
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.close_rounded, color: mutedColor, size: 20),
          ),
        ],
      ),
    );
  }
}

class _MapMenuSheet extends StatelessWidget {
  const _MapMenuSheet({
    required this.onWarehouse,
    required this.onTruckRegistration,
    required this.onTrackShipment,
    required this.onAbout,
  });

  final VoidCallback onWarehouse;
  final VoidCallback onTruckRegistration;
  final VoidCallback onTrackShipment;
  final VoidCallback onAbout;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(22, 12, 22, 28),
      decoration: const BoxDecoration(
        color: background,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 38,
                height: 4,
                decoration: BoxDecoration(
                  color: borderColor,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
            const SizedBox(height: 22),
            const Text(
              'Quick actions',
              style: TextStyle(
                color: textColor,
                fontSize: 22,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 5),
            const Text(
              'Manage warehouses, trucks and deliveries',
              style: TextStyle(color: mutedColor, fontSize: 14),
            ),
            const SizedBox(height: 18),
            _MenuAction(
              icon: Icons.warehouse_rounded,
              title: 'Warehouse',
              subtitle: 'Register and manage warehouses',
              onTap: onWarehouse,
            ),
            _MenuAction(
              icon: Icons.local_shipping_rounded,
              title: 'Truck Registration',
              subtitle: 'Register a truck or driver',
              onTap: onTruckRegistration,
            ),
            _MenuAction(
              icon: Icons.inventory_2_rounded,
              title: 'Track Shipment',
              subtitle: 'Check shipment progress',
              onTap: onTrackShipment,
            ),
            _MenuAction(
              icon: Icons.info_outline_rounded,
              title: 'About BetterRoutes',
              subtitle: 'App and map information',
              onTap: onAbout,
            ),
          ],
        ),
      ),
    );
  }
}

class _ProjectPanel extends StatelessWidget {
  const _ProjectPanel({required this.scrollController, required this.onAction});

  final ScrollController scrollController;
  final ValueChanged<String> onAction;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: background.withValues(alpha: 0.98),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        border: Border.all(color: borderColor),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.32),
            blurRadius: 22,
            offset: const Offset(0, -6),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        child: CustomScrollView(
          controller: scrollController,
          physics: const ClampingScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                child: Column(
                  children: [
                    Container(
                      width: 42,
                      height: 5,
                      decoration: BoxDecoration(
                        color: borderColor,
                        borderRadius: BorderRadius.circular(5),
                      ),
                    ),
                    const SizedBox(height: 20),
                    const Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Plan your journey',
                                style: TextStyle(
                                  color: textColor,
                                  fontSize: 22,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              SizedBox(height: 5),
                              Text(
                                'Everything you need for a better route.',
                                style: TextStyle(
                                  color: mutedColor,
                                  fontSize: 14,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Icon(Icons.route_rounded, color: purple, size: 30),
                      ],
                    ),
                    const SizedBox(height: 20),
                  ],
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 120),
              sliver: SliverGrid(
                delegate: SliverChildListDelegate([
                  _ProjectActionCard(
                    icon: Icons.route_rounded,
                    title: 'Plan a route',
                    subtitle: 'Find the best way to go',
                    onTap: () => onAction('Route planning is coming soon.'),
                  ),
                  _ProjectActionCard(
                    icon: Icons.bookmark_border_rounded,
                    title: 'Saved places',
                    subtitle: 'Keep favourite destinations',
                    onTap: () => onAction('Saved places are coming soon.'),
                  ),
                  _ProjectActionCard(
                    icon: Icons.local_shipping_outlined,
                    title: 'Track delivery',
                    subtitle: 'Follow a shipment live',
                    onTap: () => onAction('Delivery tracking is coming soon.'),
                  ),
                  _ProjectActionCard(
                    icon: Icons.history_rounded,
                    title: 'Recent searches',
                    subtitle: 'Return to a previous place',
                    onTap: () => onAction('Recent searches are coming soon.'),
                  ),
                ]),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  childAspectRatio: 1.45,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProjectActionCard extends StatelessWidget {
  const _ProjectActionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: surface,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: borderColor),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: purple, size: 26),
              const Spacer(),
              Text(
                title,
                style: const TextStyle(
                  color: textColor,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: mutedColor, fontSize: 11),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MenuAction extends StatelessWidget {
  const _MenuAction({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: surface,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Icon(icon, color: purple, size: 21),
      ),
      title: Text(
        title,
        style: const TextStyle(
          color: textColor,
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: const TextStyle(color: mutedColor, fontSize: 12),
      ),
      trailing: const Icon(
        Icons.chevron_right_rounded,
        color: mutedColor,
        size: 20,
      ),
      onTap: onTap,
    );
  }
}

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
                  disabledBackgroundColor: purple.withValues(alpha: 0.5),
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
