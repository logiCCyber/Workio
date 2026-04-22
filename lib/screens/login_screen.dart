import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../ui/app_toast.dart';

import 'worker_screen.dart';
import 'admin_panel.dart';

import '../utils/company_logo_helper.dart';

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

  // FocusNodes (для анимации фокуса)
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

  // ====== STYLE ======
  static const _bgTop = Color(0xFF0B0D12);
  static const _bgMid = Color(0xFF0A0C10);
  static const _bgBot = Color(0xFF07080C);

  static const _cardTop = Color(0xFF2F3036);
  static const _cardBottom = Color(0xFF24252B);

  static const _green1 = Color(0xFF6CFF8D);
  static const _green2 = Color(0xFF2E7D32);

  static const _textMain = Color(0xFFEDEFF6);
  static const _textSoft = Color(0xFFB7BCCB);

  void _toastInfo(String t) => AppToast.show(t);          // синий (default)
  void _toastOk(String t) => AppToast.success(t);         // зеленый
  void _toastWarn(String t) => AppToast.warning(t);       // оранжевый
  void _toastErr(String t) => AppToast.error(t);          // красный

  String _prettyAuthError(Object e) {
    if (e is AuthException) {
      final m = e.message;
      if (m.toLowerCase().contains('only request this after')) {
        return m; // покажет "wait 49 seconds" как есть
      }
      return m;
    }

    final s = e.toString().toLowerCase();
    if (s.contains('invalid login credentials')) return 'Wrong email or password';
    return 'Something went wrong. Try again.';
  }

  // ✅ ВАЖНО: ищем worker по auth_user_id (а не по id)
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

      // 🚫 BLOCK
      if (accessMode == 'suspended') {
        await supabase.auth.signOut();
        _toastErr('Your account is suspended. Contact admin.');
        return;
      }

      if (!mounted) return;

      // ✅ ADMIN
      if (role == 'admin') {
        Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const AdminPanel()));
        return;
      }

      // ✅ WORKER (active OR readonly)
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
      // ✅ Разрешаем reset только админам: проверяем email в admin_users
      final adminRow = await supabase
          .from('admin_users')
          .select('email')
          .eq('email', email)
          .maybeSingle();

      if (adminRow == null) {
        _toastErr('Password reset here is for admins only.');
        return;
      }

      // ✅ Шлём письмо на reset (оно откроет workio://reset-password)
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
        data: {'name': name, 'role': 'admin'}, // <-- ВАЖНО
      );

      // если включена email confirmation -> session будет null
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
      backgroundColor: _bgTop,
      body: Stack(
        children: [
          // BACKGROUND
          const _AuthBackground(),
          // CONTENT
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(18, 18, 18, 22),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 440),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(26),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                      child: Container(
                        decoration: BoxDecoration(
                          color: const Color(0xFF1E1C22), // solid
                          borderRadius: BorderRadius.circular(26),
                          border: Border.all(color: Colors.white.withOpacity(0.10)),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.55),
                              blurRadius: 34,
                              offset: const Offset(0, 18),
                            ),
                          ],
                        ),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // LOGO (big centered) + TITLE
                              Column(
                                children: [
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 6),
                                    child: Image.network(
                                      CompanyLogoHelper.defaultLogoUrl,
                                      height: 70,
                                      fit: BoxFit.contain,
                                      filterQuality: FilterQuality.high,
                                    )
                                  ),
                                  const SizedBox(height: 14),

                                  Text(
                                    isRegister ? 'Create admin' : 'Sign in',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      color: _textMain.withOpacity(0.92),
                                      fontWeight: FontWeight.w900,
                                      fontSize: 20,
                                    ),
                                  ),
                                  const SizedBox(height: 6),

                                  Text(
                                    isRegister
                                        ? 'Admin account (workers are created by admin)'
                                        : 'Admin / Worker login',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      color: _textSoft.withOpacity(0.75),
                                      fontWeight: FontWeight.w700,
                                      fontSize: 12.5,
                                    ),
                                  ),
                                ],
                              ),

                              const SizedBox(height: 14),

                              Container(
                                height: 2,
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: [
                                      Colors.transparent,
                                      _green1.withOpacity(0.55),
                                      Colors.transparent,
                                    ],
                                  ),
                                ),
                              ),

                              const SizedBox(height: 16),

                              AnimatedSwitcher(
                                duration: const Duration(milliseconds: 260),
                                switchInCurve: Curves.easeOutCubic,
                                switchOutCurve: Curves.easeInCubic,
                                transitionBuilder: (child, anim) {
                                  final inFrom = isRegister ? const Offset(0.08, 0) : const Offset(-0.08, 0);
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

                              const SizedBox(height: 14),

                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(
                                    isRegister ? 'Already have admin?' : 'Need admin account?',
                                    style: TextStyle(
                                      color: Colors.white.withOpacity(0.55),
                                      fontWeight: FontWeight.w700,
                                      fontSize: 12,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  InkWell(
                                    borderRadius: BorderRadius.circular(999),
                                    onTap: loading
                                        ? null
                                        : () => setState(() => isRegister = !isRegister),
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                                      child: Text(
                                        isRegister ? 'Sign in' : 'Create admin',
                                        style: TextStyle(
                                          color: _green1.withOpacity(0.95),
                                          fontWeight: FontWeight.w900,
                                          fontSize: 12.5,
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
        _GlassField(
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
        _GlassField(
          controller: _loginPass,
          focusNode: _fLoginPass,
          hint: 'Password',
          icon: Icons.lock_rounded,
          accent: const Color(0xFFF59E0B), // 🟠 password
          obscureText: !showPass,
          enabled: !loading,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _login(),
          trailing: IconButton(
            onPressed: loading ? null : () => setState(() => showPass = !showPass),
            icon: Icon(
              showPass ? Icons.visibility_off_rounded : Icons.visibility_rounded,
            ),
          ),
        ),
        const SizedBox(height: 8),
        ValueListenableBuilder<TextEditingValue>(
          valueListenable: _loginEmail,
          builder: (_, __, ___) {
            final email = _loginEmail.text.trim().toLowerCase();
            final canReset = !loading && email.contains('@'); // минимальная проверка

            return Align(
              alignment: Alignment.centerRight,
              child: InkWell(
                onTap: canReset ? _forgotPasswordAdmin : () {
                  _toastWarn('Enter admin email above');
                  FocusScope.of(context).requestFocus(_fLoginEmail);
                }, // ✅ можно нажать всегда
                borderRadius: BorderRadius.circular(999),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                  child: Text(
                    canReset ? 'Forgot password? (admin)' : 'Enter email to reset (admin)',
                    style: TextStyle(
                      color: canReset
                          ? Colors.white.withOpacity(0.60)
                          : Colors.white.withOpacity(0.30),
                      fontWeight: FontWeight.w800,
                      fontSize: 12,
                    ),
                  ),
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 8),
        const SizedBox(height: 16),
        _PrimaryButton(
          label: loading ? 'Signing in…' : 'Sign in',
          loading: loading,
          onTap: loading ? null : _login,
          icon: Icons.login_rounded, // ✅ вход
        ),
      ],
    );
  }

  Widget _registerForm() {
    return Column(
      key: const ValueKey('register'),
      children: [
        _GlassField(
          controller: _regName,
          focusNode: _fRegName,
          hint: 'Name',
          icon: Icons.badge_rounded,
          accent: Colors.white, // ⚪ name
          enabled: !loading,
          textInputAction: TextInputAction.next,
        ),
        const SizedBox(height: 12),
        _GlassField(
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
        _GlassField(
          controller: _regPass,
          focusNode: _fRegPass,
          hint: 'Password',
          icon: Icons.lock_rounded,
          accent: const Color(0xFFF59E0B), // 🟠 password
          obscureText: !showPass,
          enabled: !loading,
          textInputAction: TextInputAction.next,
          trailing: IconButton(
            onPressed: loading ? null : () => setState(() => showPass = !showPass),
            icon: Icon(
              showPass ? Icons.visibility_off_rounded : Icons.visibility_rounded,
            ),
          ),
        ),
        const SizedBox(height: 12),
        _GlassField(
          controller: _regPass2,
          focusNode: _fRegPass2,
          hint: 'Confirm password',
          icon: Icons.lock_outline_rounded,
          accent: const Color(0xFFF59E0B), // 🟠 confirm
          obscureText: !showPass2,
          enabled: !loading,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _registerAdmin(),
          trailing: IconButton(
            onPressed: loading ? null : () => setState(() => showPass2 = !showPass2),
            icon: Icon(
              showPass2 ? Icons.visibility_off_rounded : Icons.visibility_rounded,
            ),
          ),
        ),
        const SizedBox(height: 16),
        _PrimaryButton(
          label: loading ? 'Creating…' : 'Create admin',
          loading: loading,
          onTap: loading ? null : _registerAdmin,
          icon: Icons.person_add_alt_1_rounded, // ✅ человек + плюс
        ),
        const SizedBox(height: 10),
        Text(
          'Workers are created by admin inside the app.',
          style: TextStyle(
            color: Colors.white.withOpacity(0.45),
            fontWeight: FontWeight.w700,
            fontSize: 11.5,
          ),
        ),
      ],
    );
  }
}

class _AuthBackground extends StatelessWidget {
  const _AuthBackground();

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // base dark gradient
        Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Color(0xFF07080C),
                Color(0xFF0A0C10),
                Color(0xFF0B0D12),
              ],
            ),
          ),
        ),

        // mesh blobs (modern)
        Positioned(
          top: -160,
          left: -140,
          child: _GlowBlob(color: Color(0xFF34D399), size: 360, opacity: 0.12),
        ),
        Positioned(
          top: 80,
          right: -160,
          child: _GlowBlob(color: Color(0xFF38BDF8), size: 320, opacity: 0.10),
        ),
        Positioned(
          bottom: -190,
          right: -160,
          child: _GlowBlob(color: Color(0xFFA78BFA), size: 420, opacity: 0.12),
        ),

        // vignette (делает края "дороже")
        Positioned.fill(
          child: Container(
            decoration: const BoxDecoration(
              gradient: RadialGradient(
                center: Alignment(0, -0.2),
                radius: 1.2,
                colors: [
                  Colors.transparent,
                  Color(0xCC000000),
                ],
              ),
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
          filter: ImageFilter.blur(sigmaX: 50, sigmaY: 50),
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

class _GlassField extends StatefulWidget {
  final TextEditingController controller;
  final FocusNode focusNode;

  final String hint;
  final IconData icon;

  final bool enabled;
  final bool obscureText;

  final Color accent; // ✅ цвет фокуса (бордер/иконка)
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onSubmitted;
  final Widget? trailing;

  const _GlassField({
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
  State<_GlassField> createState() => _GlassFieldState();
}

class _GlassFieldState extends State<_GlassField> with SingleTickerProviderStateMixin {
  bool _focused = false;
  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _focused = widget.focusNode.hasFocus;

    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );

    widget.focusNode.addListener(_onFocus);

    // если экран открылся уже с фокусом
    if (_focused && widget.enabled) {
      _pulse.repeat(reverse: true);
    }
  }

  @override
  void didUpdateWidget(covariant _GlassField oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.focusNode != widget.focusNode) {
      oldWidget.focusNode.removeListener(_onFocus);

      _focused = widget.focusNode.hasFocus;
      widget.focusNode.addListener(_onFocus);

      if (_focused && widget.enabled) {
        _pulse.repeat(reverse: true);
      } else {
        _pulse.stop();
        _pulse.value = 0;
      }
    }
  }

  void _onFocus() {
    if (!mounted) return;

    final f = widget.focusNode.hasFocus;

    if (f == _focused) return; // чтобы лишний раз не setState
    setState(() => _focused = f);

    if (f && widget.enabled) {
      _pulse.repeat(reverse: true);
    } else {
      _pulse.stop();
      _pulse.value = 0;
    }
  }

  @override
  void dispose() {
    widget.focusNode.removeListener(_onFocus);
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final accent = widget.accent;

// ✅ фон всегда одинаковый (НЕ красим)
    final bg = Colors.white.withOpacity(0.05);

// ✅ красим только бордер
    final border = _focused
        ? accent.withOpacity(0.70)
        : Colors.white.withOpacity(0.10);

// ✅ красим только иконку
    final iconColor = _focused
        ? accent.withOpacity(0.95)
        : Colors.white.withOpacity(0.55);

    return Opacity(
      opacity: widget.enabled ? 1 : 0.55,
      child: AnimatedScale(
        scale: _focused ? 1.02 : 1.0,
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOutCubic,
        child: AnimatedBuilder(
          animation: _pulse,
          builder: (context, _) {
            final accent = widget.accent;

            // t = 0..1 только когда focused
            final t = (_focused && widget.enabled) ? _pulse.value : 0.0;

            // ✅ мигающий бордер (как в reset password)
            final borderColor = _focused
                ? accent.withOpacity(0.45 + 0.35 * t)  // 0.45 -> 0.80
                : Colors.white.withOpacity(0.10);

            // ✅ опционально: лёгкое “свечение” вокруг (если НЕ хочешь — просто удали boxShadow ниже)
            final glowOpacity = _focused ? (0.06 + 0.14 * t) : 0.0;

            // ✅ иконка тоже чуть оживает
            final iconColor = _focused
                ? accent.withOpacity(0.85 + 0.15 * t)
                : Colors.white.withOpacity(0.55);

            final trailingColor = (_focused && widget.enabled)
                ? accent.withOpacity(0.70 + 0.25 * t) // ✅ 0.70 -> 0.95 (мигает)
                : Colors.white.withOpacity(0.35);     // ✅ обычный серый

            return Container(
              height: 52,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.05),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: borderColor, width: 1.2),
              ),
              child: Row(
                children: [
                  Icon(widget.icon, color: iconColor),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: widget.controller,
                      focusNode: widget.focusNode,
                      enabled: widget.enabled,
                      obscureText: widget.obscureText,
                      keyboardType: widget.keyboardType,
                      textInputAction: widget.textInputAction,
                      onSubmitted: widget.onSubmitted,
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.92),
                        fontWeight: FontWeight.w800,
                      ),
                      decoration: InputDecoration(
                        hintText: widget.hint,
                        hintStyle: TextStyle(color: Colors.white.withOpacity(0.35)),
                        border: InputBorder.none,
                      ),
                    ),
                  ),
                  if (widget.trailing != null)
                    IconTheme(
                      data: IconThemeData(
                        color: trailingColor, // ✅ тут красим глазок
                        size: 20,
                      ),
                      child: widget.trailing!,
                    ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

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
    return GestureDetector(
      onTap: onTap,
      child: Opacity(
        opacity: onTap == null ? 0.55 : 1,
        child: Container(
          height: 52,
          width: double.infinity,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF6CFF8D), Color(0xFF2E7D32)],
            ),
            border: Border.all(color: Colors.white10),
            boxShadow: const [],
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
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                  ),
                  SizedBox(width: 10),
                  Text(
                    'Please wait…',
                    style: TextStyle(color: Colors.black, fontWeight: FontWeight.w900),
                  ),
                ],
              )
                  : Row(
                key: const ValueKey('idle'),
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, color: Colors.black),
                  const SizedBox(width: 10),
                  Text(
                    label,
                    style: const TextStyle(color: Colors.black, fontWeight: FontWeight.w900),
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