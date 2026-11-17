import 'dart:async';

import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';

import '../models/truck_registration_model.dart';
import '../models/warehouse_model.dart';
import '../services/firestore_service.dart';
import 'map_page.dart';
import 'warehouse_location_picker_page.dart';

class WarehousePage extends StatefulWidget {
  const WarehousePage({super.key});

  @override
  State<WarehousePage> createState() => _WarehousePageState();
}

class _WarehousePageState extends State<WarehousePage> {
  final FirestoreService _firestoreService = FirestoreService();
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _addressController = TextEditingController();
  final TextEditingController _contactNameController = TextEditingController();
  final TextEditingController _contactNumberController =
      TextEditingController();
  final TextEditingController _locationController = TextEditingController();

  final List<WarehouseModel> _savedWarehouses = [];
  WarehouseModel? _savedWarehouse;
  WarehouseModel? _editingWarehouse;
  bool _isShowingForm = false;
  bool _isLoading = true;
  bool _isSaving = false;
  String? _errorMessage;
  StreamSubscription<List<TruckRegistrationModel>>? _truckRequestsSubscription;
  List<TruckRegistrationModel> _truckRequests = const [];
  bool _isLoadingTruckRequests = true;
  String? _truckRequestsError;
  double? _selectedLatitude;
  double? _selectedLongitude;

  @override
  void initState() {
    super.initState();
    _loadWarehouses();
    _subscribeToTruckRequests();
  }

  @override
  void dispose() {
    _truckRequestsSubscription?.cancel();
    _nameController.dispose();
    _addressController.dispose();
    _contactNameController.dispose();
    _contactNumberController.dispose();
    _locationController.dispose();
    super.dispose();
  }

  void _subscribeToTruckRequests() {
    _truckRequestsSubscription = _firestoreService
        .watchMyTruckRegistrationRequests()
        .listen(
          (requests) {
            if (!mounted) return;
            setState(() {
              _truckRequests = requests;
              _isLoadingTruckRequests = false;
              _truckRequestsError = null;
            });
          },
          onError: (Object error) {
            if (!mounted) return;
            setState(() {
              _isLoadingTruckRequests = false;
              _truckRequestsError = _friendlyError(error);
            });
          },
        );
  }

  Future<void> _loadWarehouses() async {
    try {
      final warehouses = await _firestoreService.getMyWarehouses();
      if (!mounted) return;
      setState(() {
        _savedWarehouses
          ..clear()
          ..addAll(warehouses);
        _savedWarehouse = warehouses.isEmpty ? null : warehouses.first;
        _selectedLatitude = _savedWarehouse?.latitude;
        _selectedLongitude = _savedWarehouse?.longitude;
        _isLoading = false;
        _errorMessage = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = _friendlyError(error);
      });
    }
  }

  void _openRegistrationForm() {
    _clearForm();
    _editingWarehouse = null;
    setState(() => _isShowingForm = true);
  }

  void _clearForm() {
    _nameController.clear();
    _addressController.clear();
    _contactNameController.clear();
    _contactNumberController.clear();
    _locationController.clear();
    _selectedLatitude = null;
    _selectedLongitude = null;
    _formKey.currentState?.reset();
  }

  void _openEditForm() {
    final warehouse = _savedWarehouse;
    if (warehouse == null) return;
    _editingWarehouse = warehouse;
    _nameController.text = warehouse.name;
    _addressController.text = warehouse.address;
    _contactNameController.text = warehouse.contactName;
    _contactNumberController.text = warehouse.contactNumber;
    _locationController.text = warehouse.location;
    _selectedLatitude = warehouse.latitude;
    _selectedLongitude = warehouse.longitude;
    setState(() => _isShowingForm = true);
  }

  Future<void> _pickWarehouseLocation() async {
    final selection = await Navigator.of(context)
        .push<WarehouseLocationSelection>(
          MaterialPageRoute(
            builder: (_) => WarehouseLocationPickerPage(
              initialDisplayName: _locationController.text.trim().isEmpty
                  ? null
                  : _locationController.text.trim(),
              initialLatitude: _selectedLatitude,
              initialLongitude: _selectedLongitude,
            ),
          ),
        );
    if (!mounted || selection == null) return;
    setState(() {
      _locationController.text = selection.displayName;
      _selectedLatitude = selection.latitude;
      _selectedLongitude = selection.longitude;
    });
  }

  Future<void> _registerWarehouse() async {
    if (!_formKey.currentState!.validate()) return;

    FocusScope.of(context).unfocus();
    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });
    try {
      final existing = _editingWarehouse;
      if (existing == null) {
        final created = await _firestoreService.createWarehouse(
          name: _nameController.text,
          address: _addressController.text,
          contactName: _contactNameController.text,
          contactNumber: _contactNumberController.text,
          location: _locationController.text,
          latitude: _selectedLatitude,
          longitude: _selectedLongitude,
        );
        _savedWarehouses.add(created);
        _savedWarehouse = created;
      } else {
        await _firestoreService.updateWarehouse(
          warehouse: existing,
          name: _nameController.text,
          address: _addressController.text,
          contactName: _contactNameController.text,
          contactNumber: _contactNumberController.text,
          location: _locationController.text,
          latitude: _selectedLatitude,
          longitude: _selectedLongitude,
        );
        final updated = WarehouseModel(
          warehouseId: existing.warehouseId,
          code: existing.code,
          name: _nameController.text.trim(),
          address: _addressController.text.trim(),
          contactName: _contactNameController.text.trim(),
          contactNumber: _contactNumberController.text.trim(),
          location: _locationController.text.trim(),
          latitude: _selectedLatitude,
          longitude: _selectedLongitude,
          ownerUid: existing.ownerUid,
          createdAt: existing.createdAt,
          updatedAt: DateTime.now(),
        );
        final index = _savedWarehouses.indexWhere(
          (warehouse) => warehouse.warehouseId == updated.warehouseId,
        );
        if (index >= 0) {
          _savedWarehouses[index] = updated;
        }
        _savedWarehouse = updated;
      }
      if (!mounted) return;
      setState(() {
        _isShowingForm = false;
        _isSaving = false;
        _editingWarehouse = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            existing == null
                ? 'Warehouse registered successfully.'
                : 'Warehouse updated successfully.',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isSaving = false;
        _errorMessage = _friendlyError(error);
      });
    }
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
          'Warehouse Management',
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
                  if (_errorMessage != null) ...[
                    _ErrorBanner(message: _errorMessage!),
                    const SizedBox(height: 16),
                  ],
                  if (_isLoading)
                    const Center(child: CircularProgressIndicator())
                  else if (_isShowingForm)
                    _buildRegistrationForm()
                  else
                    _buildDashboard(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDashboard() {
    if (_savedWarehouses.isEmpty) {
      return _buildEmptyState();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _SectionHeading(
          eyebrow: 'WAREHOUSE OVERVIEW',
          title: 'Your warehouses',
          subtitle: 'Manage your registered warehouse locations.',
          icon: Icons.warehouse_rounded,
        ),
        const SizedBox(height: 20),
        ..._savedWarehouses.map(
          (warehouse) => Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: _buildWarehouseCard(warehouse),
          ),
        ),
        OutlinedButton.icon(
          onPressed: _openRegistrationForm,
          icon: const Icon(Icons.add_business_outlined),
          label: const Text('Add another warehouse'),
          style: _outlinedButtonStyle(),
        ),
        const SizedBox(height: 28),
        const _SectionHeading(
          eyebrow: 'ASSOCIATED TRUCKS',
          title: 'Truck activity',
          subtitle: 'Review trucks linked to this warehouse.',
          icon: Icons.local_shipping_rounded,
        ),
        const SizedBox(height: 14),
        if (_isLoadingTruckRequests)
          const Center(child: CircularProgressIndicator())
        else if (_truckRequestsError != null)
          _buildTruckActivityMessage(
            Icons.error_outline_rounded,
            _truckRequestsError!,
            const Color(0xFFE58B9B),
          )
        else
          ..._savedWarehouses.map(
            (warehouse) => Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: _buildWarehouseTruckActivity(warehouse),
            ),
          ),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _buildWarehouseTruckActivity(WarehouseModel warehouse) {
    final requests = _truckRequests
        .where((request) => request.warehouseId == warehouse.warehouseId)
        .toList();
    final pending = requests
        .where((request) => request.status.toLowerCase() == 'pending')
        .toList();
    final approved = requests
        .where((request) => request.status.toLowerCase() == 'approved')
        .toList();
    final rejected = requests
        .where((request) => request.status.toLowerCase() == 'rejected')
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '${warehouse.name} · ${warehouse.code}',
          style: const TextStyle(
            color: textColor,
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 10),
        _buildTruckSection(
          title: 'Approved trucks',
          requests: approved,
          emptyText: 'No approved trucks for this warehouse.',
          icon: Icons.check_circle_outline_rounded,
          color: const Color(0xFF5CC6A3),
        ),
        const SizedBox(height: 10),
        _buildTruckSection(
          title: 'Pending requests',
          requests: pending,
          emptyText: 'No pending requests for this warehouse.',
          icon: Icons.pending_actions_rounded,
          color: purple,
        ),
        const SizedBox(height: 10),
        _buildTruckSection(
          title: 'Rejected requests',
          requests: rejected,
          emptyText: 'No rejected requests for this warehouse.',
          icon: Icons.cancel_outlined,
          color: const Color(0xFFE58B9B),
        ),
      ],
    );
  }

  Widget _buildEmptyState() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 24),
        Container(
          padding: const EdgeInsets.fromLTRB(24, 30, 24, 26),
          decoration: BoxDecoration(
            color: surface,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: borderColor),
          ),
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.all(18),
                decoration: const BoxDecoration(
                  color: Color(0xFF302544),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.warehouse_rounded,
                  color: purple,
                  size: 42,
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                'No warehouse registered yet',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: textColor,
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                'Register your warehouse to manage its details and review '
                'associated truck requests in one place.',
                textAlign: TextAlign.center,
                style: TextStyle(color: mutedColor, height: 1.5),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 54,
                child: ElevatedButton.icon(
                  onPressed: _openRegistrationForm,
                  icon: const Icon(Icons.add_business_rounded),
                  label: const Text('Register Warehouse'),
                  style: _primaryButtonStyle(),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 28),
        const _SectionHeading(
          eyebrow: 'TRUCK ACTIVITY',
          title: 'Associated trucks',
          subtitle: 'Truck requests linked to your warehouses.',
          icon: Icons.local_shipping_outlined,
        ),
        const SizedBox(height: 14),
        if (_isLoadingTruckRequests)
          const Center(child: CircularProgressIndicator())
        else if (_truckRequestsError != null)
          _buildTruckActivityMessage(
            Icons.error_outline_rounded,
            _truckRequestsError!,
            const Color(0xFFE58B9B),
          )
        else
          _buildTruckActivityMessage(
            Icons.inbox_outlined,
            'No truck registration requests are linked to your warehouses.',
            mutedColor,
          ),
      ],
    );
  }

  Widget _buildRegistrationForm() {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _SectionHeading(
            eyebrow: 'WAREHOUSE REGISTRATION',
            title: 'Add your warehouse',
            subtitle: 'Enter the details used to identify and contact it.',
            icon: Icons.add_business_rounded,
          ),
          const SizedBox(height: 24),
          _WarehouseField(
            controller: _nameController,
            label: 'Warehouse name',
            hint: 'e.g. North Hub Warehouse',
            icon: Icons.business_rounded,
            validator: _requiredValidator,
          ),
          const SizedBox(height: 15),
          _WarehouseField(
            controller: _addressController,
            label: 'Address',
            hint: 'Street, city, and postal code',
            icon: Icons.location_on_outlined,
            validator: _requiredValidator,
            maxLines: 2,
          ),
          const SizedBox(height: 15),
          _WarehouseField(
            controller: _contactNameController,
            label: 'Contact name',
            hint: 'Primary warehouse contact',
            icon: Icons.person_outline_rounded,
            validator: _requiredValidator,
          ),
          const SizedBox(height: 15),
          _WarehouseField(
            controller: _contactNumberController,
            label: 'Contact number',
            hint: 'Enter a reachable phone number',
            icon: Icons.phone_outlined,
            keyboardType: TextInputType.phone,
            validator: _phoneValidator,
          ),
          const SizedBox(height: 15),
          _WarehouseField(
            controller: _locationController,
            label: 'Warehouse location',
            hint: 'Tap to select on the map',
            icon: Icons.my_location_rounded,
            textInputAction: TextInputAction.done,
            readOnly: true,
            onTap: _pickWarehouseLocation,
          ),
          const SizedBox(height: 12),
          Text(
            _selectedLatitude == null || _selectedLongitude == null
                ? 'Select a point on the map to save its approximate name and '
                      'coordinates.'
                : 'Coordinates: ${_selectedLatitude!.toStringAsFixed(6)}, '
                      '${_selectedLongitude!.toStringAsFixed(6)}',
            style: TextStyle(color: mutedColor, fontSize: 12, height: 1.4),
          ),
          const SizedBox(height: 8),
          const Text(
            'A unique warehouse code will be generated in the WH-12345 '
            'format.',
            style: TextStyle(color: mutedColor, fontSize: 12, height: 1.4),
          ),
          const SizedBox(height: 24),
          SizedBox(
            height: 54,
            child: ElevatedButton.icon(
              onPressed: _isSaving ? null : _registerWarehouse,
              icon: const Icon(Icons.check_rounded),
              label: Text(_isSaving ? 'Saving...' : 'Save Warehouse'),
              style: _primaryButtonStyle(),
            ),
          ),
          const SizedBox(height: 10),
          TextButton(
            onPressed: _isSaving
                ? null
                : () => setState(() => _isShowingForm = false),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }

  Widget _buildWarehouseCard(WarehouseModel model) {
    final warehouse = _WarehouseDetails.fromModel(model);
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        children: [
          Row(
            children: [
              const Icon(Icons.verified_rounded, color: Color(0xFF5CC6A3)),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'Registration active',
                  style: TextStyle(
                    color: Color(0xFF5CC6A3),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Text(
                warehouse.code,
                style: const TextStyle(
                  color: purple,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const Divider(height: 28, color: borderColor),
          _DetailRow(
            icon: Icons.location_on_outlined,
            label: 'Address',
            value: warehouse.address,
          ),
          _DetailRow(
            icon: Icons.person_outline_rounded,
            label: 'Contact',
            value: '${warehouse.contactName} · ${warehouse.contactNumber}',
          ),
          if (warehouse.location.isNotEmpty)
            _DetailRow(
              icon: Icons.my_location_rounded,
              label: 'Location',
              value: warehouse.location,
            ),
          Padding(
            padding: const EdgeInsets.only(top: 4, left: 12, right: 12),
            child: SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () {
                  _savedWarehouse = model;
                  _openEditForm();
                },
                icon: const Icon(Icons.edit_outlined),
                label: const Text('Update warehouse details'),
                style: _outlinedButtonStyle(
                  padding: const EdgeInsets.symmetric(vertical: 17),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTruckSection({
    required String title,
    required List<TruckRegistrationModel> requests,
    required String emptyText,
    required IconData icon,
    required Color color,
  }) {
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
              Icon(icon, color: color, size: 25),
              const SizedBox(width: 12),
              Text(
                title,
                style: const TextStyle(
                  color: textColor,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (requests.isEmpty)
            Text(
              emptyText,
              style: const TextStyle(color: mutedColor, fontSize: 13),
            )
          else
            ...requests.map(
              (request) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _WarehouseTruckRequest(request: request),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildTruckActivityMessage(
    IconData icon,
    String message,
    Color color,
  ) {
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
            child: Text(
              message,
              style: const TextStyle(color: mutedColor, height: 1.35),
            ),
          ),
        ],
      ),
    );
  }

  ButtonStyle _primaryButtonStyle() {
    return ElevatedButton.styleFrom(
      backgroundColor: purple,
      foregroundColor: background,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    );
  }

  ButtonStyle _outlinedButtonStyle({
    EdgeInsetsGeometry? padding,
    double borderRadius = 16,
  }) {
    return OutlinedButton.styleFrom(
      foregroundColor: textColor,
      side: const BorderSide(color: borderColor),
      padding: padding ?? const EdgeInsets.symmetric(vertical: 14),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(borderRadius),
      ),
    );
  }

  String? _requiredValidator(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'This field is required';
    }
    return null;
  }

  String? _phoneValidator(String? value) {
    final requiredError = _requiredValidator(value);
    if (requiredError != null) return requiredError;
    if (value!.trim().replaceAll(RegExp(r'\D'), '').length < 7) {
      return 'Enter a valid contact number';
    }
    return null;
  }

  String _friendlyError(Object error) {
    if (error is StateError) return error.message.toString();
    if (error is FirebaseException) {
      return 'Unable to complete the request (${error.code}). '
          'Please try again.';
    }
    return 'Could not complete the request. Check your connection and try again.';
  }
}

class _WarehouseTruckRequest extends StatelessWidget {
  const _WarehouseTruckRequest({required this.request});

  final TruckRegistrationModel request;

  @override
  Widget build(BuildContext context) {
    final capacity = [
      request.capacity.toString(),
      if (request.capacityUnit != null) request.capacityUnit!,
    ].join(' ');

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            request.registrationNumber,
            style: const TextStyle(
              color: textColor,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 7),
          Text(
            '${request.truckType} · $capacity',
            style: const TextStyle(color: mutedColor, fontSize: 13),
          ),
          const SizedBox(height: 4),
          Text(
            'Driver: ${request.driverName}',
            style: const TextStyle(color: mutedColor, fontSize: 13),
          ),
        ],
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF3A202C),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE58B9B)),
      ),
      child: Text(
        message,
        style: const TextStyle(color: Color(0xFFE58B9B), height: 1.35),
      ),
    );
  }
}

class _WarehouseField extends StatelessWidget {
  const _WarehouseField({
    required this.controller,
    required this.label,
    required this.hint,
    required this.icon,
    this.validator,
    this.keyboardType,
    this.maxLines = 1,
    this.textInputAction,
    this.readOnly = false,
    this.onTap,
  });

  final TextEditingController controller;
  final String label;
  final String hint;
  final IconData icon;
  final String? Function(String?)? validator;
  final TextInputType? keyboardType;
  final int maxLines;
  final TextInputAction? textInputAction;
  final bool readOnly;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      validator: validator,
      keyboardType: keyboardType,
      textInputAction: textInputAction,
      maxLines: maxLines,
      readOnly: readOnly,
      onTap: onTap,
      style: const TextStyle(color: textColor),
      cursorColor: purple,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        labelStyle: const TextStyle(color: mutedColor),
        hintStyle: const TextStyle(color: mutedColor, fontSize: 13),
        prefixIcon: Icon(icon, color: purple),
        filled: true,
        fillColor: surface,
        errorStyle: const TextStyle(color: Color(0xFFE58B9B)),
        border: _inputBorder(),
        enabledBorder: _inputBorder(),
        focusedBorder: _inputBorder(color: purple),
        errorBorder: _inputBorder(color: const Color(0xFFE58B9B)),
        focusedErrorBorder: _inputBorder(
          color: const Color(0xFFE58B9B),
          width: 1.5,
        ),
      ),
    );
  }

  OutlineInputBorder _inputBorder({Color? color, double width = 1}) {
    return OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: BorderSide(color: color ?? borderColor, width: width),
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

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 15),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: purple, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(color: mutedColor, fontSize: 12),
                ),
                const SizedBox(height: 3),
                Text(
                  value,
                  style: const TextStyle(color: textColor, height: 1.35),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _WarehouseDetails {
  const _WarehouseDetails({
    required this.name,
    required this.address,
    required this.contactName,
    required this.contactNumber,
    required this.location,
    required this.latitude,
    required this.longitude,
    required this.code,
  });

  final String name;
  final String address;
  final String contactName;
  final String contactNumber;
  final String location;
  final double? latitude;
  final double? longitude;
  final String code;

  factory _WarehouseDetails.fromModel(WarehouseModel model) {
    return _WarehouseDetails(
      name: model.name,
      address: model.address,
      contactName: model.contactName,
      contactNumber: model.contactNumber,
      location: model.location,
      latitude: model.latitude,
      longitude: model.longitude,
      code: model.code,
    );
  }
}
