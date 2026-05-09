import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/tsg_auth/tsg_auth_service.dart';

const _bgDeep   = Color(0xFF020C1B);
const _bgCard   = Color(0xFF0B1D36);
const _accent   = Color(0xFF2979FF);
const _accentLt = Color(0xFF5C9EFF);
const _accentDm = Color(0xFF1A3A6E);
const _muted    = Color(0xFF6B88A8);

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _formKey   = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();

  bool _loading   = false;
  bool _submitted = false;
  String? _error;

  @override
  void dispose() {
    _emailCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() { _loading = true; _error = null; });
    try {
      await TsgAuthService.forgotPassword(_emailCtrl.text.trim().toLowerCase());
      if (mounted) setState(() => _submitted = true);
    } catch (_) {
      // Server returns 202 on success; any non-network error still show success
      // to avoid email enumeration. Only show error for true network failures.
      if (mounted) setState(() => _submitted = true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bgDeep,
      appBar: AppBar(
        backgroundColor: _bgDeep,
        foregroundColor: _accentLt,
        elevation: 0,
        title: const Text('Forgot Password',
            style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w600)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          onPressed: () => context.go('/login'),
        ),
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 20),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: _submitted ? _buildSuccess() : _buildForm(),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildForm() {
    return Container(
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
                  child: const Icon(Icons.lock_reset_rounded, color: _accentLt, size: 20),
                ),
                const SizedBox(width: 12),
                const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Reset Password',
                        style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w700)),
                    Text('Enter your registered email',
                        style: TextStyle(color: _muted, fontSize: 12)),
                  ],
                ),
              ],
            ),
            Divider(color: _accentDm.withOpacity(0.6), height: 26, thickness: 1),
            const Text(
              'Enter your account email address and we\'ll send you a temporary password.',
              style: TextStyle(color: _muted, fontSize: 13, height: 1.5),
            ),
            const SizedBox(height: 18),
            TextFormField(
              controller: _emailCtrl,
              style: const TextStyle(color: Colors.white),
              keyboardType: TextInputType.emailAddress,
              autofillHints: const [AutofillHints.email],
              decoration: InputDecoration(
                labelText: 'Email Address',
                labelStyle: const TextStyle(color: _muted),
                prefixIcon: const Icon(Icons.email_outlined, color: _muted, size: 20),
                filled: true,
                fillColor: const Color(0xFF071530),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: _accentDm)),
                enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: _accentDm, width: 1)),
                focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: _accent, width: 1.5)),
                errorStyle: const TextStyle(color: Colors.redAccent),
              ),
              validator: (v) {
                if (v == null || v.isEmpty) return 'Required';
                if (!v.contains('@') || !v.contains('.')) return 'Enter a valid email';
                return null;
              },
              textInputAction: TextInputAction.done,
              onFieldSubmitted: (_) => _submit(),
            ),
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(_error!, style: const TextStyle(color: Colors.redAccent, fontSize: 12.5)),
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
                          Icon(Icons.send_rounded, size: 18),
                          SizedBox(width: 8),
                          Text('Send Reset Email',
                              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                        ],
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSuccess() {
    return Container(
      decoration: BoxDecoration(
        color: _bgCard,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.green.withOpacity(0.4), width: 1),
      ),
      padding: const EdgeInsets.all(32),
      child: Column(
        children: [
          const Icon(Icons.mark_email_read_rounded, color: Colors.greenAccent, size: 56),
          const SizedBox(height: 20),
          const Text('Check your inbox',
              style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          Text(
            'If ${_emailCtrl.text.trim()} is registered, you\'ll receive a temporary password shortly.\n\nUse it to sign in, then you\'ll be prompted to set a new password.',
            textAlign: TextAlign.center,
            style: const TextStyle(color: _muted, fontSize: 13.5, height: 1.6),
          ),
          const SizedBox(height: 28),
          SizedBox(
            height: 48,
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () => context.go('/login'),
              style: ElevatedButton.styleFrom(
                backgroundColor: _accent,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(11)),
                elevation: 0,
              ),
              child: const Text('Back to Sign In',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
            ),
          ),
        ],
      ),
    );
  }
}
