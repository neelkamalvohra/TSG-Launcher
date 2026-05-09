import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/auth/auth_provider.dart';

// ── Palette ───────────────────────────────────────────────────────────────────

const _bgDeep    = Color(0xFF020C1B);
const _bgMid     = Color(0xFF051525);
const _bgCard    = Color(0xFF0B1D36);
const _accent    = Color(0xFF2979FF);
const _accentLt  = Color(0xFF5C9EFF);
const _accentDm  = Color(0xFF1A3A6E);
const _muted     = Color(0xFF6B88A8);
const _subtle    = Color(0xFF2A4060);

// ── Background: network topology painter ─────────────────────────────────────

class _NetworkBgPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final rng = Random(7); // fixed seed → deterministic layout

    // ── Node grid (staggered hex-ish) ──────────────────────────────────────
    final nodes = <Offset>[];
    const cols = 7;
    const rows = 11;
    for (var r = 0; r <= rows; r++) {
      for (var c = 0; c <= cols; c++) {
        final x = c * size.width / cols +
            (r.isOdd ? size.width / (cols * 2) : 0) +
            (rng.nextDouble() - 0.5) * 18;
        final y = r * size.height / rows +
            (rng.nextDouble() - 0.5) * 18;
        nodes.add(Offset(x, y));
      }
    }

    // ── Draw edges between near nodes ──────────────────────────────────────
    final maxDist = size.width / cols * 1.55;
    final linePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.7;
    for (var i = 0; i < nodes.length; i++) {
      for (var j = i + 1; j < nodes.length; j++) {
        final d = (nodes[i] - nodes[j]).distance;
        if (d < maxDist) {
          final alpha = (1.0 - d / maxDist) * 0.38;
          canvas.drawLine(
            nodes[i],
            nodes[j],
            linePaint..color = const Color(0xFF1E5AAA).withOpacity(alpha),
          );
        }
      }
    }

    // ── Draw node dots ─────────────────────────────────────────────────────
    final dotPaint = Paint()..style = PaintingStyle.fill;
    final glowPaint = Paint()..style = PaintingStyle.fill;
    for (final n in nodes) {
      glowPaint.color = _accent.withOpacity(0.07);
      dotPaint.color = const Color(0xFF1E5AAA).withOpacity(0.7);
      canvas.drawCircle(n, 5.0, glowPaint);
      canvas.drawCircle(n, 2.0, dotPaint);
    }

    // ── Signal arcs from top-left (cell tower position) ────────────────────
    final towerPt = Offset(size.width * 0.06, size.height * 0.13);
    final arcPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    for (var i = 1; i <= 5; i++) {
      final r = i * 52.0;
      canvas.drawArc(
        Rect.fromCenter(center: towerPt, width: r * 2, height: r * 2),
        -pi * 0.6,
        pi * 0.42,
        false,
        arcPaint
          ..strokeWidth = 1.0
          ..color = _accent.withOpacity(0.20 - i * 0.03),
      );
    }

    // ── Arcs from bottom-right (home broadband hub) ────────────────────────
    final hubPt = Offset(size.width * 0.94, size.height * 0.88);
    for (var i = 1; i <= 4; i++) {
      final r = i * 44.0;
      canvas.drawArc(
        Rect.fromCenter(center: hubPt, width: r * 2, height: r * 2),
        pi * 0.85,
        pi * 0.48,
        false,
        arcPaint
          ..strokeWidth = 1.0
          ..color = _accentLt.withOpacity(0.16 - i * 0.025),
      );
    }

    // ── Faint complaint/analytics line in the middle-right ─────────────────
    final dashPaint = Paint()
      ..color = _accentDm.withOpacity(0.5)
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;
    // Horizontal dashed "signal strength" bars
    final barX = size.width * 0.82;
    final barY = size.height * 0.45;
    final barHeights = [18.0, 28.0, 38.0, 48.0, 36.0, 22.0];
    for (var b = 0; b < barHeights.length; b++) {
      final bx = barX + b * 10.0;
      canvas.drawLine(
        Offset(bx, barY),
        Offset(bx, barY - barHeights[b]),
        dashPaint..strokeWidth = 6.0,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ── Login screen ──────────────────────────────────────────────────────────────

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen>
    with SingleTickerProviderStateMixin {
  final _formKey   = GlobalKey<FormState>();
  final _userCtrl  = TextEditingController();
  final _passCtrl  = TextEditingController();
  bool _obscure   = true;
  bool _loading   = false;
  String? _error;
  bool _errorIsNetwork = false;

  late final AnimationController _pulseCtrl;
  late final Animation<double> _pulse;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2, milliseconds: 800),
    )..repeat(reverse: true);
    _pulse = CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut);
  }

  @override
  void dispose() {
    _userCtrl.dispose();
    _passCtrl.dispose();
    _pulseCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() { _loading = true; _error = null; });
    try {
      await ref.read(authProvider.notifier).login(
        username: _userCtrl.text.trim().toLowerCase(),
        password: _passCtrl.text,
      );
    } catch (e) {
      if (mounted) {
        final isNet = e is AuthException && e.isNetworkError;
        setState(() {
          _errorIsNetwork = isNet;
          _error = isNet
              ? 'Cannot reach the server.\nCheck your network connection.'
              : 'Invalid username or password.';
        });
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // Gradient background
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                stops: [0.0, 0.45, 1.0],
                colors: [_bgDeep, Color(0xFF061422), Color(0xFF0A1E38)],
              ),
            ),
          ),
          // Network topology layer
          CustomPaint(
            painter: _NetworkBgPainter(),
            child: const SizedBox.expand(),
          ),
          // Animated glow — tower position (top-left)
          Positioned(
            top: 0, left: 0,
            child: AnimatedBuilder(
              animation: _pulse,
              builder: (_, __) => Container(
                width: 220, height: 220,
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    colors: [
                      _accent.withOpacity(0.13 * _pulse.value),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
          ),
          // Decorative cell tower — top-left
          Positioned(
            top: 18, left: 16,
            child: Opacity(
              opacity: 0.28,
              child: Column(
                children: [
                  const Icon(Icons.cell_tower, color: _accentLt, size: 56),
                  const SizedBox(height: 3),
                  // Mini signal bars
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: List.generate(4, (i) => Container(
                      width: 5,
                      height: 5.0 + i * 4.5,
                      margin: const EdgeInsets.symmetric(horizontal: 1.5),
                      decoration: BoxDecoration(
                        color: _accentLt,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    )),
                  ),
                ],
              ),
            ),
          ),
          // Decorative router — bottom-right
          Positioned(
            bottom: 18, right: 14,
            child: Opacity(
              opacity: 0.22,
              child: const Column(
                children: [
                  Icon(Icons.router_rounded, color: _accentLt, size: 44),
                  SizedBox(height: 4),
                  Icon(Icons.wifi_tethering_rounded, color: _muted, size: 30),
                ],
              ),
            ),
          ),
          // Main content
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 20),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: Column(
                    children: [
                      _buildBranding(),
                      const SizedBox(height: 24),
                      _buildCard(),
                      const SizedBox(height: 18),
                      _buildTechPills(),
                      const SizedBox(height: 12),
                      _buildStatusBar(),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Branding ──────────────────────────────────────────────────────────────

  Widget _buildBranding() {
    return Column(
      children: [
        // Icon cluster
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedBuilder(
              animation: _pulse,
              builder: (_, __) => Icon(
                Icons.cell_tower,
                color: Color.lerp(_accentLt, Colors.white, _pulse.value * 0.25)!,
                size: 38,
              ),
            ),
            const SizedBox(width: 8),
            const Icon(Icons.signal_cellular_alt_rounded, color: _accent, size: 28),
            const SizedBox(width: 5),
            const Icon(Icons.wifi_rounded, color: _accentLt, size: 26),
            const SizedBox(width: 6),
            const Icon(Icons.phone_android_rounded, color: _muted, size: 24),
          ],
        ),
        const SizedBox(height: 14),
        // TSG wordmark with gradient
        ShaderMask(
          shaderCallback: (b) => const LinearGradient(
            colors: [Colors.white, _accentLt],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ).createShader(b),
          child: const Text(
            'TSG',
            style: TextStyle(
              color: Colors.white,
              fontSize: 52,
              fontWeight: FontWeight.w900,
              letterSpacing: 14,
              height: 1.0,
            ),
          ),
        ),
        const SizedBox(height: 5),
        Text(
          'TECHNICAL  SUPPORT  GROUP',
          style: TextStyle(
            color: _accentLt.withOpacity(0.85),
            fontSize: 10.5,
            fontWeight: FontWeight.w600,
            letterSpacing: 3.5,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Mobility & Home Broadband Analytics',
          style: TextStyle(color: _muted.withOpacity(0.9), fontSize: 12.5),
        ),
      ],
    );
  }

  // ── Login card ────────────────────────────────────────────────────────────

  Widget _buildCard() {
    return Container(
      decoration: BoxDecoration(
        color: _bgCard,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _accentDm.withOpacity(0.9), width: 1),
        boxShadow: [
          BoxShadow(
            color: _accent.withOpacity(0.14),
            blurRadius: 36,
            spreadRadius: 2,
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(26),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Card header row
              Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: _accent.withOpacity(0.14),
                      borderRadius: BorderRadius.circular(9),
                      border: Border.all(color: _accent.withOpacity(0.3)),
                    ),
                    child: const Icon(Icons.lock_outline_rounded,
                        color: _accentLt, size: 20),
                  ),
                  const SizedBox(width: 12),
                  const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Sign In',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.w700)),
                      Text('Enter your credentials to continue',
                          style: TextStyle(color: _muted, fontSize: 12)),
                    ],
                  ),
                ],
              ),
              Divider(
                  color: _accentDm.withOpacity(0.6), height: 26, thickness: 1),
              // Username
              TextFormField(
                controller: _userCtrl,
                style: const TextStyle(color: Colors.white),
                decoration: _field('Username', Icons.person_rounded),
                validator: (v) => (v == null || v.isEmpty) ? 'Required' : null,
                textInputAction: TextInputAction.next,
                autofillHints: const [AutofillHints.username],
              ),
              const SizedBox(height: 14),
              // Password
              TextFormField(
                controller: _passCtrl,
                style: const TextStyle(color: Colors.white),
                obscureText: _obscure,
                decoration: _field('Password', Icons.key_rounded).copyWith(
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscure
                          ? Icons.visibility_off_rounded
                          : Icons.visibility_rounded,
                      color: _accentLt,
                      size: 20,
                    ),
                    onPressed: () => setState(() => _obscure = !_obscure),
                  ),
                ),
                validator: (v) => (v == null || v.isEmpty) ? 'Required' : null,
                textInputAction: TextInputAction.done,
                onFieldSubmitted: (_) => _submit(),
                autofillHints: const [AutofillHints.password],
              ),
              // Error banner
              if (_error != null) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                  decoration: BoxDecoration(
                    color: (_errorIsNetwork ? Colors.orange : Colors.red)
                        .withOpacity(0.08),
                    borderRadius: BorderRadius.circular(9),
                    border: Border.all(
                      color: (_errorIsNetwork ? Colors.orange : Colors.redAccent)
                          .withOpacity(0.4),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        _errorIsNetwork
                            ? Icons.cloud_off_rounded
                            : Icons.warning_amber_rounded,
                        color: _errorIsNetwork ? Colors.orange : Colors.redAccent,
                        size: 16,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _error!,
                          style: TextStyle(
                            color: _errorIsNetwork
                                ? Colors.orange
                                : Colors.redAccent,
                            fontSize: 12.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 20),
              // Sign In button
              SizedBox(
                height: 50,
                child: ElevatedButton(
                  onPressed: _loading ? null : _submit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _accent,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: _accentDm,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(11)),
                    elevation: 0,
                  ),
                  child: _loading
                      ? const SizedBox(
                          height: 20, width: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.login_rounded, size: 18),
                            SizedBox(width: 8),
                            Text('Sign In',
                                style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600)),
                          ],
                        ),
                ),
              ),
              const SizedBox(height: 12),
              // Forgot password link
              Center(
                child: TextButton(
                  onPressed: () => context.go('/forgot-password'),
                  style: TextButton.styleFrom(
                    foregroundColor: _accentLt,
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  ),
                  child: const Text(
                    'Forgot Password?',
                    style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w500),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Tech pills ────────────────────────────────────────────────────────────

  Widget _buildTechPills() {
    const tags = [
      (Icons.signal_cellular_alt_rounded, '4G'),
      (Icons.five_g_rounded,              '5G'),
      (Icons.sensors_rounded,             'IoT'),
      (Icons.lan_rounded,                 'FTTx'),
      (Icons.wifi_tethering_rounded,      'Airfiber'),
    ];
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      alignment: WrapAlignment.center,
      children: tags.map((t) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
        decoration: BoxDecoration(
          border: Border.all(color: _subtle),
          borderRadius: BorderRadius.circular(20),
          color: _accentDm.withOpacity(0.22),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(t.$1, color: _accentLt, size: 13),
            const SizedBox(width: 5),
            Text(t.$2,
                style: const TextStyle(
                    color: _muted, fontSize: 11.5, fontWeight: FontWeight.w500)),
          ],
        ),
      )).toList(),
    );
  }

  // ── Status bar ────────────────────────────────────────────────────────────

  Widget _buildStatusBar() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.analytics_outlined, color: _muted.withOpacity(0.5), size: 13),
        const SizedBox(width: 5),
        Text(
          'Network Analytics  ·  Complaint Management  ·  Fault Tracking',
          style: TextStyle(
            color: _muted.withOpacity(0.45),
            fontSize: 10,
            letterSpacing: 0.3,
          ),
        ),
      ],
    );
  }

  // ── Input decoration ──────────────────────────────────────────────────────

  InputDecoration _field(String label, IconData icon) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: _muted),
      prefixIcon: Icon(icon, color: _muted, size: 20),
      filled: true,
      fillColor: const Color(0xFF071530),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: _accentDm),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: _accentDm, width: 1),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: _accent, width: 1.5),
      ),
      errorStyle: const TextStyle(color: Colors.redAccent),
    );
  }
}

