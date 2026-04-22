import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:image_picker/image_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class _WorkioPalette {
  static const bg = Color(0xFF0B0D12);
  static const pill = Color(0xFF1F2025);       // фон инпутов (как в Summary)
  static const pillBorder = Color(0xFF34353C); // базовый бордер

  // EXACT like Summary / _SolidPanel
  static const cardTop = Color(0xFF2F3036);
  static const cardBottom = Color(0xFF24252B);
  static const cardBorder = Color(0xFF3A3B42);

  static const textMain = Color(0xFFEDEFF6);
  static const textSoft = Color(0xFFB7BCCB);

  static const green = Color(0xFF34D399);
  static const orange = Color(0xFFF59E0B);
  static const blue = Color(0xFF38BDF8);
}

class AddWorkerDialog extends StatefulWidget {
  final VoidCallback onCreated;
  const AddWorkerDialog({super.key, required this.onCreated});

  @override
  State<AddWorkerDialog> createState() => _AddWorkerDialogState();
}

class _AddWorkerDialogState extends State<AddWorkerDialog> {
  final supabase = Supabase.instance.client;

  final emailCtrl = TextEditingController();
  final nameCtrl = TextEditingController();
  final rateCtrl = TextEditingController();

  final _emailFocus = FocusNode();
  final _nameFocus = FocusNode();
  final _rateFocus = FocusNode();

  bool loading = false;
  bool formOk = false;

  bool emailOk = false;
  bool nameOk = false;
  bool rateOk = false;

  File? avatarFile;
  final picker = ImagePicker();

  @override
  void initState() {
    super.initState();

    // ✅ live validation для enable/disable Create
    emailCtrl.addListener(_recalc);
    nameCtrl.addListener(_recalc);
    rateCtrl.addListener(_recalc);

    _recalc();
  }

  void _recalc() {
    final email = emailCtrl.text.trim().toLowerCase();
    final name = nameCtrl.text.trim();
    final rate = _parseRate(rateCtrl.text);

    final newEmailOk = _isEmailValid(email);
    final newNameOk = name.isNotEmpty;
    final newRateOk = rate != null && rate > 0;
    final newFormOk = newEmailOk && newNameOk && newRateOk;

    if (!mounted) return;

    if (emailOk != newEmailOk ||
        nameOk != newNameOk ||
        rateOk != newRateOk ||
        formOk != newFormOk) {
      setState(() {
        emailOk = newEmailOk;
        nameOk = newNameOk;
        rateOk = newRateOk;
        formOk = newFormOk;
      });
    }
  }

  bool _isEmailValid(String email) {
    // достаточно для UI (не идеальный RFC, зато быстрый)
    return email.contains('@') && email.contains('.') && email.length >= 5;
  }

  double? _parseRate(String raw) {
    final s = raw.trim().replaceAll(',', '.');
    return double.tryParse(s);
  }

  @override
  void dispose() {
    emailCtrl.removeListener(_recalc);
    nameCtrl.removeListener(_recalc);
    rateCtrl.removeListener(_recalc);

    emailCtrl.dispose();
    nameCtrl.dispose();
    rateCtrl.dispose();

    _emailFocus.dispose();
    _nameFocus.dispose();
    _rateFocus.dispose();

    super.dispose();
  }

  Future<void> _pickAvatarFromGallery() async {
    final x = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 75,
    );
    if (x == null) return;

    setState(() => avatarFile = File(x.path));
    HapticFeedback.selectionClick();
  }

  Future<void> _pickAvatarFromCamera() async {
    final x = await picker.pickImage(
      source: ImageSource.camera,
      imageQuality: 75,
      preferredCameraDevice: CameraDevice.front,
    );
    if (x == null) return;

    setState(() => avatarFile = File(x.path));
    HapticFeedback.selectionClick();
  }

  Future<void> _openAvatarPickerSheet() async {
    if (loading) return;

    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                child: Container(
                  padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(24),
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        Color(0xFF3C3F47),
                        Color(0xFF2E3138),
                        Color(0xFF262930),
                      ],
                    ),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.10),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.35),
                        blurRadius: 22,
                        offset: const Offset(0, 12),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 46,
                        height: 4,
                        margin: const EdgeInsets.only(bottom: 14),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.18),
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                      const Row(
                        children: [
                          Icon(
                            Icons.photo_camera_rounded,
                            color: Colors.white70,
                            size: 18,
                          ),
                          SizedBox(width: 10),
                          Text(
                            'Choose photo source',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w900,
                              fontSize: 15,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      _AvatarSourceTile(
                        icon: Icons.photo_camera_rounded,
                        title: 'Take photo',
                        subtitle: 'Open camera and make a profile picture',
                        accent: const Color(0xFF38BDF8),
                        onTap: () async {
                          Navigator.pop(context);
                          await _pickAvatarFromCamera();
                        },
                      ),
                      const SizedBox(height: 10),
                      _AvatarSourceTile(
                        icon: Icons.photo_library_rounded,
                        title: 'Choose from gallery',
                        subtitle: 'Pick an existing image from phone',
                        accent: const Color(0xFFF59E0B),
                        onTap: () async {
                          Navigator.pop(context);
                          await _pickAvatarFromGallery();
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Future<String?> _avatarAsDataUrl() async {
    if (avatarFile == null) return null;
    final bytes = await avatarFile!.readAsBytes();
    final b64 = base64Encode(bytes);
    return "data:image/jpeg;base64,$b64";
  }

  Future<void> _create() async {
    if (loading) return;

    // ✅ защита: если форма невалидна — ничего не делаем
    if (!formOk) {
      HapticFeedback.lightImpact();
      return;
    }

    final email = emailCtrl.text.trim().toLowerCase();
    final name = nameCtrl.text.trim();
    final rate = _parseRate(rateCtrl.text);

    // (на всякий случай — повторная валидация)
    if (!_isEmailValid(email)) {
      _showError(title: "Invalid email", message: "Please enter a valid email.");
      return;
    }
    if (name.isEmpty) {
      _showError(title: "Missing name", message: "Please enter worker name.");
      return;
    }
    if (rate == null || rate <= 0) {
      _showError(title: "Invalid rate", message: "Hourly rate must be greater than 0.");
      return;
    }

    setState(() => loading = true);

    try {
      final session = supabase.auth.currentSession;
      if (session == null) {
        _showError(title: "No session", message: "Please login as admin again.");
        return;
      }

      final avatarDataUrl = await _avatarAsDataUrl();

      final res = await supabase.functions.invoke(
        'create-worker',
        body: {
          'email': email,
          'name': name,
          'hourly_rate': rate,
          if (avatarDataUrl != null) 'avatar_base64': avatarDataUrl,
        },
        headers: {'Authorization': 'Bearer ${session.accessToken}'},
      );

      if (res.status == 200) {
        await _showSuccess(
          title: "Worker created",
          message: "Worker was successfully created.\nPassword setup email has been sent.",
        );

        widget.onCreated();
        if (mounted) Navigator.pop(context);
        return;
      }

      if (res.status == 409) {
        _showError(
          title: "Email already exists",
          message: "A worker with this email already exists.\nUse another email.",
          icon: Icons.warning_amber_rounded,
        );
        return;
      }

      _showError(
        title: "Error",
        message: res.data?.toString() ?? "Something went wrong.",
      );
    } on FunctionException catch (e) {
      // ✅ supabase_flutter может кидать FunctionException на 4xx/5xx
      final details = e.details?.toString() ?? e.toString();
      final low = details.toLowerCase();

      if (low.contains('worker_exists') || low.contains('already') || low.contains('registered')) {
        _showError(
          title: "Email already exists",
          message: "A worker with this email already exists.\nUse another email.",
          icon: Icons.warning_amber_rounded,
        );
      } else {
        _showError(title: "Create failed", message: details);
      }
    } catch (e) {
      _showError(title: "Create failed", message: e.toString());
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _showSuccess({required String title, required String message}) async {
    HapticFeedback.mediumImpact();

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => _StatusDialog(
        title: title,
        message: message,
        success: true,
        primaryLabel: "Done",
        onPrimary: () => Navigator.pop(context),
      ),
    );
  }

  void _showError({
    required String title,
    required String message,
    IconData icon = Icons.error_outline_rounded,
  }) {
    HapticFeedback.lightImpact();

    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (_) => _StatusDialog(
        title: title,
        message: message,
        success: false,
        icon: icon,
        primaryLabel: "OK",
        onPrimary: () => Navigator.pop(context),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final viewInsets = MediaQuery.of(context).viewInsets;

    return PopScope(
      canPop: !loading,
      child: Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
        child: SingleChildScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: EdgeInsets.only(bottom: viewInsets.bottom),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(28),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
              child: Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF2C2E32),
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.55),
                      blurRadius: 34,
                      offset: const Offset(0, 18),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.fromLTRB(18, 16, 18, 12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF34353C),
                        border: Border(
                          bottom: BorderSide(
                            color: Colors.white.withValues(alpha: 0.08),
                          ),
                        ),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.person_add_alt_1_rounded,
                            color: Colors.white70,
                            size: 20,
                          ),
                          const SizedBox(width: 10),
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Add worker',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w900,
                                    fontSize: 18,
                                    letterSpacing: 0.2,
                                  ),
                                ),
                                SizedBox(height: 2),
                                Text(
                                  'Invite a worker & set hourly rate',
                                  style: TextStyle(
                                    color: Colors.white54,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(height: 1, color: Colors.white.withOpacity(0.06)),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
                      child: AutofillGroup(
                        child: Column(
                          children: [
                            _PhotoPickField(
                              enabled: !loading,
                              onTap: loading ? null : _openAvatarPickerSheet,
                              avatarFile: avatarFile,
                            ),
                            const SizedBox(height: 14),
                            _FieldsSection(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      _GlassField(
                                        controller: emailCtrl,
                                        focusNode: _emailFocus,
                                        hint: 'Email address',
                                        icon: Icons.alternate_email_rounded,
                                        accent: const Color(0xFF38BDF8),
                                        keyboardType: TextInputType.emailAddress,
                                        enabled: !loading,
                                        textInputAction: TextInputAction.next,
                                        autofillHints: const [AutofillHints.email],
                                        isValid: emailOk,
                                        onSubmitted: (_) => _nameFocus.requestFocus(),
                                      ),
                                      const _FieldHint(
                                        icon: Icons.info_outline_rounded,
                                        text: 'Enter a valid worker email for login and invitation.',
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 10),
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      _GlassField(
                                        controller: nameCtrl,
                                        focusNode: _nameFocus,
                                        hint: 'Worker full name',
                                        icon: Icons.badge_rounded,
                                        accent: const Color(0xFFF59E0B),
                                        enabled: !loading,
                                        textInputAction: TextInputAction.next,
                                        autofillHints: const [AutofillHints.name],
                                        isValid: nameOk,
                                        onSubmitted: (_) => _rateFocus.requestFocus(),
                                      ),
                                      const _FieldHint(
                                        icon: Icons.person_outline_rounded,
                                        text: 'Use full real name so the profile looks correct.',
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 10),
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      _GlassField(
                                        controller: rateCtrl,
                                        focusNode: _rateFocus,
                                        hint: 'Hourly rate',
                                        icon: Icons.attach_money_rounded,
                                        accent: const Color(0xFF34D399),
                                        enabled: !loading,
                                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                        textInputAction: TextInputAction.done,
                                        inputFormatters: [
                                          FilteringTextInputFormatter.allow(RegExp(r'[\d\.,]')),
                                        ],
                                        isValid: rateOk,
                                        onSubmitted: (_) => _create(),
                                      ),
                                      const _FieldHint(
                                        icon: Icons.payments_outlined,
                                        text: 'Set hourly pay rate. Example: 18 or 18.50',
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 16),
                            Container(
                              height: 1.2,
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.centerLeft,
                                  end: Alignment.centerRight,
                                  colors: [
                                    Colors.transparent,
                                    const Color(0xFF59F0A7).withValues(alpha: 0.18),
                                    const Color(0xFF59F0A7).withValues(alpha: 0.55),
                                    const Color(0xFF59F0A7).withValues(alpha: 0.18),
                                    Colors.transparent,
                                  ],
                                ),
                              ),
                            ),
                            if (!loading) ...[
                              const SizedBox(height: 14),
                              Row(
                                children: [
                                  Icon(
                                    formOk ? Icons.verified_rounded : Icons.lock_rounded,
                                    size: 14,
                                    color: formOk
                                        ? Colors.white.withValues(alpha: 0.62)
                                        : Colors.white.withValues(alpha: 0.40),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      formOk
                                          ? 'Everything looks good. You can create the worker now.'
                                          : 'Fill Email, Name and Hourly rate to enable Create.',
                                      style: TextStyle(
                                        color: formOk
                                            ? Colors.white.withValues(alpha: 0.62)
                                            : Colors.white.withValues(alpha: 0.40),
                                        fontWeight: FontWeight.w700,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Expanded(
                                  child: _SecondaryPremiumButton(
                                    label: 'Cancel',
                                    icon: Icons.close_rounded,
                                    enabled: !loading,
                                    onTap: loading ? null : () => Navigator.pop(context),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: _PrimaryPremiumButton(
                                    label: loading ? 'Creating…' : 'Create',
                                    icon: Icons.person_add_alt_1_rounded,
                                    loading: loading,
                                    enabled: formOk && !loading,
                                    onTap: (formOk && !loading) ? _create : null,
                                  ),
                                ),
                              ],
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
      ),
    );
  }
}

class _SecondaryPremiumButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback? onTap;
  final bool enabled;

  const _SecondaryPremiumButton({
    required this.label,
    required this.icon,
    required this.onTap,
    required this.enabled,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: Opacity(
        opacity: enabled ? 1 : 0.55,
        child: Container(
          height: 52,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            color: Colors.white.withOpacity(0.06),
            border: Border.all(color: Colors.white.withOpacity(0.10)),
          ),
          child: Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, color: Colors.white70, size: 18),
                const SizedBox(width: 8),
                Text(
                  label,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PrimaryPremiumButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback? onTap;
  final bool enabled;
  final bool loading;

  const _PrimaryPremiumButton({
    required this.label,
    required this.icon,
    required this.onTap,
    required this.enabled,
    required this.loading,
  });

  @override
  Widget build(BuildContext context) {
    final bool locked = !enabled && !loading;

    final gradient = locked
        ? const LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [
        Color(0xFF5B5E66),
        Color(0xFF3E4047),
      ],
    )
        : const LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [
        Color(0xFF59F0A7),
        Color(0xFF1FA463),
      ],
    );

    final fg = locked
        ? Colors.white.withValues(alpha: 0.92)
        : Colors.black;
// 🔥 на красном/зелёном лучше чёрный
    final effectiveIcon = locked ? Icons.lock_rounded : icon;

    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        height: 52,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          gradient: gradient,
          border: Border.all(
            color: locked
                ? Colors.white.withValues(alpha: 0.14)
                : const Color(0xFF59F0A7).withValues(alpha: 0.24),
          ),
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
                Text('Creating…', style: TextStyle(color: Colors.black, fontWeight: FontWeight.w900)),
              ],
            )
                : Row(
              key: ValueKey(locked ? 'locked' : 'idle'),
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(effectiveIcon, color: fg),
                const SizedBox(width: 8),
                Text(
                  label,
                  style: TextStyle(color: fg, fontWeight: FontWeight.w900),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StatusDialog extends StatelessWidget {
  final String title;
  final String message;
  final bool success;
  final String primaryLabel;
  final VoidCallback onPrimary;
  final IconData icon;

  const _StatusDialog({
    required this.title,
    required this.message,
    required this.success,
    required this.primaryLabel,
    required this.onPrimary,
    this.icon = Icons.check_circle_outline_rounded,
  });

  @override
  Widget build(BuildContext context) {
    final IconData i = success ? Icons.check_circle_rounded : icon;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 22),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Container(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
          decoration: BoxDecoration(
            color: const Color(0xFF1E1C22),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: Colors.white.withOpacity(0.10)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Icon(i, color: success ? Colors.greenAccent : Colors.redAccent),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        fontSize: 16,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  message,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.60),
                    height: 1.35,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Align(
                alignment: Alignment.centerRight,
                child: SizedBox(
                  width: 140,
                  child: _PrimaryPremiumButton(
                    label: primaryLabel,
                    icon: Icons.check_rounded,
                    onTap: onPrimary,
                    enabled: true,
                    loading: false,
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
class _GlassField extends StatefulWidget {
  final TextEditingController controller;
  final FocusNode focusNode;

  final String hint;
  final IconData icon;

  final bool enabled;
  final bool obscureText;

  final Color accent;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onSubmitted;
  final Widget? trailing;
  final bool isValid;

  final List<String>? autofillHints;
  final List<TextInputFormatter>? inputFormatters;

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
    this.autofillHints,
    this.inputFormatters,
    this.isValid = false,
  });

  @override
  State<_GlassField> createState() => _GlassFieldState();
}

class _GlassFieldState extends State<_GlassField>
    with SingleTickerProviderStateMixin {
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

    if (!widget.enabled) {
      _pulse.stop();
      _pulse.value = 0;
    }
  }

  void _onFocus() {
    if (!mounted) return;
    final f = widget.focusNode.hasFocus;
    if (f == _focused) return;

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
    return Opacity(
      opacity: widget.enabled ? 1 : 0.55,
      child: AnimatedScale(
        scale: _focused ? 1.02 : 1.0,
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOutCubic,
        child: AnimatedBuilder(
          animation: _pulse,
          builder: (context, _) {
            final t = (_focused && widget.enabled) ? _pulse.value : 0.0;

            final borderColor = _focused
                ? widget.accent.withValues(alpha: 0.50 + 0.32 * t)
                : widget.isValid
                ? widget.accent.withValues(alpha: 0.42)
                : Colors.white.withValues(alpha: 0.14);

            final iconColor = _focused
                ? widget.accent.withValues(alpha: 0.88 + 0.12 * t)
                : widget.isValid
                ? widget.accent.withValues(alpha: 0.92)
                : Colors.white.withValues(alpha: 0.96);

            final trailingColor = widget.isValid
                ? widget.accent.withValues(alpha: 0.95)
                : (_focused && widget.enabled)
                ? widget.accent.withValues(alpha: 0.70 + 0.25 * t)
                : Colors.white.withValues(alpha: 0.35);

            return Container(
              height: 52,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: const Color(0xFF404047),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: borderColor,
                  width: (_focused || widget.isValid) ? 1.35 : 1.05,
                ),
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
                      autofillHints: widget.autofillHints,
                      inputFormatters: widget.inputFormatters,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.96),
                        fontWeight: FontWeight.w800,
                        fontSize: 14.5,
                      ),
                      decoration: InputDecoration(
                        hintText: widget.hint,
                        hintStyle: TextStyle(
                          color: Colors.white.withValues(alpha: 0.68),
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                        ),
                        border: InputBorder.none,
                      ),
                    ),
                  ),
                  if (widget.trailing != null || widget.isValid)
                    IconTheme(
                      data: IconThemeData(color: trailingColor, size: 20),
                      child: widget.trailing ??
                          Icon(
                            Icons.check_circle_rounded,
                            color: trailingColor,
                            size: 20,
                          ),
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
class _PhotoPickField extends StatefulWidget {
  final bool enabled;
  final VoidCallback? onTap;
  final File? avatarFile;

  const _PhotoPickField({
    required this.enabled,
    required this.onTap,
    required this.avatarFile,
  });

  @override
  State<_PhotoPickField> createState() => _PhotoPickFieldState();
}

class _PhotoPickFieldState extends State<_PhotoPickField>
    with SingleTickerProviderStateMixin {
  bool _pressed = false;
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  void _setPressed(bool v) {
    if (!mounted) return;
    if (_pressed == v) return;
    setState(() => _pressed = v);

    if (_pressed && widget.enabled) {
      _pulse.repeat(reverse: true);
    } else {
      _pulse.stop();
      _pulse.value = 0;
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const accent = Color(0xFFF59E0B);
    final selected = widget.avatarFile != null;

    return Opacity(
      opacity: widget.enabled ? 1 : 0.55,
      child: GestureDetector(
        onTapDown: (_) => _setPressed(true),
        onTapCancel: () => _setPressed(false),
        onTapUp: (_) => _setPressed(false),
        onTap: widget.enabled ? widget.onTap : null,
        child: AnimatedScale(
          scale: _pressed ? 1.02 : 1.0,
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOutCubic,
          child: AnimatedBuilder(
            animation: _pulse,
            builder: (_, __) {
              final t = (_pressed && widget.enabled) ? _pulse.value : 0.0;

              final borderColor = _pressed
                  ? accent.withValues(alpha: 0.45 + 0.35 * t)
                  : Colors.white.withValues(alpha: 0.12);


              final iconColor = _pressed
                  ? accent.withValues(alpha: 0.85 + 0.15 * t)
                  : Colors.white.withValues(alpha: 0.55);

              final titleColor = Colors.white.withValues(alpha: 0.92);

              final subColor = Colors.white.withValues(alpha: 0.62);

              return Container(
                height: 74,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Color(0xFF3C3F47),
                      Color(0xFF2E3138),
                      Color(0xFF262930),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: selected
                        ? Colors.white.withValues(alpha: 0.16)
                        : borderColor,
                    width: 1.15,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.30),
                      blurRadius: 22,
                      offset: const Offset(0, 12),
                    ),
                    BoxShadow(
                      color: Colors.white.withValues(alpha: 0.035),
                      blurRadius: 8,
                      offset: const Offset(0, -2),
                    ),
                  ],
                ),

                child: Row(
                  children: [
                    Container(
                      width: 50,
                      height: 50,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            Color(0xFF464852),
                            Color(0xFF34363E),
                          ],
                        ),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.12),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.18),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),

                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: widget.avatarFile == null
                            ? Icon(Icons.person_rounded, color: iconColor)
                            : Image.file(widget.avatarFile!, fit: BoxFit.cover),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            selected ? 'Photo added' : 'Add profile photo',
                            style: TextStyle(
                              color: titleColor,
                              fontWeight: FontWeight.w900,
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            selected
                                ? 'Ready for profile'
                                : 'Camera or gallery • optional',
                            style: TextStyle(
                              color: subColor,
                              fontWeight: FontWeight.w700,
                              fontSize: 11.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        gradient: selected
                            ? const LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            Color(0xFF59F0A7),
                            Color(0xFF1FA463),
                          ],
                        )
                            : null,
                        color: selected ? null : const Color(0xFF40424A),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                          color: selected
                              ? const Color(0xFF59F0A7).withValues(alpha: 0.26)
                              : Colors.white.withValues(alpha: 0.14),
                        ),
                      ),

                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            selected ? Icons.check_rounded : Icons.upload_rounded,
                            size: 16,
                            color: selected ? Colors.black : Colors.white.withValues(alpha: 0.75),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            selected ? 'Added' : 'Add',
                            style: TextStyle(
                              color: selected
                                  ? Colors.black
                                  : Colors.white.withValues(alpha: 0.75),
                              fontWeight: FontWeight.w900,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _AvatarSourceTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color accent;
  final VoidCallback onTap;

  const _AvatarSourceTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.accent,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.10),
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: accent.withValues(alpha: 0.28),
                  ),
                ),
                child: Icon(icon, color: accent, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        fontSize: 13.5,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.58),
                        fontWeight: FontWeight.w700,
                        fontSize: 11.5,
                        height: 1.2,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                color: Colors.white.withValues(alpha: 0.42),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FieldHint extends StatelessWidget {
  final IconData icon;
  final String text;

  const _FieldHint({
    required this.icon,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 6, 6, 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            icon,
            size: 14,
            color: Colors.white.withValues(alpha: 0.34),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.42),
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                height: 1.2,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FieldsSection extends StatelessWidget {
  final Widget child;

  const _FieldsSection({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(15, 15, 15, 15),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0xFF3C3F47),
            Color(0xFF2E3138),
            Color(0xFF262930),
          ],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.14),
          width: 1.15,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.30),
            blurRadius: 22,
            offset: const Offset(0, 12),
          ),
          BoxShadow(
            color: Colors.white.withValues(alpha: 0.035),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Stack(
        children: [
          Positioned(
            left: 12,
            right: 12,
            top: 0,
            child: Container(
              height: 1,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(999),
                gradient: LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: [
                    Colors.transparent,
                    Colors.white.withValues(alpha: 0.05),
                    Colors.white.withValues(alpha: 0.14),
                    Colors.white.withValues(alpha: 0.05),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: child,
          ),
        ],
      ),
    );
  }
}

