import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/auth_provider.dart';
import '../../core/tsg_auth/tsg_auth_service.dart';

const _bgDeep   = Color(0xFF020C1B);
const _bgCard   = Color(0xFF0B1D36);
const _accent   = Color(0xFF2979FF);
const _accentLt = Color(0xFF5C9EFF);
const _accentDm = Color(0xFF1A3A6E);
const _muted    = Color(0xFF6B88A8);

class ChangePasswordScreen extends ConsumerStatefulWidget {
  /// Whether the user is here because of a 90-day expiry (vs first-login / admin reset).
  final bool isExpired;

  const ChangePasswordScreen({super.key, this.isExpired = false});

  @override
  ConsumerState<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends ConsumerState<ChangePasswordScreen> {
  final _formKey     = GlobalKey<FormState>();
  final _currentCtrl = TextEditingController();
  final _newCtrl     = TextEditingController();
  final _confirmCtrl = TextEditingController();

  bool _obscureCurrent = true;
  bool _obscureNew     = true;
  bool _obscureConfirm = true;
  bool _loading        = false;
  String? _error;

  @override
  void dispose() {
    _currentCtrl.dispose();
    _newCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() { _loading = true; _error = null; });
    try {
      final authState = ref.read(authProvider);
      String? accessToken;
      if (authState is AuthStateMustChangePassword) {
        accessToken = authState.accessToken;
      } else if (authState is AuthStateAuthenticated) {
        accessToken = authState.accessToken;
      }
      if (accessToken == null) {
        setState(() => _error = 'Session expired. Please log in again.');
        return;
      }
      await TsgAuthService.changePassword(
        accessToken: accessToken,
        currentPassword: _currentCtrl.text,
        newPassword: _newCtrl.text,
      );
      if (mounted) {
        await ref.read(authProvider.notifier).completePasswordChange();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _error = _parseError(e));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _parseError(Object e) {
    final msg = e.toString().toLowerCase();
    if (msg.contains('incorrect') || msg.contains('400')) {
      return 'Current password is incorrect.';
    }
    if (msg.contains('8 characters') || msg.contains('422')) {
      return 'New password must be at least 8 characters.';
    }
    if (msg.contains('network') || msg.contains('connection')) {
      return 'Cannot reach the server. Check your connection.';
    }
    return 'Failed to change password. Please try again.';
  }

  Future<void> _cancelAndLogout() async {
    await ref.read(authProvider.notifier).logout();
  }

  @override
  Widget build(BuildContext context) {
    final isExpired = widget.isExpired;
    return Scaffold(
      backgroundColor: _bgDeep,
      appBar: AppBar(
        backgroundColor: _bgDeep,
        foregroundColor: _accentLt,
        elevation: 0,
        title: const Text('Change Password',
            style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w600)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          tooltip: 'Back to Login',
          onPressed: _loading ? null : _cancelAndLogout,
        ),
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 20),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                children: [
                  // Banner
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    margin: const EdgeInsets.only(bottom: 20),
                    decoration: BoxDecoration(
                      color: (isExpired ? Colors.orange : _accent).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: (isExpired ? Colors.orange : _accentLt).withOpacity(0.4),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          isExpired ? Icons.timer_off_rounded : Icons.security_update_good_rounded,
                          color: isExpired ? Colors.orange : _accentLt,
                          size: 22,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            isExpired
                                ? 'Your password has expired (90-day policy). Please set a new password to continue.'
                                : 'You must set a new password before continuing.',
                            style: TextStyle(
                              color: isExpired ? Colors.orange : _accentLt,
                              fontSize: 13,
                              height: 1.45,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Card
                  Container(
                    decoration: BoxDecoration(
                      color: _bgCard,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: _accentDm.withOpacity(0.9), width: 1),
                      boxShadow: [BoxShadow(color: _accent.withOpacity(0.14), blurRadius: 36, spreadRadius: 2)],
                    ),
                    padding: const EdgeInsets.all(26),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 38, height: 38,
                                decoration: BoxDecoration(
                                  color: _accent.withOpacity(0.14),
                                  borderRadius: BorderRadius.circular(9),
                                  border: Border.all(color: _accent.withOpacity(0.3)),
                                ),
                                child: const Icon(Icons.key_rounded, color: _accentLt, size: 20),
                              ),
                              const SizedBox(width: 12),
                              const Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('Change Password',
                                      style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w700)),
                                  Text('Choose a strong new password',
                                      style: TextStyle(color: _muted, fontSize: 12)),
                                ],
                              ),
                            ],
                          ),
                          Divider(color: _accentDm.withOpacity(0.6), height: 26, thickness: 1),
                          // Current password
                          _buildField(
                            controller: _currentCtrl,
                            label: 'Current / Temporary Password',
                            icon: Icons.lock_outline_rounded,
                            obscure: _obscureCurrent,
                            onToggleObscure: () => setState(() => _obscureCurrent = !_obscureCurrent),
                            validator: (v) => (v == null || v.isEmpty) ? 'Required' : null,
                          ),
                          const SizedBox(height: 14),
                          // New password
                          _buildField(
                            controller: _newCtrl,
                            label: 'New Password',
                            icon: Icons.lock_rounded,
                            obscure: _obscureNew,
                            onToggleObscure: () => setState(() => _obscureNew = !_obscureNew),
                            validator: (v) {
                              if (v == null || v.isEmpty) return 'Required';
                              if (v.length < 8) return 'Must be at least 8 characters';
                              return null;
                            },
                          ),
                          const SizedBox(height: 14),
                          // Confirm password
                          _buildField(
                            controller: _confirmCtrl,
                            label: 'Confirm New Password',
                            icon: Icons.lock_rounded,
                            obscure: _obscureConfirm,
                            onToggleObscure: () => setState(() => _obscureConfirm = !_obscureConfirm),
                            validator: (v) {
                              if (v == null || v.isEmpty) return 'Required';
                              if (v != _newCtrl.text) return 'Passwords do not match';
                              return null;
                            },
                            textInputAction: TextInputAction.done,
                            onFieldSubmitted: (_) => _submit(),
                          ),
                          // Error
                          if (_error != null) ...[
                            const SizedBox(height: 10),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                              decoration: BoxDecoration(
                                color: Colors.red.withOpacity(0.08),
                                borderRadius: BorderRadius.circular(9),
                                border: Border.all(color: Colors.redAccent.withOpacity(0.4)),
                              ),
                              child: Row(
                                children: [
                                  const Icon(Icons.warning_amber_rounded, color: Colors.redAccent, size: 16),
                                  const SizedBox(width: 8),
                                  Expanded(child: Text(_error!,
                                      style: const TextStyle(color: Colors.redAccent, fontSize: 12.5))),
                                ],
                              ),
                            ),
                          ],
                          const SizedBox(height: 20),
                          SizedBox(
                            height: 50,
                            child: ElevatedButton(
                              onPressed: _loading ? null : _submit,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: _accent,
                                foregroundColor: Colors.white,
                                disabledBackgroundColor: _accentDm,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(11)),
                                elevation: 0,
                              ),
                              child: _loading
                                  ? const SizedBox(
                                      height: 20, width: 20,
                                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                  : const Row(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Icon(Icons.check_circle_rounded, size: 18),
                                        SizedBox(width: 8),
                                        Text('Set New Password',
                                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                                      ],
                                    ),
                            ),
                          ),
                        ],
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

  Widget _buildField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    required bool obscure,
    required VoidCallback onToggleObscure,
    String? Function(String?)? validator,
    TextInputAction textInputAction = TextInputAction.next,
    void Function(String)? onFieldSubmitted,
  }) {
    return TextFormField(
      controller: controller,
      style: const TextStyle(color: Colors.white),
      obscureText: obscure,
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: _muted),
        prefixIcon: Icon(icon, color: _muted, size: 20),
        suffixIcon: IconButton(
          icon: Icon(obscure ? Icons.visibility_off_rounded : Icons.visibility_rounded,
              color: _accentLt, size: 20),
          onPressed: onToggleObscure,
        ),
        filled: true,
        fillColor: const Color(0xFF071530),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: _accentDm)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: _accentDm, width: 1)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: _accent, width: 1.5)),
        errorStyle: const TextStyle(color: Colors.redAccent),
      ),
      validator: validator,
      textInputAction: textInputAction,
      onFieldSubmitted: onFieldSubmitted,
    );
  }
}
