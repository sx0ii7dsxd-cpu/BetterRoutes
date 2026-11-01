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
import 'package:share_plus/share_plus.dart';

import 'place_search_service.dart';
import 'track_shipment_page.dart';
import 'truck_registration_page.dart';
import 'warehouse_page.dart';
import 'profile_menu.dart';
import 'route_calculation_service.dart';
import 'route_navigation_progress.dart';
import 'route_planning_page.dart';
import 'route_preview_panel.dart';

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
  static const String _mapTilerApiKey = PlaceSearchService.configuredApiKey;
  static const String _mapTilerStyleId = String.fromEnvironment(
    'MAPTILER_STYLE_ID',
    defaultValue: '01a17d04-02f5-792b-8055-66c8af6dad5f',
  );
  static const Duration _mapLibreLoadTimeout = Duration(seconds: 30);

  final legacy.MapController _legacyMapController = legacy.MapController();
  final TextEditingController _searchController = TextEditingController();
  final http.Client _httpClient = http.Client();
  late final PlaceSearchService _placeSearchService = PlaceSearchService(
    apiKey: _mapTilerApiKey,
    client: _httpClient,
  );
  Timer? _suggestionDebounce;
  List<PlaceSearchResult> _placeSuggestions = [];
  bool _isLoadingSuggestions = false;
  int _suggestionGeneration = 0;

  maplibre.MapLibreMapController? _mapLibreController;
  _LocationState _state = _LocationState.checking;
  Position? _position;
  maplibre.LatLng? _searchedLocation;
  String? _searchedName;
  String? _searchedAddress;
  RoutePlanResult? _activeRoutePlan;
  int _selectedRouteIndex = 0;
  bool _isNavigating = false;
  bool _navigationLocationUnavailable = false;
  RouteNavigationProgress? _navigationProgress;
  double _greatestNavigationProgress = 0;
  StreamSubscription<Position>? _navigationPositionSubscription;
  bool _isRenderingMapLibreRoute = false;
  RoutePlanResult? _pendingMapLibreRoute;
  bool _isRefreshingMapAnnotations = false;
  bool _refreshMapAnnotationsAgain = false;
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
    _suggestionDebounce?.cancel();
    unawaited(_navigationPositionSubscription?.cancel());
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
    if (_searchedLocation != null && _activeRoutePlan == null) {
      setState(() {
        _searchedLocation = null;
        _searchedName = null;
        _searchedAddress = null;
      });
    }
  }

  void _onSearchTextChanged(String rawQuery) {
    _suggestionDebounce?.cancel();
    final int generation = ++_suggestionGeneration;

    final String query = rawQuery.trim();

    setState(() {
      _placeSuggestions = [];
      _isLoadingSuggestions = false;
    });

    if (query.length < 2 || _mapTilerApiKey.trim().isEmpty) {
      return;
    }

    _suggestionDebounce = Timer(
      const Duration(milliseconds: 400),
      () => _fetchPlaceSuggestions(query, generation),
    );
  }

  void _hideSuggestions() {
    _suggestionDebounce?.cancel();
    _suggestionDebounce = null;
    _suggestionGeneration++;
    if (!mounted) return;
    setState(() {
      _placeSuggestions = [];
      _isLoadingSuggestions = false;
    });
  }

  Future<void> _fetchPlaceSuggestions(String query, int generation) async {
    if (!mounted || generation != _suggestionGeneration) return;

    setState(() => _isLoadingSuggestions = true);

    try {
      final List<PlaceSearchResult> suggestions = await _placeSearchService
          .search(
            query,
            proximityLatitude: _position?.latitude,
            proximityLongitude: _position?.longitude,
          );
      if (!mounted || generation != _suggestionGeneration) return;

      setState(() {
        _placeSuggestions = suggestions;
        _isLoadingSuggestions = false;
      });
    } catch (error) {
      if (!mounted || generation != _suggestionGeneration) return;
      setState(() {
        _placeSuggestions = [];
        _isLoadingSuggestions = false;
      });
      if (error is TimeoutException) {
        _showMessage('Place suggestions took too long. Please try again.');
      } else if (error is PlaceSearchException) {
        _showMessage(error.message);
      } else if (error is FormatException) {
        _showMessage('Place search returned invalid results.');
      } else if (error is http.ClientException) {
        _showMessage(
          'Could not connect to place search. Check your connection.',
        );
      } else {
        _showMessage('Could not load place suggestions.');
      }
    }
  }

  Future<void> _searchPlace(String rawQuery) async {
    _hideSuggestions();
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
      final String? resultName = result['name'] as String?;
      final String name = resultName?.trim().isNotEmpty == true
          ? resultName!.trim()
          : query;
      final String? displayAddress = result['display_name'] as String?;
      final String? address =
          displayAddress?.trim().isNotEmpty == true &&
              displayAddress!.trim() != name
          ? displayAddress.trim()
          : null;
      if (!mounted) return;
      setState(() {
        _searchedLocation = place;
        _searchedName = name;
        _searchedAddress = address;
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

  void _showPlaceDetails() {
    final String? name = _searchedName;
    final maplibre.LatLng? location = _searchedLocation;
    if (name == null || location == null) return;

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _PlaceDetailsSheet(
        name: name,
        address: _searchedAddress,
        location: location,
      ),
    );
  }

  Future<void> _shareSelectedPlace() async {
    final String? name = _searchedName;
    final maplibre.LatLng? location = _searchedLocation;
    if (name == null || location == null) return;

    final Uri mapUri = Uri.https('www.openstreetmap.org', '/', {
      'mlat': location.latitude.toString(),
      'mlon': location.longitude.toString(),
      'zoom': '16',
    });
    final String address = _searchedAddress == null
        ? ''
        : '\n${_searchedAddress!}';
    try {
      await SharePlus.instance.share(
        ShareParams(text: '$name$address\n$mapUri'),
      );
    } on PlatformException {
      if (mounted) _showMessage('Could not open the share sheet.');
    }
  }

  Future<void> _openRoutePlanner({RoutePlanResult? existingPlan}) async {
    final String? destinationName =
        existingPlan?.to.displayName ?? _searchedName;
    final maplibre.LatLng? destinationLocation = existingPlan == null
        ? _searchedLocation
        : maplibre.LatLng(existingPlan.to.latitude, existingPlan.to.longitude);
    if (destinationName == null || destinationLocation == null) return;
    final PlaceSearchResult? startingLocation =
        existingPlan?.from ??
        (_position == null
            ? null
            : PlaceSearchResult(
                name: 'Current location',
                displayName: 'Current location',
                latitude: _position!.latitude,
                longitude: _position!.longitude,
              ));

    final RoutePlanResult? result = await Navigator.of(context)
        .push<RoutePlanResult>(
          MaterialPageRoute<RoutePlanResult>(
            builder: (_) => RoutePlanningPage(
              startingLocation: startingLocation,
              destination: PlaceSearchResult(
                name: destinationName,
                displayName: destinationName,
                address: existingPlan?.to.address ?? _searchedAddress,
                latitude: destinationLocation.latitude,
                longitude: destinationLocation.longitude,
              ),
              viaStops: existingPlan?.viaStops ?? const [],
              placeSearchService: _placeSearchService,
            ),
          ),
        );
    if (!mounted || result == null) return;
    await _showRoutePlan(result);
  }

  Future<void> _showRoutePlan(RoutePlanResult result) async {
    await _stopNavigation();
    setState(() {
      _activeRoutePlan = result;
      _selectedRouteIndex = 0;
      _navigationProgress = null;
      _greatestNavigationProgress = 0;
      _searchedLocation = maplibre.LatLng(
        result.to.latitude,
        result.to.longitude,
      );
      _searchedName = result.to.displayName;
      _searchedAddress = result.to.address;
    });

    if (_isMapLibreActive) {
      if (_mapStyleLoaded) {
        await _renderMapLibreRoute(result);
      }
    } else {
      _fitLegacyRouteCamera(result.routes.first);
    }

    if (mounted) {
      _showMessage(
        '${result.routes.length} route${result.routes.length == 1 ? '' : 's'} found.',
      );
    }
  }

  Future<void> _renderMapLibreRoute(RoutePlanResult plan) async {
    _pendingMapLibreRoute = plan;
    if (_isRenderingMapLibreRoute) return;
    _isRenderingMapLibreRoute = true;
    try {
      while (mounted && _pendingMapLibreRoute != null) {
        final RoutePlanResult nextPlan = _pendingMapLibreRoute!;
        _pendingMapLibreRoute = null;
        await _renderMapLibreRouteOnce(nextPlan);
      }
    } finally {
      _isRenderingMapLibreRoute = false;
    }
  }

  Future<void> _renderMapLibreRouteOnce(RoutePlanResult plan) async {
    final maplibre.MapLibreMapController? controller = _mapLibreController;
    if (controller == null || !_mapStyleLoaded) return;

    try {
      await controller.clearLines();
      final List<maplibre.LineOptions> lines = [
        for (final (index, route) in plan.routes.indexed)
          if (index != _selectedRouteIndex)
            maplibre.LineOptions(
              geometry: [
                for (final point in route.geometry)
                  maplibre.LatLng(point.latitude, point.longitude),
              ],
              lineColor: '#8A8298',
              lineOpacity: 0.68,
              lineWidth: 4,
              lineJoin: 'round',
            ),
        maplibre.LineOptions(
          geometry: [
            for (final point in plan.routes[_selectedRouteIndex].geometry)
              maplibre.LatLng(point.latitude, point.longitude),
          ],
          lineColor: '#9B82C8',
          lineOpacity: 1,
          lineWidth: 8,
          lineJoin: 'round',
        ),
      ];
      await controller.addLines(lines);
      await _refreshMapAnnotations();
      await controller.animateCamera(
        maplibre.CameraUpdate.newLatLngBounds(
          _mapLibreRouteBounds(plan.routes[_selectedRouteIndex]),
          left: 44,
          top: 105,
          right: 44,
          bottom: 320,
        ),
      );
    } on PlatformException {
      _fallbackToLegacyMap(
        'Could not draw the route on the custom map. Showing the standard map.',
      );
      _fitLegacyRouteCamera(plan.routes[_selectedRouteIndex]);
    } on StateError {
      _fallbackToLegacyMap(
        'The custom map is not ready to draw the route. Showing the standard map.',
      );
      _fitLegacyRouteCamera(plan.routes[_selectedRouteIndex]);
    }
  }

  Future<void> _selectRoute(int index) async {
    final RoutePlanResult? plan = _activeRoutePlan;
    if (plan == null || index < 0 || index >= plan.routes.length) return;
    setState(() {
      _selectedRouteIndex = index;
      _navigationProgress = null;
      _greatestNavigationProgress = 0;
    });
    if (_isMapLibreActive) {
      await _renderMapLibreRoute(plan);
    } else {
      _fitLegacyRouteCamera(plan.routes[index]);
    }
  }

  Future<bool> _ensureNavigationLocationAccess() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        _showNavigationLocationMessage(
          'Turn on location services to start live navigation.',
          actionLabel: 'Location settings',
          onAction: _openLocationSettings,
        );
        return false;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.deniedForever) {
        _showNavigationLocationMessage(
          'Live navigation needs location access. Allow it in app settings.',
          actionLabel: 'App settings',
          onAction: _openAppSettings,
        );
        return false;
      }
      if (permission != LocationPermission.whileInUse &&
          permission != LocationPermission.always) {
        _showNavigationLocationMessage(
          'Live navigation needs location permission. You can still preview '
          'the route.',
          actionLabel: 'Try again',
          onAction: _startNavigation,
        );
        return false;
      }
      return true;
    } on PlatformException {
      _showMessage('Could not check location permission. Please try again.');
      return false;
    } on PermissionDefinitionsNotFoundException {
      _showMessage('Location permission is not configured for this app build.');
      return false;
    } on PermissionRequestInProgressException {
      _showMessage('A location permission request is already in progress.');
      return false;
    }
  }

  Future<void> _startNavigation() async {
    final RoutePlanResult? plan = _activeRoutePlan;
    if (plan == null || !await _ensureNavigationLocationAccess()) return;

    final Position position;
    try {
      position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      ).timeout(const Duration(seconds: 15));
    } on TimeoutException {
      _showMessage(
        'GPS is temporarily unavailable. Try starting navigation again.',
      );
      return;
    } on LocationServiceDisabledException {
      _showNavigationLocationMessage(
        'Turn on location services to start live navigation.',
        actionLabel: 'Location settings',
        onAction: _openLocationSettings,
      );
      return;
    } on PermissionDeniedException {
      _showNavigationLocationMessage(
        'Live navigation needs location permission. You can still preview '
        'the route.',
        actionLabel: 'App settings',
        onAction: _openAppSettings,
      );
      return;
    } on PermissionDefinitionsNotFoundException {
      _showMessage('Location permission is not configured for this app build.');
      return;
    } on PlatformException {
      _showMessage(
        'Could not get your current location. The route is still available '
        'for preview.',
      );
      return;
    }
    if (!mounted) return;

    await _navigationPositionSubscription?.cancel();
    final RouteNavigationProgress initialProgress =
        RouteNavigationProgress.calculate(
          route: plan.routes[_selectedRouteIndex],
          latitude: position.latitude,
          longitude: position.longitude,
        );
    setState(() {
      _position = position;
      _isNavigating = true;
      _navigationLocationUnavailable = false;
      _greatestNavigationProgress = initialProgress.progressMeters;
      _navigationProgress = initialProgress;
    });
    await _refreshMapAnnotations();
    _navigationPositionSubscription = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 10,
      ),
    ).listen(_onNavigationPosition, onError: _onNavigationLocationError);
  }

  void _onNavigationPosition(Position position) {
    final RoutePlanResult? plan = _activeRoutePlan;
    if (!mounted || !_isNavigating || plan == null) return;
    final RouteNavigationProgress progress = RouteNavigationProgress.calculate(
      route: plan.routes[_selectedRouteIndex],
      latitude: position.latitude,
      longitude: position.longitude,
      minimumProgressMeters: _greatestNavigationProgress,
    );
    _greatestNavigationProgress = progress.progressMeters;
    setState(() {
      _position = position;
      _navigationLocationUnavailable = false;
      _navigationProgress = RouteNavigationProgress(
        remainingDistanceMeters: progress.remainingDistanceMeters,
        remainingDuration: progress.remainingDuration,
        distanceFromRouteMeters: progress.distanceFromRouteMeters,
        progressMeters: _greatestNavigationProgress,
      );
    });
    unawaited(_refreshMapAnnotations());
  }

  void _onNavigationLocationError(Object error, StackTrace stackTrace) {
    if (!mounted || !_isNavigating) return;
    setState(() => _navigationLocationUnavailable = true);
  }

  Future<void> _stopNavigation() async {
    await _navigationPositionSubscription?.cancel();
    _navigationPositionSubscription = null;
    if (mounted) {
      setState(() {
        _isNavigating = false;
        _navigationLocationUnavailable = false;
        _navigationProgress = null;
        _greatestNavigationProgress = 0;
      });
    }
  }

  Future<void> _clearRoute() async {
    await _stopNavigation();
    setState(() {
      _activeRoutePlan = null;
      _selectedRouteIndex = 0;
      _searchedLocation = null;
      _searchedName = null;
      _searchedAddress = null;
    });
    final maplibre.MapLibreMapController? controller = _mapLibreController;
    if (_isMapLibreActive && _mapStyleLoaded && controller != null) {
      try {
        await controller.clearLines();
      } on PlatformException {
        _fallbackToLegacyMap(
          'Could not remove the route from the custom map. Showing the standard map.',
        );
      }
      await _refreshMapAnnotations();
    }
  }

  void _showNavigationLocationMessage(
    String message, {
    required String actionLabel,
    required VoidCallback onAction,
  }) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        action: SnackBarAction(label: actionLabel, onPressed: onAction),
        behavior: SnackBarBehavior.floating,
        backgroundColor: surface,
      ),
    );
  }

  maplibre.LatLngBounds _mapLibreRouteBounds(OsrmRoute route) {
    final List<RouteCoordinate> points = route.geometry;
    double west = points
        .map((point) => point.longitude)
        .reduce((a, b) => a < b ? a : b);
    double east = points
        .map((point) => point.longitude)
        .reduce((a, b) => a > b ? a : b);
    double south = points
        .map((point) => point.latitude)
        .reduce((a, b) => a < b ? a : b);
    double north = points
        .map((point) => point.latitude)
        .reduce((a, b) => a > b ? a : b);
    if (west == east) {
      west = (west - 0.001).clamp(-180, 180).toDouble();
      east = (east + 0.001).clamp(-180, 180).toDouble();
    }
    if (south == north) {
      south = (south - 0.001).clamp(-90, 90).toDouble();
      north = (north + 0.001).clamp(-90, 90).toDouble();
    }
    return maplibre.LatLngBounds(
      southwest: maplibre.LatLng(south, west),
      northeast: maplibre.LatLng(north, east),
    );
  }

  void _fitLegacyRouteCamera(OsrmRoute route) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final List<latlong.LatLng> points = [
        for (final point in route.geometry)
          latlong.LatLng(point.latitude, point.longitude),
      ];
      if (points.length < 2) return;
      _legacyMapController.fitCamera(
        legacy.CameraFit.coordinates(
          coordinates: points,
          padding: const EdgeInsets.fromLTRB(44, 105, 44, 320),
        ),
      );
    });
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
    final RoutePlanResult? routePlan = _activeRoutePlan;
    if (routePlan != null) {
      unawaited(_renderMapLibreRoute(routePlan));
    } else {
      unawaited(_refreshMapAnnotations());
      final maplibre.LatLng? searchedLocation = _searchedLocation;
      if (searchedLocation != null) {
        unawaited(_moveMapLibreCamera(searchedLocation, 15));
      }
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
    if (_isRefreshingMapAnnotations) {
      _refreshMapAnnotationsAgain = true;
      return;
    }
    _isRefreshingMapAnnotations = true;
    try {
      do {
        _refreshMapAnnotationsAgain = false;
        await _refreshMapAnnotationsOnce();
      } while (_refreshMapAnnotationsAgain && mounted);
    } finally {
      _isRefreshingMapAnnotations = false;
    }
  }

  Future<void> _refreshMapAnnotationsOnce() async {
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
      final RoutePlanResult? routePlan = _activeRoutePlan;
      if (searchedLocation != null && routePlan == null) {
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
      if (routePlan != null) {
        circles.addAll([
          for (final stop in routePlan.viaStops)
            maplibre.CircleOptions(
              geometry: maplibre.LatLng(stop.latitude, stop.longitude),
              circleRadius: 8,
              circleColor: '#B39DDB',
              circleStrokeWidth: 2,
              circleStrokeColor: '#FFFFFF',
            ),
        ]);
        final bool currentLocationIsStart =
            position != null &&
            (position.latitude - routePlan.from.latitude).abs() < 0.00001 &&
            (position.longitude - routePlan.from.longitude).abs() < 0.00001;
        if (!currentLocationIsStart) {
          circles.add(
            maplibre.CircleOptions(
              geometry: maplibre.LatLng(
                routePlan.from.latitude,
                routePlan.from.longitude,
              ),
              circleRadius: 9,
              circleColor: '#5CC6A3',
              circleStrokeWidth: 3,
              circleStrokeColor: '#FFFFFF',
            ),
          );
        }
        circles.add(
          maplibre.CircleOptions(
            geometry: maplibre.LatLng(
              routePlan.to.latitude,
              routePlan.to.longitude,
            ),
            circleRadius: 9,
            circleColor: '#B39DDB',
            circleStrokeWidth: 3,
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
        onWarehouse: () =>
            _closeMenuWithPage(sheetContext, const WarehousePage()),
        onTruckRegistration: () =>
            _closeMenuWithPage(sheetContext, const TruckRegistrationPage()),
        onTrackShipment: () =>
            _closeMenuWithPage(sheetContext, const TrackShipmentPage()),
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
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));
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
      resizeToAvoidBottomInset: false,
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
            onTextChanged: _onSearchTextChanged,
            isDarkMode: _isDarkMode,
            onThemeToggle: () {
              setState(() => _isDarkMode = !_isDarkMode);
            },
            onProfileTap: _openProfile,
          ),
        ),
        if (_placeSuggestions.isNotEmpty || _isLoadingSuggestions)
          Positioned(
            top: 84,
            left: 16,
            right: 16,
            child: Material(
              color: surface,
              borderRadius: BorderRadius.circular(16),
              child: _isLoadingSuggestions
                  ? const Padding(
                      padding: EdgeInsets.all(16),
                      child: Center(
                        child: CircularProgressIndicator(color: purple),
                      ),
                    )
                  : ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 280),
                      child: ListView.builder(
                        shrinkWrap: true,
                        padding: EdgeInsets.zero,
                        itemCount: _placeSuggestions.length,
                        itemBuilder: (context, index) {
                          final suggestion = _placeSuggestions[index];
                          return ListTile(
                            title: Text(
                              suggestion.displayName,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: textColor),
                            ),
                            onTap: () {
                              final String placeName = suggestion.displayName;
                              _searchController.text = placeName;
                              _hideSuggestions();
                              FocusScope.of(context).unfocus();
                              unawaited(_searchPlace(placeName));
                            },
                          );
                        },
                      ),
                    ),
            ),
          ),
        DraggableScrollableSheet(
          initialChildSize: _activeRoutePlan != null
              ? (_isNavigating ? 0.35 : 0.41)
              : (_searchedName == null ? 0.3 : 0.31),
          minChildSize: _activeRoutePlan != null
              ? 0.28
              : (_searchedName == null ? 0.27 : 0.26),
          maxChildSize: _activeRoutePlan != null
              ? (_isNavigating ? 0.62 : 0.7)
              : (_searchedName == null ? 0.6 : 0.46),
          snap: true,
          snapSizes: _activeRoutePlan != null
              ? (_isNavigating ? const [0.35, 0.62] : const [0.41, 0.7])
              : (_searchedName == null ? const [0.3, 0.6] : const [0.31, 0.46]),
          builder: (context, scrollController) {
            final String? selectedName = _searchedName;
            final maplibre.LatLng? selectedLocation = _searchedLocation;
            final RoutePlanResult? routePlan = _activeRoutePlan;
            if (routePlan != null) {
              return RoutePreviewPanel(
                scrollController: scrollController,
                plan: routePlan,
                selectedRouteIndex: _selectedRouteIndex,
                isNavigating: _isNavigating,
                onSelectRoute: (index) => unawaited(_selectRoute(index)),
                onStartNavigation: () => unawaited(_startNavigation()),
                onExitNavigation: () => unawaited(_stopNavigation()),
                onEditStops: () {
                  final RoutePlanResult currentPlan = routePlan;
                  unawaited(
                    _stopNavigation().then((_) {
                      if (mounted) {
                        return _openRoutePlanner(existingPlan: currentPlan);
                      }
                    }),
                  );
                },
                onClearRoute: () => unawaited(_clearRoute()),
                remainingDistanceMeters:
                    _navigationProgress?.remainingDistanceMeters,
                remainingDuration: _navigationProgress?.remainingDuration,
                isOffRoute: _navigationProgress?.isOffRoute ?? false,
                isLocationUnavailable: _navigationLocationUnavailable,
              );
            }
            if (selectedName != null && selectedLocation != null) {
              return _SelectedPlacePanel(
                scrollController: scrollController,
                name: selectedName,
                address: _searchedAddress,
                onDirections: _openRoutePlanner,
                onShare: _shareSelectedPlace,
                onDetails: _showPlaceDetails,
              );
            }
            return _ProjectPanel(
              scrollController: scrollController,
              onAction: _showMessage,
              onTrackDelivery: () {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const TrackShipmentPage(),
                  ),
                );
              },
            );
          },
        ),
        Positioned(
          right: 18,
          bottom: _activeRoutePlan != null
              ? MediaQuery.sizeOf(context).height *
                        (_isNavigating ? 0.62 : 0.7) +
                    16
              : (_searchedName == null
                    ? 24
                    : MediaQuery.sizeOf(context).height * 0.31 + 16),
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
            if (_activeRoutePlan == null && _searchedLocation != null)
              legacy.Marker(
                point: latlong.LatLng(
                  _searchedLocation!.latitude,
                  _searchedLocation!.longitude,
                ),
                width: 48,
                height: 54,
                child: const Icon(Icons.location_pin, color: purple, size: 48),
              ),
            if (_activeRoutePlan case final RoutePlanResult routePlan) ...[
              for (final stop in routePlan.viaStops)
                legacy.Marker(
                  point: latlong.LatLng(stop.latitude, stop.longitude),
                  width: 34,
                  height: 34,
                  child: const Icon(
                    Icons.stop_circle_rounded,
                    color: purple,
                    size: 26,
                  ),
                ),
              if (!(_position != null &&
                  (_position!.latitude - routePlan.from.latitude).abs() <
                      0.00001 &&
                  (_position!.longitude - routePlan.from.longitude).abs() <
                      0.00001))
                legacy.Marker(
                  point: latlong.LatLng(
                    routePlan.from.latitude,
                    routePlan.from.longitude,
                  ),
                  width: 30,
                  height: 30,
                  child: const Icon(
                    Icons.trip_origin_rounded,
                    color: Color(0xFF5CC6A3),
                    size: 25,
                  ),
                ),
              legacy.Marker(
                point: latlong.LatLng(
                  routePlan.to.latitude,
                  routePlan.to.longitude,
                ),
                width: 42,
                height: 48,
                child: const Icon(Icons.location_pin, color: purple, size: 42),
              ),
            ],
          ],
        ),
        if (_activeRoutePlan case final RoutePlanResult routePlan)
          legacy.PolylineLayer(
            polylines: [
              for (final (index, route) in routePlan.routes.indexed)
                if (index != _selectedRouteIndex)
                  legacy.Polyline(
                    points: [
                      for (final point in route.geometry)
                        latlong.LatLng(point.latitude, point.longitude),
                    ],
                    color: const Color(0xFF8A8298).withValues(alpha: 0.68),
                    strokeWidth: 4,
                  ),
              legacy.Polyline(
                points: [
                  for (final point
                      in routePlan.routes[_selectedRouteIndex].geometry)
                    latlong.LatLng(point.latitude, point.longitude),
                ],
                color: purple,
                strokeWidth: 8,
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
    required this.onTextChanged,
    required this.isDarkMode,
    required this.onThemeToggle,
    required this.onProfileTap,
  });

  final TextEditingController controller;
  final bool isSearching;
  final ValueChanged<String> onSearch;
  final ValueChanged<String> onTextChanged;
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
              onChanged: onTextChanged,
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
      child: Material(
        color: Colors.transparent,
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
                icon: Icons.track_changes_rounded,
                title: 'Track Shipment',
                subtitle: 'Follow a shipment live',
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
      ),
    );
  }
}

class _SelectedPlacePanel extends StatelessWidget {
  const _SelectedPlacePanel({
    required this.scrollController,
    required this.name,
    required this.address,
    required this.onDirections,
    required this.onShare,
    required this.onDetails,
  });

  final ScrollController scrollController;
  final String name;
  final String? address;
  final VoidCallback onDirections;
  final VoidCallback onShare;
  final VoidCallback onDetails;

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
      child: CustomScrollView(
        controller: scrollController,
        physics: const BouncingScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 42,
                      height: 5,
                      decoration: BoxDecoration(
                        color: borderColor,
                        borderRadius: BorderRadius.circular(5),
                      ),
                    ),
                  ),
                  const SizedBox(height: 17),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 46,
                        height: 46,
                        decoration: BoxDecoration(
                          color: surface,
                          borderRadius: BorderRadius.circular(15),
                          border: Border.all(color: borderColor),
                        ),
                        child: const Icon(
                          Icons.location_on_rounded,
                          color: purple,
                          size: 25,
                        ),
                      ),
                      const SizedBox(width: 13),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'SELECTED PLACE',
                              style: TextStyle(
                                color: purple,
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 1.15,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              name,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: textColor,
                                fontSize: 17,
                                height: 1.2,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  if (address != null) ...[
                    const SizedBox(height: 10),
                    Padding(
                      padding: const EdgeInsets.only(left: 59),
                      child: Text(
                        address!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: mutedColor,
                          fontSize: 12,
                          height: 1.35,
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 17),
                  Row(
                    children: [
                      Expanded(
                        child: _SelectedPlaceActionButton(
                          icon: Icons.directions_rounded,
                          label: 'Directions',
                          onPressed: onDirections,
                          primary: true,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _SelectedPlaceActionButton(
                          icon: Icons.ios_share_rounded,
                          label: 'Share',
                          onPressed: onShare,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _SelectedPlaceActionButton(
                          icon: Icons.info_outline_rounded,
                          label: 'Details',
                          onPressed: onDetails,
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
    );
  }
}

class _SelectedPlaceActionButton extends StatelessWidget {
  const _SelectedPlaceActionButton({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.primary = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    final Color foreground = primary ? background : textColor;
    return Material(
      color: primary ? purple : surface,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          height: 68,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: primary ? null : Border.all(color: borderColor),
            boxShadow: primary
                ? [
                    BoxShadow(
                      color: purple.withValues(alpha: 0.18),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ]
                : null,
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: foreground, size: 20),
              const SizedBox(height: 5),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.clip,
                style: TextStyle(
                  color: foreground,
                  fontSize: 12,
                  height: 1,
                  fontWeight: primary ? FontWeight.w700 : FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PlaceDetailsSheet extends StatelessWidget {
  const _PlaceDetailsSheet({
    required this.name,
    required this.address,
    required this.location,
  });

  final String name;
  final String? address;
  final maplibre.LatLng location;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(22, 12, 22, 26),
      decoration: const BoxDecoration(
        color: background,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        border: Border.fromBorderSide(BorderSide(color: borderColor)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 42,
                height: 5,
                decoration: BoxDecoration(
                  color: borderColor,
                  borderRadius: BorderRadius.circular(5),
                ),
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Place details',
              style: TextStyle(
                color: textColor,
                fontSize: 21,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 16),
            _PlaceDetailRow(icon: Icons.place_rounded, value: name),
            if (address != null) ...[
              const SizedBox(height: 13),
              _PlaceDetailRow(
                icon: Icons.location_on_outlined,
                value: address!,
              ),
            ],
            const SizedBox(height: 13),
            _PlaceDetailRow(
              icon: Icons.my_location_rounded,
              value:
                  '${location.latitude.toStringAsFixed(6)}, '
                  '${location.longitude.toStringAsFixed(6)}',
            ),
          ],
        ),
      ),
    );
  }
}

class _PlaceDetailRow extends StatelessWidget {
  const _PlaceDetailRow({required this.icon, required this.value});

  final IconData icon;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: purple, size: 20),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
              color: mutedColor,
              fontSize: 14,
              height: 1.4,
            ),
          ),
        ),
      ],
    );
  }
}

class _ProjectPanel extends StatelessWidget {
  const _ProjectPanel({
    required this.scrollController,
    required this.onAction,
    required this.onTrackDelivery,
  });

  final ScrollController scrollController;
  final ValueChanged<String> onAction;
  final VoidCallback onTrackDelivery;

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
                    onTap: onTrackDelivery,
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
