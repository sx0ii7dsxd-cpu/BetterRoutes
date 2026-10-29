import 'package:flutter/material.dart';

import 'map_page.dart';

class TruckRegistrationPage extends StatefulWidget {
  const TruckRegistrationPage({super.key});

  @override
  State<TruckRegistrationPage> createState() => _TruckRegistrationPageState();
}

class _TruckRegistrationPageState extends State<TruckRegistrationPage> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _registrationController = TextEditingController();
  final TextEditingController _capacityController = TextEditingController();
  final TextEditingController _detailsController = TextEditingController();
  final TextEditingController _driverController = TextEditingController();
  final TextEditingController _driverContactController =
      TextEditingController();
  final TextEditingController _warehouseCodeController =
      TextEditingController();

  String? _truckType;
  bool _isCheckingWarehouse = false;
  bool _warehouseCodeValid = false;
  bool _submitted = false;
  String? _warehouseMessage;

  @override
  void dispose() {
    _registrationController.dispose();
    _capacityController.dispose();
    _detailsController.dispose();
    _driverController.dispose();
    _driverContactController.dispose();
    _warehouseCodeController.dispose();
    super.dispose();
  }

  Future<void> _validateWarehouseCode() async {
    final code = _warehouseCodeController.text.trim().toUpperCase();
    if (code.isEmpty) {
      setState(() {
        _warehouseCodeValid = false;
        _warehouseMessage = 'Enter a warehouse code to validate it.';
      });
      return;
    }

    setState(() {
      _isCheckingWarehouse = true;
      _warehouseCodeValid = false;
      _warehouseMessage = null;
    });

    await Future<void>.delayed(const Duration(milliseconds: 450));
    if (!mounted) return;

    final isValid = RegExp(r'^WH-\d{6}$').hasMatch(code);
    setState(() {
      _isCheckingWarehouse = false;
      _warehouseCodeValid = isValid;
      _warehouseMessage = isValid
          ? 'Code format accepted. Warehouse name will be resolved from '
                'Firestore after integration.'
          : 'Use a warehouse code in the format WH-123456.';
    });
  }

  Future<void> _submitRegistration() async {
    if (!_formKey.currentState!.validate()) return;
    if (!_warehouseCodeValid) {
      setState(() {
        _warehouseMessage =
            'Validate a valid warehouse code before submitting.';
      });
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() => _submitted = true);
    await Future<void>.delayed(const Duration(milliseconds: 650));
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Registration submitted for administrator approval.'),
      ),
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
          'Truck Registration',
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
              child: _submitted ? _buildSubmittedView() : _buildForm(),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildForm() {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _SectionHeading(
            eyebrow: 'TRUCK REGISTRATION',
            title: 'Register a truck',
            subtitle: 'Add vehicle details and associate it with a warehouse.',
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
            value: _truckType,
            onChanged: (value) => setState(() => _truckType = value),
            validator: (value) => value == null ? 'Select a truck type' : null,
            dropdownColor: surface,
            style: const TextStyle(color: textColor),
            decoration: _fieldDecoration(
              label: 'Truck type',
              hint: 'Select vehicle type',
              icon: Icons.fire_truck_outlined,
            ),
            items: const [
              DropdownMenuItem(value: 'Mini truck', child: Text('Mini truck')),
              DropdownMenuItem(value: 'Box truck', child: Text('Box truck')),
              DropdownMenuItem(
                value: 'Heavy truck',
                child: Text('Heavy truck'),
              ),
              DropdownMenuItem(
                value: 'Refrigerated truck',
                child: Text('Refrigerated truck'),
              ),
            ],
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
            title: 'Warehouse association',
            icon: Icons.warehouse_outlined,
          ),
          const SizedBox(height: 12),
          _TruckField(
            controller: _warehouseCodeController,
            label: 'Warehouse code',
            hint: 'e.g. WH-123456',
            icon: Icons.qr_code_2_rounded,
            validator: _requiredValidator,
            textCapitalization: TextCapitalization.characters,
            onChanged: (_) {
              if (_warehouseCodeValid || _warehouseMessage != null) {
                setState(() {
                  _warehouseCodeValid = false;
                  _warehouseMessage = null;
                });
              }
            },
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 48,
            child: OutlinedButton.icon(
              onPressed: _isCheckingWarehouse ? null : _validateWarehouseCode,
              icon: _isCheckingWarehouse
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: purple,
                      ),
                    )
                  : const Icon(Icons.verified_outlined),
              label: Text(
                _isCheckingWarehouse ? 'Checking code...' : 'Validate code',
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: textColor,
                side: const BorderSide(color: borderColor),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          ),
          if (_warehouseMessage != null) ...[
            const SizedBox(height: 10),
            _ValidationMessage(
              valid: _warehouseCodeValid,
              message: _warehouseMessage!,
            ),
          ],
          const SizedBox(height: 12),
          const Text(
            'Warehouse-code validation and administrator approval are '
            'separate steps.',
            style: TextStyle(color: mutedColor, fontSize: 12, height: 1.4),
          ),
          const SizedBox(height: 24),
          SizedBox(
            height: 54,
            child: ElevatedButton.icon(
              onPressed: _isCheckingWarehouse ? null : _submitRegistration,
              icon: const Icon(Icons.send_rounded),
              label: const Text('Submit Registration'),
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
        ],
      ),
    );
  }

  Widget _buildSubmittedView() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _SectionHeading(
          eyebrow: 'REGISTRATION STATUS',
          title: 'Registration submitted',
          subtitle: 'Your truck is awaiting administrator review.',
          icon: Icons.pending_actions_rounded,
        ),
        const SizedBox(height: 24),
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: surface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: borderColor),
          ),
          child: Column(
            children: [
              const _StatusStep(
                title: 'Submitted',
                subtitle: 'Registration details received',
                icon: Icons.check_circle_rounded,
                color: Color(0xFF5CC6A3),
                isLast: false,
              ),
              _StatusStep(
                title: 'Pending approval',
                subtitle: 'An administrator must review this registration',
                icon: Icons.pending_actions_rounded,
                color: purple,
                isLast: false,
              ),
              const _StatusStep(
                title: 'Approved',
                subtitle: 'Not approved yet',
                icon: Icons.radio_button_unchecked_rounded,
                color: mutedColor,
                isLast: true,
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        const Text(
          'This status is local to the current session until registration '
          'data is connected to Firestore.',
          textAlign: TextAlign.center,
          style: TextStyle(color: mutedColor, fontSize: 12, height: 1.4),
        ),
        const SizedBox(height: 24),
        OutlinedButton.icon(
          onPressed: () => setState(() => _submitted = false),
          icon: const Icon(Icons.arrow_back_rounded),
          label: const Text('Back to registration form'),
          style: OutlinedButton.styleFrom(
            foregroundColor: textColor,
            side: const BorderSide(color: borderColor),
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
        ),
      ],
    );
  }

  InputDecoration _fieldDecoration({
    required String label,
    required String hint,
    required IconData icon,
  }) {
    return InputDecoration(
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
    );
  }

  OutlineInputBorder _inputBorder({Color? color, double width = 1}) {
    return OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: BorderSide(color: color ?? borderColor, width: width),
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
    if (value!.replaceAll(RegExp(r'\D'), '').length < 7) {
      return 'Enter a valid contact number';
    }
    return null;
  }
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
    this.onChanged,
  });

  final TextEditingController controller;
  final String label;
  final String hint;
  final IconData icon;
  final String? Function(String?)? validator;
  final TextInputType? keyboardType;
  final int maxLines;
  final TextCapitalization textCapitalization;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      validator: validator,
      keyboardType: keyboardType,
      maxLines: maxLines,
      textCapitalization: textCapitalization,
      onChanged: onChanged,
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

class _FormSectionLabel extends StatelessWidget {
  const _FormSectionLabel({required this.title, required this.icon});

  final String title;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Row(
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
}

class _ValidationMessage extends StatelessWidget {
  const _ValidationMessage({required this.valid, required this.message});

  final bool valid;
  final String message;

  @override
  Widget build(BuildContext context) {
    final color = valid ? const Color(0xFF5CC6A3) : const Color(0xFFE58B9B);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          valid ? Icons.check_circle_outline : Icons.error_outline,
          color: color,
          size: 18,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            message,
            style: TextStyle(color: color, fontSize: 12, height: 1.35),
          ),
        ),
      ],
    );
  }
}

class _StatusStep extends StatelessWidget {
  const _StatusStep({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.isLast,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              Icon(icon, color: color, size: 24),
              if (!isLast)
                Expanded(
                  child: Container(
                    width: 1,
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    color: borderColor,
                  ),
                ),
            ],
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 20),
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
          ),
        ],
      ),
    );
  }
}
