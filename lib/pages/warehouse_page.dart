import 'package:flutter/material.dart';

import 'map_page.dart';

class WarehousePage extends StatefulWidget {
  const WarehousePage({super.key});

  @override
  State<WarehousePage> createState() => _WarehousePageState();
}

class _WarehousePageState extends State<WarehousePage> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _addressController = TextEditingController();
  final TextEditingController _contactNameController = TextEditingController();
  final TextEditingController _contactNumberController =
      TextEditingController();
  final TextEditingController _locationController = TextEditingController();

  _WarehouseDetails? _warehouse;
  bool _isShowingForm = false;

  @override
  void dispose() {
    _nameController.dispose();
    _addressController.dispose();
    _contactNameController.dispose();
    _contactNumberController.dispose();
    _locationController.dispose();
    super.dispose();
  }

  void _openRegistrationForm() {
    setState(() => _isShowingForm = true);
  }

  void _registerWarehouse() {
    if (!_formKey.currentState!.validate()) return;

    FocusScope.of(context).unfocus();
    setState(() {
      _warehouse = _WarehouseDetails(
        name: _nameController.text.trim(),
        address: _addressController.text.trim(),
        contactName: _contactNameController.text.trim(),
        contactNumber: _contactNumberController.text.trim(),
        location: _locationController.text.trim(),
        code: 'WH-${DateTime.now().millisecondsSinceEpoch % 1000000}',
      );
      _isShowingForm = false;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Warehouse registered successfully.')),
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
              child: _isShowingForm
                  ? _buildRegistrationForm()
                  : _buildDashboard(),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDashboard() {
    final warehouse = _warehouse;
    if (warehouse == null) {
      return _buildEmptyState();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionHeading(
          eyebrow: 'WAREHOUSE OVERVIEW',
          title: warehouse.name,
          subtitle: 'Your warehouse is ready to manage.',
          icon: Icons.warehouse_rounded,
        ),
        const SizedBox(height: 20),
        _buildWarehouseCard(warehouse),
        const SizedBox(height: 28),
        const _SectionHeading(
          eyebrow: 'ASSOCIATED TRUCKS',
          title: 'Truck activity',
          subtitle: 'Review trucks linked to this warehouse.',
          icon: Icons.local_shipping_rounded,
        ),
        const SizedBox(height: 14),
        _buildTruckSection(
          title: 'Approved trucks',
          subtitle: 'No approved trucks yet.',
          icon: Icons.check_circle_outline_rounded,
          color: const Color(0xFF5CC6A3),
        ),
        const SizedBox(height: 12),
        _buildTruckSection(
          title: 'Pending requests',
          subtitle: 'No pending registration requests.',
          icon: Icons.pending_actions_rounded,
          color: purple,
        ),
        const SizedBox(height: 12),
        _buildTruckSection(
          title: 'Rejected requests',
          subtitle: 'No rejected requests.',
          icon: Icons.cancel_outlined,
          color: const Color(0xFFE58B9B),
        ),
        const SizedBox(height: 24),
        OutlinedButton.icon(
          onPressed: () => setState(() => _isShowingForm = true),
          icon: const Icon(Icons.edit_outlined),
          label: const Text('Update warehouse details'),
          style: _outlinedButtonStyle(),
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
          subtitle: 'Truck requests will appear here after registration.',
          icon: Icons.local_shipping_outlined,
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
            hint: 'Optional location note or landmark',
            icon: Icons.my_location_rounded,
            textInputAction: TextInputAction.done,
          ),
          const SizedBox(height: 12),
          const Text(
            'Warehouse location can be connected to the map and Firestore '
            'data model in a later phase.',
            style: TextStyle(color: mutedColor, fontSize: 12, height: 1.4),
          ),
          const SizedBox(height: 24),
          SizedBox(
            height: 54,
            child: ElevatedButton.icon(
              onPressed: _registerWarehouse,
              icon: const Icon(Icons.check_rounded),
              label: const Text('Register Warehouse'),
              style: _primaryButtonStyle(),
            ),
          ),
          const SizedBox(height: 10),
          TextButton(
            onPressed: () => setState(() => _isShowingForm = false),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }

  Widget _buildWarehouseCard(_WarehouseDetails warehouse) {
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
        ],
      ),
    );
  }

  Widget _buildTruckSection({
    required String title,
    required String subtitle,
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
      child: Row(
        children: [
          Icon(icon, color: color, size: 25),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: textColor,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: const TextStyle(color: mutedColor, fontSize: 13),
                ),
              ],
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

  ButtonStyle _outlinedButtonStyle() {
    return OutlinedButton.styleFrom(
      foregroundColor: textColor,
      side: const BorderSide(color: borderColor),
      padding: const EdgeInsets.symmetric(vertical: 14),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
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
    required this.code,
  });

  final String name;
  final String address;
  final String contactName;
  final String contactNumber;
  final String location;
  final String code;
}
