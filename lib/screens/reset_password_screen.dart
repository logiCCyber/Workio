import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'reset_success_screen.dart';

import 'dart:ui';

class ResetPasswordScreen extends StatefulWidget {
  const ResetPasswordScreen({super.key});

  @override
  State<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

const String kLogoUrl =
    'https://mnycxmpofeajhjecsvhk.supabase.co/storage/v1/object/public/images/workio.png';

class _ResetPasswordScreenState extends State<ResetPasswordScreen> {
  // ===== colors =====
  static const Color bg = Colors.black;
  static const Color card = Color(0xFF14151B);
  static const Color stroke = Color(0xFF2A2C36);
  static const Color textMain = Colors.white;
  static const Color textSub = Color(0xFF9AA3B2);

  static const Color accentGreen = Color(0xFF5CFF8A);
  static const Color accentGreen2 = Color(0xFF2E7D32);

  // ✅ твой accentOrange
  static const Color accentOrange = Color(0xFFFFB020);

  final _pass1Ctrl = TextEditingController();
  final _pass2Ctrl = TextEditingController();

  bool _loading = false;
  bool _obscure1 = true;
  bool _obscure2 = true;

  // banner state
  String? _bannerText;
  BannerKind _bannerKind = BannerKind.info;

  @override
  void dispose() {
    _pass1Ctrl.dispose();
    _pass2Ctrl.dispose();
    super.dispose();
  }

  void _showBanner(String text, {BannerKind kind = BannerKind.warn}) {
    setState(() {
      _bannerText = text;
      _bannerKind = kind;
    });
  }

  void _hideBanner() {
    if (_bannerText == null) return;
    setState(() => _bannerText = null);
  }

  bool _validateLocal() {
    final p1 = _pass1Ctrl.text.trim();
    final p2 = _pass2Ctrl.text.trim();

    if (p1.length < 6) {
      _showBanner('Password must be at least 6 characters.', kind: BannerKind.warn);
      return false;
    }
    if (p2.isEmpty) {
      _showBanner('Please repeat the new password.', kind: BannerKind.warn);
      return false;
    }
    if (p1 != p2) {
      _showBanner('Passwords do not match.', kind: BannerKind.warn);
      return false;
    }

    _hideBanner();
    return true;
  }

  String _mapSupabaseError(Object e) {
    final raw = e.toString().toLowerCase();

    if (raw.contains('same_password') ||
        (raw.contains('password') && raw.contains('should be different'))) {
      return "Don’t reuse your old password.";
    }
    if (raw.contains('weak_password')) {
      return "Password is too weak. Use letters + numbers.";
    }
    if (raw.contains('expired') || raw.contains('token')) {
      return "Reset link expired. Please request a new one.";
    }
    return "Something went wrong. Try again.";
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();

    if (!_validateLocal()) return;

    setState(() => _loading = true);
    try {
      final supabase = Supabase.instance.client;
      final user = supabase.auth.currentUser;

      if (user == null) {
        _showBanner('Reset session not found. Open the reset link again.', kind: BannerKind.warn);
        return;
      }

      await supabase.auth.updateUser(
        UserAttributes(password: _pass1Ctrl.text.trim()),
      );

      await supabase.auth.signOut();

      if (!mounted) return;

      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const ResetSuccessScreen()),
            (_) => false,
      );
    } catch (e) {
      if (!mounted) return;
      _showBanner(_mapSupabaseError(e), kind: BannerKind.warn);
    }
    finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bg,
      body: SafeArea(
        child: Stack(
          children: [
            // ===== background like login =====
            const _AuthBackground(),

            // back button (top-left)
            Positioned(
              left: 6,
              top: 6,
              child: IconButton(
                onPressed: () => Navigator.of(context).maybePop(),
                icon: const Icon(Icons.arrow_back, color: Colors.white70),
              ),
            ),

            // ===== center card =====
            Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(18, 64, 18, 22),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: _GlassCard(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Center(
                          child: Image.network(
                            kLogoUrl,
                            height: 64, // ✅ было 34 -> стало больше
                            fit: BoxFit.contain,
                            filterQuality: FilterQuality.high,
                            errorBuilder: (_, __, ___) => const SizedBox(height: 46),
                          ),
                        ),
                        const SizedBox(height: 10),

                        const SizedBox(height: 6),
                        // title row (like login)
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: const [
                            Icon(Icons.lock_reset_rounded, color: Colors.white70, size: 22),
                            SizedBox(width: 10),
                            Text(
                              'Reset password',
                              style: TextStyle(
                                color: textMain,
                                fontSize: 26,
                                fontWeight: FontWeight.w900,
                                letterSpacing: -0.2,
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 8),

                        const Text(
                          'Create a new password for your account.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: textSub, fontSize: 14),
                        ),

                        const SizedBox(height: 14),

                        Container(
                          height: 1.5,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                Colors.transparent,
                                accentGreen.withOpacity(0.45),
                                Colors.transparent,
                              ],
                            ),
                          ),
                        ),

                        const SizedBox(height: 16),

                        const SizedBox(height: 16),

                        // banner
                        AnimatedSwitcher(
                          duration: const Duration(milliseconds: 220),
                          child: _InfoCapsule(
                            key: ValueKey('${_bannerText ?? 'info'}_${_bannerKind.name}'),
                            text: _bannerText ??
                                "Password must be at least 6 characters. Don’t reuse your old password.",
                            kind: _bannerText == null ? BannerKind.info : _bannerKind,
                          ),
                        ),

                        const SizedBox(height: 14),

                        // ===== inputs with glow + scale on focus =====
                        _GlowPasswordField(
                          controller: _pass1Ctrl,
                          hint: 'New password',
                          obscure: _obscure1,
                          onToggle: () => setState(() => _obscure1 = !_obscure1),
                          leadingIcon: Icons.lock_outline_rounded,
                          activeColor: accentGreen,
                        ),

                        const SizedBox(height: 12),

                        _GlowPasswordField(
                          controller: _pass2Ctrl,
                          hint: 'Repeat new password',
                          obscure: _obscure2,
                          onToggle: () => setState(() => _obscure2 = !_obscure2),
                          leadingIcon: Icons.lock_outline_rounded,
                          activeColor: accentGreen,
                        ),

                        const SizedBox(height: 18),

                        // save button (like login)
                        SizedBox(
                          height: 54,
                          width: double.infinity,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(28),
                              gradient: const LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [accentGreen, accentGreen2],
                              ),
                              boxShadow: const [],
                            ),
                            child: ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.transparent,
                                shadowColor: Colors.transparent,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(28),
                                ),
                              ),
                              onPressed: _loading ? null : _submit,
                              child: _loading
                                  ? const SizedBox(
                                height: 22,
                                width: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.black,
                                ),
                              )
                                  : Row(
                                mainAxisSize: MainAxisSize.min,
                                children: const [
                                  Icon(Icons.check_rounded, color: Colors.black, size: 20),
                                  SizedBox(width: 10),
                                  Text(
                                    'Save',
                                    style: TextStyle(
                                      color: Colors.black,
                                      fontSize: 16,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),

                        const SizedBox(height: 6),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ====== INFO CAPSULE ======
enum BannerKind { info, warn }

class _AuthBackground extends StatelessWidget {
  const _AuthBackground();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF07080C), Color(0xFF05060A), Color(0xFF000000)],
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            left: -120,
            top: -140,
            child: Container(
              width: 320,
              height: 320,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Color(0xFF34D399).withOpacity(0.08),
              ),
            ),
          ),
          Positioned(
            right: -140,
            top: 60,
            child: Container(
              width: 360,
              height: 360,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Color(0xFF38BDF8).withOpacity(0.06),
              ),
            ),
          ),
          Positioned(
            left: -140,
            bottom: -160,
            child: Container(
              width: 420,
              height: 420,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Color(0xFFA78BFA).withOpacity(0.05),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _GlassCard extends StatelessWidget {
  final Widget child;
  const _GlassCard({required this.child});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                const Color(0xFF1C1E26).withOpacity(0.92),
                const Color(0xFF14151B).withOpacity(0.90),
              ],
            ),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: Colors.white.withOpacity(0.10)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.55),
                blurRadius: 30,
                offset: const Offset(0, 18),
              ),
            ],
          ),
          child: child,
        ),
      ),
    );
  }
}

class _InfoCapsule extends StatelessWidget {
  final String text;
  final BannerKind kind;

  const _InfoCapsule({super.key, required this.text, required this.kind});

  static const Color card = Color(0xFF14151B);
  static const Color stroke = Color(0xFF2A2C36);
  static const Color textMain = Colors.white;
  static const Color textSub = Color(0xFF9AA3B2);
  static const Color accentOrange = Color(0xFFFFB020);

  @override
  Widget build(BuildContext context) {
    final Color iconColor = accentOrange;
    final Color borderColor = accentOrange.withOpacity(0.35);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: kind == BannerKind.warn ? borderColor : stroke),
      ),
      child: Row(
        children: [
          Container(
            height: 28,
            width: 28,
            decoration: BoxDecoration(
              color: accentOrange.withOpacity(0.12),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: accentOrange.withOpacity(0.35)),
            ),
            child: Icon(Icons.error_outline, color: iconColor, size: 18),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: kind == BannerKind.warn ? textMain.withOpacity(0.9) : textSub,
                fontSize: 13,
                height: 1.25,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ====== THIN PASSWORD FIELD ======
class _GlowPasswordField extends StatefulWidget {
  final TextEditingController controller;
  final String hint;
  final bool obscure;
  final VoidCallback onToggle;
  final IconData leadingIcon;
  final Color activeColor;

  const _GlowPasswordField({
    required this.controller,
    required this.hint,
    required this.obscure,
    required this.onToggle,
    required this.leadingIcon,
    required this.activeColor,
  });

  @override
  State<_GlowPasswordField> createState() => _GlowPasswordFieldState();
}

class _GlowPasswordFieldState extends State<_GlowPasswordField>
    with SingleTickerProviderStateMixin {
  static const Color card = Color(0xFF14151B);
  static const Color stroke = Color(0xFF2A2C36);
  static const Color textMain = Colors.white;
  static const Color textSub = Color(0xFF9AA3B2);

  final FocusNode _focus = FocusNode();
  late final AnimationController _pulse;

  bool _focused = false;

  @override
  void initState() {
    super.initState();

    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );

    _focus.addListener(() {
      final f = _focus.hasFocus;
      setState(() => _focused = f);

      if (f) {
        _pulse.repeat(reverse: true);
      } else {
        _pulse.stop();
        _pulse.value = 0;
      }
    });
  }

  @override
  void dispose() {
    _pulse.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedScale(
      duration: const Duration(milliseconds: 160),
      curve: Curves.easeOutCubic,
      scale: _focused ? 1.02 : 1.0, // ✅ чуть увеличивается на фокусе
      child: AnimatedBuilder(
        animation: _pulse,
        builder: (context, _) {
          final t = _focused ? _pulse.value : 0.0; // 0..1

          final borderColor = _focused
              ? widget.activeColor.withOpacity(0.30 + 0.25 * t)
              : stroke;

          final iconColor = _focused
              ? widget.activeColor.withOpacity(0.95)
              : textSub.withOpacity(0.90);

          return Container(
            height: 54,
            decoration: BoxDecoration(
              color: card,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: borderColor, width: 1),
              boxShadow: const [],
            ),
            child: Row(
              children: [
                const SizedBox(width: 12),

                // leading icon with tiny glow capsule
                Icon(
                  widget.leadingIcon,
                  size: 20,
                  color: iconColor, // ✅ остаётся “живой” цвет
                ),

                const SizedBox(width: 10),

                // input
                Expanded(
                  child: TextField(
                    focusNode: _focus,
                    controller: widget.controller,
                    obscureText: widget.obscure,
                    style: const TextStyle(
                      color: textMain,
                      fontWeight: FontWeight.w800,
                    ),
                    cursorColor: widget.activeColor,
                    decoration: InputDecoration(
                      border: InputBorder.none,
                      hintText: widget.hint,
                      hintStyle: TextStyle(
                        color: textSub.withOpacity(0.85),
                        fontWeight: FontWeight.w700,
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 0,
                        vertical: 14,
                      ),
                    ),
                  ),
                ),

                // eye icon
                InkWell(
                  onTap: widget.onToggle,
                  borderRadius: BorderRadius.circular(14),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Icon(
                      widget.obscure
                          ? Icons.visibility_off_rounded
                          : Icons.visibility_rounded,
                      size: 20,
                      color: _focused
                          ? widget.activeColor.withOpacity(0.70)
                          : textSub.withOpacity(0.85),
                    ),
                  ),
                ),

                const SizedBox(width: 2),
              ],
            ),
          );
        },
      ),
    );
  }
}
