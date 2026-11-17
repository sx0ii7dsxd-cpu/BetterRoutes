import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../models/approved_truck_model.dart';
import '../services/trusted_operations_service.dart';
import 'map_page.dart';

class IdentityManagementPage extends StatefulWidget {
  const IdentityManagementPage({super.key});

  @override
  State<IdentityManagementPage> createState() => _IdentityManagementPageState();
}

class _IdentityManagementPageState extends State<IdentityManagementPage> {
  final TrustedOperationsService _service = TrustedOperationsService();
  late Future<_IdentityData> _data;

  @override
  void initState() {
    super.initState();
    _data = _load();
  }

  @override
  void dispose() {
    _service.dispose();
    super.dispose();
  }

  Future<_IdentityData> _load() async {
    final results = await Future.wait([
      _service.listActiveTrucks(),
      _service.listOwnRequests(),
      _service.listInvitations(),
    ]);
    return _IdentityData(
      trucks: results[0] as List<ApprovedTruckModel>,
      requests: results[1] as Map<String, Object?>,
      invitations: results[2] as List<Map<String, Object?>>,
    );
  }

  void _refresh() => setState(() => _data = _load());

  Future<void> _requestOwnership() async {
    final truckId = await _textDialog(
      title: 'Request truck ownership',
      label: 'Approved truck ID',
    );
    if (!mounted || truckId == null || truckId.trim().isEmpty) return;
    try {
      await _service.requestTruckOwnership(truckId.trim());
      if (!mounted) return;
      _showMessage('Ownership request submitted for review.');
      _refresh();
    } catch (error) {
      if (mounted) _showMessage(error.toString());
    }
  }

  Future<void> _acceptInvitation() async {
    final token = await _textDialog(
      title: 'Accept invitation',
      label: 'Invitation token',
      obscureText: true,
    );
    if (!mounted || token == null || token.trim().isEmpty) return;
    try {
      await _service.acceptInvitation(token.trim());
      if (!mounted) return;
      _showMessage('Invitation accepted.');
      _refresh();
    } catch (error) {
      if (mounted) _showMessage(error.toString());
    }
  }

  Future<void> _createInvitation() async {
    final values = await _invitationDialog();
    if (!mounted || values == null) return;
    try {
      final result = values.role == 'driver'
          ? await _service.createDriverInvitation(
              truckId: values.resourceId,
              targetUid: values.targetUid,
            )
          : await _service.createParticipantInvitation(
              shipmentId: values.resourceId,
              targetUid: values.targetUid,
              role: values.role,
            );
      if (!mounted) return;
      final token = result['token'];
      _showMessage(
        token is String
            ? 'Invitation created. Share this one-time token: $token'
            : 'Invitation created.',
      );
      _refresh();
    } catch (error) {
      if (mounted) _showMessage(error.toString());
    }
  }

  Future<String?> _textDialog({
    required String title,
    required String label,
    bool obscureText = false,
  }) async {
    final controller = TextEditingController();
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          obscureText: obscureText,
          autofocus: true,
          decoration: InputDecoration(labelText: label),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Continue'),
          ),
        ],
      ),
    );
    controller.dispose();
    return value;
  }

  Future<_InvitationInput?> _invitationDialog() async {
    final resourceController = TextEditingController();
    final targetController = TextEditingController();
    String role = 'driver';
    final value = await showDialog<_InvitationInput>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Create invitation'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                initialValue: role,
                items: const [
                  DropdownMenuItem(value: 'driver', child: Text('Driver')),
                  DropdownMenuItem(value: 'customer', child: Text('Customer')),
                  DropdownMenuItem(value: 'receiver', child: Text('Receiver')),
                ],
                onChanged: (value) =>
                    setDialogState(() => role = value ?? 'driver'),
                decoration: const InputDecoration(labelText: 'Role'),
              ),
              TextField(
                controller: resourceController,
                decoration: InputDecoration(
                  labelText: role == 'driver' ? 'Truck ID' : 'Shipment ID',
                ),
              ),
              TextField(
                controller: targetController,
                decoration: const InputDecoration(
                  labelText: 'Target Firebase UID',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(
                context,
                _InvitationInput(
                  role: role,
                  resourceId: resourceController.text.trim(),
                  targetUid: targetController.text.trim(),
                ),
              ),
              child: const Text('Create'),
            ),
          ],
        ),
      ),
    );
    resourceController.dispose();
    targetController.dispose();
    return value;
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: background,
      appBar: AppBar(
        backgroundColor: background,
        foregroundColor: textColor,
        title: const Text('Identity management'),
        actions: [
          IconButton(onPressed: _refresh, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: FutureBuilder<_IdentityData>(
        future: _data,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return _Message(
              message: snapshot.error.toString(),
              onRetry: _refresh,
            );
          }
          final data = snapshot.data!;
          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              _Heading(
                title: 'Approved trucks',
                subtitle: 'Only trusted backend records appear here.',
              ),
              if (data.trucks.isEmpty)
                const _Empty(text: 'No approved trucks are linked to you.')
              else
                ...data.trucks.map(_TruckCard.new),
              const SizedBox(height: 18),
              _Heading(
                title: 'Ownership requests',
                subtitle: 'Approval is performed by an administrator.',
              ),
              ..._requestCards(data.requests['ownershipRequests']),
              const SizedBox(height: 18),
              _Heading(
                title: 'Invitations',
                subtitle: 'Tokens are single-use and expire.',
              ),
              if (data.invitations.isEmpty)
                const _Empty(text: 'No invitations found.')
              else
                ...data.invitations.map(
                  (invitation) => _MapCard(data: invitation),
                ),
              const SizedBox(height: 18),
              OutlinedButton.icon(
                onPressed: _requestOwnership,
                icon: const Icon(Icons.verified_user_outlined),
                label: const Text('Request truck ownership'),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: _acceptInvitation,
                icon: const Icon(Icons.how_to_reg_outlined),
                label: const Text('Accept invitation'),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: _createInvitation,
                icon: const Icon(Icons.person_add_alt_1_outlined),
                label: const Text('Create driver or participant invitation'),
              ),
            ],
          );
        },
      ),
    );
  }

  List<Widget> _requestCards(Object? value) {
    if (value is! List || value.isEmpty) {
      return const [_Empty(text: 'No ownership requests found.')];
    }
    return value
        .whereType<Map>()
        .map((item) => _MapCard(data: Map<String, Object?>.from(item)))
        .toList();
  }
}

class AdminConsolePage extends StatefulWidget {
  const AdminConsolePage({super.key});

  @override
  State<AdminConsolePage> createState() => _AdminConsolePageState();
}

class _AdminConsolePageState extends State<AdminConsolePage> {
  final TrustedOperationsService _service = TrustedOperationsService();
  bool? _isAdmin;
  bool _loading = true;
  String? _error;
  List<Map<String, Object?>> _pending = const [];
  List<ApprovedTruckModel> _approved = const [];
  List<Map<String, Object?>> _ownership = const [];
  List<Map<String, Object?>> _invitations = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _service.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      final result = user == null ? null : await user.getIdTokenResult(true);
      final isAdmin = result?.claims?['admin'] == true;
      if (!isAdmin) {
        if (mounted) setState(() => _isAdmin = false);
        return;
      }
      final values = await Future.wait([
        _service.listPendingTruckRequests(),
        _service.listApprovedTrucks(),
        _service.listOwnershipRequests(),
        _service.listAllInvitations(),
      ]);
      if (!mounted) return;
      setState(() {
        _isAdmin = true;
        _pending = values[0] as List<Map<String, Object?>>;
        _approved = values[1] as List<ApprovedTruckModel>;
        _ownership = values[2] as List<Map<String, Object?>>;
        _invitations = values[3] as List<Map<String, Object?>>;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.toString();
      });
    }
  }

  Future<void> _action(String action, Map<String, Object?> data) async {
    try {
      await _service.adminAction(action, data);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Administrator action completed.')),
      );
      setState(() {
        _loading = true;
        _error = null;
      });
      await _load();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.toString())));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        backgroundColor: background,
        appBar: AppBar(backgroundColor: background, title: const Text('Admin')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    if (_isAdmin != true) {
      return Scaffold(
        backgroundColor: background,
        appBar: AppBar(backgroundColor: background, title: const Text('Admin')),
        body: const _Empty(text: 'Administrator access is required.'),
      );
    }
    if (_error != null) {
      return Scaffold(
        backgroundColor: background,
        appBar: AppBar(backgroundColor: background, title: const Text('Admin')),
        body: _Message(message: _error!, onRetry: _load),
      );
    }
    return Scaffold(
      backgroundColor: background,
      appBar: AppBar(
        backgroundColor: background,
        foregroundColor: textColor,
        title: const Text('Administrator console'),
        actions: [
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          _Heading(
            title: 'Pending truck requests',
            subtitle: 'Approval creates a separate trusted truck record.',
          ),
          if (_pending.isEmpty)
            const _Empty(text: 'No pending truck requests.')
          else
            ..._pending.map(
              (request) => _AdminRequestCard(
                data: request,
                onApprove: () => _action('approve-truck', {
                  'requestId': request['requestId'] ?? request['id'],
                }),
                onReject: () => _action('reject-truck', {
                  'requestId': request['requestId'] ?? request['id'],
                }),
              ),
            ),
          const SizedBox(height: 18),
          _Heading(
            title: 'Ownership requests',
            subtitle: 'Ownership is never inferred from registration requests.',
          ),
          if (_ownership.isEmpty)
            const _Empty(text: 'No pending ownership requests.')
          else
            ..._ownership.map(
              (request) => _AdminRequestCard(
                data: request,
                onApprove: () => _action('truck-ownership-decision', {
                  'requestId': request['requestId'] ?? request['id'],
                  'status': 'approved',
                }),
                onReject: () => _action('truck-ownership-decision', {
                  'requestId': request['requestId'] ?? request['id'],
                  'status': 'revoked',
                }),
              ),
            ),
          const SizedBox(height: 18),
          _Heading(
            title: 'Approved trucks',
            subtitle: 'Suspension and revocation remain backend-only.',
          ),
          ..._approved.map(
            (truck) => _TruckCard(
              truck,
              trailing: PopupMenuButton<String>(
                onSelected: (status) => _action('truck-status', {
                  'truckId': truck.truckId,
                  'status': status,
                }),
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'active', child: Text('Activate')),
                  PopupMenuItem(value: 'suspended', child: Text('Suspend')),
                  PopupMenuItem(value: 'revoked', child: Text('Revoke')),
                ],
              ),
            ),
          ),
          const SizedBox(height: 18),
          _Heading(
            title: 'Assignments and participants',
            subtitle: 'Invitation records contain no raw token secrets.',
          ),
          if (_invitations.isEmpty)
            const _Empty(text: 'No invitation records found.')
          else
            ..._invitations.map((invitation) => _MapCard(data: invitation)),
        ],
      ),
    );
  }
}

class _IdentityData {
  const _IdentityData({
    required this.trucks,
    required this.requests,
    required this.invitations,
  });

  final List<ApprovedTruckModel> trucks;
  final Map<String, Object?> requests;
  final List<Map<String, Object?>> invitations;
}

class _InvitationInput {
  const _InvitationInput({
    required this.role,
    required this.resourceId,
    required this.targetUid,
  });

  final String role;
  final String resourceId;
  final String targetUid;
}

class _Heading extends StatelessWidget {
  const _Heading({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: textColor,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(subtitle, style: const TextStyle(color: mutedColor)),
        ],
      ),
    );
  }
}

class _TruckCard extends StatelessWidget {
  const _TruckCard(this.truck, {this.trailing});

  final ApprovedTruckModel truck;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: surface,
      child: ListTile(
        leading: const Icon(Icons.local_shipping_outlined, color: purple),
        title: Text(
          truck.registrationNumber,
          style: const TextStyle(color: textColor),
        ),
        subtitle: Text(
          '${truck.truckType} · ${truck.capacity} ${truck.capacityUnit ?? ''}\n'
          'Owner: ${truck.ownerUid ?? 'Unverified'} · '
          'Driver: ${truck.driverUid ?? 'Unassigned'}',
          style: const TextStyle(color: mutedColor),
        ),
        trailing: trailing,
      ),
    );
  }
}

class _AdminRequestCard extends StatelessWidget {
  const _AdminRequestCard({
    required this.data,
    required this.onApprove,
    required this.onReject,
  });

  final Map<String, Object?> data;
  final VoidCallback onApprove;
  final VoidCallback onReject;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: surface,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _MapCard(data: data),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(onPressed: onReject, child: const Text('Reject')),
                FilledButton(
                  onPressed: onApprove,
                  child: const Text('Approve'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _MapCard extends StatelessWidget {
  const _MapCard({required this.data});

  final Map<String, Object?> data;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: surface,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Text(
          data.entries
              .where((entry) => entry.key != 'tokenHash')
              .map((entry) => '${entry.key}: ${entry.value ?? '—'}')
              .join('\n'),
          style: const TextStyle(color: mutedColor, height: 1.4),
        ),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Text(text, style: const TextStyle(color: mutedColor)),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: mutedColor),
            ),
            const SizedBox(height: 12),
            OutlinedButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}
