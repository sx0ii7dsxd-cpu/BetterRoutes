import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../main.dart';

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
          : SafeArea(
              top: false,
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 480),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const SizedBox(height: 32),
                        Center(child: ProfileAvatar(user: user, radius: 54)),
                        const SizedBox(height: 20),
                        Text(
                          _displayName(user),
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: _text,
                            fontSize: 26,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        if (user.email != null && user.email!.isNotEmpty) ...[
                          const SizedBox(height: 7),
                          Text(
                            user.email!,
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: _muted, fontSize: 15),
                          ),
                        ],
                        const SizedBox(height: 34),
                        _ProfileDetail(
                          icon: Icons.person_outline_rounded,
                          label: 'Name',
                          value: _displayName(user),
                        ),
                        if (user.email != null && user.email!.isNotEmpty)
                          _ProfileDetail(
                            icon: Icons.email_outlined,
                            label: 'Email',
                            value: user.email!,
                          ),
                        _ProfileDetail(
                          icon: Icons.verified_user_outlined,
                          label: 'Sign-in method',
                          value: _providerName(user),
                        ),
                        const SizedBox(height: 28),
                        OutlinedButton.icon(
                          onPressed: () => _signOut(context),
                          icon: const Icon(Icons.logout_rounded),
                          label: const Text('Sign out'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: _text,
                            side: const BorderSide(color: _border),
                            padding: const EdgeInsets.symmetric(vertical: 15),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
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
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
      decoration: BoxDecoration(
        color: ProfileMenu._surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: ProfileMenu._border),
      ),
      child: Row(
        children: [
          Icon(icon, color: ProfileMenu._purple, size: 21),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    color: ProfileMenu._muted,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: const TextStyle(
                    color: ProfileMenu._text,
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
