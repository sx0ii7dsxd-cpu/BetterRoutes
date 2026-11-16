import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../models/business_model.dart';
import '../models/truck_model.dart';
import '../models/warehouse_model.dart';
import '../services/business_service.dart';
import '../services/truck_service.dart';
import '../services/user_profile_service.dart';
import '../services/warehouse_service.dart';
import '../theme/app_colors.dart';
import 'business_management_page.dart';
import 'truck_details_page.dart';

class TruckRegistrationPage extends StatefulWidget {
  const TruckRegistrationPage({
    super.key,
    this.businessIdFilter,
    this.businessNameFilter,
    this.warehouseIdFilter,
    this.warehouseNameFilter,
    this.warehouseManagementPageBuilder,
  });

  final String? businessIdFilter;
  final String? businessNameFilter;
  final String? warehouseIdFilter;
  final String? warehouseNameFilter;
  final Widget Function()? warehouseManagementPageBuilder;

  @override
  State<TruckRegistrationPage> createState() => _TruckRegistrationPageState();
}

class _TruckRegistrationPageState extends State<TruckRegistrationPage> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _registrationController = TextEditingController();
  final TextEditingController _capacityController = TextEditingController();
  final TextEditingController _detailsController = TextEditingController();
  final TextEditingController _driverController = TextEditingController();
  final TextEditingController _driverContactController =
      TextEditingController();

  final TruckService _truckService = TruckService.local();
  final WarehouseService _warehouseService = WarehouseService.local();
  final BusinessService _businessService = BusinessService.local();
  final UserProfileService _profileService = UserProfileService.local();
  final String? _ownerUid = FirebaseAuth.instance.currentUser?.uid;

  List<Truck> _trucks = [];
  List<Warehouse> _warehouses = [];
  List<Business> _businesses = [];
  Truck? _editingTruck;
  String? _truckType;
  String? _selectedWarehouseId;
  String? _selectedBusinessId;
  String _statusFilter = 'all';
  bool _isShowingForm = false;
  bool _isLoading = true;
  bool _isSaving = false;
  String? _loadError;
  int _loadGeneration = 0;

  @override
  void initState() {
    super.initState();
    _loadPage();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _registrationController.dispose();
    _capacityController.dispose();
    _detailsController.dispose();
    _driverController.dispose();
    _driverContactController.dispose();
    super.dispose();
  }

  Future<void> _loadPage() async {
    final String? ownerUid = _ownerUid;
    if (ownerUid == null || ownerUid.isEmpty) {
      setState(() {
        _loadError = 'Sign in to manage trucks.';
        _isLoading = false;
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _loadError = null;
    });
    try {
      final User? user = FirebaseAuth.instance.currentUser;
      if (user == null || user.uid != ownerUid) {
        throw const FormatException(
          'The signed-in Firebase account is unavailable.',
        );
      }
      await _profileService.saveFromAuthentication(
        uid: user.uid,
        displayName: user.displayName,
        email: user.email,
        photoUrl: user.photoURL,
        providerIds: user.providerData
            .map((UserInfo info) => info.providerId)
            .toList(growable: false),
      );
      final List<Business> businesses = await _businessService.getForOwner(
        ownerUid,
      );
      final List<Warehouse> warehouses = await _warehouseService.getAll();
      if (!mounted) return;
      setState(() {
        _businesses = businesses;
        _warehouses = warehouses;
        _isLoading = false;
      });
      await _loadTrucks();
    } on Exception catch (error) {
      if (!mounted) return;
      setState(() {
        _loadError = 'Truck data could not be loaded: $error';
        _isLoading = false;
      });
    }
  }

  Future<void> _loadTrucks() async {
    final String? ownerUid = _ownerUid;
    if (ownerUid == null) return;
    final int generation = ++_loadGeneration;
    setState(() {
      _isLoading = true;
      _loadError = null;
    });
    try {
      final String? status = _statusFilter == 'all' ? null : _statusFilter;
      final String query = _searchController.text.trim();
      final List<Truck> trucks = query.isEmpty
          ? await _truckService.getForOwner(
              ownerUid,
              approvalStatus: status,
              businessId: widget.businessIdFilter,
              warehouseId: widget.warehouseIdFilter,
            )
          : await _truckService.searchForOwner(
              ownerUid,
              query,
              approvalStatus: status,
              businessId: widget.businessIdFilter,
              warehouseId: widget.warehouseIdFilter,
            );
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _trucks = trucks;
        _isLoading = false;
      });
    } on Exception catch (error) {
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _loadError = 'Trucks could not be loaded: $error';
        _isLoading = false;
      });
    }
  }

  void _startCreate() {
    _clearForm();
    setState(() {
      _editingTruck = null;
      _truckType = null;
      _selectedBusinessId =
          widget.businessIdFilter ?? _businesses.firstOrNull?.id;
      _selectedWarehouseId =
          widget.warehouseIdFilter ?? _warehouses.firstOrNull?.id;
      _isShowingForm = true;
    });
  }

  void _startEdit(Truck truck) {
    _registrationController.text = truck.registrationNumber;
    _capacityController.text = truck.capacity;
    _detailsController.text = truck.details;
    _driverController.text = truck.driverName;
    _driverContactController.text = truck.driverContactNumber;
    setState(() {
      _editingTruck = truck;
      _truckType = truck.truckType;
      _selectedWarehouseId = truck.warehouseId;
      _selectedBusinessId = truck.businessId;
      _isShowingForm = true;
    });
  }

  void _clearForm() {
    _registrationController.clear();
    _capacityController.clear();
    _detailsController.clear();
    _driverController.clear();
    _driverContactController.clear();
  }

  Future<void> _submitRegistration() async {
    if (!_formKey.currentState!.validate()) return;
    final String? ownerUid = _ownerUid;
    final String? truckType = _truckType;
    final String? businessId = _selectedBusinessId;
    final String? warehouseId = _selectedWarehouseId;
    if (ownerUid == null ||
        truckType == null ||
        businessId == null ||
        warehouseId == null) {
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() => _isSaving = true);
    try {
      final Truck? existing = _editingTruck;
      if (existing == null) {
        await _truckService.create(
          ownerUid: ownerUid,
          registrationNumber: _registrationController.text,
          truckType: truckType,
          capacity: _capacityController.text,
          details: _detailsController.text,
          driverName: _driverController.text,
          driverContactNumber: _driverContactController.text,
          warehouseId: warehouseId,
          businessId: businessId,
        );
      } else {
        await _truckService.update(
          ownerUid: ownerUid,
          existing: existing,
          registrationNumber: _registrationController.text,
          truckType: truckType,
          capacity: _capacityController.text,
          details: _detailsController.text,
          driverName: _driverController.text,
          driverContactNumber: _driverContactController.text,
          warehouseId: warehouseId,
          businessId: businessId,
        );
      }
      if (!mounted) return;
      setState(() {
        _isShowingForm = false;
        _editingTruck = null;
      });
      await _loadTrucks();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            existing == null
                ? 'Truck registration saved as pending approval.'
                : 'Truck details updated.',
          ),
        ),
      );
    } on Exception catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Truck could not be saved: $error')),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _deleteTruck(Truck truck) async {
    final bool confirmed =
        await showDialog<bool>(
          context: context,
          builder: (BuildContext dialogContext) => AlertDialog(
            backgroundColor: surface,
            title: const Text(
              'Delete truck?',
              style: TextStyle(color: textColor),
            ),
            content: Text(
              'Delete "${truck.registrationNumber}"? This cannot be undone.',
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
    if (!confirmed || !mounted || _ownerUid == null) return;

    try {
      await _truckService.delete(truck.id, _ownerUid);
      await _loadTrucks();
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Truck deleted.')));
    } on Exception catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Truck could not be deleted: $error')),
      );
    }
  }

  Future<void> _openBusinessManagement() async {
    final String? ownerUid = _ownerUid;
    if (ownerUid == null) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => BusinessManagementPage(
          ownerUid: ownerUid,
          truckManagementPageBuilder: (Business business) =>
              TruckRegistrationPage(
                businessIdFilter: business.id,
                businessNameFilter: business.name,
                warehouseManagementPageBuilder:
                    widget.warehouseManagementPageBuilder,
              ),
        ),
      ),
    );
    await _loadPage();
  }

  Future<void> _openWarehouseManagement() async {
    final Widget Function()? pageBuilder =
        widget.warehouseManagementPageBuilder;
    if (pageBuilder == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Open Warehouse Management from the main menu.'),
        ),
      );
      return;
    }
    await Navigator.of(context)
        .push<void>(MaterialPageRoute<void>(builder: (_) => pageBuilder()));
    await _loadPage();
  }

  Future<void> _showDetails(Truck truck) async {
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
          'Truck Management',
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
          eyebrow: 'TRUCK FLEET',
          title:
              '${_trucks.length} ${_trucks.length == 1 ? 'truck' : 'trucks'}',
          subtitle: widget.businessNameFilter != null
              ? 'Trucks associated with ${widget.businessNameFilter}.'
              : widget.warehouseNameFilter != null
              ? 'Trucks assigned to ${widget.warehouseNameFilter}.'
              : 'Registered vehicles associated with your businesses.',
          icon: Icons.local_shipping_rounded,
        ),
        const SizedBox(height: 20),
        TextField(
          controller: _searchController,
          onChanged: (_) => _loadTrucks(),
          style: const TextStyle(color: textColor),
          cursorColor: purple,
          decoration: InputDecoration(
            hintText: 'Search registration, driver, type, or association',
            hintStyle: const TextStyle(color: mutedColor, fontSize: 13),
            prefixIcon: const Icon(Icons.search_rounded, color: purple),
            filled: true,
            fillColor: surface,
            border: _inputBorder(),
            enabledBorder: _inputBorder(),
            focusedBorder: _inputBorder(color: purple),
          ),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          initialValue: _statusFilter,
          onChanged: (String? status) {
            if (status == null) return;
            setState(() => _statusFilter = status);
            _loadTrucks();
          },
          dropdownColor: surface,
          style: const TextStyle(color: textColor),
          decoration: _fieldDecoration(
            label: 'Approval status',
            icon: Icons.filter_list_rounded,
          ),
          items: const [
            DropdownMenuItem(value: 'all', child: Text('All statuses')),
            DropdownMenuItem(value: 'pending', child: Text('Pending')),
            DropdownMenuItem(value: 'approved', child: Text('Approved')),
            DropdownMenuItem(value: 'rejected', child: Text('Rejected')),
          ],
        ),
        const SizedBox(height: 16),
        SizedBox(
          height: 52,
          child: ElevatedButton.icon(
            onPressed: _startCreate,
            icon: const Icon(Icons.add_road_rounded),
            label: const Text('Register Truck'),
            style: _primaryButtonStyle(),
          ),
        ),
        if (_businesses.isEmpty || _warehouses.isEmpty) ...[
          const SizedBox(height: 12),
          Text(
            _businesses.isEmpty
                ? 'Create a business profile before registering a truck.'
                : 'Create a warehouse before registering a truck.',
            textAlign: TextAlign.center,
            style: const TextStyle(color: mutedColor, fontSize: 12),
          ),
          TextButton(
            onPressed: _businesses.isEmpty
                ? _openBusinessManagement
                : _openWarehouseManagement,
            child: Text(
              _businesses.isEmpty ? 'Manage businesses' : 'Manage warehouses',
            ),
          ),
        ],
        const SizedBox(height: 16),
        if (_isLoading)
          const Padding(
            padding: EdgeInsets.all(28),
            child: Center(child: CircularProgressIndicator(color: purple)),
          )
        else if (_loadError case final String error)
          _ErrorCard(message: error, onRetry: _loadPage)
        else if (_trucks.isEmpty)
          _buildEmptyState()
        else
          ..._trucks.map(_buildTruckCard),
      ],
    );
  }

  Widget _buildEmptyState() {
    final bool isSearching = _searchController.text.trim().isNotEmpty;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: surface,
        border: Border.all(color: borderColor),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Text(
        isSearching
            ? 'No trucks match this search.'
            : widget.warehouseNameFilter != null
            ? 'No trucks are currently assigned to '
                  '${widget.warehouseNameFilter}.'
            : widget.businessNameFilter != null
            ? 'No trucks are currently associated with '
                  '${widget.businessNameFilter}.'
            : 'No trucks registered yet. Register a truck to get started.',
        textAlign: TextAlign.center,
        style: const TextStyle(color: mutedColor, height: 1.4),
      ),
    );
  }

  Widget _buildTruckCard(Truck truck) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: surface,
        border: Border.all(color: borderColor),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.local_shipping_rounded, color: purple),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  truck.registrationNumber,
                  style: const TextStyle(
                    color: textColor,
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              _StatusBadge(status: truck.approvalStatus),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            '${truck.truckType} · ${truck.capacity}',
            style: const TextStyle(color: mutedColor),
          ),
          const SizedBox(height: 5),
          Text(
            '${truck.businessName ?? 'Business'} · '
            '${truck.warehouseName ?? 'Warehouse'} '
            '(${truck.warehouseCode ?? truck.warehouseId})',
            style: const TextStyle(color: mutedColor, fontSize: 13),
          ),
          const SizedBox(height: 5),
          Text(
            '${truck.driverName} · ${truck.driverContactNumber}',
            style: const TextStyle(color: mutedColor, fontSize: 13),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              TextButton.icon(
                onPressed: () => _showDetails(truck),
                icon: const Icon(Icons.info_outline_rounded, size: 18),
                label: const Text('Details'),
              ),
              TextButton.icon(
                onPressed: () => _startEdit(truck),
                icon: const Icon(Icons.edit_outlined, size: 18),
                label: const Text('Edit'),
              ),
              TextButton.icon(
                onPressed: () => _deleteTruck(truck),
                icon: const Icon(Icons.delete_outline_rounded, size: 18),
                label: const Text('Delete'),
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFFE58B9B),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildForm() {
    final bool isEditing = _editingTruck != null;
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _SectionHeading(
            eyebrow: isEditing ? 'TRUCK DETAILS' : 'TRUCK REGISTRATION',
            title: isEditing ? 'Edit truck' : 'Register a truck',
            subtitle: isEditing
                ? 'Update vehicle, driver, business, or warehouse details.'
                : 'Add vehicle details and associate it with a business and '
                      'warehouse.',
            icon: Icons.local_shipping_rounded,
          ),
          const SizedBox(height: 24),
          const _FormSectionLabel(
            title: 'Vehicle information',
            icon: Icons.local_shipping_outlined,
          ),
          const SizedBox(height: 12),
          _TruckField(
            controller: _registrationController,
            label: 'Vehicle registration number',
            hint: 'e.g. TN 01 AB 1234',
            icon: Icons.confirmation_number_outlined,
            validator: _requiredValidator,
            textCapitalization: TextCapitalization.characters,
          ),
          const SizedBox(height: 15),
          DropdownButtonFormField<String>(
            initialValue: _truckType,
            onChanged: (String? type) => setState(() => _truckType = type),
            validator: (String? type) =>
                type == null ? 'Select a truck type' : null,
            dropdownColor: surface,
            style: const TextStyle(color: textColor),
            decoration: _fieldDecoration(
              label: 'Truck type',
              icon: Icons.fire_truck_outlined,
            ),
            items: Truck.supportedTypes
                .map(
                  (String type) =>
                      DropdownMenuItem(value: type, child: Text(type)),
                )
                .toList(growable: false),
          ),
          const SizedBox(height: 15),
          _TruckField(
            controller: _capacityController,
            label: 'Vehicle capacity',
            hint: 'e.g. 5 tonnes',
            icon: Icons.scale_outlined,
            validator: _requiredValidator,
          ),
          const SizedBox(height: 15),
          _TruckField(
            controller: _detailsController,
            label: 'Additional vehicle details',
            hint: 'Optional notes about the vehicle',
            icon: Icons.notes_rounded,
            maxLines: 2,
          ),
          const SizedBox(height: 26),
          const _FormSectionLabel(
            title: 'Driver information',
            icon: Icons.person_outline_rounded,
          ),
          const SizedBox(height: 12),
          _TruckField(
            controller: _driverController,
            label: 'Driver name',
            hint: 'Full name',
            icon: Icons.person_outline_rounded,
            validator: _requiredValidator,
          ),
          const SizedBox(height: 15),
          _TruckField(
            controller: _driverContactController,
            label: 'Driver contact number',
            hint: 'Reachable phone number',
            icon: Icons.phone_outlined,
            keyboardType: TextInputType.phone,
            validator: _phoneValidator,
          ),
          const SizedBox(height: 26),
          const _FormSectionLabel(
            title: 'Associations',
            icon: Icons.link_rounded,
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _selectedBusinessId,
            onChanged: (String? id) => setState(() => _selectedBusinessId = id),
            validator: (String? id) => id == null ? 'Select a business' : null,
            dropdownColor: surface,
            style: const TextStyle(color: textColor),
            decoration: _fieldDecoration(
              label: 'Business',
              icon: Icons.business_outlined,
            ),
            items: _businesses
                .map(
                  (Business business) => DropdownMenuItem(
                    value: business.id,
                    child: Text(business.name),
                  ),
                )
                .toList(growable: false),
          ),
          TextButton.icon(
            onPressed: _openBusinessManagement,
            icon: const Icon(Icons.manage_accounts_outlined, size: 18),
            label: const Text('Manage business profiles'),
          ),
          DropdownButtonFormField<String>(
            initialValue: _selectedWarehouseId,
            onChanged: (String? id) =>
                setState(() => _selectedWarehouseId = id),
            validator: (String? id) => id == null ? 'Select a warehouse' : null,
            dropdownColor: surface,
            style: const TextStyle(color: textColor),
            decoration: _fieldDecoration(
              label: 'Warehouse',
              icon: Icons.warehouse_outlined,
            ),
            items: _warehouses
                .map(
                  (Warehouse warehouse) => DropdownMenuItem(
                    value: warehouse.id,
                    child: Text('${warehouse.name} · ${warehouse.code}'),
                  ),
                )
                .toList(growable: false),
          ),
          TextButton.icon(
            onPressed: _openWarehouseManagement,
            icon: const Icon(Icons.warehouse_outlined, size: 18),
            label: const Text('Manage warehouses'),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 54,
            child: ElevatedButton.icon(
              onPressed: _isSaving ? null : _submitRegistration,
              icon: _isSaving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: background,
                      ),
                    )
                  : Icon(isEditing ? Icons.save_rounded : Icons.check_rounded),
              label: Text(
                _isSaving
                    ? 'Saving...'
                    : isEditing
                    ? 'Save Changes'
                    : 'Register Truck',
              ),
              style: _primaryButtonStyle(),
            ),
          ),
          TextButton(
            onPressed: () => setState(() => _isShowingForm = false),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }

  InputDecoration _fieldDecoration({
    required String label,
    required IconData icon,
  }) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: mutedColor),
      prefixIcon: Icon(icon, color: purple),
      filled: true,
      fillColor: surface,
      errorStyle: const TextStyle(color: Color(0xFFE58B9B)),
      border: _inputBorder(),
      enabledBorder: _inputBorder(),
      focusedBorder: _inputBorder(color: purple),
      errorBorder: _inputBorder(color: const Color(0xFFE58B9B)),
      focusedErrorBorder: _inputBorder(color: const Color(0xFFE58B9B)),
    );
  }

  ButtonStyle _primaryButtonStyle() => ElevatedButton.styleFrom(
    backgroundColor: purple,
    foregroundColor: background,
    elevation: 0,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
  );

  OutlineInputBorder _inputBorder({Color? color}) => OutlineInputBorder(
    borderRadius: BorderRadius.circular(16),
    borderSide: BorderSide(color: color ?? borderColor),
  );

  String? _requiredValidator(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'This field is required';
    }
    return null;
  }

  String? _phoneValidator(String? value) {
    final String? requiredError = _requiredValidator(value);
    if (requiredError != null) return requiredError;
    if (value!.replaceAll(RegExp(r'\D'), '').length < 7) {
      return 'Enter a valid contact number';
    }
    return null;
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final Color color = switch (status) {
      'approved' => const Color(0xFF5CC6A3),
      'rejected' => const Color(0xFFE58B9B),
      _ => purple,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        status.toUpperCase(),
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w800,
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
  Widget build(BuildContext context) => Column(
    children: [
      Text(message, style: const TextStyle(color: textColor)),
      TextButton(onPressed: onRetry, child: const Text('Retry')),
    ],
  );
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
  Widget build(BuildContext context) => Row(
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
            Text(subtitle, style: const TextStyle(color: mutedColor)),
          ],
        ),
      ),
    ],
  );
}

class _FormSectionLabel extends StatelessWidget {
  const _FormSectionLabel({required this.title, required this.icon});

  final String title;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Icon(icon, color: purple, size: 20),
      const SizedBox(width: 8),
      Text(
        title,
        style: const TextStyle(
          color: textColor,
          fontSize: 16,
          fontWeight: FontWeight.w700,
        ),
      ),
    ],
  );
}

class _TruckField extends StatelessWidget {
  const _TruckField({
    required this.controller,
    required this.label,
    required this.hint,
    required this.icon,
    this.validator,
    this.keyboardType,
    this.maxLines = 1,
    this.textCapitalization = TextCapitalization.none,
  });

  final TextEditingController controller;
  final String label;
  final String hint;
  final IconData icon;
  final String? Function(String?)? validator;
  final TextInputType? keyboardType;
  final int maxLines;
  final TextCapitalization textCapitalization;

  @override
  Widget build(BuildContext context) => TextFormField(
    controller: controller,
    validator: validator,
    keyboardType: keyboardType,
    maxLines: maxLines,
    textCapitalization: textCapitalization,
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

  OutlineInputBorder _inputBorder({Color? color}) => OutlineInputBorder(
    borderRadius: BorderRadius.circular(16),
    borderSide: BorderSide(color: color ?? borderColor),
  );
}
