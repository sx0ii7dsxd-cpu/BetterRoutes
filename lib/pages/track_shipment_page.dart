import 'package:flutter/material.dart';

import 'map_page.dart';

class TrackShipmentPage extends StatefulWidget {
  const TrackShipmentPage({super.key});

  @override
  State<TrackShipmentPage> createState() => _TrackShipmentPageState();
}

class _TrackShipmentPageState extends State<TrackShipmentPage> {
  final TextEditingController _shipmentController = TextEditingController();
  String? _errorMessage;
  String? _searchedShipmentId;
  bool _isSearching = false;

  @override
  void dispose() {
    _shipmentController.dispose();
    super.dispose();
  }

  Future<void> _trackShipment() async {
    final shipmentId = _shipmentController.text.trim().toUpperCase();
    setState(() {
      _errorMessage = null;
      _searchedShipmentId = null;
    });

    if (shipmentId.isEmpty) {
      setState(() => _errorMessage = 'Enter a shipment ID to continue.');
      return;
    }

    if (!RegExp(r'^SHP-[A-Z0-9]{6,12}$').hasMatch(shipmentId)) {
      setState(() {
        _errorMessage = 'Use a shipment ID in the format SHP-ABC123.';
      });
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() => _isSearching = true);
    await Future<void>.delayed(const Duration(milliseconds: 500));
    if (!mounted) return;

    setState(() {
      _isSearching = false;
      _searchedShipmentId = shipmentId;
    });
  }

  @override
  Widget build(BuildContext context) {
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
                  TextField(
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
                      hintStyle: const TextStyle(
                        color: mutedColor,
                        fontSize: 13,
                      ),
                      prefixIcon: const Icon(
                        Icons.receipt_long_outlined,
                        color: purple,
                      ),
                      filled: true,
                      fillColor: surface,
                      errorText: _errorMessage,
                      errorStyle: const TextStyle(
                        color: Color(0xFFE58B9B),
                      ),
                      border: _inputBorder(),
                      enabledBorder: _inputBorder(),
                      focusedBorder: _inputBorder(color: purple),
                      errorBorder: _inputBorder(
                        color: const Color(0xFFE58B9B),
                      ),
                    ),
                    onSubmitted: (_) => _trackShipment(),
                  ),
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
                        _isSearching ? 'Looking up shipment...' : 'Track Shipment',
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
                  if (_searchedShipmentId != null)
                    _UnavailableShipmentCard(
                      shipmentId: _searchedShipmentId!,
                    )
                  else
                    const _EmptyTrackingState(),
                ],
              ),
            ),
          ),
        ),
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

class _UnavailableShipmentCard extends StatelessWidget {
  const _UnavailableShipmentCard({required this.shipmentId});

  final String shipmentId;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.info_outline_rounded, color: purple, size: 25),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  shipmentId,
                  style: const TextStyle(
                    color: textColor,
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Text(
            'Shipment data unavailable',
            style: TextStyle(
              color: textColor,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'This shipment ID is formatted correctly, but no accessible '
            'shipment record was found. Connect the shipment data source to '
            'show its summary and progress.',
            style: TextStyle(color: mutedColor, height: 1.45),
          ),
          const SizedBox(height: 18),
          const _UnavailableRow(
            icon: Icons.timeline_rounded,
            title: 'Progress timeline',
            message: 'Unavailable until shipment data is available.',
          ),
          const _UnavailableRow(
            icon: Icons.location_on_outlined,
            title: 'Latest truck location',
            message: 'No live location data available.',
          ),
          const _UnavailableRow(
            icon: Icons.schedule_rounded,
            title: 'Estimated arrival',
            message: 'Not available.',
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
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: borderColor),
      ),
      child: const Column(
        children: [
          Icon(Icons.route_outlined, color: purple, size: 42),
          SizedBox(height: 14),
          Text(
            'No shipment selected',
            style: TextStyle(
              color: textColor,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
          SizedBox(height: 7),
          Text(
            'Shipment status, timeline, and location will appear here when '
            'accessible tracking data is available.',
            textAlign: TextAlign.center,
            style: TextStyle(color: mutedColor, height: 1.45),
          ),
        ],
      ),
    );
  }
}

class _UnavailableRow extends StatelessWidget {
  const _UnavailableRow({
    required this.icon,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: mutedColor, size: 21),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: textColor,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  message,
                  style: const TextStyle(color: mutedColor, fontSize: 13),
                ),
              ],
            ),
          ),
        ],
      ),
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
