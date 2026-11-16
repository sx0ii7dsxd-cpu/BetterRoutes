import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../main.dart';
import '../models/user_profile_model.dart';
import '../services/user_profile_service.dart';
import 'business_management_page.dart';
import 'email_change_page.dart';
import 'truck_registration_page.dart';
import 'warehouse_page.dart';

class ProfileMenu extends StatelessWidget {
  const ProfileMenu({super.key, this.onWarehousesChanged});

  final VoidCallback? onWarehousesChanged;

  static const Color _background = Color(0xFF17131F);
  static const Color _purple = Color(0xFFB39DDB);
  static const Color _text = Color(0xFFF7F5FC);
  static const Color _muted = Color(0xFFB5AEC5);
  static const Color _surface = Color(0xFF211C2B);
  static const Color _border = Color(0xFF383044);

  @override
  Widget build(BuildContext context) {
    final User? user = FirebaseAuth.instance.currentUser;

    return Scaffold(
      backgroundColor: _background,
      appBar: AppBar(
        backgroundColor: _background,
        foregroundColor: _text,
        elevation: 0,
        leading: IconButton(
          onPressed: () => Navigator.of(context).pop(),
          tooltip: 'Back to map',
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        title: const Text(
          'My Profile',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      body: user == null
          ? const Center(
              child: Text(
                'No signed-in profile found.',
                style: TextStyle(color: _muted, fontSize: 16),
              ),
            )
          : SafeArea(
              top: false,
              child: _ProfileContent(
                user: user,
                onWarehousesChanged: onWarehousesChanged,
              ),
            ),
    );
  }

  static String _displayName(User user) {
    final String name = user.displayName?.trim() ?? '';
    if (name.isNotEmpty) return name;

    final String email = user.email?.trim() ?? '';
    if (email.isNotEmpty) return email.split('@').first;

    return 'My account';
  }

  static Future<void> _signOut(BuildContext context) async {
    try {
      await FirebaseAuth.instance.signOut();
    } on FirebaseAuthException catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            error.message ?? 'Could not sign out. Please try again.',
          ),
        ),
      );
      return;
    }
    if (!context.mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const HomePage()),
      (route) => false,
    );
  }
}

class _ProfileContent extends StatefulWidget {
  const _ProfileContent({required this.user, this.onWarehousesChanged});

  final User user;
  final VoidCallback? onWarehousesChanged;

  @override
  State<_ProfileContent> createState() => _ProfileContentState();
}

class _ProfileContentState extends State<_ProfileContent> {
  final UserProfileService _profileService = UserProfileService.local();
  UserProfile? _profile;
  String? _updatedEmail;
  String? _profileError;
  bool _isLoadingProfile = true;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    try {
      final UserProfile profile = await _profileService.saveFromAuthentication(
        uid: widget.user.uid,
        displayName: widget.user.displayName,
        email: widget.user.email,
        photoUrl: widget.user.photoURL,
        providerIds: widget.user.providerData
            .map((UserInfo info) => info.providerId)
            .toList(growable: false),
      );
      if (!mounted) return;
      setState(() {
        _profile = profile;
        _profileError = null;
        _isLoadingProfile = false;
      });
    } on Exception catch (error) {
      if (!mounted) return;
      setState(() {
        _profileError = 'Local profile could not be loaded: $error';
        _isLoadingProfile = false;
      });
    }
  }

  Future<void> _changeEmail() async {
    final String? currentEmail = _updatedEmail ?? widget.user.email;
    if (currentEmail == null || currentEmail.isEmpty) return;

    final String? updatedEmail = await Navigator.of(context).push<String>(
      MaterialPageRoute<String>(
        builder: (_) => EmailChangePage(
          currentEmail: currentEmail,
          googleSignInLinked: widget.user.providerData.any(
            (UserInfo info) => info.providerId == 'google.com',
          ),
        ),
      ),
    );
    if (!mounted || updatedEmail == null) return;
    setState(() => _updatedEmail = updatedEmail);
    try {
      final UserProfile profile = await _profileService.saveFromAuthentication(
        uid: widget.user.uid,
        displayName: widget.user.displayName,
        email: updatedEmail,
        photoUrl: widget.user.photoURL,
        providerIds: widget.user.providerData
            .map((UserInfo info) => info.providerId)
            .toList(growable: false),
      );
      if (mounted) setState(() => _profile = profile);
    } on Exception catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Updated email could not be saved locally: $error'),
        ),
      );
    }
  }

  Future<void> _manageBusinesses() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => BusinessManagementPage(
          ownerUid: widget.user.uid,
          truckManagementPageBuilder: (business) => TruckRegistrationPage(
            businessIdFilter: business.id,
            businessNameFilter: business.name,
            warehouseManagementPageBuilder: () =>
                WarehousePage(onWarehousesChanged: widget.onWarehousesChanged),
          ),
        ),
      ),
    );
  }

  String get _displayName {
    final String savedName = _profile?.displayName.trim() ?? '';
    return savedName.isEmpty
        ? ProfileMenu._displayName(widget.user)
        : savedName;
  }

  String get _providerName {
    final Set<String> providerIds =
        _profile?.providerIds.toSet() ??
        widget.user.providerData
            .map((UserInfo info) => info.providerId)
            .toSet();
    if (providerIds.contains('google.com')) return 'Google';
    if (providerIds.contains('password')) return 'Email and password';
    return providerIds.isEmpty ? 'Account' : providerIds.join(', ');
  }

  @override
  Widget build(BuildContext context) {
    final String? email = _updatedEmail ?? _profile?.email ?? widget.user.email;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [ProfileMenu._surface, Color(0xFF282132)],
                  ),
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: ProfileMenu._border),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(3),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: ProfileMenu._purple.withValues(alpha: 0.65),
                          width: 1.5,
                        ),
                      ),
                      child: ProfileAvatar(user: widget.user, radius: 34),
                    ),
                    const SizedBox(width: 17),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'PROFILE OVERVIEW',
                            style: TextStyle(
                              color: ProfileMenu._purple,
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1.5,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _displayName,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: ProfileMenu._text,
                              fontSize: 20,
                              height: 1.2,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          if (email != null && email.isNotEmpty) ...[
                            const SizedBox(height: 5),
                            Text(
                              email,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: ProfileMenu._muted,
                                fontSize: 13,
                                height: 1.3,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              if (_isLoadingProfile) ...[
                const SizedBox(height: 10),
                const LinearProgressIndicator(
                  color: ProfileMenu._purple,
                  backgroundColor: ProfileMenu._border,
                ),
              ],
              if (_profileError != null) ...[
                const SizedBox(height: 12),
                Text(
                  _profileError!,
                  style: const TextStyle(
                    color: Color(0xFFE58B9B),
                    fontSize: 12,
                  ),
                ),
                TextButton(onPressed: _loadProfile, child: const Text('Retry')),
              ],
              const SizedBox(height: 28),
              const Text(
                'ACCOUNT DETAILS',
                style: TextStyle(
                  color: ProfileMenu._muted,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.4,
                ),
              ),
              const SizedBox(height: 11),
              Container(
                decoration: BoxDecoration(
                  color: ProfileMenu._surface,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: ProfileMenu._border),
                ),
                child: Column(
                  children: [
                    _ProfileDetail(
                      icon: Icons.person_outline_rounded,
                      label: 'Name',
                      value: _displayName,
                      showDivider: true,
                    ),
                    if (email != null && email.isNotEmpty)
                      _ProfileDetail(
                        icon: Icons.email_outlined,
                        label: 'Email',
                        value: email,
                        showDivider: true,
                        actionLabel: 'Change',
                        onAction: _changeEmail,
                      ),
                    _ProfileDetail(
                      icon: Icons.verified_user_outlined,
                      label: 'Sign-in method',
                      value: _providerName,
                      showDivider: false,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              OutlinedButton.icon(
                onPressed: _manageBusinesses,
                icon: const Icon(Icons.business_outlined, size: 19),
                label: const Text('Manage business profiles'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: ProfileMenu._purple,
                  side: const BorderSide(color: ProfileMenu._border),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  textStyle: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: () => ProfileMenu._signOut(context),
                icon: const Icon(Icons.logout_rounded, size: 19),
                label: const Text('Sign out'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: ProfileMenu._muted,
                  side: const BorderSide(color: ProfileMenu._border),
                  backgroundColor: ProfileMenu._surface.withValues(alpha: 0.45),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  textStyle: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class ProfileAvatar extends StatelessWidget {
  const ProfileAvatar({required this.user, required this.radius, super.key});

  final User? user;
  final double radius;

  static const Color _background = Color(0xFF17131F);
  static const Color _purple = Color(0xFFB39DDB);

  @override
  Widget build(BuildContext context) {
    final String? photoUrl = user?.photoURL?.trim().isNotEmpty == true
        ? user!.photoURL
        : user?.providerData
              .map((UserInfo info) => info.photoURL)
              .firstWhere(
                (String? url) => url?.trim().isNotEmpty == true,
                orElse: () => null,
              );
    final String initials = _initials(user);

    return CircleAvatar(
      radius: radius,
      backgroundColor: _purple,
      foregroundImage: photoUrl == null ? null : NetworkImage(photoUrl),
      child: Text(
        initials,
        style: TextStyle(
          color: _background,
          fontSize: radius * 0.63,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  static String _initials(User? user) {
    final String name = user?.displayName?.trim() ?? '';
    if (name.isNotEmpty) {
      final List<String> words = name.split(RegExp(r'\s+'));
      if (words.length > 1) {
        return '${words.first[0]}${words.last[0]}'.toUpperCase();
      }
      return name[0].toUpperCase();
    }

    final String email = user?.email?.trim() ?? '';
    return email.isNotEmpty ? email[0].toUpperCase() : 'U';
  }
}

class _ProfileDetail extends StatelessWidget {
  const _ProfileDetail({
    required this.icon,
    required this.label,
    required this.value,
    required this.showDivider,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String label;
  final String value;
  final bool showDivider;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 17, vertical: 16),
          child: Row(
            children: [
              Icon(icon, color: ProfileMenu._purple, size: 20),
              const SizedBox(width: 15),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: const TextStyle(
                        color: ProfileMenu._muted,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      value,
                      style: const TextStyle(
                        color: ProfileMenu._text,
                        fontSize: 15,
                        height: 1.25,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              if (onAction != null)
                TextButton(
                  onPressed: onAction,
                  style: TextButton.styleFrom(
                    foregroundColor: ProfileMenu._purple,
                    visualDensity: VisualDensity.compact,
                  ),
                  child: Text(actionLabel ?? 'Edit'),
                ),
            ],
          ),
        ),
        if (showDivider)
          const Divider(
            height: 1,
            thickness: 1,
            indent: 52,
            color: ProfileMenu._border,
          ),
      ],
    );
  }
}
