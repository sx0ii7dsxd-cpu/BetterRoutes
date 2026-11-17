import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../main.dart';
import 'email_change_page.dart';
import 'phase2_identity_page.dart';

class ProfileMenu extends StatelessWidget {
  const ProfileMenu({super.key});

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
          : SafeArea(top: false, child: _ProfileContent(user: user)),
    );
  }

  static String _displayName(User user) {
    final String name = user.displayName?.trim() ?? '';
    if (name.isNotEmpty) return name;

    final String email = user.email?.trim() ?? '';
    if (email.isNotEmpty) return email.split('@').first;

    return 'My account';
  }

  static String _providerName(User user) {
    final Set<String> providerIds = user.providerData
        .map((UserInfo info) => info.providerId)
        .toSet();
    if (providerIds.contains('google.com')) return 'Google';
    if (providerIds.contains('password')) return 'Email and password';
    return providerIds.isEmpty ? 'Account' : providerIds.join(', ');
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
  const _ProfileContent({required this.user});

  final User user;

  @override
  State<_ProfileContent> createState() => _ProfileContentState();
}

class _ProfileContentState extends State<_ProfileContent> {
  String? _updatedEmail;
  bool _isAdmin = false;

  @override
  void initState() {
    super.initState();
    _loadAdminClaim();
  }

  Future<void> _loadAdminClaim() async {
    try {
      final result = await widget.user.getIdTokenResult(true);
      if (mounted) {
        setState(() => _isAdmin = result.claims?['admin'] == true);
      }
    } on FirebaseAuthException {
      if (mounted) setState(() => _isAdmin = false);
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
  }

  @override
  Widget build(BuildContext context) {
    final String? email = _updatedEmail ?? widget.user.email;
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
                            ProfileMenu._displayName(widget.user),
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
                      value: ProfileMenu._displayName(widget.user),
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
                      value: ProfileMenu._providerName(widget.user),
                      showDivider: false,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              OutlinedButton.icon(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const IdentityManagementPage(),
                  ),
                ),
                icon: const Icon(Icons.badge_outlined, size: 19),
                label: const Text('Identity management'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: ProfileMenu._purple,
                  side: const BorderSide(color: ProfileMenu._border),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
              ),
              if (_isAdmin) ...[
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const AdminConsolePage(),
                    ),
                  ),
                  icon: const Icon(
                    Icons.admin_panel_settings_outlined,
                    size: 19,
                  ),
                  label: const Text('Administrator console'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: ProfileMenu._purple,
                    side: const BorderSide(color: ProfileMenu._border),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                ),
              ],
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
