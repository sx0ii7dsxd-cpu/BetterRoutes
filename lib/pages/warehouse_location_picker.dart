import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../theme/app_colors.dart';

typedef CurrentLocationProvider = Future<LatLng> Function();

class WarehouseLocationPicker extends StatefulWidget {
  const WarehouseLocationPicker({
    super.key,
    this.initialLatitude,
    this.initialLongitude,
    this.currentLocationProvider,
    this.tileProvider,
  }) : assert(
         (initialLatitude == null) == (initialLongitude == null),
         'Latitude and longitude must be supplied together.',
       );

  final double? initialLatitude;
  final double? initialLongitude;
  final CurrentLocationProvider? currentLocationProvider;
  final TileProvider? tileProvider;

  @override
  State<WarehouseLocationPicker> createState() =>
      _WarehouseLocationPickerState();
}

class _WarehouseLocationPickerState extends State<WarehouseLocationPicker> {
  static const LatLng _defaultCenter = LatLng(20.5937, 78.9629);

  late final MapController _mapController = MapController();
  late LatLng _selectedLocation = widget.initialLatitude == null
      ? _defaultCenter
      : LatLng(widget.initialLatitude!, widget.initialLongitude!);
  late bool _hasConfirmedSelection = widget.initialLatitude != null;
  bool _isGettingCurrentLocation = false;
  bool _mapTilesFailed = false;
  String? _locationError;

  @override
  void dispose() {
    _mapController.dispose();
    super.dispose();
  }

  Future<void> _useCurrentLocation() async {
    setState(() => _isGettingCurrentLocation = true);
    try {
      final CurrentLocationProvider provider =
          widget.currentLocationProvider ?? _getCurrentLocation;
      final LatLng location = await provider();
      if (!mounted) return;
      _setLocation(location);
      setState(() => _locationError = null);
      _mapController.move(location, _mapController.camera.zoom);
    } on Exception catch (error) {
      if (!mounted) return;
      setState(
        () => _locationError = '$error Manual map selection remains available.',
      );
    } finally {
      if (mounted) setState(() => _isGettingCurrentLocation = false);
    }
  }

  Future<LatLng> _getCurrentLocation() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw const WarehouseLocationException('Location services are disabled.');
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission != LocationPermission.whileInUse &&
        permission != LocationPermission.always) {
      throw const WarehouseLocationException('Location permission was denied.');
    }

    final Position position = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
    );
    return LatLng(position.latitude, position.longitude);
  }

  void _setLocation(LatLng location) {
    setState(() {
      _selectedLocation = location;
      _hasConfirmedSelection = true;
    });
  }

  void _confirmLocation() {
    Navigator.of(context).pop(_selectedLocation);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: background,
      appBar: AppBar(
        backgroundColor: background,
        foregroundColor: textColor,
        title: const Text(
          'Pin warehouse location',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            Expanded(
              child: Stack(
                children: [
                  FlutterMap(
                    mapController: _mapController,
                    options: MapOptions(
                      initialCenter: _selectedLocation,
                      initialZoom: 14,
                      onTap: (_, LatLng point) {
                        _mapController.move(point, _mapController.camera.zoom);
                        _setLocation(point);
                      },
                      onPositionChanged: (MapCamera camera, bool hasGesture) {
                        if (hasGesture) _setLocation(camera.center);
                      },
                    ),
                    children: [
                      TileLayer(
                        urlTemplate:
                            'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                        userAgentPackageName: 'com.betterroutes.app',
                        tileProvider:
                            widget.tileProvider ??
                            NetworkTileProvider(
                              cachingProvider: DisabledMapCachingProvider(),
                            ),
                        errorTileCallback: (_, _, _) {
                          if (mounted && !_mapTilesFailed) {
                            setState(() => _mapTilesFailed = true);
                          }
                        },
                      ),
                      const RichAttributionWidget(
                        attributions: [
                          TextSourceAttribution('OpenStreetMap contributors'),
                        ],
                      ),
                    ],
                  ),
                  const IgnorePointer(
                    child: Center(
                      child: Padding(
                        padding: EdgeInsets.only(bottom: 30),
                        child: Icon(
                          Icons.location_pin,
                          color: Color(0xFFB3435C),
                          size: 48,
                          shadows: [Shadow(color: Colors.white, blurRadius: 3)],
                        ),
                      ),
                    ),
                  ),
                  if (_mapTilesFailed)
                    Positioned(
                      left: 16,
                      right: 16,
                      top: 16,
                      child: Material(
                        color: surface,
                        borderRadius: BorderRadius.circular(12),
                        child: const Padding(
                          padding: EdgeInsets.all(12),
                          child: Text(
                            'Map tiles could not load. You can still move or '
                            'tap the map to select coordinates.',
                            style: TextStyle(color: textColor),
                          ),
                        ),
                      ),
                    ),
                  Positioned(
                    right: 16,
                    bottom: 20,
                    child: FloatingActionButton(
                      heroTag: 'warehouse-current-location',
                      backgroundColor: surface,
                      foregroundColor: textColor,
                      tooltip: 'Use current location',
                      onPressed: _isGettingCurrentLocation
                          ? null
                          : _useCurrentLocation,
                      child: _isGettingCurrentLocation
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.my_location_rounded),
                    ),
                  ),
                ],
              ),
            ),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
              decoration: const BoxDecoration(
                color: background,
                border: Border(top: BorderSide(color: borderColor)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_locationError case final String error) ...[
                    Text(
                      error,
                      style: const TextStyle(
                        color: Color(0xFFE58B9B),
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                  Text(
                    _hasConfirmedSelection
                        ? 'Selected location'
                        : 'Move the map or tap it to place the pin',
                    style: const TextStyle(
                      color: mutedColor,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${_selectedLocation.latitude.toStringAsFixed(6)}, '
                    '${_selectedLocation.longitude.toStringAsFixed(6)}',
                    style: const TextStyle(
                      color: textColor,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    height: 52,
                    child: ElevatedButton.icon(
                      onPressed: _hasConfirmedSelection
                          ? _confirmLocation
                          : null,
                      icon: const Icon(Icons.check_rounded),
                      label: const Text('Confirm location'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: purple,
                        foregroundColor: background,
                        disabledBackgroundColor: surface,
                        disabledForegroundColor: mutedColor,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class WarehouseLocationException implements Exception {
  const WarehouseLocationException(this.message);

  final String message;

  @override
  String toString() => message;
}
