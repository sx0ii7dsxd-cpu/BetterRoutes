import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../models/truck_model.dart';
import '../models/warehouse_model.dart';
import '../services/truck_service.dart';
import '../services/warehouse_service.dart';
import '../theme/app_colors.dart';
import 'truck_details_page.dart';
import 'truck_registration_page.dart';
import 'warehouse_location_picker.dart';

class WarehousePage extends StatefulWidget {
  const WarehousePage({
    super.key,
    this.service,
    this.truckService,
    this.ownerUid,
    this.onWarehousesChanged,
  });

  final WarehouseService? service;
  final TruckService? truckService;
  final String? ownerUid;
  final VoidCallback? onWarehousesChanged;

  @override
  State<WarehousePage> createState() => _WarehousePageState();
}

class _WarehousePageState extends State<WarehousePage> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _addressController = TextEditingController();
  final TextEditingController _contactNameController = TextEditingController();
  final TextEditingController _contactNumberController =
      TextEditingController();
  final TextEditingController _locationNoteController = TextEditingController();

  late final WarehouseService _service =
      widget.service ?? WarehouseService.local();
  late final TruckService _truckService =
      widget.truckService ?? TruckService.local();
  List<Warehouse> _warehouses = [];
  Map<String, List<Truck>> _trucksByWarehouse = {};
  Warehouse? _editingWarehouse;
  LatLng? _selectedLocation;
  bool _isShowingForm = false;
  bool _isLoading = true;
  String? _loadError;
  int _loadGeneration = 0;

  @override
  void initState() {
    super.initState();
    _loadWarehouses();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _nameController.dispose();
    _addressController.dispose();
    _contactNameController.dispose();
    _contactNumberController.dispose();
    _locationNoteController.dispose();
    super.dispose();
  }

  Future<void> _loadWarehouses({String? query}) async {
    final int generation = ++_loadGeneration;
    setState(() {
      _isLoading = true;
      _loadError = null;
    });
    try {
      final List<Warehouse> warehouses = (query == null || query.isEmpty)
          ? await _service.getAll()
          : await _service.search(query);
      final String? ownerUid =
          widget.ownerUid ?? FirebaseAuth.instance.currentUser?.uid;
      final List<Truck> trucks = ownerUid == null
          ? <Truck>[]
          : await _truckService.getForOwner(ownerUid);
      final Map<String, List<Truck>> trucksByWarehouse = {};
      for (final Truck truck in trucks) {
        trucksByWarehouse
            .putIfAbsent(truck.warehouseId, () => <Truck>[])
            .add(truck);
      }
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _warehouses = warehouses;
        _trucksByWarehouse = trucksByWarehouse;
        _isLoading = false;
      });
    } on Exception catch (error) {
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _loadError = 'Warehouses could not be loaded: $error';
        _isLoading = false;
      });
    }
  }

  void _openAddForm() {
    _clearForm();
    setState(() {
      _editingWarehouse = null;
      _selectedLocation = null;
      _isShowingForm = true;
    });
  }

  void _openEditForm(Warehouse warehouse) {
    _nameController.text = warehouse.name;
    _addressController.text = warehouse.address;
    _contactNameController.text = warehouse.contactName;
    _contactNumberController.text = warehouse.contactNumber;
    _locationNoteController.text = warehouse.locationNote;
    setState(() {
      _editingWarehouse = warehouse;
      _selectedLocation =
          warehouse.latitude != null && warehouse.longitude != null
          ? LatLng(warehouse.latitude!, warehouse.longitude!)
          : null;
      _isShowingForm = true;
    });
  }

  void _clearForm() {
    _nameController.clear();
    _addressController.clear();
    _contactNameController.clear();
    _contactNumberController.clear();
    _locationNoteController.clear();
  }

  Future<void> _openLocationPicker() async {
    final LatLng? selectedLocation = await Navigator.of(context).push<LatLng>(
      MaterialPageRoute<LatLng>(
        builder: (_) => WarehouseLocationPicker(
          initialLatitude: _selectedLocation?.latitude,
          initialLongitude: _selectedLocation?.longitude,
        ),
      ),
    );
    if (!mounted || selectedLocation == null) return;
    setState(() => _selectedLocation = selectedLocation);
  }

  Future<void> _saveWarehouse() async {
    if (!_formKey.currentState!.validate()) return;
    final LatLng? location = _selectedLocation;
    if (location == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pin the warehouse location first.')),
      );
      return;
    }

    FocusScope.of(context).unfocus();
    try {
      final Warehouse? existing = _editingWarehouse;
      if (existing == null) {
        await _service.create(
          name: _nameController.text,
          address: _addressController.text,
          contactName: _contactNameController.text,
          contactNumber: _contactNumberController.text,
          locationNote: _locationNoteController.text,
          latitude: location.latitude,
          longitude: location.longitude,
        );
      } else {
        await _service.update(
          existing: existing,
          name: _nameController.text,
          address: _addressController.text,
          contactName: _contactNameController.text,
          contactNumber: _contactNumberController.text,
          locationNote: _locationNoteController.text,
          latitude: location.latitude,
          longitude: location.longitude,
        );
      }

      widget.onWarehousesChanged?.call();
      if (!mounted) return;
      setState(() => _isShowingForm = false);
      await _loadWarehouses(query: _searchController.text);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            existing == null
                ? 'Warehouse registered successfully.'
                : 'Warehouse updated successfully.',
          ),
        ),
      );
    } on Exception catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Warehouse could not be saved: $error')),
      );
    }
  }

  Future<void> _confirmDelete(Warehouse warehouse) async {
    final bool confirmed =
        await showDialog<bool>(
          context: context,
          builder: (BuildContext dialogContext) => AlertDialog(
            backgroundColor: surface,
            title: const Text(
              'Delete warehouse?',
              style: TextStyle(color: textColor),
            ),
            content: Text(
              'Delete "${warehouse.name}"? This cannot be undone. '
              'Warehouses referenced by other records cannot be deleted.',
              style: const TextStyle(color: mutedColor),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text(
                  'Delete',
                  style: TextStyle(color: Color(0xFFE58B9B)),
                ),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed || !mounted) return;

    try {
      await _service.delete(warehouse.id);
      widget.onWarehousesChanged?.call();
      if (mounted && _editingWarehouse?.id == warehouse.id) {
        setState(() {
          _editingWarehouse = null;
          _isShowingForm = false;
        });
      }
      await _loadWarehouses(query: _searchController.text);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Warehouse deleted.')));
    } on Exception catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Warehouse could not be deleted. It may be referenced by '
            'another record. $error',
          ),
        ),
      );
    }
  }

  Future<void> _openWarehouseTrucks(Warehouse warehouse) async {
    final String? ownerUid =
        widget.ownerUid ?? FirebaseAuth.instance.currentUser?.uid;
    if (ownerUid == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sign in to manage trucks.')),
      );
      return;
    }

    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => TruckRegistrationPage(
          warehouseIdFilter: warehouse.id,
          warehouseNameFilter: warehouse.name,
          warehouseManagementPageBuilder: () => WarehousePage(
            onWarehousesChanged: widget.onWarehousesChanged,
          ),
        ),
      ),
    );
    if (mounted) {
      await _loadWarehouses(query: _searchController.text);
    }
  }

  Future<void> _openTruckDetails(Truck truck) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(builder: (_) => TruckDetailsPage(truck: truck)),
    );
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
              child: _isShowingForm ? _buildForm() : _buildDashboard(),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDashboard() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionHeading(
          eyebrow: 'WAREHOUSE OVERVIEW',
          title:
              '${_warehouses.length} '
              '${_warehouses.length == 1 ? 'warehouse' : 'warehouses'}',
          subtitle: 'Create and manage your warehouse locations.',
          icon: Icons.warehouse_rounded,
        ),
        const SizedBox(height: 20),
        TextField(
          controller: _searchController,
          onChanged: (String query) => _loadWarehouses(query: query),
          style: const TextStyle(color: textColor),
          cursorColor: purple,
          decoration: InputDecoration(
            hintText: 'Search name, code, address, or contact',
            hintStyle: const TextStyle(color: mutedColor, fontSize: 13),
            prefixIcon: const Icon(Icons.search_rounded, color: purple),
            filled: true,
            fillColor: surface,
            border: _inputBorder(),
            enabledBorder: _inputBorder(),
            focusedBorder: _inputBorder(color: purple),
          ),
        ),
        const SizedBox(height: 16),
        SizedBox(
          height: 52,
          child: ElevatedButton.icon(
            onPressed: _openAddForm,
            icon: const Icon(Icons.add_business_rounded),
            label: const Text('Add Warehouse'),
            style: _primaryButtonStyle(),
          ),
        ),
        const SizedBox(height: 20),
        if (_isLoading)
          const Padding(
            padding: EdgeInsets.all(28),
            child: Center(child: CircularProgressIndicator(color: purple)),
          )
        else if (_loadError != null)
          _ErrorCard(
            message: _loadError!,
            onRetry: () => _loadWarehouses(query: _searchController.text),
          )
        else if (_warehouses.isEmpty)
          _buildEmptyState()
        else
          ..._warehouses.map(
            (Warehouse warehouse) => Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: _buildWarehouseCard(warehouse),
            ),
          ),
      ],
    );
  }

  Widget _buildEmptyState() {
    final bool isSearching = _searchController.text.trim().isNotEmpty;
    return Container(
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
            child: const Icon(Icons.warehouse_rounded, color: purple, size: 42),
          ),
          const SizedBox(height: 20),
          Text(
            isSearching ? 'No matching warehouses' : 'No warehouses yet',
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: textColor,
              fontSize: 22,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            isSearching
                ? 'Try another name, code, address, or contact.'
                : 'Add a warehouse and pin its location to get started.',
            textAlign: TextAlign.center,
            style: const TextStyle(color: mutedColor, height: 1.5),
          ),
        ],
      ),
    );
  }

  Widget _buildForm() {
    final bool isEditing = _editingWarehouse != null;
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _SectionHeading(
            eyebrow: isEditing ? 'WAREHOUSE DETAILS' : 'WAREHOUSE REGISTRATION',
            title: isEditing ? 'Edit warehouse' : 'Add your warehouse',
            subtitle: isEditing
                ? 'Update its details or confirm a new map pin.'
                : 'Enter its details and pin the warehouse on the map.',
            icon: isEditing
                ? Icons.edit_location_alt_rounded
                : Icons.add_business_rounded,
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
            controller: _locationNoteController,
            label: 'Location note (optional)',
            hint: 'Landmark or additional directions',
            icon: Icons.notes_rounded,
            textInputAction: TextInputAction.done,
          ),
          const SizedBox(height: 20),
          SizedBox(
            height: 54,
            child: ElevatedButton.icon(
              onPressed: _openLocationPicker,
              icon: const Icon(Icons.add_location_alt_rounded),
              label: Text(
                _selectedLocation == null ? 'Pin Location' : 'Change Pin',
              ),
              style: _primaryButtonStyle(),
            ),
          ),
          if (_selectedLocation case final LatLng location) ...[
            const SizedBox(height: 10),
            Text(
              'Pinned: ${location.latitude.toStringAsFixed(6)}, '
              '${location.longitude.toStringAsFixed(6)}',
              textAlign: TextAlign.center,
              style: const TextStyle(color: mutedColor, fontSize: 13),
            ),
          ] else ...[
            const SizedBox(height: 10),
            const Text(
              'A confirmed map pin is required before saving.',
              textAlign: TextAlign.center,
              style: TextStyle(color: mutedColor, fontSize: 13),
            ),
          ],
          const SizedBox(height: 24),
          SizedBox(
            height: 54,
            child: ElevatedButton.icon(
              onPressed: _saveWarehouse,
              icon: Icon(isEditing ? Icons.save_rounded : Icons.check_rounded),
              label: Text(isEditing ? 'Save Changes' : 'Register Warehouse'),
              style: _primaryButtonStyle(),
            ),
          ),
          if (isEditing) ...[
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () => _confirmDelete(_editingWarehouse!),
              icon: const Icon(Icons.delete_outline_rounded),
              label: const Text('Delete Warehouse'),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFFE58B9B),
                side: const BorderSide(color: borderColor),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            ),
          ],
          const SizedBox(height: 10),
          TextButton(
            onPressed: () => setState(() => _isShowingForm = false),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }

  Widget _buildWarehouseCard(Warehouse warehouse) {
    final List<Truck> trucks = _trucksByWarehouse[warehouse.id] ?? const [];
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
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
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              warehouse.name,
              style: const TextStyle(
                color: textColor,
                fontSize: 20,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(height: 16),
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
          if (warehouse.locationNote.isNotEmpty)
            _DetailRow(
              icon: Icons.notes_rounded,
              label: 'Location note',
              value: warehouse.locationNote,
            ),
          _DetailRow(
            icon: Icons.my_location_rounded,
            label: 'Pinned coordinates',
            value:
                '${warehouse.latitude!.toStringAsFixed(6)}, '
                '${warehouse.longitude!.toStringAsFixed(6)}',
          ),
          const Divider(height: 28, color: borderColor),
          Row(
            children: [
              const Icon(Icons.local_shipping_rounded, color: purple, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Truck activity · ${trucks.length}',
                  style: const TextStyle(
                    color: textColor,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              TextButton(
                onPressed: () => _openWarehouseTrucks(warehouse),
                child: const Text('Manage'),
              ),
            ],
          ),
          if (trucks.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 6, bottom: 12),
              child: Text(
                'No trucks are currently assigned to this warehouse.',
                style: TextStyle(color: mutedColor, fontSize: 13),
              ),
            )
          else
            ...trucks.map(
              (Truck truck) => _WarehouseTruckTile(
                truck: truck,
                onTap: () => _openTruckDetails(truck),
              ),
            ),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _openEditForm(warehouse),
                  icon: const Icon(Icons.edit_outlined),
                  label: const Text('Edit'),
                  style: _outlinedButtonStyle(),
                ),
              ),
              const SizedBox(width: 10),
              IconButton(
                onPressed: () => _confirmDelete(warehouse),
                tooltip: 'Delete warehouse',
                icon: const Icon(
                  Icons.delete_outline_rounded,
                  color: Color(0xFFE58B9B),
                ),
              ),
            ],
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

  ButtonStyle _outlinedButtonStyle() {
    return OutlinedButton.styleFrom(
      foregroundColor: textColor,
      side: const BorderSide(color: borderColor),
      padding: const EdgeInsets.symmetric(vertical: 14),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    );
  }

  OutlineInputBorder _inputBorder({Color? color}) {
    return OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: BorderSide(color: color ?? borderColor),
    );
  }

  String? _requiredValidator(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'This field is required';
    }
    return null;
  }

  String? _phoneValidator(String? value) {
    final String? requiredError = _requiredValidator(value);
    if (requiredError != null) return requiredError;
    if (value!.trim().replaceAll(RegExp(r'\D'), '').length < 7) {
      return 'Enter a valid contact number';
    }
    return null;
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
  });

  final TextEditingController controller;
  final String label;
  final String hint;
  final IconData icon;
  final String? Function(String?)? validator;
  final TextInputType? keyboardType;
  final int maxLines;
  final TextInputAction? textInputAction;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      validator: validator,
      keyboardType: keyboardType,
      textInputAction: textInputAction,
      maxLines: maxLines,
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
        focusedErrorBorder: _inputBorder(color: const Color(0xFFE58B9B)),
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

class _WarehouseTruckTile extends StatelessWidget {
  const _WarehouseTruckTile({required this.truck, required this.onTap});

  final Truck truck;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final Color statusColor = switch (truck.approvalStatus) {
      'approved' => const Color(0xFF5CC6A3),
      'rejected' => const Color(0xFFE58B9B),
      _ => purple,
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: const Color(0xFF292332),
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            child: Row(
              children: [
                const Icon(Icons.local_shipping_outlined, color: purple),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        truck.registrationNumber,
                        style: const TextStyle(
                          color: textColor,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '${truck.truckType} · '
                        '${truck.businessName ?? 'Business'}',
                        style: const TextStyle(color: mutedColor, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  truck.approvalStatus.toUpperCase(),
                  style: TextStyle(
                    color: statusColor,
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border.all(color: borderColor),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Text(message, style: const TextStyle(color: textColor)),
          TextButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }
}
