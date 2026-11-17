import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import 'map_page.dart';
import 'place_search_service.dart';

class WarehouseLocationSelection {
  const WarehouseLocationSelection({
    required this.displayName,
    required this.latitude,
    required this.longitude,
  });

  final String displayName;
  final double latitude;
  final double longitude;
}

class WarehouseLocationPickerPage extends StatefulWidget {
  const WarehouseLocationPickerPage({
    super.key,
    this.initialDisplayName,
    this.initialLatitude,
    this.initialLongitude,
  });

  final String? initialDisplayName;
  final double? initialLatitude;
  final double? initialLongitude;

  @override
  State<WarehouseLocationPickerPage> createState() =>
      _WarehouseLocationPickerPageState();
}

class _WarehouseLocationPickerPageState
    extends State<WarehouseLocationPickerPage> {
  static const LatLng _defaultCenter = LatLng(20.5937, 78.9629);
  static const String _tileUrl =
      'https://tile.openstreetmap.org/{z}/{x}/{y}.png';

  late final PlaceSearchService _placeSearchService = PlaceSearchService(
    apiKey: PlaceSearchService.configuredApiKey,
  );
  final MapController _mapController = MapController();
  Timer? _reverseGeocodeTimer;
  LatLng? _selectedPoint;
  LatLng? _pendingMapPoint;
  String? _displayName;
  bool _isLookingUpName = false;
  String? _message;
  bool _mapReady = false;

  @override
  void initState() {
    super.initState();
    if (widget.initialLatitude != null && widget.initialLongitude != null) {
      _selectedPoint = LatLng(
        widget.initialLatitude!,
        widget.initialLongitude!,
      );
      _displayName = widget.initialDisplayName;
    } else {
      _useCurrentLocation();
    }
  }

  @override
  void dispose() {
    _reverseGeocodeTimer?.cancel();
    _placeSearchService.dispose();
    super.dispose();
  }

  Future<void> _useCurrentLocation() async {
    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );
      if (!mounted || _selectedPoint != null) return;
      final point = LatLng(position.latitude, position.longitude);
      _selectPoint(point);
      _moveMapTo(point);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _message = 'Tap the map to select the warehouse location.';
      });
    }
  }

  void _selectPoint(LatLng point) {
    _reverseGeocodeTimer?.cancel();
    setState(() {
      _selectedPoint = point;
      _displayName = null;
      _message = null;
      _isLookingUpName = true;
    });

    _reverseGeocodeTimer = Timer(
      const Duration(milliseconds: 450),
      () => _lookupLocationName(point),
    );
  }

  void _moveMapTo(LatLng point) {
    if (!_mapReady) {
      _pendingMapPoint = point;
      return;
    }
    _mapController.move(point, 16);
  }

  void _onMapReady() {
    _mapReady = true;
    final pendingPoint = _pendingMapPoint;
    if (pendingPoint == null) return;
    _pendingMapPoint = null;
    _mapController.move(pendingPoint, 16);
  }

  Future<void> _lookupLocationName(LatLng point) async {
    try {
      final result = await _placeSearchService.reverseGeocode(
        latitude: point.latitude,
        longitude: point.longitude,
      );
      if (!mounted) return;
      setState(() {
        _displayName = result?.displayName;
        _isLookingUpName = false;
        _message = result == null
            ? 'Location selected. The coordinates will still be saved.'
            : null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isLookingUpName = false;
        _message =
            'Location selected. The coordinates will still be saved.';
      });
    }
  }

  void _confirm() {
    final point = _selectedPoint;
    if (point == null) {
      setState(() => _message = 'Tap the map to select a location first.');
      return;
    }

    Navigator.of(context).pop(
      WarehouseLocationSelection(
        displayName: _displayName ?? 'Selected warehouse location',
        latitude: point.latitude,
        longitude: point.longitude,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final point = _selectedPoint;
    return Scaffold(
      backgroundColor: background,
      appBar: AppBar(
        backgroundColor: background,
        foregroundColor: textColor,
        elevation: 0,
        title: const Text(
          'Select Warehouse Location',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        actions: [
          TextButton(
            onPressed: _confirm,
            child: const Text(
              'Use location',
              style: TextStyle(color: purple, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: point ?? _defaultCenter,
              initialZoom: point == null ? 5 : 16,
              onMapReady: _onMapReady,
              onPositionChanged: (position, hasGesture) {
                if (hasGesture) {
                  _selectPoint(position.center);
                }
              },
            ),
            children: [
              TileLayer(
                urlTemplate: _tileUrl,
                userAgentPackageName: 'com.betterroutes.app',
              ),
            ],
          ),
          Positioned.fill(
            child: IgnorePointer(
              child: Center(
                child: Transform.translate(
                  offset: const Offset(0, -26),
                  child: const Icon(
                    Icons.location_pin,
                    color: Color(0xFFE58B9B),
                    size: 52,
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            top: 16,
            left: 16,
            right: 16,
            child: _LocationSummary(
              displayName: _displayName,
              point: point,
              isLookingUpName: _isLookingUpName,
              message: _message,
            ),
          ),
          Positioned(
            bottom: 20,
            left: 20,
            right: 20,
            child: ElevatedButton.icon(
              onPressed: _confirm,
              icon: const Icon(Icons.check_rounded),
              label: const Text('Confirm warehouse location'),
              style: ElevatedButton.styleFrom(
                backgroundColor: purple,
                foregroundColor: background,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LocationSummary extends StatelessWidget {
  const _LocationSummary({
    required this.displayName,
    required this.point,
    required this.isLookingUpName,
    required this.message,
  });

  final String? displayName;
  final LatLng? point;
  final bool isLookingUpName;
  final String? message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: surface.withValues(alpha: 0.96),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor),
        boxShadow: const [
          BoxShadow(
            color: Colors.black26,
            blurRadius: 12,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: point == null
          ? const Text(
              'Tap the map to choose the warehouse location.',
              style: TextStyle(color: textColor),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isLookingUpName
                      ? 'Finding approximate location...'
                      : displayName ?? 'Selected warehouse location',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: textColor,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  '${point!.latitude.toStringAsFixed(6)}, '
                  '${point!.longitude.toStringAsFixed(6)}',
                  style: const TextStyle(color: purple, fontSize: 13),
                ),
                if (message != null) ...[
                  const SizedBox(height: 5),
                  Text(
                    message!,
                    style: const TextStyle(color: mutedColor, fontSize: 12),
                  ),
                ],
              ],
            ),
    );
  }
}
