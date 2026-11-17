import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../models/shipment_model.dart';
import '../services/firestore_service.dart';
import 'map_page.dart';

class TrackShipmentPage extends StatefulWidget {
  const TrackShipmentPage({super.key});

  @override
  State<TrackShipmentPage> createState() => _TrackShipmentPageState();
}

class _TrackShipmentPageState extends State<TrackShipmentPage> {
  final FirestoreService _firestoreService = FirestoreService();
  final TextEditingController _shipmentController = TextEditingController();
  StreamSubscription<ShipmentModel?>? _shipmentSubscription;
  StreamSubscription<List<ShipmentEventModel>>? _eventsSubscription;
  ShipmentModel? _shipment;
  List<ShipmentEventModel> _events = const [];
  String? _errorMessage;
  bool _isSearching = false;
  bool _hasSearched = false;
  bool _isLoadingEvents = false;

  @override
  void dispose() {
    unawaited(_shipmentSubscription?.cancel());
    unawaited(_eventsSubscription?.cancel());
    _shipmentController.dispose();
    super.dispose();
  }

  Future<void> _trackShipment() async {
    final trackingCode = _shipmentController.text.trim().toUpperCase();
    if (trackingCode.isEmpty) {
      setState(() {
        _errorMessage = 'Enter a shipment ID to continue.';
        _hasSearched = false;
      });
      return;
    }

    if (!RegExp(r'^SHP-[A-Z0-9]{6,12}$').hasMatch(trackingCode)) {
      setState(() {
        _errorMessage = 'Use a shipment ID in the format SHP-ABC123.';
        _hasSearched = false;
      });
      return;
    }

    FocusScope.of(context).unfocus();
    await _cancelShipmentSubscriptions();
    if (!mounted) return;
    setState(() {
      _isSearching = true;
      _hasSearched = true;
      _shipment = null;
      _events = const [];
      _errorMessage = null;
    });

    try {
      final shipment = await _firestoreService.findShipmentByTrackingCode(
        trackingCode,
      );
      if (!mounted) return;
      if (shipment == null) {
        setState(() => _isSearching = false);
        return;
      }

      setState(() {
        _shipment = shipment;
        _isSearching = false;
        _isLoadingEvents = true;
      });
      _subscribeToShipment(shipment.shipmentId);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isSearching = false;
        _errorMessage = _friendlyError(error);
      });
    }
  }

  void _subscribeToShipment(String shipmentId) {
    _shipmentSubscription = _firestoreService
        .watchShipment(shipmentId)
        .listen(
          (shipment) {
            if (!mounted) return;
            if (shipment == null) {
              setState(() {
                _shipment = null;
                _errorMessage = 'This shipment is no longer available.';
              });
              return;
            }
            setState(() => _shipment = shipment);
          },
          onError: (Object error) {
            if (!mounted) return;
            setState(() => _errorMessage = _friendlyError(error));
          },
        );
    _eventsSubscription = _firestoreService
        .watchShipmentEvents(shipmentId)
        .listen(
          (events) {
            if (!mounted) return;
            setState(() {
              _events = events;
              _isLoadingEvents = false;
            });
          },
          onError: (Object error) {
            if (!mounted) return;
            setState(() {
              _isLoadingEvents = false;
              _errorMessage = _friendlyError(error);
            });
          },
        );
  }

  Future<void> _cancelShipmentSubscriptions() async {
    await _shipmentSubscription?.cancel();
    await _eventsSubscription?.cancel();
    _shipmentSubscription = null;
    _eventsSubscription = null;
  }

  String _friendlyError(Object error) {
    if (error is StateError) return error.message.toString();
    if (error is FirebaseException && error.code == 'permission-denied') {
      return 'You are not authorized to view this shipment.';
    }
    return 'Could not load this shipment. Check your connection and try again.';
  }

  @override
  Widget build(BuildContext context) {
    final shipment = _shipment;
    return Scaffold(
      backgroundColor: background,
      appBar: AppBar(
        backgroundColor: background,
        foregroundColor: textColor,
        elevation: 0,
        leading: IconButton(
          onPressed: () => Navigator.of(context).pop(),
          tooltip: 'Back to map',
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        title: const Text(
          'Track Shipment',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      body: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const _SectionHeading(
                    eyebrow: 'SHIPMENT LOOKUP',
                    title: 'Track your delivery',
                    subtitle: 'Enter a shipment ID to check its latest status.',
                    icon: Icons.inventory_2_rounded,
                  ),
                  const SizedBox(height: 24),
                  _buildLookupField(),
                  const SizedBox(height: 16),
                  SizedBox(
                    height: 54,
                    child: ElevatedButton.icon(
                      onPressed: _isSearching ? null : _trackShipment,
                      icon: _isSearching
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: background,
                              ),
                            )
                          : const Icon(Icons.search_rounded),
                      label: Text(
                        _isSearching
                            ? 'Looking up shipment...'
                            : 'Track Shipment',
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: purple,
                        foregroundColor: background,
                        disabledBackgroundColor: purple.withValues(alpha: 0.5),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  if (_errorMessage != null)
                    _MessageCard(
                      icon: Icons.error_outline_rounded,
                      message: _errorMessage!,
                      color: const Color(0xFFE58B9B),
                      actionLabel: 'Retry',
                      onAction: _trackShipment,
                    )
                  else if (_isSearching)
                    const Center(
                      child: CircularProgressIndicator(color: purple),
                    )
                  else if (!_hasSearched)
                    const _EmptyTrackingState()
                  else if (shipment == null)
                    const _MessageCard(
                      icon: Icons.search_off_rounded,
                      message: 'No accessible shipment was found for that ID.',
                      color: mutedColor,
                    )
                  else
                    _buildShipmentDetails(shipment),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLookupField() {
    return TextField(
      controller: _shipmentController,
      textCapitalization: TextCapitalization.characters,
      onChanged: (_) {
        if (_errorMessage != null) {
          setState(() => _errorMessage = null);
        }
      },
      style: const TextStyle(color: textColor),
      cursorColor: purple,
      decoration: InputDecoration(
        labelText: 'Shipment ID',
        hintText: 'e.g. SHP-ABC123',
        labelStyle: const TextStyle(color: mutedColor),
        hintStyle: const TextStyle(color: mutedColor, fontSize: 13),
        prefixIcon: const Icon(Icons.receipt_long_outlined, color: purple),
        filled: true,
        fillColor: surface,
        border: _inputBorder(),
        enabledBorder: _inputBorder(),
        focusedBorder: _inputBorder(color: purple),
      ),
      onSubmitted: (_) => _trackShipment(),
    );
  }

  Widget _buildShipmentDetails(ShipmentModel shipment) {
    final status = shipment.status.toLowerCase();
    final hasMapCoordinates =
        shipment.origin?.hasCoordinates == true ||
        shipment.destination?.hasCoordinates == true ||
        shipment.currentLocation != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _ShipmentSummaryCard(shipment: shipment, status: status),
        const SizedBox(height: 14),
        _buildPlaceCard(
          title: 'Origin',
          icon: Icons.trip_origin_rounded,
          place: shipment.origin,
        ),
        const SizedBox(height: 12),
        _buildPlaceCard(
          title: 'Destination',
          icon: Icons.location_on_outlined,
          place: shipment.destination,
        ),
        const SizedBox(height: 12),
        _buildAssociationCard(shipment),
        const SizedBox(height: 12),
        if (hasMapCoordinates)
          OutlinedButton.icon(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => MapPage(shipment: shipment),
              ),
            ),
            icon: const Icon(Icons.map_outlined),
            label: const Text('View shipment locations on map'),
            style: OutlinedButton.styleFrom(
              foregroundColor: textColor,
              side: const BorderSide(color: borderColor),
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          )
        else
          const _MessageCard(
            icon: Icons.location_off_outlined,
            message:
                'Map tracking is unavailable because no coordinates '
                'are stored for this shipment.',
            color: mutedColor,
          ),
        const SizedBox(height: 20),
        _buildTimeline(),
      ],
    );
  }

  Widget _buildPlaceCard({
    required String title,
    required IconData icon,
    required ShipmentPlace? place,
  }) {
    return _InfoCard(
      title: title,
      icon: icon,
      child: place == null
          ? const Text('Unavailable', style: TextStyle(color: mutedColor))
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  place.name ?? 'Unnamed location',
                  style: const TextStyle(
                    color: textColor,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (place.address != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    place.address!,
                    style: const TextStyle(color: mutedColor, height: 1.35),
                  ),
                ],
                if (!place.hasCoordinates) ...[
                  const SizedBox(height: 5),
                  const Text(
                    'Coordinates unavailable',
                    style: TextStyle(color: mutedColor, fontSize: 12),
                  ),
                ],
              ],
            ),
    );
  }

  Widget _buildAssociationCard(ShipmentModel shipment) {
    return _InfoCard(
      title: 'Shipment details',
      icon: Icons.local_shipping_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _DetailRow(
            label: 'Warehouse',
            value: shipment.warehouseCode ?? 'Unavailable',
          ),
          _DetailRow(label: 'Truck', value: shipment.truckId ?? 'Unavailable'),
          _DetailRow(
            label: 'Driver',
            value: shipment.driverName ?? 'Unavailable',
          ),
          _DetailRow(
            label: 'Driver contact',
            value: shipment.driverContact ?? 'Unavailable',
          ),
          _DetailRow(
            label: 'Estimated delivery',
            value: shipment.estimatedDelivery == null
                ? 'Unavailable'
                : _formatDateTime(shipment.estimatedDelivery!),
          ),
          _DetailRow(
            label: 'Last updated',
            value: shipment.updatedAt == null
                ? 'Unavailable'
                : _formatDateTime(shipment.updatedAt!),
            isLast: true,
          ),
        ],
      ),
    );
  }

  Widget _buildTimeline() {
    return _InfoCard(
      title: 'Shipment timeline',
      icon: Icons.timeline_rounded,
      child: _isLoadingEvents
          ? const Center(child: CircularProgressIndicator(color: purple))
          : _events.isEmpty
          ? const Text(
              'No shipment events are available yet.',
              style: TextStyle(color: mutedColor),
            )
          : Column(
              children: [
                for (final (index, event) in _events.indexed)
                  _TimelineEvent(
                    event: event,
                    isLast: index == _events.length - 1,
                  ),
              ],
            ),
    );
  }

  OutlineInputBorder _inputBorder({Color? color}) {
    return OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: BorderSide(color: color ?? borderColor),
    );
  }
}

class _ShipmentSummaryCard extends StatelessWidget {
  const _ShipmentSummaryCard({required this.shipment, required this.status});

  final ShipmentModel shipment;
  final String status;

  @override
  Widget build(BuildContext context) {
    final statusColor = status == 'delivered'
        ? const Color(0xFF5CC6A3)
        : status == 'cancelled'
        ? const Color(0xFFE58B9B)
        : purple;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: borderColor),
      ),
      child: Row(
        children: [
          const Icon(Icons.inventory_2_outlined, color: purple, size: 28),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  shipment.shipmentId,
                  style: const TextStyle(
                    color: textColor,
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Tracking code: ${shipment.trackingCode}',
                  style: const TextStyle(color: mutedColor, fontSize: 12),
                ),
              ],
            ),
          ),
          Text(
            _statusLabel(status),
            style: TextStyle(color: statusColor, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({
    required this.title,
    required this.icon,
    required this.child,
  });

  final String title;
  final IconData icon;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(icon, color: purple, size: 22),
              const SizedBox(width: 10),
              Text(
                title,
                style: const TextStyle(
                  color: textColor,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.label,
    required this.value,
    this.isLast = false,
  });

  final String label;
  final String value;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: isLast ? 0 : 9),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 125,
            child: Text(
              label,
              style: const TextStyle(color: mutedColor, fontSize: 12),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(color: textColor, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}

class _TimelineEvent extends StatelessWidget {
  const _TimelineEvent({required this.event, required this.isLast});

  final ShipmentEventModel event;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              Icon(Icons.circle, color: purple, size: 13),
              if (!isLast)
                Expanded(
                  child: Container(
                    width: 1,
                    color: borderColor,
                    margin: const EdgeInsets.symmetric(vertical: 4),
                  ),
                ),
            ],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0 : 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    event.title,
                    style: const TextStyle(
                      color: textColor,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    _statusLabel(event.status),
                    style: const TextStyle(color: purple, fontSize: 12),
                  ),
                  if (event.description != null) ...[
                    const SizedBox(height: 3),
                    Text(
                      event.description!,
                      style: const TextStyle(
                        color: mutedColor,
                        fontSize: 13,
                        height: 1.35,
                      ),
                    ),
                  ],
                  if (event.locationName != null ||
                      event.timestamp != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      [
                        if (event.locationName != null) event.locationName!,
                        if (event.timestamp != null)
                          _formatDateTime(event.timestamp!),
                      ].join(' · '),
                      style: const TextStyle(color: mutedColor, fontSize: 12),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MessageCard extends StatelessWidget {
  const _MessageCard({
    required this.icon,
    required this.message,
    required this.color,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String message;
  final Color color;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: borderColor),
      ),
      child: Row(
        children: [
          Icon(icon, color: color),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  message,
                  style: const TextStyle(color: mutedColor, height: 1.35),
                ),
                if (actionLabel != null && onAction != null)
                  TextButton(
                    onPressed: onAction,
                    style: TextButton.styleFrom(
                      foregroundColor: purple,
                      padding: EdgeInsets.zero,
                    ),
                    child: Text(actionLabel!),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyTrackingState extends StatelessWidget {
  const _EmptyTrackingState();

  @override
  Widget build(BuildContext context) {
    return const _MessageCard(
      icon: Icons.route_outlined,
      message:
          'Shipment status, timeline, and location will appear here '
          'when accessible tracking data is available.',
      color: mutedColor,
    );
  }
}

class _SectionHeading extends StatelessWidget {
  const _SectionHeading({
    required this.eyebrow,
    required this.title,
    required this.subtitle,
    required this.icon,
  });

  final String eyebrow;
  final String title;
  final String subtitle;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(11),
          decoration: const BoxDecoration(
            color: Color(0xFF302544),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: purple, size: 24),
        ),
        const SizedBox(width: 13),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                eyebrow,
                style: const TextStyle(
                  color: purple,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                title,
                style: const TextStyle(
                  color: textColor,
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: const TextStyle(color: mutedColor, height: 1.35),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

String _statusLabel(String status) {
  if (status.isEmpty) return 'Unknown';
  return status
      .split(RegExp(r'[_-]'))
      .map(
        (part) => part.isEmpty
            ? part
            : '${part[0].toUpperCase()}${part.substring(1)}',
      )
      .join(' ');
}

String _formatDateTime(DateTime date) {
  final local = date.toLocal();
  final month = local.month.toString().padLeft(2, '0');
  final day = local.day.toString().padLeft(2, '0');
  final hour = local.hour.toString().padLeft(2, '0');
  final minute = local.minute.toString().padLeft(2, '0');
  return '${local.year}-$month-$day $hour:$minute';
}
