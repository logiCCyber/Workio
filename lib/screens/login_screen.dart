import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../ui/app_toast.dart';

import 'worker_screen.dart';
import 'admin_panel.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final supabase = Supabase.instance.client;

  // toggle
  bool isRegister = false;

  // controllers
  final _loginEmail = TextEditingController();
  final _loginPass = TextEditingController();

  final _regName = TextEditingController();
  final _regEmail = TextEditingController();
  final _regPass = TextEditingController();
  final _regPass2 = TextEditingController();

  // FocusNodes
  final _fLoginEmail = FocusNode();
  final _fLoginPass = FocusNode();

  final _fRegName = FocusNode();
  final _fRegEmail = FocusNode();
  final _fRegPass = FocusNode();
  final _fRegPass2 = FocusNode();

  bool loading = false;
  bool showPass = false;
  bool showPass2 = false;

  @override
  void dispose() {
    _loginEmail.dispose();
    _loginPass.dispose();
    _regName.dispose();
    _regEmail.dispose();
    _regPass.dispose();
    _regPass2.dispose();

    _fLoginEmail.dispose();
    _fLoginPass.dispose();
    _fRegName.dispose();
    _fRegEmail.dispose();
    _fRegPass.dispose();
    _fRegPass2.dispose();

    super.dispose();
  }

  // ====== STYLE (matches HTML design) ======
  static const _bg       = Color(0xFF0A0C10);
  static const _card     = Color(0xFF171A21);
  static const _field    = Color(0xFF22262F);
  static const _fieldHi  = Color(0xFF262B35);

  static const _accent   = Color(0xFF22C55E); // green-500
  static const _accentHi = Color(0xFF34D76F);
  static const _accentLo = Color(0xFF1EA34D);

  static const _ink0     = Color(0xFFFFFFFF);
  static const _ink1     = Color(0xFFA8AEBA);
  static const _ink2     = Color(0xFF6B7281);
  static const _ink3     = Color(0xFF4A4F5A);

  void _toastInfo(String t) => AppToast.show(t);
  void _toastOk(String t) => AppToast.success(t);
  void _toastWarn(String t) => AppToast.warning(t);
  void _toastErr(String t) => AppToast.error(t);

  String _prettyAuthError(Object e) {
    final raw = e.toString();
    final s = raw.toLowerCase();

    if (s.contains('failed host lookup') ||
        s.contains('socketexception') ||
        s.contains('clientexception') ||
        s.contains('network is unreachable') ||
        s.contains('connection timed out') ||
        s.contains('connection refused') ||
        s.contains('connection reset')) {
      return 'Can’t connect to server. Check your internet connection and try again.';
    }

    if (s.contains('invalid login credentials')) {
      return 'Wrong email or password.';
    }

    if (s.contains('email not confirmed')) {
      return 'Please confirm your email before signing in.';
    }

    if (s.contains('user already registered') ||
        s.contains('already registered')) {
      return 'An account with this email already exists.';
    }

    if (s.contains('signup disabled')) {
      return 'Creating accounts is currently disabled.';
    }

    if (s.contains('only request this after')) {
      return 'Please wait a moment before trying again.';
    }

    if (s.contains('jwt') || s.contains('session')) {
      return 'Your session expired. Please sign in again.';
    }

    if (s.contains('postgrestexception') ||
        s.contains('permission denied') ||
        s.contains('violates row-level security')) {
      return 'Server profile error. Please try again or contact support.';
    }

    if (e is AuthException && e.message.trim().isNotEmpty) {
      return e.message;
    }

    return 'Something went wrong. Please try again.';
  }

  Future<Map<String, dynamic>?> _fetchWorkerProfile(String authUserId) async {
    final row = await supabase
        .from('workers')
        .select('role, access_mode')
        .eq('auth_user_id', authUserId)
        .maybeSingle();
    return row == null ? null : Map<String, dynamic>.from(row);
  }

  Future<void> _login() async {
    if (loading) return;

    final email = _loginEmail.text.trim().toLowerCase();
    final pass = _loginPass.text.trim();

    if (email.isEmpty || !email.contains('@')) return _toastWarn('Enter a valid email');
    if (pass.length < 6) return _toastWarn('Password must be at least 6 characters');

    setState(() => loading = true);

    try {
      final res = await supabase.auth.signInWithPassword(email: email, password: pass);
      final user = res.user;
      if (user == null) throw 'No user';

      final profile = await _fetchWorkerProfile(user.id);
      if (profile == null) {
        await supabase.auth.signOut();
        _toastErr('No profile in workers table for this account.');
        return;
      }

      final role = (profile['role'] as String?) ?? 'worker';
      final accessMode = (profile['access_mode'] as String?) ?? 'active';

      if (accessMode == 'suspended') {
        await supabase.auth.signOut();
        _toastErr('Your account is suspended. Contact admin.');
        return;
      }

      if (!mounted) return;

      if (role == 'admin') {
        Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const AdminPanel()));
        return;
      }

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => WorkerScreen(accessMode: accessMode)),
      );
    } catch (e) {
      final msg = _prettyAuthError(e);
      if (msg.toLowerCase().contains('only request this after')) {
        _toastWarn(msg);
      } else {
        _toastErr(msg);
      }
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _forgotPasswordAdmin() async {
    if (loading) return;

    final email = _loginEmail.text.trim().toLowerCase();
    if (email.isEmpty || !email.contains('@')) {
      _toastWarn('Enter admin email above');
      FocusScope.of(context).requestFocus(_fLoginEmail);
      return;
    }

    try {
      final adminRow = await supabase
          .from('admin_users')
          .select('email')
          .eq('email', email)
          .maybeSingle();

      if (adminRow == null) {
        _toastErr('Password reset here is for admins only.');
        return;
      }

      await supabase.auth.resetPasswordForEmail(
        email,
        redirectTo: 'workio://reset-password',
      );

      _toastOk('Check your email — password reset link was sent.');
    } catch (e) {
      final msg = _prettyAuthError(e);
      if (msg.toLowerCase().contains('only request this after')) {
        _toastWarn(msg);
      } else {
        _toastErr(msg);
      }
    }
  }

  Future<void> _registerAdmin() async {
    if (loading) return;

    final name = _regName.text.trim();
    final email = _regEmail.text.trim().toLowerCase();
    final pass = _regPass.text.trim();
    final pass2 = _regPass2.text.trim();

    if (name.length < 2) return _toastWarn('Enter your name');
    if (email.isEmpty || !email.contains('@')) return _toastWarn('Enter a valid email');
    if (pass.length < 6) return _toastWarn('Password must be at least 6 characters');
    if (pass != pass2) return _toastWarn('Passwords do not match');

    setState(() => loading = true);

    try {
      final res = await supabase.auth.signUp(
        email: email,
        password: pass,
        emailRedirectTo: 'workio://confirmed',
        data: {'name': name, 'role': 'admin'},
      );

      if (res.session == null) {
        _toastInfo('Check your email to confirm, then sign in.');
        if (mounted) setState(() => isRegister = false);
        return;
      }

      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const AdminPanel()),
      );
    } catch (e) {
      final msg = _prettyAuthError(e);
      if (msg.toLowerCase().contains('only request this after')) {
        _toastWarn(msg);
      } else {
        _toastErr(msg);
      }
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: Stack(
        children: [
          // BACKGROUND — subtle green ambient
          const _AuthBackground(),

          // CONTENT
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 400),
                  child: Container(
                    decoration: BoxDecoration(
                      color: _card,
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: Colors.white.withOpacity(0.06)),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.55),
                          blurRadius: 60,
                          spreadRadius: -20,
                          offset: const Offset(0, 24),
                        ),
                      ],
                    ),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(28, 30, 28, 24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // BRAND LOCKUP — W icon + "orkio" wordmark + tagline
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              SvgPicture.asset(
                                'assets/images/workio.svg',
                                height: 56,
                              ),
                              const SizedBox(width: 4),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: const [
                                  Text(
                                    'orkio',
                                    style: TextStyle(
                                      color: _ink0,
                                      fontSize: 38,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: -1.2,
                                      height: 1,
                                    ),
                                  ),
                                  SizedBox(height: 4),
                                  // 👇 МЕНЯЙ ТЭГЛАЙН ТУТ
                                  Text(
                                    'WORKFORCE  OPS',
                                    style: TextStyle(
                                      color: _ink2,
                                      fontSize: 9,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: 2.8,
                                      height: 1,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),

                          const SizedBox(height: 22),

                          // TITLE
                          Text(
                            isRegister ? 'Create admin' : 'Sign in',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: _ink0,
                              fontWeight: FontWeight.w700,
                              fontSize: 18,
                              letterSpacing: -0.6,
                              height: 1.1,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            isRegister
                                ? 'Admin account (workers are created by admin)'
                                : 'Admin / Worker login',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: _ink1.withOpacity(0.85),
                              fontWeight: FontWeight.w500,
                              fontSize: 13,
                            ),
                          ),

                          const SizedBox(height: 18),

                          // GRADIENT DIVIDER (green)
                          Container(
                            height: 1,
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  Colors.transparent,
                                  _accent.withOpacity(0.55),
                                  Colors.transparent,
                                ],
                              ),
                            ),
                          ),

                          const SizedBox(height: 20),

                          // FORM
                          AnimatedSwitcher(
                            duration: const Duration(milliseconds: 260),
                            switchInCurve: Curves.easeOutCubic,
                            switchOutCurve: Curves.easeInCubic,
                            transitionBuilder: (child, anim) {
                              final inFrom = isRegister
                                  ? const Offset(0.08, 0)
                                  : const Offset(-0.08, 0);
                              final slide = Tween<Offset>(begin: inFrom, end: Offset.zero).animate(anim);
                              return FadeTransition(
                                opacity: anim,
                                child: SlideTransition(position: slide, child: child),
                              );
                            },
                            child: AnimatedSize(
                              duration: const Duration(milliseconds: 220),
                              curve: Curves.easeOutCubic,
                              child: isRegister ? _registerForm() : _loginForm(),
                            ),
                          ),

                          const SizedBox(height: 18),

                          // FOOTER
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                isRegister ? 'Already have admin?' : 'Need admin account?',
                                style: TextStyle(
                                  color: _ink1.withOpacity(0.85),
                                  fontWeight: FontWeight.w500,
                                  fontSize: 13,
                                ),
                              ),
                              const SizedBox(width: 6),
                              InkWell(
                                borderRadius: BorderRadius.circular(999),
                                onTap: loading
                                    ? null
                                    : () => setState(() => isRegister = !isRegister),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                                  child: Text(
                                    isRegister ? 'Sign in' : 'Create admin',
                                    style: const TextStyle(
                                      color: _accent,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 13,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _loginForm() {
    return Column(
      key: const ValueKey('login'),
      children: [
        _PillField(
          controller: _loginEmail,
          focusNode: _fLoginEmail,
          hint: 'Email',
          icon: Icons.alternate_email_rounded,
          accent: const Color(0xFF38BDF8), // 🔵 email
          keyboardType: TextInputType.emailAddress,
          enabled: !loading,
          textInputAction: TextInputAction.next,
        ),
        const SizedBox(height: 12),
        _PillField(
          controller: _loginPass,
          focusNode: _fLoginPass,
          hint: 'Password',
          icon: Icons.lock_rounded,
          accent: const Color(0xFFF59E0B), // 🟠 password
          obscureText: !showPass,
          enabled: !loading,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _login(),
          trailing: _EyeButton(
            visible: showPass,
            accent: const Color(0xFFF59E0B),
            onTap: loading ? null : () => setState(() => showPass = !showPass),
          ),
        ),
        const SizedBox(height: 8),
        ValueListenableBuilder<TextEditingValue>(
          valueListenable: _loginEmail,
          builder: (_, __, ___) {
            final email = _loginEmail.text.trim().toLowerCase();
            final canReset = !loading && email.contains('@');

            return Align(
              alignment: Alignment.centerRight,
              child: InkWell(
                onTap: canReset
                    ? _forgotPasswordAdmin
                    : () {
                  _toastWarn('Enter admin email above');
                  FocusScope.of(context).requestFocus(_fLoginEmail);
                },
                borderRadius: BorderRadius.circular(999),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                  child: Text(
                    canReset ? 'Forgot password? (admin)' : 'Enter email to reset (admin)',
                    style: TextStyle(
                      color: canReset
                          ? _accent.withOpacity(0.9)
                          : _ink2,
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                    ),
                  ),
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 16),
        _PrimaryButton(
          label: loading ? 'Signing in…' : 'Sign in',
          loading: loading,
          onTap: loading ? null : _login,
          icon: Icons.login_rounded,
        ),
      ],
    );
  }

  Widget _registerForm() {
    return Column(
      key: const ValueKey('register'),
      children: [
        _PillField(
          controller: _regName,
          focusNode: _fRegName,
          hint: 'Name',
          icon: Icons.badge_rounded,
          accent: Colors.white, // ⚪ name
          enabled: !loading,
          textInputAction: TextInputAction.next,
        ),
        const SizedBox(height: 12),
        _PillField(
          controller: _regEmail,
          focusNode: _fRegEmail,
          hint: 'Email',
          icon: Icons.alternate_email_rounded,
          accent: const Color(0xFF38BDF8), // 🔵 email
          keyboardType: TextInputType.emailAddress,
          enabled: !loading,
          textInputAction: TextInputAction.next,
        ),
        const SizedBox(height: 12),
        _PillField(
          controller: _regPass,
          focusNode: _fRegPass,
          hint: 'Password',
          icon: Icons.lock_rounded,
          accent: const Color(0xFFF59E0B), // 🟠 password
          obscureText: !showPass,
          enabled: !loading,
          textInputAction: TextInputAction.next,
          trailing: _EyeButton(
            visible: showPass,
            accent: const Color(0xFFF59E0B),
            onTap: loading ? null : () => setState(() => showPass = !showPass),
          ),
        ),
        const SizedBox(height: 12),
        _PillField(
          controller: _regPass2,
          focusNode: _fRegPass2,
          hint: 'Confirm password',
          icon: Icons.lock_outline_rounded,
          accent: const Color(0xFFF59E0B), // 🟠 confirm
          obscureText: !showPass2,
          enabled: !loading,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _registerAdmin(),
          trailing: _EyeButton(
            visible: showPass2,
            accent: const Color(0xFFF59E0B),
            onTap: loading ? null : () => setState(() => showPass2 = !showPass2),
          ),
        ),
        const SizedBox(height: 16),
        _PrimaryButton(
          label: loading ? 'Creating…' : 'Create admin',
          loading: loading,
          onTap: loading ? null : _registerAdmin,
          icon: Icons.person_add_alt_1_rounded,
        ),
        const SizedBox(height: 10),
        Text(
          'Workers are created by admin inside the app.',
          style: TextStyle(
            color: _ink2,
            fontWeight: FontWeight.w500,
            fontSize: 11.5,
          ),
        ),
      ],
    );
  }
}

// ════════════════════════════════════════════════════════════════
// BACKGROUND
// ════════════════════════════════════════════════════════════════

class _AuthBackground extends StatelessWidget {
  const _AuthBackground();

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // base flat dark
        Container(color: const Color(0xFF0A0C10)),

        // subtle green glow top
        Positioned(
          top: -180,
          left: 0,
          right: 0,
          child: Center(
            child: _GlowBlob(
              color: const Color(0xFF22C55E),
              size: 420,
              opacity: 0.06,
            ),
          ),
        ),

        // subtle green glow bottom
        Positioned(
          bottom: -220,
          left: 0,
          right: 0,
          child: Center(
            child: _GlowBlob(
              color: const Color(0xFF22C55E),
              size: 460,
              opacity: 0.03,
            ),
          ),
        ),
      ],
    );
  }
}

class _GlowBlob extends StatelessWidget {
  final Color color;
  final double size;
  final double opacity;

  const _GlowBlob({
    required this.color,
    required this.size,
    this.opacity = 0.10,
  });

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: ClipOval(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 80, sigmaY: 80),
          child: Container(
            width: size,
            height: size,
            color: color.withOpacity(opacity),
          ),
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════
// PILL FIELD (matches HTML design)
// ════════════════════════════════════════════════════════════════

class _PillField extends StatefulWidget {
  final TextEditingController controller;
  final FocusNode focusNode;

  final String hint;
  final IconData icon;

  final Color accent; // ✅ focus color per-field

  final bool enabled;
  final bool obscureText;

  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onSubmitted;
  final Widget? trailing;

  const _PillField({
    required this.controller,
    required this.focusNode,
    required this.hint,
    required this.icon,
    required this.accent,
    this.enabled = true,
    this.obscureText = false,
    this.keyboardType,
    this.textInputAction,
    this.onSubmitted,
    this.trailing,
  });

  @override
  State<_PillField> createState() => _PillFieldState();
}

class _PillFieldState extends State<_PillField> {
  static const _field   = Color(0xFF22262F);
  static const _fieldHi = Color(0xFF262B35);

  bool _focused = false;

  @override
  void initState() {
    super.initState();
    _focused = widget.focusNode.hasFocus;
    widget.focusNode.addListener(_onFocus);
  }

  @override
  void didUpdateWidget(covariant _PillField old) {
    super.didUpdateWidget(old);
    if (old.focusNode != widget.focusNode) {
      old.focusNode.removeListener(_onFocus);
      widget.focusNode.addListener(_onFocus);
      _focused = widget.focusNode.hasFocus;
    }
  }

  void _onFocus() {
    if (!mounted) return;
    final f = widget.focusNode.hasFocus;
    if (f == _focused) return;
    setState(() => _focused = f);
  }

  @override
  void dispose() {
    widget.focusNode.removeListener(_onFocus);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final accent = widget.accent;
    final bg = _focused ? _fieldHi : _field;
    final borderColor = _focused
        ? accent.withOpacity(0.55)
        : Colors.transparent;
    final iconColor = _focused
        ? accent
        : Colors.white.withOpacity(0.50);

    return Opacity(
      opacity: widget.enabled ? 1 : 0.55,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
        height: 52,
        padding: const EdgeInsets.symmetric(horizontal: 18),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: borderColor, width: 1.2),
          boxShadow: _focused
              ? [
            BoxShadow(
              color: accent.withOpacity(0.10),
              blurRadius: 0,
              spreadRadius: 4,
            ),
          ]
              : null,
        ),
        child: Row(
          children: [
            Icon(widget.icon, color: iconColor, size: 22),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                controller: widget.controller,
                focusNode: widget.focusNode,
                enabled: widget.enabled,
                obscureText: widget.obscureText,
                keyboardType: widget.keyboardType,
                textInputAction: widget.textInputAction,
                onSubmitted: widget.onSubmitted,
                cursorColor: accent,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w500,
                  fontSize: 14.5,
                ),
                decoration: InputDecoration(
                  hintText: widget.hint,
                  hintStyle: TextStyle(
                    color: Colors.white.withOpacity(0.38),
                    fontWeight: FontWeight.w500,
                  ),
                  border: InputBorder.none,
                  isCollapsed: true,
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ),
            if (widget.trailing != null) widget.trailing!,
          ],
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════
// EYE BUTTON (circle hover, green on active)
// ════════════════════════════════════════════════════════════════

class _EyeButton extends StatelessWidget {
  final bool visible;
  final VoidCallback? onTap;
  final Color accent;

  const _EyeButton({
    required this.visible,
    required this.onTap,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Container(
          width: 34,
          height: 34,
          alignment: Alignment.center,
          child: Icon(
            visible ? Icons.visibility_off_rounded : Icons.visibility_rounded,
            color: accent.withOpacity(0.85),
            size: 21,
          ),
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════
// PRIMARY BUTTON (green pill, gradient, glow)
// ════════════════════════════════════════════════════════════════

class _PrimaryButton extends StatelessWidget {
  final String label;
  final bool loading;
  final VoidCallback? onTap;
  final IconData icon;

  const _PrimaryButton({
    required this.label,
    required this.loading,
    required this.onTap,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final disabled = onTap == null;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 180),
        opacity: disabled ? 0.6 : 1,
        child: Container(
          height: 54,
          width: double.infinity,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            gradient: const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Color(0xFF34D76F),
                Color(0xFF22C55E),
              ],
            ),
            boxShadow: disabled
                ? []
                : [
              BoxShadow(
                color: const Color(0xFF22C55E).withOpacity(0.35),
                blurRadius: 20,
                spreadRadius: -8,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Center(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
              child: loading
                  ? Row(
                key: const ValueKey('loading'),
                mainAxisSize: MainAxisSize.min,
                children: const [
                  SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Color(0xFF0A1A0F),
                    ),
                  ),
                  SizedBox(width: 10),
                  Text(
                    'Please wait…',
                    style: TextStyle(
                      color: Color(0xFF0A1A0F),
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                    ),
                  ),
                ],
              )
                  : Row(
                key: const ValueKey('idle'),
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, color: const Color(0xFF0A1A0F), size: 18),
                  const SizedBox(width: 10),
                  Text(
                    label,
                    style: const TextStyle(
                      color: Color(0xFF0A1A0F),
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
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
}