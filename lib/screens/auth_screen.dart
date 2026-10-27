import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../pages/map_page.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _isCreatingAccount = false;
  bool _obscurePassword = true;
  bool _isLoading = false;
  String? _authMessage;

  static const Color background = Color(0xFF17131F);
  static const Color purple = Color(0xFFB39DDB);
  static const Color textColor = Color(0xFFF7F5FC);
  static const Color mutedColor = Color(0xFFB5AEC5);

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _showMessage(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _authenticate() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      final auth = FirebaseAuth.instance;

      if (_isCreatingAccount) {
        final credential = await auth.createUserWithEmailAndPassword(
          email: _emailController.text.trim(),
          password: _passwordController.text,
        );
        final name = _nameController.text.trim();
        if (name.isNotEmpty) {
          await credential.user?.updateDisplayName(name);
        }
      } else {
        await auth.signInWithEmailAndPassword(
          email: _emailController.text.trim(),
          password: _passwordController.text,
        );
      }

      if (!mounted) return;
      _showMessage('Authentication successful!');
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const MapPage()),
        (route) => false,
      );
    } on FirebaseAuthException catch (e) {
      if ((e.code == 'user-not-found' || e.code == 'invalid-credential') &&
          !_isCreatingAccount &&
          mounted) {
        setState(() {
          _isCreatingAccount = true;
          _authMessage =
              'This email does not have an account. Create one below.';
        });
        return;
      }
      if (e.code == 'email-already-in-use' && _isCreatingAccount && mounted) {
        setState(() {
          _isCreatingAccount = false;
          _authMessage = 'This email already has an account. Sign in below.';
        });
        return;
      }
      _showMessage(_firebaseErrorMessage(e.code));
    } catch (_) {
      _showMessage('Something went wrong. Please try again.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _resetEmailFlow() {
    setState(() {
      _isCreatingAccount = false;
      _authMessage = null;
      _nameController.clear();
      _passwordController.clear();
      _formKey.currentState?.reset();
    });
  }

  String _firebaseErrorMessage(String code) {
    switch (code) {
      case 'invalid-email':
        return 'Please enter a valid email address.';
      case 'user-not-found':
      case 'wrong-password':
      case 'invalid-credential':
        return 'Incorrect email or password.';
      case 'email-already-in-use':
        return 'An account already exists with this email.';
      case 'weak-password':
        return 'Please choose a stronger password.';
      case 'too-many-requests':
        return 'Too many attempts. Please try again later.';
      case 'network-request-failed':
        return 'Check your internet connection.';
      default:
        return 'Authentication failed. Please try again.';
    }
  }

  Future<void> _signInWithGoogle() async {
    setState(() => _isLoading = true);

    try {
      final googleSignIn = GoogleSignIn.instance;

      await googleSignIn.initialize(
        serverClientId: "698588431992-5u8rc9ptv8g2tl87eiljt2rrnagcplb5.apps.googleusercontent.com",
      );

      final googleUser = await googleSignIn.authenticate();

      final googleAuth = googleUser.authentication;

      final credential = GoogleAuthProvider.credential(
        idToken: googleAuth.idToken,
      );

      await FirebaseAuth.instance.signInWithCredential(credential);

      if (!mounted) return;

      _showMessage('Google sign-in successful!');
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const MapPage()),
        (route) => false,
      );
    } on FirebaseAuthException catch (e) {
      _showMessage(_firebaseErrorMessage(e.code));
    } catch (_) {
      _showMessage(
        'Google sign-in could not be completed. Check your configuration.',
      );
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _resetPassword() async {
    final email = _emailController.text.trim();

    if (email.isEmpty ||
        !RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) {
      _showMessage('Enter your email address first.');
      return;
    }

    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: email);

      if (!mounted) return;

      _showMessage('Password reset email sent. Check your inbox.');
    } on FirebaseAuthException catch (e) {
      _showMessage(_firebaseErrorMessage(e.code));
    } catch (_) {
      _showMessage('Could not send the reset email. Please try again.');
    }
  }

  Widget _textField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    TextInputType keyboardType = TextInputType.text,
    bool password = false,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      obscureText: password && _obscurePassword,
      style: const TextStyle(color: textColor),
      validator: validator,
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: mutedColor),
        prefixIcon: Icon(icon, color: purple),
        suffixIcon: password
            ? IconButton(
                icon: Icon(
                  _obscurePassword
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                  color: mutedColor,
                ),
                onPressed: () {
                  setState(() => _obscurePassword = !_obscurePassword);
                },
              )
            : null,
        filled: true,
        fillColor: const Color(0xFF211C2B),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Color(0xFF383044)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: purple, width: 1.5),
        ),
        errorStyle: const TextStyle(color: Color(0xFFFF8A80)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: background,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 28),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                      child: Image.asset(
                        'assets/images/BetterRoutes.png',
                        width: 86,
                        height: 86,
                        fit: BoxFit.contain,
                      ),
                    ),
                    const SizedBox(height: 22),
                    const Text(
                      'Welcome to BetterRoutes',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: textColor,
                        fontSize: 27,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 9),
                    const Text(
                      'Every journey, made better.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: mutedColor, fontSize: 15),
                    ),
                    const SizedBox(height: 32),
                    OutlinedButton.icon(
                      onPressed: _isLoading ? null : _signInWithGoogle,
                      icon: const Icon(
                        Icons.g_mobiledata,
                        size: 30,
                        color: textColor,
                      ),
                      label: const Text('Continue with Google'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: textColor,
                        side: const BorderSide(color: Color(0xFF494052)),
                        minimumSize: const Size.fromHeight(54),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    const Row(
                      children: [
                        Expanded(child: Divider(color: Color(0xFF383044))),
                        Padding(
                          padding: EdgeInsets.symmetric(horizontal: 14),
                          child: Text(
                            'OR CONTINUE WITH EMAIL',
                            style: TextStyle(color: mutedColor, fontSize: 12),
                          ),
                        ),
                        Expanded(child: Divider(color: Color(0xFF383044))),
                      ],
                    ),
                    const SizedBox(height: 24),
                    if (_authMessage != null) ...[
                      Text(
                        _authMessage!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: textColor, fontSize: 13),
                      ),
                      const SizedBox(height: 12),
                    ],
                    _textField(
                      controller: _emailController,
                      label: 'Email address',
                      icon: Icons.email_outlined,
                      keyboardType: TextInputType.emailAddress,
                      validator: (value) {
                        if (value == null ||
                            !RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$')
                                .hasMatch(value.trim())) {
                          return 'Enter a valid email address.';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    if (_isCreatingAccount) ...[
                      _textField(
                        controller: _nameController,
                        label: 'Full name',
                        icon: Icons.person_outline,
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Enter your name to create an account.';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),
                    ],
                    _textField(
                      controller: _passwordController,
                      label: 'Password',
                      icon: Icons.lock_outline,
                      password: true,
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Please enter your password.';
                        }
                        if (_isCreatingAccount && value.length < 6) {
                          return 'Use at least 6 characters.';
                        }
                        return null;
                      },
                    ),
                    if (!_isCreatingAccount)
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          onPressed: _isLoading ? null : _resetPassword,
                          child: const Text(
                            'Forgot password?',
                            style: TextStyle(color: purple),
                          ),
                        ),
                      ),
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 54,
                      child: ElevatedButton(
                        onPressed: _isLoading ? null : _authenticate,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: purple,
                          foregroundColor: background,
                          disabledBackgroundColor: purple.withValues(
                            alpha: 0.5,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        child: _isLoading
                            ? const SizedBox(
                                width: 23,
                                height: 23,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : Text(
                                _isCreatingAccount
                                    ? 'Create Account'
                                    : 'Sign in',
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (!_isCreatingAccount)
                      TextButton(
                        onPressed: _isLoading
                            ? null
                            : () {
                                setState(() {
                                  _isCreatingAccount = true;
                                  _authMessage = null;
                                  _passwordController.clear();
                                });
                              },
                        child: const Text(
                          'Create a new account',
                          style: TextStyle(color: purple),
                        ),
                      ),
                    if (_isCreatingAccount)
                      TextButton(
                        onPressed: _isLoading ? null : _resetEmailFlow,
                        child: const Text(
                          'Use a different email',
                          style: TextStyle(color: purple),
                        ),
                      ),
                    Text(
                      _isCreatingAccount
                          ? 'Create an account with your email and password.'
                          : 'Enter your password to sign in.',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: mutedColor, fontSize: 13),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
