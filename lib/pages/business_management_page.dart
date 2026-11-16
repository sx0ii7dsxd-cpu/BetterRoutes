import 'package:flutter/material.dart';

import '../models/business_model.dart';
import '../services/business_service.dart';
import '../theme/app_colors.dart';

class BusinessManagementPage extends StatefulWidget {
  const BusinessManagementPage({
    required this.ownerUid,
    super.key,
    this.service,
    this.truckManagementPageBuilder,
  });

  final String ownerUid;
  final BusinessService? service;
  final Widget Function(Business business)? truckManagementPageBuilder;

  @override
  State<BusinessManagementPage> createState() => _BusinessManagementPageState();
}

class _BusinessManagementPageState extends State<BusinessManagementPage> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _nameController = TextEditingController();

  late final BusinessService _service =
      widget.service ?? BusinessService.local();
  List<Business> _businesses = [];
  Business? _editingBusiness;
  bool _isShowingForm = false;
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadBusinesses();
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _loadBusinesses() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final List<Business> businesses = await _service.getForOwner(
        widget.ownerUid,
      );
      if (!mounted) return;
      setState(() {
        _businesses = businesses;
        _isLoading = false;
      });
    } on Exception catch (error) {
      if (!mounted) return;
      setState(() {
        _error = 'Businesses could not be loaded: $error';
        _isLoading = false;
      });
    }
  }

  void _startCreate() {
    _nameController.clear();
    setState(() {
      _editingBusiness = null;
      _isShowingForm = true;
    });
  }

  void _startEdit(Business business) {
    _nameController.text = business.name;
    setState(() {
      _editingBusiness = business;
      _isShowingForm = true;
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    try {
      final Business? existing = _editingBusiness;
      if (existing == null) {
        await _service.create(
          ownerUid: widget.ownerUid,
          name: _nameController.text,
        );
      } else {
        await _service.update(
          ownerUid: widget.ownerUid,
          existing: existing,
          name: _nameController.text,
        );
      }
      if (!mounted) return;
      setState(() {
        _isShowingForm = false;
        _editingBusiness = null;
      });
      await _loadBusinesses();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            existing == null
                ? 'Business profile saved.'
                : 'Business profile updated.',
          ),
        ),
      );
    } on Exception catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Business could not be saved: $error')),
      );
    }
  }

  Future<void> _delete(Business business) async {
    try {
      final int truckCount = await _service.getTruckCountForOwner(
        business.id,
        widget.ownerUid,
      );
      if (!mounted) return;
      if (truckCount > 0) {
        await _showAssociatedTrucksDialog(business, truckCount);
        return;
      }
    } on BusinessHasTrucksException catch (error) {
      if (!mounted) return;
      await _showAssociatedTrucksDialog(business, error.truckCount);
      return;
    } on Exception {
      if (!mounted) return;
      _showDeleteError();
      return;
    }

    if (!mounted) return;
    final bool confirmed =
        await showDialog<bool>(
          context: context,
          builder: (BuildContext dialogContext) => AlertDialog(
            backgroundColor: surface,
            title: const Text(
              'Delete business?',
              style: TextStyle(color: textColor),
            ),
            content: Text(
              'Delete "${business.name}"? Businesses referenced by trucks '
              'cannot be deleted.',
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
      await _service.delete(business.id, widget.ownerUid);
      await _loadBusinesses();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Business profile deleted.')),
      );
    } on BusinessHasTrucksException catch (error) {
      if (!mounted) return;
      await _showAssociatedTrucksDialog(business, error.truckCount);
    } on Exception {
      if (!mounted) return;
      _showDeleteError();
    }
  }

  Future<void> _showAssociatedTrucksDialog(
    Business business,
    int truckCount,
  ) async {
    final bool manageTrucks =
        await showDialog<bool>(
          context: context,
          builder: (BuildContext dialogContext) => AlertDialog(
            backgroundColor: surface,
            title: const Text(
              'Business cannot be deleted',
              style: TextStyle(color: textColor),
            ),
            content: Text(
              '"${business.name}" has $truckCount associated '
              '${truckCount == 1 ? 'truck' : 'trucks'}. Reassign or delete '
              'those trucks before deleting this business.',
              style: const TextStyle(color: mutedColor, height: 1.4),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Close'),
              ),
              ElevatedButton.icon(
                onPressed: widget.truckManagementPageBuilder == null
                    ? null
                    : () => Navigator.pop(dialogContext, true),
                icon: const Icon(Icons.local_shipping_outlined),
                label: const Text('Manage trucks'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: purple,
                  foregroundColor: background,
                ),
              ),
            ],
          ),
        ) ??
        false;
    final Widget Function(Business business)? pageBuilder =
        widget.truckManagementPageBuilder;
    if (!manageTrucks || !mounted || pageBuilder == null) return;

    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(builder: (_) => pageBuilder(business)),
    );
    if (mounted) await _loadBusinesses();
  }

  void _showDeleteError() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Business could not be deleted. Please try again.'),
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
        title: const Text(
          'Business profiles',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      body: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: _isShowingForm ? _buildForm() : _buildList(),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildList() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Add the business name used to group your trucks. Your Firebase '
          'account owns each business profile.',
          style: TextStyle(color: mutedColor, height: 1.45),
        ),
        const SizedBox(height: 18),
        SizedBox(
          height: 52,
          child: ElevatedButton.icon(
            onPressed: _startCreate,
            icon: const Icon(Icons.add_business_rounded),
            label: const Text('Add Business'),
            style: _primaryButtonStyle(),
          ),
        ),
        const SizedBox(height: 18),
        if (_isLoading)
          const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: CircularProgressIndicator(color: purple),
            ),
          )
        else if (_error case final String error)
          _ErrorCard(message: error, onRetry: _loadBusinesses)
        else if (_businesses.isEmpty)
          const _EmptyBusinesses()
        else
          ..._businesses.map(_buildBusinessCard),
      ],
    );
  }

  Widget _buildBusinessCard(Business business) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: surface,
        border: Border.all(color: borderColor),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          const Icon(Icons.business_rounded, color: purple, size: 25),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  business.name,
                  style: const TextStyle(
                    color: textColor,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Owned by this Firebase account',
                  style: TextStyle(color: mutedColor, fontSize: 12),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: () => _startEdit(business),
            tooltip: 'Edit business',
            icon: const Icon(Icons.edit_outlined, color: purple),
          ),
          IconButton(
            onPressed: () => _delete(business),
            tooltip: 'Delete business',
            icon: const Icon(
              Icons.delete_outline_rounded,
              color: Color(0xFFE58B9B),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildForm() {
    final bool isEditing = _editingBusiness != null;
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            isEditing ? 'Edit business name' : 'Add a business',
            style: const TextStyle(
              color: textColor,
              fontSize: 22,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Only the business name is stored because no broader business '
            'schema is defined in the project yet.',
            style: TextStyle(color: mutedColor, height: 1.4),
          ),
          const SizedBox(height: 20),
          TextFormField(
            controller: _nameController,
            autofocus: true,
            validator: (String? value) => value == null || value.trim().isEmpty
                ? 'Enter a business name.'
                : null,
            style: const TextStyle(color: textColor),
            cursorColor: purple,
            decoration: InputDecoration(
              labelText: 'Business name',
              labelStyle: const TextStyle(color: mutedColor),
              prefixIcon: const Icon(Icons.business_outlined, color: purple),
              filled: true,
              fillColor: surface,
              border: _inputBorder(),
              enabledBorder: _inputBorder(),
              focusedBorder: _inputBorder(color: purple),
              errorBorder: _inputBorder(color: const Color(0xFFE58B9B)),
              focusedErrorBorder: _inputBorder(color: const Color(0xFFE58B9B)),
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            height: 52,
            child: ElevatedButton.icon(
              onPressed: _save,
              icon: const Icon(Icons.save_rounded),
              label: Text(isEditing ? 'Save Changes' : 'Save Business'),
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
}

class _EmptyBusinesses extends StatelessWidget {
  const _EmptyBusinesses();

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(22),
    decoration: BoxDecoration(
      color: surface,
      border: Border.all(color: borderColor),
      borderRadius: BorderRadius.circular(18),
    ),
    child: const Text(
      'No business profiles yet. Add one before registering a truck.',
      textAlign: TextAlign.center,
      style: TextStyle(color: mutedColor, height: 1.4),
    ),
  );
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
