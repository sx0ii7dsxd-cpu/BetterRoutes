import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'email_change_service.dart';

class EmailChangePage extends StatefulWidget {
  const EmailChangePage({
    required this.currentEmail,
    required this.googleSignInLinked,
    super.key,
  });

  final String currentEmail;
  final bool googleSignInLinked;

  @override
  State<EmailChangePage> createState() => _EmailChangePageState();
}

class _EmailChangePageState extends State<EmailChangePage> {
  static const Color _background = Color(0xFF17131F);
  static const Color _surface = Color(0xFF211C2B);
  static const Color _surfaceRaised = Color(0xFF292334);
  static const Color _purple = Color(0xFFB39DDB);
  static const Color _text = Color(0xFFF7F5FC);
  static const Color _muted = Color(0xFFB5AEC5);
  static const Color _border = Color(0xFF383044);

  static final RegExp _emailPattern = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');

  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _codeController = TextEditingController();
  late final EmailChangeService _emailChangeService = EmailChangeService();
  EmailChangeStatus _status = const EmailChangeStatus(
    stage: EmailChangeStage.idle,
  );
  bool _isWorking = true;
  String? _errorMessage;
  String? _noticeMessage;

  @override
  void initState() {
    super.initState();
    unawaited(_loadStatus());
  }

  @override
  void dispose() {
    _emailController.dispose();
    _codeController.dispose();
    _emailChangeService.dispose();
    super.dispose();
  }

  Future<void> _loadStatus() async {
    setState(() {
      _isWorking = true;
      _errorMessage = null;
    });
    try {
      final EmailChangeStatus status = await _emailChangeService.getStatus();
      await _receiveStatus(status);
    } on EmailChangeApiException catch (error) {
      _setApiError(error, fallback: 'Could not load email-change status.');
    } on FirebaseException catch (error) {
      _setError(error.message ?? 'Could not connect to your account.');
    } on FormatException catch (error) {
      _setError(error.message);
    } finally {
      if (mounted) setState(() => _isWorking = false);
    }
  }

  Future<void> _runAction(
    Future<EmailChangeStatus> Function() action, {
    String? notice,
  }) async {
    if (_isWorking) return;
    setState(() {
      _isWorking = true;
      _errorMessage = null;
      _noticeMessage = null;
    });
    try {
      final EmailChangeStatus status = await action();
      await _receiveStatus(status, notice: notice);
    } on EmailChangeApiException catch (error) {
      _setApiError(error, fallback: 'Could not complete the email change.');
    } on FirebaseException catch (error) {
      _setError(error.message ?? 'Could not connect to your account.');
    } on FormatException catch (error) {
      _setError(error.message);
    } finally {
      if (mounted) setState(() => _isWorking = false);
    }
  }

  Future<void> _receiveStatus(
    EmailChangeStatus status, {
    String? notice,
  }) async {
    if (status.stage == EmailChangeStage.complete) {
      await _finish(status.email ?? _status.newEmail);
      return;
    }
    if (_status.stage != status.stage) _codeController.clear();
    if (!mounted) return;
    setState(() {
      _status = status;
      _errorMessage = null;
      _noticeMessage = notice;
    });
  }

  Future<void> _finish(String? email) async {
    if (email == null || email.isEmpty) {
      throw const FormatException(
        'The updated email address was not returned.',
      );
    }
    final User? user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      try {
        await user.reload();
        await user.getIdToken(true);
      } on FirebaseAuthException catch (error) {
        debugPrint(
          'Email changed, but refreshing the signed-in user failed '
          '(${error.code}): ${error.message}',
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Email changed. Your profile will refresh when you reopen it.',
              ),
            ),
          );
        }
      }
    }
    if (mounted) Navigator.of(context).pop(email);
  }

  void _setError(String message) {
    if (!mounted) return;
    setState(() {
      _errorMessage = message;
      _noticeMessage = null;
    });
  }

  void _setApiError(EmailChangeApiException error, {required String fallback}) {
    final Object? rawAttempts = error.details['attemptsRemaining'];
    if (rawAttempts is num && mounted) {
      setState(() {
        _status = _status.copyWith(attemptsRemaining: rawAttempts.toInt());
        _errorMessage = error.message.isNotEmpty ? error.message : fallback;
        _noticeMessage = null;
      });
      return;
    }
    _setError(error.message.isNotEmpty ? error.message : fallback);
  }

  Future<void> _startChange() async {
    if (!_formKey.currentState!.validate()) return;
    await _runAction(
      () => _emailChangeService.start(_emailController.text.trim()),
      notice: 'A verification code was sent to your current email.',
    );
  }

  Future<void> _verifyCode() async {
    final String code = _codeController.text.trim();
    if (code.length != 6) {
      _setError('Enter the six-digit code from the email.');
      return;
    }
    if (_status.stage == EmailChangeStage.verifyOld) {
      await _runAction(() => _emailChangeService.verifyOldCode(code));
    }
  }

  Future<void> _resendCode() async {
    await _runAction(
      _emailChangeService.resendCode,
      notice: 'A new verification code was sent.',
    );
    if (mounted && _errorMessage == null) _codeController.clear();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _background,
      appBar: AppBar(
        backgroundColor: _background,
        foregroundColor: _text,
        elevation: 0,
        title: const Text(
          'Change email',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      body: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildIntroCard(),
                  if (widget.googleSignInLinked) ...[
                    const SizedBox(height: 12),
                    _buildInfoCard(
                      icon: Icons.info_outline_rounded,
                      message:
                          'This changes the email on your BetterRoutes account. '
                          'Google sign-in will stay connected to your current Google account.',
                    ),
                  ],
                  const SizedBox(height: 24),
                  if (_isWorking && _status.stage == EmailChangeStage.idle)
                    const Center(
                      child: Padding(
                        padding: EdgeInsets.all(28),
                        child: CircularProgressIndicator(color: _purple),
                      ),
                    )
                  else
                    _buildCurrentStep(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildIntroCard() {
    return Container(
      padding: const EdgeInsets.all(19),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [_surface, Color(0xFF282132)],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _border),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.mark_email_read_outlined, color: _purple, size: 23),
          SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Verify your current email',
                  style: TextStyle(
                    color: _text,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                SizedBox(height: 6),
                Text(
                  "We'll send one code to your current email. Once verified, your BetterRoutes email will be updated.",
                  style: TextStyle(color: _muted, fontSize: 13, height: 1.45),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoCard({required IconData icon, required String message}) {
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: _surfaceRaised,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: _purple, size: 19),
          const SizedBox(width: 11),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(color: _muted, fontSize: 12, height: 1.45),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCurrentStep() {
    final Widget step = switch (_status.stage) {
      EmailChangeStage.idle => _buildNewEmailForm(),
      EmailChangeStage.verifyOld => _buildVerificationStep(),
      EmailChangeStage.updating => _buildUpdatingStep(),
      EmailChangeStage.complete => const SizedBox.shrink(),
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_noticeMessage != null) ...[
          _buildInfoCard(
            icon: Icons.check_circle_outline_rounded,
            message: _noticeMessage!,
          ),
          const SizedBox(height: 14),
        ],
        if (_errorMessage != null) ...[
          _buildInfoCard(
            icon: Icons.error_outline_rounded,
            message: _errorMessage!,
          ),
          const SizedBox(height: 14),
        ],
        step,
      ],
    );
  }

  Widget _buildNewEmailForm() {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildSectionLabel('NEW EMAIL ADDRESS'),
          const SizedBox(height: 10),
          TextFormField(
            controller: _emailController,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.done,
            autocorrect: false,
            enableSuggestions: false,
            style: const TextStyle(color: _text, fontSize: 15),
            validator: (String? value) {
              final String email = value?.trim() ?? '';
              if (email.isEmpty || !_emailPattern.hasMatch(email)) {
                return 'Enter a valid email address.';
              }
              if (email.toLowerCase() == widget.currentEmail.toLowerCase()) {
                return 'Enter an address different from your current email.';
              }
              return null;
            },
            decoration: _inputDecoration(
              hintText: 'name@example.com',
              prefixIcon: Icons.alternate_email_rounded,
            ),
            onFieldSubmitted: (_) => _startChange(),
          ),
          const SizedBox(height: 14),
          _buildCooldownNotice(),
          const SizedBox(height: 22),
          _primaryButton(
            label: 'Send code to current email',
            icon: Icons.arrow_forward_rounded,
            onPressed: _isWorking ? null : _startChange,
          ),
        ],
      ),
    );
  }

  Widget _buildVerificationStep() {
    final String address = widget.currentEmail;
    final bool attemptsRemain = _status.attemptsRemaining > 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildSectionLabel('CURRENT EMAIL'),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: _surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: _border),
          ),
          child: Row(
            children: [
              const Icon(Icons.mail_outline_rounded, color: _purple, size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  address,
                  style: const TextStyle(
                    color: _text,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 15),
        Text(
          'Enter the six-digit code sent to your current email. Your new email will be applied after verification.',
          style: const TextStyle(color: _muted, fontSize: 13, height: 1.45),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _codeController,
          keyboardType: TextInputType.number,
          textInputAction: TextInputAction.done,
          autofillHints: const [AutofillHints.oneTimeCode],
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(6),
          ],
          style: const TextStyle(
            color: _text,
            fontSize: 22,
            fontWeight: FontWeight.w700,
            letterSpacing: 8,
          ),
          textAlign: TextAlign.center,
          decoration: _inputDecoration(hintText: '------'),
          onSubmitted: (_) => _verifyCode(),
        ),
        const SizedBox(height: 11),
        Text(
          'Code expires in 10 minutes. An unfinished change can be resumed, but a different change must wait until the 24-hour window ends.',
          style: TextStyle(
            color: _muted.withValues(alpha: 0.9),
            fontSize: 12,
            height: 1.45,
          ),
        ),
        const SizedBox(height: 10),
        _buildCooldownNotice(),
        const SizedBox(height: 12),
        _primaryButton(
          label: 'Verify and change email',
          icon: Icons.verified_outlined,
          onPressed: _isWorking || !attemptsRemain ? null : _verifyCode,
        ),
        Align(
          alignment: Alignment.center,
          child: TextButton.icon(
            onPressed:
                _isWorking ||
                    !attemptsRemain ||
                    _status.resendCount >= _status.maxResends
                ? null
                : _resendCode,
            icon: const Icon(Icons.refresh_rounded, size: 17),
            label: Text(
              _status.resendCount >= _status.maxResends
                  ? 'No resends remaining'
                  : 'Resend code',
            ),
            style: TextButton.styleFrom(foregroundColor: _purple),
          ),
        ),
      ],
    );
  }

  Widget _buildUpdatingStep() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _border),
      ),
      child: Column(
        children: [
          const CircularProgressIndicator(color: _purple),
          const SizedBox(height: 16),
          const Text(
            'Finishing your email change...',
            style: TextStyle(
              color: _text,
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          TextButton(
            onPressed: _isWorking ? null : _loadStatus,
            child: const Text('Check status'),
          ),
        ],
      ),
    );
  }

  Widget _buildCooldownNotice() {
    final DateTime? cooldownUntil = _status.cooldownUntil;
    if (cooldownUntil == null) return const SizedBox.shrink();
    final DateTime localTime = cooldownUntil.toLocal();
    final String date = MaterialLocalizations.of(context)
        .formatMediumDate(localTime);
    final String time = MaterialLocalizations.of(context)
        .formatTimeOfDay(TimeOfDay.fromDateTime(localTime));
    return _buildInfoCard(
      icon: Icons.lock_clock_outlined,
      message:
          'This change is reserved until $date at $time. You can resume this request; a different email change must wait until then.',
    );
  }

  Widget _buildSectionLabel(String label) {
    return Text(
      label,
      style: const TextStyle(
        color: _muted,
        fontSize: 11,
        fontWeight: FontWeight.w800,
        letterSpacing: 1.3,
      ),
    );
  }

  InputDecoration _inputDecoration({
    required String hintText,
    IconData? prefixIcon,
  }) {
    return InputDecoration(
      hintText: hintText,
      hintStyle: const TextStyle(color: _muted),
      prefixIcon: prefixIcon == null
          ? null
          : Icon(prefixIcon, color: _purple, size: 20),
      filled: true,
      fillColor: _surface,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(15),
        borderSide: const BorderSide(color: _border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(15),
        borderSide: const BorderSide(color: _purple, width: 1.4),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(15),
        borderSide: const BorderSide(color: Color(0xFFE6A5AF)),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(15),
        borderSide: const BorderSide(color: Color(0xFFE6A5AF), width: 1.4),
      ),
    );
  }

  Widget _primaryButton({
    required String label,
    required IconData icon,
    required VoidCallback? onPressed,
  }) {
    return SizedBox(
      height: 54,
      child: FilledButton.icon(
        onPressed: onPressed,
        icon: _isWorking
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: _background,
                ),
              )
            : Icon(icon, size: 19),
        label: Text(label),
        style: FilledButton.styleFrom(
          backgroundColor: _purple,
          foregroundColor: _background,
          disabledBackgroundColor: _purple.withValues(alpha: 0.45),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
        ),
      ),
    );
  }
}
