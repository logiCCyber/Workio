import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:ui';
import 'package:intl/intl.dart';
import 'package:flutter/services.dart';
import 'dart:async';

class _EditWorkerPalette {
  static const shell = Color(0xFF2C2E32);
  static const header = Color(0xFF34353C);

  static const panelTop = Color(0xFF3C3F47);
  static const panelMid = Color(0xFF2E3138);
  static const panelBottom = Color(0xFF262930);

  static const textMain = Color(0xFFEDEFF6);
  static const textSoft = Color(0xFFB7BCCB);}


class EditWorkerDialog extends StatefulWidget {
  final Map<String, dynamic> worker;

  const EditWorkerDialog({super.key, required this.worker});

  @override
  State<EditWorkerDialog> createState() => _EditWorkerDialogState();
}

class _EditWorkerDialogState extends State<EditWorkerDialog> {
  late bool _canViewAddress;
  bool _addressAccessSaving = false;
  late String _accessMode;
  final supabase = Supabase.instance.client;
  late TextEditingController emailCtrl;
  late String initialEmail;
  late double? initialRate;
  late TextEditingController nameCtrl;
  late TextEditingController rateCtrl;
  Timer? _undoTimer;
  bool _undoPressed = false;
  OverlayEntry? _snackOverlay;
  OverlayEntry? _undoOverlay;
  late ValueNotifier<int> _undoCounter;

  bool saving = false;
  bool sendingReset = false;
  int _resetCooldown = 0;
  Timer? _resetTimer;
  int historyCount = 0;
  Map<String, dynamic>? lastShift;
  bool get _onShiftLocked => widget.worker['on_shift'] == true;

  void _hideStyledSnack() {
    _snackOverlay?.remove();
    _snackOverlay = null;
  }

  bool get _accessModeLocked => _onShiftLocked;

  bool get _salaryLocked =>
      _onShiftLocked || _accessMode == 'view_only' || _accessMode == 'suspended';

  bool get _resetLocked =>
      _onShiftLocked || _accessMode == 'suspended';
  bool loadingLastShift = true;
  Map<String, dynamic>? lastChange;

  @override
  void initState() {
    super.initState();
    emailCtrl = TextEditingController(
      text: widget.worker['email'] ?? '',
    );
    nameCtrl = TextEditingController(text: widget.worker['name'] ?? '');
    rateCtrl = TextEditingController(
      text: (widget.worker['hourly_rate'] ?? '').toString(),
    );
    initialEmail = widget.worker['email'] ?? '';
    initialRate = widget.worker['hourly_rate']?.toDouble();

    Future.microtask(() async {
      final rows = await supabase
          .from('worker_rate_history')
          .select('old_rate,new_rate,changed_at')
          .eq('worker_id', widget.worker['id'])
          .order('changed_at', ascending: false);

      if (!mounted) return;

      setState(() {
        historyCount = rows.length;
        if (rows.isNotEmpty) {
          lastChange = rows.first;
        }
      });
    });

    Future.microtask(() async {
      try {
        final rows = await supabase
            .from('work_logs')
            .select('start_time, end_time, total_hours, total_payment')
            .eq('user_id', widget.worker['auth_user_id']) // ✅ ВАЖНО
            .not('end_time', 'is', null)
            .order('end_time', ascending: false)
            .limit(1);

        if (!mounted) return;

        setState(() {
          lastShift = rows.isNotEmpty ? rows.first : null;
          loadingLastShift = false;
        });
      } catch (e) {
        // ⛑️ чтобы НИКОГДА не зависало
        if (!mounted) return;
        setState(() {
          loadingLastShift = false;
          lastShift = null;
        });
      }
    });
    _accessMode = (widget.worker['access_mode'] ?? 'active').toString();
    _canViewAddress = widget.worker['can_view_address'] == true;
  }

  void _startResetCooldown() {
    _resetCooldown = 60;
    _resetTimer?.cancel();
    _resetTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;
      setState(() => _resetCooldown--);
      if (_resetCooldown <= 0) {
        t.cancel();
        _resetTimer = null;
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    emailCtrl.dispose();
    nameCtrl.dispose();
    rateCtrl.dispose();
    _resetTimer?.cancel();
    _hideStyledSnack();
    super.dispose();
  }

  void _showStyledSnack({
    required String text,
    required IconData icon,
    required Color accent,
  }) {
    if (!mounted) return;

    _hideStyledSnack();

    final overlay = Overlay.of(context, rootOverlay: true);
    if (overlay == null) return;

    final media = MediaQuery.of(context);

    _snackOverlay = OverlayEntry(
      builder: (_) {
        return Positioned(
          left: 14,
          right: 14,
          bottom: media.padding.bottom + 18,
          child: IgnorePointer(
            ignoring: true,
            child: Material(
              color: Colors.transparent,
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 18, end: 0),
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutCubic,
                builder: (context, value, child) {
                  return Transform.translate(
                    offset: Offset(0, value),
                    child: child,
                  );
                },
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(22),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                    child: Container(
                      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(22),
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            const Color(0xFF232833).withOpacity(0.96),
                            const Color(0xFF1A1F28).withOpacity(0.97),
                            const Color(0xFF141922).withOpacity(0.98),
                          ],
                        ),
                        border: Border.all(
                          color: accent.withOpacity(0.34),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: accent.withOpacity(0.16),
                            blurRadius: 18,
                            spreadRadius: -5,
                            offset: const Offset(0, 8),
                          ),
                          BoxShadow(
                            color: Colors.black.withOpacity(0.30),
                            blurRadius: 18,
                            offset: const Offset(0, 10),
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 38,
                            height: 38,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(13),
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [
                                  accent,
                                  accent.withOpacity(0.78),
                                ],
                              ),
                            ),
                            child: Icon(
                              icon,
                              color: Colors.white,
                              size: 19,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              text,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                                fontSize: 13.4,
                                height: 1.25,
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
          ),
        );
      },
    );

    overlay.insert(_snackOverlay!);

    Future.delayed(const Duration(milliseconds: 2200), () {
      if (mounted) {
        _hideStyledSnack();
      }
    });
  }

  Future<double> _getLastClosedMonthHours() async {
    final authUserId = widget.worker['auth_user_id'];
    if (authUserId == null) return 0;

    final now = DateTime.now();
    final currentMonthStart = DateTime(now.year, now.month, 1);
    final lastMonthStart = DateTime(now.year, now.month - 1, 1);

    final rows = await supabase
        .from('work_logs')
        .select('total_hours,end_time')
        .eq('user_id', authUserId)
        .not('end_time', 'is', null)
        .gte('end_time', lastMonthStart.toUtc().toIso8601String())
        .lt('end_time', currentMonthStart.toUtc().toIso8601String());

    double total = 0;
    for (final row in rows) {
      total += ((row['total_hours'] ?? 0) as num).toDouble();
    }

    return total;
  }

  Future<bool> _confirmAddressAccessChange(bool nextValue) async {
    final accent = nextValue
        ? const Color(0xFF59F0A7)
        : const Color(0xFFFF6B6B);

    final icon = nextValue
        ? Icons.location_on_rounded
        : Icons.location_off_rounded;

    final title = nextValue
        ? 'Enable address access?'
        : 'Disable address access?';

    final desc = nextValue
        ? 'The worker will be able to see shift start and end addresses in history.'
        : 'The worker will no longer see shift start and end addresses in history.';

    final actionText = nextValue ? 'Enable' : 'Disable';

    final gradient = nextValue
        ? const [Color(0xFF5CFF8A), Color(0xFF2E7D32)]
        : const [Color(0xFFFF8A80), Color(0xFFC62828)];

    return await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 22),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(26),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
            child: Container(
              padding: const EdgeInsets.fromLTRB(22, 20, 22, 22),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(26),
                color: const Color(0xFF2A2930),
                border: Border.all(
                  color: accent.withOpacity(0.28),
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Icon(
                        icon,
                        color: accent,
                        size: 22,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          title,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    height: 2,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.centerLeft,
                        end: Alignment.centerRight,
                        colors: [
                          Colors.transparent,
                          accent.withOpacity(0.45),
                          Colors.transparent,
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      desc,
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.68),
                        fontSize: 13,
                        height: 1.35,
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      Expanded(
                        child: GestureDetector(
                          onTap: () => Navigator.pop(context, false),
                          child: Container(
                            height: 48,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(999),
                              color: Colors.white.withOpacity(0.08),
                              border: Border.all(
                                color: Colors.white.withOpacity(0.10),
                              ),
                            ),
                            child: const Center(
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.close_rounded,
                                    size: 18,
                                    color: Colors.white70,
                                  ),
                                  SizedBox(width: 8),
                                  Text(
                                    'Cancel',
                                    style: TextStyle(
                                      color: Colors.white70,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: GestureDetector(
                          onTap: () => Navigator.pop(context, true),
                          child: Container(
                            height: 48,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(999),
                              gradient: LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: gradient,
                              ),
                            ),
                            child: Center(
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(icon, size: 18, color: Colors.black),
                                  const SizedBox(width: 8),
                                  Text(
                                    actionText,
                                    style: const TextStyle(
                                      color: Colors.black,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                ],
                              ),
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
    ) ??
        false;
  }

  Future<void> _setAddressAccess(bool value) async {
    if (_addressAccessSaving || value == _canViewAddress) return;

    final ok = await _confirmAddressAccessChange(value);
    if (!ok || !mounted) return;

    final previous = _canViewAddress;

    setState(() {
      _addressAccessSaving = true;
      _canViewAddress = value;
      widget.worker['can_view_address'] = value;
    });

    try {
      await supabase.from('workers').update({
        'can_view_address': value,
      }).eq('id', widget.worker['id']);

      _showStyledSnack(
        text: value
            ? 'Address access enabled'
            : 'Address access disabled',
        icon: value
            ? Icons.location_on_rounded
            : Icons.location_off_rounded,
        accent: value
            ? const Color(0xFF59F0A7)
            : const Color(0xFFFF6B6B),
      );
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _canViewAddress = previous;
        widget.worker['can_view_address'] = previous;
      });

      _showStyledSnack(
        text: 'Address access update failed',
        icon: Icons.error_rounded,
        accent: const Color(0xFFFF6B6B),
      );
    } finally {
      if (mounted) {
        setState(() {
          _addressAccessSaving = false;
        });
      }
    }
  }

  Future<void> _save() async {
    final rate = double.tryParse(rateCtrl.text.trim());

    // 0) validation
    if (rate == null) {
      _showStyledSnack(
        text: 'Enter valid hourly rate',
        icon: Icons.error_outline_rounded,
        accent: const Color(0xFFFF6B6B),
      );
      return;
    }

    // 🚫 blocked for view-only / suspended
    if (_salaryLocked) {
      final msg = _onShiftLocked
          ? 'Hourly rate cannot be changed while worker is on shift'
          : 'Hourly rate is disabled for view-only / suspended worker';

      _showStyledSnack(
        text: msg,
        icon: Icons.lock_rounded,
        accent: const Color(0xFFF59E0B),
      );
      return;
    }

    // 1) если не изменилось — просто закрываем (или можно ничего не делать)
    if (rate == initialRate) {
      Navigator.pop(context, false);
      return;
    }

    // 2) confirm
    final confirmed = await _confirmRateChange(
      (initialRate ?? 0).toDouble(),
      rate,
    );
    if (!confirmed) return;

    setState(() => saving = true);

    try {
      final adminId = supabase.auth.currentUser?.id;

      // ✅ 3) пишем историю (worker_rate_history)
      await supabase.from('worker_rate_history').insert({
        'worker_id': widget.worker['id'],
        'old_rate': (initialRate ?? 0).toDouble(),
        'new_rate': rate,
        'changed_by': adminId, // uuid auth.users.id
        'note': null,
      });

      // ✅ 4) обновляем workers (ставка + метаданные)
      await supabase.from('workers').update({
        'hourly_rate': rate,
        'hourly_rate_updated_at': DateTime.now().toUtc().toIso8601String(),
        'hourly_rate_updated_by': adminId,
      }).eq('id', widget.worker['id']);

      print('SESSION = ${supabase.auth.currentSession}');
      print('=== INVOKE EDGE FUNCTION ===');

      // 5) отправляем email воркеру
      await supabase.functions.invoke(
        'send-rate-change-email',
        body: {
          'worker_email': widget.worker['email'],
          'worker_name': widget.worker['name'],
          'old_rate': initialRate ?? 0,
          'new_rate': rate,
        },
      );

      print('=== INVOKE DONE ===');



      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      _showStyledSnack(
        text: 'Save failed: $e',
        icon: Icons.error_outline_rounded,
        accent: const Color(0xFFFF6B6B),
      );
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  void _showUndoOverlay({required String workerId}) {
    _undoPressed = false;
    _undoCounter = ValueNotifier<int>(6);
    _undoOverlay = OverlayEntry(
      builder: (context) {
        return Positioned.fill(
          child: Material(
            color: Colors.black.withOpacity(0.35), // лёгкий затемняющий слой
            child: Center(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeOutCubic,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E1C22),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: Colors.redAccent.withOpacity(0.4),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.4),
                      blurRadius: 20,
                    ),
                  ],
                ),
                width: 320,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // ICON
                    const Icon(
                      Icons.block_rounded,
                      color: Colors.redAccent,
                      size: 32,
                    ),

                    const SizedBox(height: 10),

                    const Text(
                      'Worker suspended',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        fontSize: 16,
                      ),
                    ),

                    const SizedBox(height: 6),

                    ValueListenableBuilder<int>(
                      valueListenable: _undoCounter,
                      builder: (_, value, __) {
                        return Text(
                          'Undo available for $value s',
                          style: const TextStyle(
                            color: Colors.white54,
                            fontSize: 13,
                          ),
                        );
                      },
                    ),

                    const SizedBox(height: 14),

                    // UNDO BUTTON
                    GestureDetector(
                      onTap: () async {
                        _undoPressed = true;
                        _undoTimer?.cancel();

                        _undoPressed = true;
                        _undoTimer?.cancel();

                        await supabase
                            .from('workers')
                            .update({
                          'access_mode': 'active',
                          'suspended_at': null,
                          'view_only_at': null,
                        })
                            .eq('id', workerId);

                        if (mounted) {
                          setState(() {
                            _accessMode = 'active';
                            widget.worker['access_mode'] = 'active';
                            widget.worker['suspended_at'] = null;
                            widget.worker['view_only_at'] = null;
                          });
                        }

                        _hideUndoOverlay();
                        HapticFeedback.mediumImpact();

                        HapticFeedback.mediumImpact();
                      },
                      child: Container(
                        height: 42,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(999),
                          color: Colors.redAccent.withOpacity(0.18),
                        ),
                        child: const Center(
                          child: Text(
                            'UNDO',
                            style: TextStyle(
                              color: Colors.redAccent,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 1,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );

    Overlay.of(context, rootOverlay: true).insert(_undoOverlay!);

    // ⏱ TIMER
    _undoTimer = Timer.periodic(const Duration(seconds: 1), (t) async {
      _undoCounter.value--;

      // _undoOverlay?.markNeedsBuild();

      if (_undoCounter.value <= 0) {
        t.cancel();

        // ⛔ СРАЗУ закрываем overlay
        _hideUndoOverlay();

        // ⏳ commit делаем отдельно
        await _commitSuspendIfNeeded(workerId);
      }

    });
  }

  Future<void> _showWorktimeModal({
    required bool success,
    required String title,
    required String message,
  }) async {
    await showDialog(
      context: context,
      barrierDismissible: true,
      builder: (_) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 22),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(26),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
            child: Container(
              padding: const EdgeInsets.fromLTRB(22, 20, 22, 22),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(26),
                color: const Color(0xFF2A2930),
                border: Border.all(
                  color: (success ? Colors.greenAccent : Colors.redAccent)
                      .withOpacity(0.25),
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    success ? Icons.check_circle : Icons.error_outline,
                    color: success ? Colors.greenAccent : Colors.redAccent,
                    size: 40,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    title,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    message,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white60,
                      fontSize: 13,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 18),
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      height: 46,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(999),
                        color: Colors.white.withOpacity(0.08),
                      ),
                      child: const Center(
                        child: Text(
                          'OK',
                          style: TextStyle(
                            color: Colors.white70,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
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

  String _friendlyResetError(Object e) {
    final s = e.toString().toLowerCase();

    if (s.contains('statuscode: 500') ||
        s.contains('error sending recovery email') ||
        s.contains('unexpected_failure')) {
      return 'Supabase cannot send the recovery email (Email provider/SMTP issue).\nCheck Auth email settings & logs.';
    }

    if (s.contains('rate limit')) return 'Too many attempts. Try again in a minute.';
    if (s.contains('redirect') || s.contains('not allowed')) return 'Redirect URL is not allowed.';
    if (s.contains('invalid email')) return 'Email format is invalid.';
    return 'Reset failed. Please try again.';
  }

  Future<void> _commitSuspendIfNeeded(String workerId) async {
    if (_undoPressed) return;

    final nowIso = DateTime.now().toUtc().toIso8601String();

    await supabase
        .from('workers')
        .update({
      'access_mode': 'suspended',
      'suspended_at': nowIso,
      'view_only_at': null,
    })
        .eq('id', workerId);

    if (!mounted) return;

    setState(() {
      _accessMode = 'suspended';
      widget.worker['access_mode'] = 'suspended';
      widget.worker['suspended_at'] = nowIso;
      widget.worker['view_only_at'] = null;
    });

    await supabase.functions.invoke(
      'notify-worker-access-change',
      body: {'worker_id': workerId, 'new_mode': 'suspended'},
    );

    _hideUndoOverlay();

    Navigator.of(context, rootNavigator: true).pop({
      'worker_id': workerId,
      'access_mode': 'suspended',
    });
  }

  void _hideUndoOverlay() {
    _undoTimer?.cancel();
    _undoTimer = null;
    _undoCounter.dispose();
    _undoOverlay?.remove();
    _undoOverlay = null;
  }

  Future<void> _openWorkerSummary() async {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _WorkerSummarySheet(
        worker: widget.worker,
        supabase: supabase,
      ),
    );
  }

  Future<void> _openRateHistory() async {
    final rows = await supabase
        .from('worker_rate_history')
        .select('old_rate,new_rate,changed_at')
        .eq('worker_id', widget.worker['id'])
        .order('changed_at', ascending: false);

    final lastMonthHours = await _getLastClosedMonthHours();

    if (!mounted) return;

    setState(() {
      historyCount = rows.length;
      if (rows.isNotEmpty) {
        lastChange = rows.first;
      }
    });

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _RateHistorySheet(
        rows: List<Map<String, dynamic>>.from(rows),
        lastMonthHours: lastMonthHours,
      ),
    );
  }


  Future<void> _resetPassword() async {
    if (_resetLocked) {
      await _showWorktimeModal(
        success: false,
        title: 'Action locked',
        message: _onShiftLocked
            ? 'Password reset is disabled while worker is on shift.'
            : 'Password reset is disabled while worker is suspended.',
      );
      return;
    }

    final email = emailCtrl.text.trim();
    print('RESET EMAIL => "$email"');
    if (email == null || email.isEmpty) {
      await _showWorktimeModal(
        success: false,
        title: 'No email',
        message: 'Worker email not found.',
      );
      return;
    }

    // ❗ cooldown защита
    if (_resetCooldown > 0) {
      await _showWorktimeModal(
        success: false,
        title: 'Please wait',
        message: 'Try again in $_resetCooldown seconds.',
      );
      return;
    }

    setState(() => sendingReset = true);

    try {
      await supabase.auth.resetPasswordForEmail(
        email,
        redirectTo: 'workio://reset-password',
      );

      if (!mounted) return;

      // ✅ success modal (только если реально успех)
      await _showWorktimeModal(
        success: true,
        title: 'Email sent',
        message: 'Password reset email was sent to the worker.',
      );

      // ✅ запускаем cooldown после успеха
      _startResetCooldown();
    } catch (e) {
      if (!mounted) return;
      print('RESET ERROR RAW => $e');

      if (e is AuthException) {
        print('AUTH message => ${e.message}');
        print('AUTH status  => ${e.statusCode}');
      }

      await _showWorktimeModal(
        success: false,
        title: 'Reset failed',
        message: _friendlyResetError(e),
      );
    } finally {
      if (mounted) setState(() => sendingReset = false);
    }
  }

  bool _emailChanged() {
    return emailCtrl.text.trim() != initialEmail.trim();
  }

  bool _rateChanged() {
    final rate = double.tryParse(rateCtrl.text);
    return rate != null && rate != initialRate;
  }

  bool get hasHistory => initialRate != null;

  @override
  Widget build(BuildContext context) {
    final String accessMode = _accessMode;
    final bool onShift = widget.worker['on_shift'] == true;
    final String? lastActivityRaw = widget.worker['last_activity']?.toString();
    print('🔥🔥🔥 EDIT WORKER DIALOG FROM edit_worker_dialog.dart 🔥🔥🔥');
    return Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 8),
        backgroundColor: Colors.transparent,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(26),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
            child: Container(
              decoration: BoxDecoration(
                color: _EditWorkerPalette.shell,
                borderRadius: BorderRadius.circular(26),
                border: Border.all(
                  color: Colors.white.withOpacity(0.10),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.55),
                    blurRadius: 34,
                    offset: const Offset(0, 18),
                  ),
                ],
              ),
              child: Stack(
            children: [
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [

                  // ================= HEADER =================
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
                    decoration: BoxDecoration(
                      color: _EditWorkerPalette.header,
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(26),
                        topRight: Radius.circular(26),
                      ),
                      border: Border(
                        bottom: BorderSide(
                          color: Colors.white.withOpacity(0.08),
                        ),
                      ),
                    ),



                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.edit, color: Colors.white),
                            const SizedBox(width: 10),
                            const Expanded(
                              child: Text(
                                'Edit worker',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                            GestureDetector(
                              onTap: () => Navigator.pop(context),
                              child: Container(
                                width: 34,
                                height: 34,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(10),
                                  color: Colors.white.withOpacity(0.06),
                                  border: Border.all(
                                    color: Colors.white.withOpacity(0.08),
                                  ),
                                ),
                                child: const Icon(
                                  Icons.close_rounded,
                                  size: 20,
                                  color: Colors.white70,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        const Row(
                          children: [
                            Icon(
                              Icons.info_outline,
                              size: 14,
                              color: Colors.white38,
                            ),
                            SizedBox(width: 6),
                            Text(
                              'Change hourly rate and manage worker access',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.white38,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  // ================= BODY =================

                  Container(
                    padding: const EdgeInsets.fromLTRB(12, 20, 12, 20),
                    decoration: const BoxDecoration(
                      borderRadius: BorderRadius.only(
                        bottomLeft: Radius.circular(26),
                        bottomRight: Radius.circular(26),
                      ),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // ================= WORKER CARD (ONE CARD) =================
                    Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(24),
                        gradient: const LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            _EditWorkerPalette.panelTop,
                            _EditWorkerPalette.panelMid,
                            _EditWorkerPalette.panelBottom,
                          ],
                        ),
                        border: Border.all(
                          color: Colors.white.withOpacity(0.14),
                          width: 1.15,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.30),
                            blurRadius: 22,
                            offset: const Offset(0, 12),
                          ),
                          BoxShadow(
                            color: Colors.white.withOpacity(0.035),
                            blurRadius: 8,
                            offset: const Offset(0, -2),
                          ),
                        ],
                      ),
                      child: Column(

                      children: [
                        _IOSIdentitySection(
                          worker: widget.worker,
                          onOpenSettings: _openAccessModeSheet,
                          onOpenRateHistory: _openRateHistory,
                          onOpenSummary: _openWorkerSummary,
                          accessMode: _accessMode,
                          accessModeLocked: _accessModeLocked,
                          salaryLocked: _salaryLocked,
                          resetLocked: _resetLocked,
                          canViewAddress: _canViewAddress,
                          addressAccessSaving: _addressAccessSaving,
                          onToggleAddressAccess: _setAddressAccess,
                          onResetPassword: () async {
                            if (sendingReset || _resetCooldown > 0) {
                              await _showWorktimeModal(
                                success: false,
                                title: 'Please wait',
                                message: _resetCooldown > 0
                                    ? 'Try again in $_resetCooldown seconds.'
                                    : 'Request is processing…',
                              );
                              return;
                            }

                            final ok = await _confirmResetPassword();
                            if (!ok) return;
                            await _resetPassword();
                          },
                          onEditRate: () {
                            HapticFeedback.lightImpact();
                            _editRateFromCard();
                          },
                          rateText: rateCtrl.text,
                          hasHistory: historyCount > 0,
                          onShowSnack: (text, icon, accent) => _showStyledSnack(
                            text: text,
                            icon: icon,
                            accent: accent,
                          ),
                        ),


                        const SizedBox(height: 12),
                            ],
                          ),
                        ),

                        const SizedBox(height: 20),
                      ],
                    ),
                  ),

                ],
              ),
            ],
          ),
        ),
      ),
    ),
   );
  }


  // ===== HELPERS =====

  Widget _label(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Align(
      alignment: Alignment.centerLeft,
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 12,
          color: Colors.white60,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),
  );

  String _accessLabel(String? mode) {
    switch (mode) {
      case 'readonly':
        return 'Access: View only';
      case 'suspended':
        return 'Access: Suspended';
      default:
        return 'Access: Active';
    }
  }

  Widget _iconCapsule({
    required IconData icon,
    required Color color,
  }) {
    return Container(
      width: 34,
      height: 34,
      decoration: BoxDecoration(
        color: color.withOpacity(0.18),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: color.withOpacity(0.45),
        ),
      ),
      child: Icon(
        icon,
        size: 18,
        color: color,
      ),
    );
  }

  Widget _iosDivider() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Divider(
        height: 20,
        thickness: 1,
        color: Colors.white.withOpacity(0.08),
      ),
    );
  }

  Widget _glassField({required IconData icon, required String text}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: Colors.white.withOpacity(0.06),
      ),
      child: Row(
        children: [
          Icon(icon, color: Colors.white54),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(color: Colors.white60),
            ),
          ),
        ],
      ),
    );
  }

  Widget _input({
    required TextEditingController controller,
    required IconData icon,
    required String hint,
    TextInputType? keyboardType,
  }) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: Colors.white.withOpacity(0.06),
      ),
      child: TextField(
        controller: controller,
        keyboardType: keyboardType,
        style: const TextStyle(color: Colors.white),
        decoration: InputDecoration(
          prefixIcon: Icon(icon, color: Colors.white54),
          hintText: hint,
          hintStyle: const TextStyle(color: Colors.white38),
          border: InputBorder.none,
        ),
      ),
    );
  }

  Widget _actionButton({
    required String label,
    required Color color,
    required VoidCallback? onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 46,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(999),
          color: color.withOpacity(0.18),
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
      ),
    );
  }
  Future<bool> _confirmRateChange(double oldRate, double newRate) async {
    return await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 22),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(26),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
            child: Container(
              padding: const EdgeInsets.fromLTRB(22, 20, 22, 22),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(26),
                color: const Color(0xFF2A2930),
                border: Border.all(
                  color: Colors.greenAccent.withOpacity(0.18),
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ===== HEADER =====
                  Row(
                    children: const [
                      Icon(
                        Icons.help_outline_rounded,
                        color: Colors.greenAccent,
                        size: 22,
                      ),
                      SizedBox(width: 10),
                      Text(
                        'Are you sure?',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: Colors.white70,
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 12),

                  // ===== DIVIDER =====
                  Container(
                    height: 2,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.centerLeft,
                        end: Alignment.centerRight,
                        colors: [
                          Colors.transparent,
                          Colors.greenAccent.withOpacity(0.45),
                          Colors.transparent,
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 16),

                  // ===== INFO TEXT =====
                  Text(
                    'You are about to change the worker’s hourly rate '
                        'from \$${oldRate.toStringAsFixed(2)} '
                        'to \$${newRate.toStringAsFixed(2)}.',
                    style: const TextStyle(
                      color: Colors.white60,
                      fontSize: 13,
                      height: 1.4,
                    ),
                  ),

                  const SizedBox(height: 10),

                  const Text(
                    'This change will affect future payments and will be '
                        'recorded in the rate history.',
                    style: TextStyle(
                      color: Colors.white38,
                      fontSize: 12,
                      height: 1.4,
                    ),
                  ),

                  const SizedBox(height: 26),

                  // ===== ACTIONS =====
                  Row(
                    children: [
                      // CANCEL
                      Expanded(
                        child: GestureDetector(
                          onTap: () => Navigator.pop(context, false),
                          child: Container(
                            height: 48,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(999),
                              color: Colors.white.withOpacity(0.08),
                            ),
                            child: const Center(
                              child: Text(
                                'Cancel',
                                style: TextStyle(
                                  color: Colors.white70,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),

                      const SizedBox(width: 14),

                      // CONFIRM
                      Expanded(
                        child: GestureDetector(
                          onTap: () => Navigator.pop(context, true),
                          child: Container(
                            height: 48,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(999),
                              gradient: const LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [
                                  Color(0xFF6CFF8D),
                                  Color(0xFF2E7D32),
                                ],
                              ),
                            ),
                            child: const Center(
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.check_circle,
                                    size: 18,
                                    color: Colors.black,
                                  ),
                                  SizedBox(width: 8),
                                  Text(
                                    'Confirm',
                                    style: TextStyle(
                                      color: Colors.black,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                ],
                              ),
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
    ) ??
        false;
  }


  Future<bool> _confirmResetPassword() async {
    return await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 22),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(26),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
            child: Container(
              padding: const EdgeInsets.fromLTRB(22, 20, 22, 22),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(26),
                color: const Color(0xFF2A2930),
                border: Border.all(
                  color: Colors.white.withOpacity(0.08),
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ===== HEADER =====
                  Row(
                    children: const [
                      Icon(
                        Icons.lock_reset_rounded,
                        color: Colors.redAccent,
                        size: 22,
                      ),
                      SizedBox(width: 10),
                      Text(
                        'Reset password?',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: Colors.white70,
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 12),

                  // ===== DIVIDER =====
                  Container(
                    height: 2,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.centerLeft,
                        end: Alignment.centerRight,
                        colors: [
                          Colors.transparent,
                          Colors.white.withOpacity(0.35),
                          Colors.transparent,
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 16),

                  const Text(
                    'A password reset email will be sent to the worker. '
                        'They will be able to set a new password securely.',
                    style: TextStyle(
                      color: Colors.white60,
                      fontSize: 13,
                      height: 1.4,
                    ),
                  ),

                  const SizedBox(height: 26),

                  // ===== ACTIONS =====
                  Row(
                    children: [
                      // CANCEL
                      Expanded(
                        child: GestureDetector(
                          onTap: () => Navigator.pop(context, false),
                          child: Container(
                            height: 48,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(999),
                              color: Colors.white.withOpacity(0.08),
                            ),
                            child: const Center(
                              child: Text(
                                'Cancel',
                                style: TextStyle(
                                  color: Colors.white70,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),

                      const SizedBox(width: 14),

                      // CONFIRM
                      Expanded(
                        child: GestureDetector(
                          onTap: () => Navigator.pop(context, true),
                          child: Container(
                            height: 48,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(999),
                              gradient: const LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [
                                  Color(0xFFFF6C6C), // мягкий amber
                                  Color(0xFFB20000),
                                ],
                              ),
                            ),
                            child: const Center(
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.send_rounded,
                                    size: 18,
                                    color: Colors.black,
                                  ),
                                  SizedBox(width: 8),
                                  Text(
                                    'Send',
                                    style: TextStyle(
                                      color: Colors.black,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                ],
                              ),
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
    ) ??
        false;
  }


  Future<bool> _confirmDisable() async {
    return await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1E1C22),
        title: const Text(
          'Disable worker?',
          style: TextStyle(color: Colors.white),
        ),
        content: const Text(
          'The worker will lose access to the system.',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text(
              'Disable',
              style: TextStyle(color: Colors.redAccent),
            ),
          ),
        ],
      ),
    ) ??
        false;
  }

  Future<bool> _confirmSuspend() async {
    return await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 22),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(26),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
            child: Container(
              padding: const EdgeInsets.fromLTRB(22, 20, 22, 22),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(26),
                color: const Color(0xFF2A2930),
                border: Border.all(
                  color: Colors.redAccent.withValues(alpha: 0.35),
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ===== HEADER =====
                  Row(
                    children: const [
                      Icon(
                        Icons.block_rounded,
                        color: Colors.redAccent,
                        size: 24,
                      ),
                      SizedBox(width: 10),
                      Text(
                        'Suspend worker?',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                          color: Colors.white70,
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 12),

                  // ===== DIVIDER =====
                  Container(
                    height: 2,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.centerLeft,
                        end: Alignment.centerRight,
                        colors: [
                          Colors.transparent,
                          Colors.redAccent.withOpacity(0.45),
                          Colors.transparent,
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 16),

                  // ===== INFO =====
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: const [
                      Icon(
                        Icons.warning_amber_rounded,
                        size: 16,
                        color: Colors.redAccent,
                      ),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'The worker will NOT be able to log in to the system.\n'
                              'All active sessions will be blocked immediately.',
                          style: TextStyle(
                            color: Colors.white60,
                            fontSize: 13,
                            height: 1.4,
                          ),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 26),

                  // ===== ACTIONS =====
                  Row(
                    children: [
                      // CANCEL
                      Expanded(
                        child: GestureDetector(
                          onTap: () => Navigator.pop(context, false),
                          child: Container(
                            height: 48,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(999),
                              color: Colors.white.withOpacity(0.08),
                            ),
                            child: const Center(
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.close_rounded,
                                    size: 18,
                                    color: Colors.white70,
                                  ),
                                  SizedBox(width: 8),
                                  Text(
                                    'Cancel',
                                    style: TextStyle(
                                      color: Colors.white70,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),

                      const SizedBox(width: 14),

                      // SUSPEND
                      Expanded(
                        child: GestureDetector(
                          onTap: () => Navigator.pop(context, true),
                          child: Container(
                            height: 48,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(999),
                              gradient: const LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [
                                  Color(0xFFFF6C6C),
                                  Color(0xFFB20000),
                                ],
                              ),
                            ),
                            child: const Center(
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.block_rounded,
                                    size: 18,
                                    color: Colors.black,
                                  ),
                                  SizedBox(width: 8),
                                  Text(
                                    'Suspend',
                                    style: TextStyle(
                                      color: Colors.black,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                ],
                              ),
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
    ) ?? false;
  }

  Future<bool> _confirmAccessModeChange(String mode) async {
    final isActive = mode == 'active';
    final color = isActive ? const Color(0xFF34D399) : const Color(0xFFF39C12);
    final icon = isActive ? Icons.check_circle_rounded : Icons.visibility_rounded;

    final title = isActive ? 'Activate worker?' : 'Set view-only mode?';
    final desc = isActive
        ? 'The worker will have full access again.'
        : 'The worker can log in, but cannot make changes.';

    final actionText = isActive ? 'Activate' : 'Apply';

    return await showDialog<bool>(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 22),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(26),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
            child: Container(
              padding: const EdgeInsets.fromLTRB(22, 20, 22, 22),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(26),
                color: const Color(0xFF2A2930),
                border: Border.all(color: Colors.white.withOpacity(0.10)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          color: color.withOpacity(0.18),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: color.withOpacity(0.35)),
                        ),
                        child: Icon(icon, color: color, size: 20),
                      ),
                      const SizedBox(width: 12),

                      Expanded(
                        child: Text(
                          title,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 12),

// ✅ divider ПОД заголовком (как в suspended)
                  Container(
                    width: double.infinity,
                    height: 2,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.centerLeft,
                        end: Alignment.centerRight,
                        colors: [
                          Colors.transparent,
                          color.withOpacity(0.45), // зелёный для Active, оранжевый для View-only
                          Colors.transparent,
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 12),

// ✅ описание ПОСЛЕ divider
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      desc,
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.65),
                        fontSize: 13,
                        height: 1.35,
                      ),
                    ),
                  ),

                  const SizedBox(height: 18),

                  Row(
                    children: [
                      Expanded(
                        child: GestureDetector(
                          onTap: () => Navigator.pop(context, false),
                          child: Container(
                            height: 48,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(999),
                              color: Colors.white.withOpacity(0.08),
                              border: Border.all(color: Colors.white.withOpacity(0.10)),
                            ),
                            child: const Center(
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.close_rounded, size: 18, color: Colors.white70),
                                  SizedBox(width: 8),
                                  Text(
                                    'Cancel',
                                    style: TextStyle(
                                      color: Colors.white70,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: GestureDetector(
                          onTap: () => Navigator.pop(context, true),
                          child: Container(
                            height: 48,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(999),
                              gradient: LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: isActive
                                    ? const [Color(0xFF5CFF8A), Color(0xFF2E7D32)]
                                    : const [Color(0xFFF7B733), Color(0xFFB26A00)],
                              ),
                            ),
                            child: Center(
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(icon, size: 18, color: Colors.black),
                                  const SizedBox(width: 8),
                                  Text(
                                    actionText,
                                    style: const TextStyle(
                                      color: Colors.black,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                ],
                              ),
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
    ) ?? false;
  }

  void _openAccessModeSheet() {
    if (_accessModeLocked) {
      _showStyledSnack(
        text: 'Access mode cannot be changed while worker is on shift',
        icon: Icons.block_rounded,
        accent: const Color(0xFFFF6B6B),
      );
      return;
    }

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _AccessModeSheet(
        current: _accessMode,
        onSelect: (mode) async {
          if (mode == 'suspended') {
            final ok = await _confirmSuspend();
            if (!ok) return;

            Navigator.pop(context); // ❗ закрываем ТОЛЬКО sheet

            await Future.delayed(const Duration(milliseconds: 120));
            _showUndoOverlay(workerId: widget.worker['id']);
            return;
          }

          // ✅ 1) закрываем ТОЛЬКО bottom sheet
          Navigator.pop(context);

          if (mode == 'active' || mode == 'view_only') {
            final ok = await _confirmAccessModeChange(mode);
            if (!ok) return;
          }

// ✅ 2) сразу меняем UI в этом окне (чтобы было видно моментально)
          final nowIso = DateTime.now().toUtc().toIso8601String();

// ✅ 2) сразу меняем UI (чтобы мгновенно)
          if (mounted) {
            setState(() {
              _accessMode = mode;

              // обновляем локальную worker-карту (иначе после relogin/refresh может прыгать)
              widget.worker['access_mode'] = mode;

              // ✅ если ставим readonly -> записываем дату, иначе чистим
              widget.worker['view_only_at'] = (mode == 'view_only') ? nowIso : null;

              // ✅ если это не suspended ветка -> suspended_at чистим
              widget.worker['suspended_at'] = null;
            });
          }

          try {

            await supabase.from('workers').update({
              'access_mode': mode,

              // ✅ ставим дату ТОЛЬКО когда readonly, иначе очищаем
              'view_only_at': mode == 'view_only' ? nowIso : null,

              // ✅ раз мы тут НЕ в suspended ветке — suspended_at всегда чистим
              'suspended_at': null,
            }).eq('id', widget.worker['id']);

            // ✅ 4) нотификация (как у тебя было)
            await supabase.functions.invoke(
              'notify-worker-access-change',
              body: {
                'worker_id': widget.worker['id'],
                'new_mode': mode,
              },
            );
          } catch (e) {
            // если упало — покажем ошибку (можно убрать)
            if (!mounted) return;
            _showStyledSnack(
              text: 'Access change error: $e',
              icon: Icons.error_outline_rounded,
              accent: const Color(0xFFFF6B6B),
            );
          }

        },
      ),
    );
  }

  Future<void> _editRateFromCard() async {
    if (_salaryLocked) {
      final msg = _onShiftLocked
          ? 'Hourly rate cannot be changed while worker is on shift'
          : 'Hourly rate is disabled for this worker';

      _showStyledSnack(
        text: msg,
        icon: Icons.lock_rounded,
        accent: const Color(0xFFF59E0B),
      );
      return;
    }

    final controller = TextEditingController(
      text: rateCtrl.text,
    );

    const double minRate = 5.0;
    const double maxRate = 200.0;

    final result = await showDialog<double>(
      context: context,
      barrierDismissible: true,
      builder: (_) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 22),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(26),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
            child: Container(
              padding: const EdgeInsets.fromLTRB(22, 20, 22, 22),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(26),
                color: const Color(0xFF2A2930), // ✅ как карточки
                border: Border.all(
                  color: Colors.white.withOpacity(0.10),
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // ===== HEADER =====
                  Row(
                    children: const [
                      Icon(
                        Icons.edit_rounded, // ✏️
                        color: Colors.greenAccent,
                        size: 22,
                      ),
                      SizedBox(width: 10),
                      Text(
                        'Change hourly rate',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: Colors.white70,
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 10),

                  // ===== GRADIENT DIVIDER =====
                  Container(
                    height: 2,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.centerLeft,
                        end: Alignment.centerRight,
                        colors: [
                          Colors.transparent,
                          Colors.greenAccent.withOpacity(0.5),
                          Colors.transparent,
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 10),

                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: const [
                      Icon(
                        Icons.info_outline,
                        size: 14,
                        color: Colors.white38,
                      ),
                      SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'This hourly rate will be used for all future shifts. '
                              'Past shifts will not be affected.',
                          style: TextStyle(
                            color: Colors.white38,
                            fontSize: 12,
                            height: 1.4,
                          ),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 20),

                  // ===== INPUT =====
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      color: Colors.white.withOpacity(0.06),
                      border: Border.all(
                        color: Colors.white.withOpacity(0.12),
                      ),
                    ),
                    child: TextField(
                      controller: controller,
                      keyboardType: TextInputType.number,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                      decoration: InputDecoration(
                        border: InputBorder.none,
                        hintText: 'Enter new rate',
                        hintStyle: const TextStyle(color: Colors.white38),
                        prefixIcon: const Icon(
                          Icons.attach_money_rounded,
                          color: Colors.greenAccent, // ✅ зелёная
                        ),
                        helperText: 'Min $minRate  •  Max $maxRate',
                        helperStyle: const TextStyle(
                          color: Colors.white38,
                          fontSize: 12,
                        ),
                        suffixIcon: SizedBox(
                          width: 36, // фиксируем ширину
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              _rateStepButton(
                                icon: Icons.keyboard_arrow_up,
                                onTap: () => _changeRateValue(
                                  controller,
                                  0.5,
                                  minRate,
                                  maxRate,
                                ),
                              ),
                              _rateStepButton(
                                icon: Icons.keyboard_arrow_down,
                                onTap: () => _changeRateValue(
                                  controller,
                                  -0.5,
                                  minRate,
                                  maxRate,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 26),

                  // ===== ACTIONS =====
                  Row(
                    children: [
                      // CANCEL
                      Expanded(
                        child: GestureDetector(
                          onTap: () => Navigator.pop(context),
                          child: Container(
                            height: 48,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(999),
                              color: Colors.white.withOpacity(0.08),
                            ),
                            child: const Center(
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.close_rounded,
                                      size: 18, color: Colors.white70),
                                  SizedBox(width: 8),
                                  Text(
                                    'Cancel',
                                    style: TextStyle(
                                      color: Colors.white70,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),

                      const SizedBox(width: 14),

                      // SAVE
                      Expanded(
                        child: GestureDetector(
                          onTap: () {
                            final v =
                            double.tryParse(controller.text.trim());
                            if (v == null) return;

                            if (v < minRate || v > maxRate) {
                              _showStyledSnack(
                                text: 'Rate must be between $minRate and $maxRate',
                                icon: Icons.tune_rounded,
                                accent: const Color(0xFFF59E0B),
                              );
                              return;
                            }

                            Navigator.pop(context, v);
                          },
                          child: Container(
                            height: 48,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(999),
                              gradient: const LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [
                                  Color(0xFF6CFF8D),
                                  Color(0xFF2E7D32),
                                ],
                              ),
                            ),
                            child: const Center(
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.check_circle,
                                      color: Colors.black),
                                  SizedBox(width: 8),
                                  Text(
                                    'Save',
                                    style: TextStyle(
                                      color: Colors.black,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                ],
                              ),
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
    );



    if (result == null) return;

    // записываем в контроллер
    rateCtrl.text = result.toStringAsFixed(2);

    // и сохраняем
    await _save();
  }

  void _changeRateValue(
      TextEditingController ctrl,
      double delta,
      double min,
      double max,
      ) {
    final current = double.tryParse(ctrl.text) ?? min;
    double next = current + delta;

    if (next < min) next = min;
    if (next > max) next = max;

    ctrl.text = next.toStringAsFixed(1);
    HapticFeedback.selectionClick();
  }

  Widget _rateStepButton({
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 26,
        height: 22,
        margin: const EdgeInsets.symmetric(vertical: 2),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.08),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Icon(
          icon,
          size: 18,
          color: Colors.white70,
        ),
      ),
    );
  }



}
class _RateHistorySheet extends StatelessWidget {
  final List<Map<String, dynamic>> rows;
  final double lastMonthHours;

  const _RateHistorySheet({
    required this.rows,
    required this.lastMonthHours,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          color: const Color(0xFF1E1C22),
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.7,
          ),
          child: Column(
            children: [
              const SizedBox(height: 8),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              const SizedBox(height: 12),
              Column(
                children: const [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.history_rounded, color: Colors.lightBlueAccent, size: 20),
                      SizedBox(width: 8),
                      Text(
                        'Rate history',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                          fontSize: 16,
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 6),
                  Text(
                    'Track all changes made to the worker’s hourly rate.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white38,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: rows.length,
                  itemBuilder: (context, index) {
                    final r = rows[index];

                    return rateHistoryRow(
                      index: index,
                      from: (r['old_rate'] as num).toDouble(),
                      to: (r['new_rate'] as num).toDouble(),
                      at: DateTime.parse(r['changed_at']).toLocal(),
                      lastMonthHours: lastMonthHours,
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Widget _glassSection({
  required String title,
  required IconData icon,
  Color iconColor = Colors.white70,
  required Widget child,
}) {
  return Container(
    margin: const EdgeInsets.only(bottom: 14),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(20),
      color: const Color(0xFF1B1A1F), // темнее, чем фон
      border: Border.all(color: Colors.white.withOpacity(0.06)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ===== HEADER =====
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.25),
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(20),
            ),
          ),
          child: Row(
            children: [
              Icon(icon, size: 18, color: iconColor),
              const SizedBox(width: 8),
              Text(
                title,
                style: TextStyle(
                  color: iconColor,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),

        // ===== BODY =====
        Padding(
          padding: const EdgeInsets.all(14),
          child: child,
        ),
      ],
    ),
  );
}
class _MiniStat extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String text;

  const _MiniStat({
    required this.icon,
    required this.color,
    required this.text,
  });


  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 4),
        Text(
          text,
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}
class WorkerAvatar extends StatelessWidget {
  final String? avatarUrl;
  final double size;

  const WorkerAvatar({
    super.key,
    required this.avatarUrl,
    this.size = 56,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.purpleAccent.withOpacity(0.25),
      ),
      clipBehavior: Clip.antiAlias,
      child: avatarUrl != null && avatarUrl!.isNotEmpty
          ? Image.network(
        avatarUrl!,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _fallback(),
      )
          : _fallback(),
    );
  }

  Widget _fallback() => const Icon(
    Icons.person_rounded,
    size: 30,
    color: Colors.purpleAccent,
  );
}
class _AccessChip extends StatelessWidget {
  final String label;
  final String value;
  final String current;
  final Color color;
  final VoidCallback onSelect;

  const _AccessChip({
    required this.label,
    required this.value,
    required this.current,
    required this.color,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final selected = value == current;

    return GestureDetector(
      onTap: onSelect,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(999),
          color: selected ? color.withOpacity(0.25) : Colors.white.withOpacity(0.06),
          border: Border.all(
            color: selected ? color : Colors.white24,
          ),
        ),
        child: Text(
          label.toUpperCase(),
          style: TextStyle(
            color: selected ? color : Colors.white60,
            fontWeight: FontWeight.w900,
            fontSize: 11,
            letterSpacing: 0.6,
          ),
        ),
      ),
    );
  }
}

class _AccessModeSheet extends StatelessWidget {
  final String current;
  final ValueChanged<String> onSelect;

  const _AccessModeSheet({
    required this.current,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          decoration: BoxDecoration(
            color: const Color(0xFF1E1C22),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
            border: Border.all(color: Colors.white.withOpacity(0.08)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // ===== HANDLE =====
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(999),
                ),
              ),

              const SizedBox(height: 16),

              // ===== TITLE =====
              const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: const [
                  Icon(
                    Icons.security_rounded, // 🛡 shield
                    size: 22,
                    color: Colors.amberAccent, // 🟡 yellow
                  ),
                  SizedBox(width: 10),
                  Text(
                    'Access mode',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),


              const SizedBox(height: 6),

              const Text(
                'Control what the worker can do in the system',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.white38,
                ),
              ),

              const SizedBox(height: 20),

              _modeTile(
                context,
                label: 'Active',
                value: 'active',
                icon: Icons.check_circle,
                color: Colors.greenAccent,
              ),

              _modeTile(
                context,
                label: 'View only',
                value: 'view_only',
                icon: Icons.visibility,
                color: Colors.orangeAccent,
              ),

              _modeTile(
                context,
                label: 'Suspended',
                value: 'suspended',
                icon: Icons.block,
                color: Colors.redAccent,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _modeTile(
      BuildContext context, {
        required String label,
        required String value,
        required IconData icon,
        required Color color,
      }) {
    final selected = value == current;

    return GestureDetector(
      onTap: () => onSelect(value),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          color: selected
              ? color.withOpacity(0.18)
              : Colors.white.withOpacity(0.05),
          border: Border.all(
            color: selected ? color : Colors.white24,
          ),
        ),
        child: Row(
          children: [
            Icon(icon, color: selected ? color : Colors.white54),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  color: selected ? color : Colors.white70,
                ),
              ),
            ),
            if (selected)
              Icon(Icons.check, color: color),
          ],
        ),
      ),
    );
  }
}
class IOSSection extends StatelessWidget {
  final Widget child;

  const IOSSection({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(5),
        color: Colors.white.withOpacity(0.06),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: child,
    );
  }
}

class _IOSIdentitySection extends StatelessWidget {
  final void Function(String text, IconData icon, Color accent) onShowSnack;
  final bool accessModeLocked;
  final Map<String, dynamic> worker;
  final VoidCallback onOpenSettings;
  final VoidCallback onOpenRateHistory;
  final String rateText;
  final bool hasHistory;
  final String accessMode; // 🔥 ВАЖНО
  final VoidCallback onEditRate;
  final VoidCallback onOpenSummary;
  final Future<void> Function() onResetPassword;
  final bool salaryLocked;
  final bool resetLocked;
  final bool canViewAddress;
  final bool addressAccessSaving;
  final Future<void> Function(bool) onToggleAddressAccess;

  const _IOSIdentitySection({
    required this.accessModeLocked,
    required this.onShowSnack,
    required this.worker,
    required this.onOpenSettings,
    required this.onOpenRateHistory,
    required this.rateText,
    required this.hasHistory,
    required this.accessMode, // 🔥 ВАЖНО
    required this.onEditRate,
    required this.onOpenSummary,
    required this.onResetPassword,
    required this.salaryLocked,
    required this.resetLocked,
    required this.canViewAddress,
    required this.addressAccessSaving,
    required this.onToggleAddressAccess,
  });


  Widget softCapsuleRow({
    required IconData icon,
    required Color iconColor,
    required String text,
    Widget? trailing,
    VoidCallback? onTap,
    Color? backgroundColor,
    Color? borderColor,
    Color? textColor,
    IconData? textPrefixIcon,
    Color? textPrefixIconColor,
    double verticalPadding = 12,
    double iconBoxSize = 36,
    double iconSize = 22,
    double textSize = 15,
    FontWeight textWeight = FontWeight.w600,
    double? fixedHeight,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: fixedHeight,
        padding: EdgeInsets.symmetric(horizontal: 14, vertical: verticalPadding),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          color: backgroundColor ?? const Color(0xFF1B1A1F),
          border: Border.all(
            color: borderColor ?? Colors.white.withOpacity(0.12),
          ),
        ),
        child: Row(
          children: [
            Container(
              width: iconBoxSize,
              height: iconBoxSize,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: iconColor.withOpacity(0.18),
              ),
              child: Center(
                child: Icon(
                  icon,
                  size: iconSize,
                  color: iconColor,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Row(
                children: [
                  if (textPrefixIcon != null) ...[
                    Icon(
                      textPrefixIcon,
                      size: 13,
                      color: textPrefixIconColor ?? Colors.white.withOpacity(0.34),
                    ),
                    const SizedBox(width: 6),
                  ],
                  Expanded(
                    child: Text(
                      text,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: textSize,
                        color: textColor ?? Colors.white70,
                        fontWeight: textWeight,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (trailing != null) ...[
              const SizedBox(width: 8),
              trailing,
            ],
          ],
        ),
      ),
    );
  }


  Widget _softDivider() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(44, 10, 0, 10),
      child: Container(
        height: 1,
        color: Colors.white.withOpacity(0.08),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final mode = accessMode;
    final bool onShift = worker['on_shift'] == true;

    Color color;
    String label;
    IconData icon;

    switch (mode) {
      case 'view_only':
        color = Colors.orangeAccent;
        label = 'View only';
        icon = Icons.visibility;
        break;
      case 'suspended':
        color = Colors.redAccent;
        label = 'Suspended';
        icon = Icons.block;
        break;
      default:
        color = Colors.greenAccent;
        label = 'Active';
        icon = Icons.verified_rounded;
    }

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ===== HEADER: NAME + STATUS =====
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              // ===== NAME =====
              Expanded(
                child: Row(
                  children: [
                    // 👤 ФИОЛЕТОВЫЙ ЧЕЛОВЕЧЕК
                    Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: color.withOpacity(0.18), // 👈 зависит от access
                      ),
                      child: Icon(
                        Icons.person_rounded,
                        size: 16,
                        color: color, // 👈 зависит от access
                      ),
                    ),


                    const SizedBox(width: 8),

                    // 👤 ИМЯ
                    Expanded(
                      child: Text(
                        worker['name'] ?? '—',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                          letterSpacing: 0.1,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),


              const SizedBox(width: 8),

              // ===== STATUS CHIP =====
              Baseline(
                baseline: 16 * 1.2,
                baselineType: TextBaseline.alphabetic,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(icon, size: 18, color: color),
                    const SizedBox(width: 6),
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: color,
                        height: 1.1,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          GradientDivider(color: color),
          const SizedBox(height: 14),

          // ===== AVATAR + INFO =====
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // EMAIL + COPY
                    softCapsuleRow(
                      icon: Icons.email,
                      iconColor: Colors.white70,
                      text: worker['email'] ?? '—',
                      trailing: Tooltip(
                        message: 'Tap to copy email',
                        waitDuration: const Duration(milliseconds: 400),
                        child: GestureDetector(
                          onTap: () {
                            final email = worker['email'] ?? '';
                            if (email.isEmpty) return;

                            Clipboard.setData(ClipboardData(text: email));
                            HapticFeedback.selectionClick();

                            onShowSnack(
                              'Email successfully copied',
                              Icons.check_circle_rounded,
                              const Color(0xFF59F0A7),
                            );
                          },
                          child: const Icon(
                            Icons.copy_rounded,
                            size: 24,
                            color: Colors.white38,
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 8),

                    softCapsuleRow(
                      icon: canViewAddress
                          ? Icons.location_on_rounded
                          : Icons.location_off_rounded,
                      iconColor: canViewAddress
                          ? const Color(0xFF59F0A7)
                          : const Color(0xFFFF6B6B),
                      text: 'Address access',
                      verticalPadding: 9,
                      iconBoxSize: 32,
                      iconSize: 19,
                      textSize: 14,
                      textWeight: FontWeight.w700,
                      trailing: IgnorePointer(
                        ignoring: addressAccessSaving,
                        child: AnimatedOpacity(
                          duration: const Duration(milliseconds: 160),
                          opacity: addressAccessSaving ? 0.55 : 1,
                          child: Switch.adaptive(
                            value: canViewAddress,
                            onChanged: addressAccessSaving
                                ? null
                                : (v) => onToggleAddressAccess(v),
                          ),
                        ),
                      ),
                      onTap: addressAccessSaving
                          ? null
                          : () => onToggleAddressAccess(!canViewAddress),
                    ),
                    const SizedBox(height: 8),
                    // ACCESS
                    softCapsuleRow(
                      icon: Icons.security,
                      iconColor: accessModeLocked ? Colors.white12 : Colors.yellowAccent,
                      text: accessModeLocked
                          ? 'Access locked while on shift'
                          : 'Access: $label',
                      textPrefixIcon: accessModeLocked ? Icons.info_outline_rounded : null,
                      textPrefixIconColor: accessModeLocked
                          ? const Color(0xFFFFC14D).withOpacity(0.55)
                          : null,
                      textSize: accessModeLocked ? 12.4 : 15,
                      textWeight: accessModeLocked ? FontWeight.w700 : FontWeight.w600,
                      fixedHeight: 58,
                      backgroundColor: accessModeLocked
                          ? Colors.white.withOpacity(0.04)
                          : const Color(0xFF1B1A1F),
                      borderColor: accessModeLocked
                          ? Colors.white12
                          : Colors.white.withOpacity(0.12),
                      textColor: accessModeLocked
                          ? Colors.white38
                          : Colors.white70,
                      trailing: Tooltip(
                        message: accessModeLocked
                            ? 'Access mode is locked while worker is on shift'
                            : 'Change worker access permissions',
                        child: Icon(
                          accessModeLocked ? Icons.lock_rounded : Icons.settings,
                          size: 24,
                          color: accessModeLocked ? Colors.white12 : Colors.white38,
                        ),
                      ),
                      onTap: accessModeLocked ? null : onOpenSettings,
                    ),

                    const SizedBox(height: 8),

                    // RATE + ACTIONS
                    softCapsuleRow(
                      icon: Icons.attach_money,
                      iconColor: salaryLocked ? Colors.white12 : Colors.greenAccent,
                      text: salaryLocked
                          ? (onShift
                          ? 'Hourly rate locked while on shift'
                          : 'Hourly rate editing disabled')
                          : '$rateText / h',
                      textPrefixIcon: salaryLocked ? Icons.info_outline_rounded : null,
                      textPrefixIconColor: salaryLocked
                          ? const Color(0xFFFFC14D).withOpacity(0.55)
                          : null,
                      textSize: salaryLocked ? 12.4 : 15,
                      textWeight: salaryLocked ? FontWeight.w700 : FontWeight.w600,
                      fixedHeight: 58,
                      backgroundColor: salaryLocked
                          ? Colors.white.withOpacity(0.04)
                          : const Color(0xFF1B1A1F),
                      borderColor: salaryLocked
                          ? Colors.white12
                          : Colors.white.withOpacity(0.12),
                      textColor: salaryLocked
                          ? Colors.white38
                          : Colors.white70,
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Tooltip(
                            message: onShift
                                ? 'Hourly rate is locked while worker is on shift'
                                : salaryLocked
                                ? 'Rate change disabled for this worker'
                                : 'Edit hourly rate',
                            child: GestureDetector(
                              onTap: salaryLocked ? null : onEditRate,
                              child: Icon(
                                salaryLocked ? Icons.lock_rounded : Icons.edit_rounded,
                                size: 24,
                                color: salaryLocked ? Colors.white12 : Colors.white38,
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Tooltip(
                            message: 'View rate change history',
                            child: GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: salaryLocked ? null : (hasHistory ? onOpenRateHistory : null),
                              child: Icon(
                                Icons.history_rounded,
                                size: 24,
                                color: salaryLocked
                                    ? Colors.white12
                                    : (hasHistory ? Colors.white38 : Colors.white12),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),

                    // 📊 WORKER SUMMARY (как обычная строка)
                    softCapsuleRow(
                      icon: Icons.analytics_rounded,
                      iconColor: Colors.lightBlueAccent,
                      text: 'Worker summary',
                      trailing: Tooltip(
                        message: 'View work and payment summary',
                        child: const Icon(
                          Icons.chevron_right_rounded,
                          size: 28,
                          color: Colors.white38,
                        ),
                      ),
                      onTap: onOpenSummary,
                    ),

                    _softDivider(),

                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: HoldToConfirmRow(
                        enabled: !resetLocked,
                        holdDuration: const Duration(milliseconds: 900),
                        onConfirmed: onResetPassword,
                        child: softCapsuleRow(
                          icon: Icons.lock_reset_rounded,
                          iconColor: resetLocked ? Colors.white12 : Colors.redAccent,
                          text: resetLocked
                              ? (onShift
                              ? 'Password reset locked while on shift'
                              : 'Password reset disabled')
                              : 'Reset password',
                          textPrefixIcon: resetLocked ? Icons.info_outline_rounded : null,
                          textPrefixIconColor: resetLocked
                              ? const Color(0xFFFFC14D).withOpacity(0.55)
                              : null,
                          textSize: resetLocked ? 12.4 : 15,
                          textWeight: resetLocked ? FontWeight.w700 : FontWeight.w600,
                          fixedHeight: 58,
                          backgroundColor: resetLocked
                              ? Colors.white.withOpacity(0.04)
                              : const Color(0xFF241416),
                          borderColor: resetLocked
                              ? Colors.white12
                              : Colors.redAccent.withOpacity(0.35),
                          textColor: resetLocked
                              ? Colors.white38
                              : Colors.white70,
                          trailing: Icon(
                            resetLocked ? Icons.lock_rounded : Icons.key_rounded,
                            size: 22,
                            color: resetLocked ? Colors.white12 : Colors.redAccent,
                          ),
                        ),
                      ),
                    ),


                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );

  }
}

class _IOSCompensationSection extends StatelessWidget {
  final Map<String, dynamic> worker;
  const _IOSCompensationSection(this.worker);

  @override
  Widget build(BuildContext context) {
    return IOSSection(
      child: Row(
        children: [
          const Icon(Icons.attach_money, color: Colors.greenAccent),
          const SizedBox(width: 8),
          Text(
            '\$${worker['hourly_rate'] ?? '--'} / h',
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: Colors.greenAccent,
            ),
          ),
        ],
      ),
    );
  }
}
class _IOSAccessSection extends StatelessWidget {
  final Map<String, dynamic> worker;
  final VoidCallback onOpenSettings;

  const _IOSAccessSection({
    required this.worker,
    required this.onOpenSettings,
  });

  @override
  Widget build(BuildContext context) {
    final mode = worker['access_mode'] ?? 'active';

    late Color color;
    late String label;
    late IconData icon;

    switch (mode) {
      case 'view_only':
        color = Colors.orangeAccent;
        label = 'View only';
        icon = Icons.visibility;
        break;
      case 'suspended':
        color = Colors.redAccent;
        label = 'Suspended';
        icon = Icons.block;
        break;
      default:
        color = Colors.greenAccent;
        label = 'Active';
        icon = Icons.verified_rounded;
    }

    return IOSSection(
      child: Stack(
        children: [
          // ===== MAIN CONTENT =====
          Row(
            children: [
              Icon(
                Icons.security_rounded,
                size: 26,
                color: Colors.white70,
              ),
              const SizedBox(width: 10),
              const Text(
                'Access',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: Colors.white70,
                ),
              ),
            ],
          ),

          // ===== STATUS BADGE (TOP RIGHT) =====
          Positioned(
            top: 0,
            right: 0,
            child: Row(
              children: [
                Container(
                  padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.18),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Row(
                    children: [
                      Icon(icon, size: 16, color: color),
                      const SizedBox(width: 6),
                      Text(
                        label,
                        style: TextStyle(
                          color: color,
                          fontWeight: FontWeight.w900,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                GestureDetector(
                  onTap: onOpenSettings,
                  child: Icon(
                    Icons.settings,
                    size: 20,
                    color: Colors.white38,
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

class _IOSActivitySection extends StatelessWidget {
  final Map<String, dynamic> worker;
  const _IOSActivitySection(this.worker);

  @override
  Widget build(BuildContext context) {
    final bool onShift = worker['on_shift'] == true;
    final String? last = worker['last_activity'];

    return IOSSection(
      child: Row(
        children: [
          Icon(
            onShift ? Icons.circle : Icons.schedule,
            size: 14,
            color: onShift ? Colors.greenAccent : Colors.white38,
          ),
          const SizedBox(width: 8),
          Text(
            onShift
                ? 'Active now'
                : last == null
                ? 'No activity yet'
                : 'Last shift: ${DateFormat.MMMd().add_Hm().format(DateTime.parse(last).toLocal())}',
            style: const TextStyle(fontSize: 12, color: Colors.white38),
          ),
        ],
      ),
    );
  }
}
class _IOSMetaSection extends StatelessWidget {
  final Map<String, dynamic> worker;
  const _IOSMetaSection(this.worker);

  @override
  Widget build(BuildContext context) {
    return IOSSection(
      child: Align(
        alignment: Alignment.centerRight,
        child: Text(
          'ID: ${worker['id'].toString().substring(0, 6)}',
          style: const TextStyle(fontSize: 11, color: Colors.white38),
        ),
      ),
    );
  }
}
class _WorkerSummarySheet extends StatefulWidget {
  final Map<String, dynamic> worker;
  final SupabaseClient supabase;

  const _WorkerSummarySheet({
    required this.worker,
    required this.supabase,
  });

  @override
  State<_WorkerSummarySheet> createState() => _WorkerSummarySheetState();
}

class _WorkerSummarySheetState extends State<_WorkerSummarySheet> {
  bool loading = true;
  bool _appear = false;
  String? error;
  int completedShifts = 0;
  DateTime? dataUpdatedAt;
  double projectedMonthHours = 0;
  double projectedMonthCost = 0;
  double lastMonthHours = 0;
  double lastMonthCost = 0;

  double hoursDeltaPct = 0;
  double costDeltaPct = 0;

  double projectedDelta = 0; // loss / savings

  bool exceedsLimit = false;

// лимиты админа (пока константы)
  final double maxMonthlyHours = 360;
  final double maxMonthlyCost = 7000;

  // summary fields
  Map<String, dynamic>? lastShift;
  double totalHours = 0;
  double totalEarned = 0;
  double avgRate = 0;

  // best/worst month
  String? bestMonthLabel;
  double bestMonthEarned = 0;
  double bestMonthHours = 0;

  String? worstMonthLabel;
  double worstMonthEarned = 0;
  double worstMonthHours = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      setState(() {
        loading = true;
        error = null;
      });

      final authId = widget.worker['auth_user_id'];
      if (authId == null) {
        throw 'worker.auth_user_id is null';
      }

      // ✅ Берем все work_logs (для аналитики)
      final rows = await widget.supabase
          .from('work_logs')
          .select('start_time,end_time,total_hours,total_payment')
          .eq('user_id', authId)
          .not('end_time', 'is', null)
          .order('end_time', ascending: false);

      final list = List<Map<String, dynamic>>.from(rows);

      completedShifts = list.length;
      dataUpdatedAt = DateTime.now();


      if (list.isEmpty) {
        setState(() {
          loading = false;
          lastShift = null;
          totalHours = 0;
          totalEarned = 0;
          avgRate = 0;
        });
        return;
      }

      // last shift
      lastShift = list.first;

      // totals + month grouping
      final Map<String, _MonthAgg> byMonth = {};
      final Set<String> workedDaysSet = {};
      final now = DateTime.now();
      final prevMonth = DateTime(now.year, now.month - 1, 1);
      final prevKey =
          '${prevMonth.year}-${prevMonth.month.toString().padLeft(2, '0')}';

      for (final r in list) {
        final h = ((r['total_hours'] ?? 0) as num).toDouble();
        final m = ((r['total_payment'] ?? 0) as num).toDouble();

        totalHours += h;
        totalEarned += m;

// 👉 ДЕНЬ (для workedDays)
        final end = DateTime.parse(r['end_time']).toLocal();
        final dayKey = '${end.year}-${end.month}-${end.day}';
        workedDaysSet.add(dayKey);

// 👉 МЕСЯЦ (для byMonth)
        final monthKey = '${end.year}-${end.month.toString().padLeft(2, '0')}';

        byMonth.putIfAbsent(monthKey, () => _MonthAgg());
        byMonth[monthKey]!.hours += h;
        byMonth[monthKey]!.earned += m;
      }

      final workedDays = workedDaysSet.length;

      avgRate = totalHours > 0 ? (totalEarned / totalHours) : 0;
      final daysInMonth = DateUtils.getDaysInMonth(now.year, now.month);

// разумный лимит рабочих дней
      final workingDaysInMonth = daysInMonth > 22 ? 22 : daysInMonth;

      if (workedDays > 0) {
        final avgHoursPerDay = totalHours / workedDays;
        projectedMonthHours = avgHoursPerDay * workingDaysInMonth;
        projectedMonthCost = projectedMonthHours * avgRate;
      } else {
        projectedMonthHours = 0;
        projectedMonthCost = 0;
      }

      if (byMonth.containsKey(prevKey)) {
        lastMonthHours = byMonth[prevKey]!.hours;
        lastMonthCost = byMonth[prevKey]!.earned;

        if (lastMonthHours > 0) {
          hoursDeltaPct =
              ((projectedMonthHours - lastMonthHours!) / lastMonthHours!) * 100;
        }

        if (lastMonthCost > 0) {
          costDeltaPct =
              ((projectedMonthCost - lastMonthCost!) / lastMonthCost!) * 100;
        }

        projectedDelta = projectedMonthCost - lastMonthCost!;
      }

      const double safeMonthlyHours = 360;

      final currentKey =
          '${now.year}-${now.month.toString().padLeft(2, '0')}';

      final prev = DateTime(now.year, now.month - 1);

// LOSS / SAVINGS
      projectedDelta = projectedMonthCost - lastMonthCost;

// WARNING
      exceedsLimit =
          projectedMonthHours > maxMonthlyHours ||
              projectedMonthCost > maxMonthlyCost;


      // best month
      String bestKey = byMonth.keys.first;
      String worstKey = byMonth.keys.first;

      for (final k in byMonth.keys) {
        if (byMonth[k]!.earned > byMonth[bestKey]!.earned) bestKey = k;
        if (byMonth[k]!.earned < byMonth[worstKey]!.earned) worstKey = k;
      }

      bestMonthLabel = _prettyMonth(bestKey);
      bestMonthEarned = byMonth[bestKey]!.earned;
      bestMonthHours = byMonth[bestKey]!.hours;

      worstMonthLabel = _prettyMonth(worstKey);
      worstMonthEarned = byMonth[worstKey]!.earned;
      worstMonthHours = byMonth[worstKey]!.hours;

      setState(() {
        loading = false;
        _appear = false;
      });
    } catch (e) {
      setState(() {
        loading = false;
        error = e.toString();
      });
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        setState(() {
          _appear = true;
        });
      }
    });
  }

  String _prettyMonth(String key) {
    // key = "2026-01"
    final parts = key.split('-');
    final y = int.parse(parts[0]);
    final m = int.parse(parts[1]);
    final dt = DateTime(y, m, 1);
    return DateFormat.yMMM().format(dt); // "Jan 2026"
  }

  Widget gradientDivider(Color accent) {
    return Container(
      margin: const EdgeInsets.only(top: 10, bottom: 14),
      height: 1.5,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [
            Colors.transparent,
            accent.withValues(alpha: 0.9),
            Colors.transparent,
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final h = MediaQuery.of(context).size.height;

    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          height: h * 0.78,
          decoration: BoxDecoration(
            color: const Color(0xFF1E1C22),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
            border: Border.all(color: Colors.white.withOpacity(0.08)),
          ),
          child: Column(
            children: [
              const SizedBox(height: 10),
              Container(
                width: 44,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.18),
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              const SizedBox(height: 14),

              // HEADER
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 18),
                child: Row(
                  children: [
                    const Icon(Icons.analytics_rounded, color: Colors.lightBlueAccent),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text(
                        'Worker summary',
                        style: TextStyle(
                          color: Colors.white70,
                          fontWeight: FontWeight.w900,
                          fontSize: 18,
                        ),
                      ),
                    ),
                    GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: const Icon(Icons.close_rounded, color: Colors.white70),
                    )
                  ],
                ),
              ),

              const SizedBox(height: 6),

              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 18),
                child: Text(
                  widget.worker['name'] ?? '—',
                  style: const TextStyle(
                    color: Colors.white38,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),

              const SizedBox(height: 12),

              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 18),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.info_outline,
                      size: 14,
                      color: Colors.white38,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Based on $completedShifts completed '
                            '${completedShifts == 1 ? 'shift' : 'shifts'}.',
                        style: const TextStyle(
                          color: Colors.white38,
                          fontSize: 12,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              if (dataUpdatedAt != null) ...[
                const SizedBox(height: 6),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.schedule,
                        size: 13,
                        color: Colors.white24,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'Data last updated: '
                            '${DateFormat.MMMd().add_Hm().format(dataUpdatedAt!)}',
                        style: const TextStyle(
                          color: Colors.white24,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
              ],


              const SizedBox(height: 16),
              Expanded(
                child: loading
                    ? const Center(
                  child: CircularProgressIndicator(color: Colors.white54),
                )
                    : error != null
                    ? _errorView()
                    : _content(),
              ),
              const SizedBox(height: 12),

              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 18),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    Icon(
                      Icons.info_outline,
                      size: 14,
                      color: Colors.white38,
                    ),
                    SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'This summary is based on completed shifts only. '
                            'Ongoing shifts and future changes are not included.',
                        style: TextStyle(
                          color: Colors.white38,
                          fontSize: 12,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 14),

            ],
          ),
        ),
      ),
    );
  }

  Widget _errorView() {
    return Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Failed to load summary',
            style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 8),
          Text(error!, style: const TextStyle(color: Colors.white54)),
          const SizedBox(height: 16),
          GestureDetector(
            onTap: _load,
            child: Container(
              height: 44,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(999),
                color: Colors.white.withOpacity(0.08),
              ),
              child: const Center(
                child: Text(
                  'Retry',
                  style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w800),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _content() {
    if (lastShift == null) {
      return const Center(
        child: Text('No activity yet', style: TextStyle(color: Colors.white38)),
      );
    }

    final lastEnd = DateTime.parse(lastShift!['end_time']).toLocal();
    final lastHours = ((lastShift!['total_hours'] ?? 0) as num).toDouble();
    final lastMoney = ((lastShift!['total_payment'] ?? 0) as num).toDouble();

    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 0, 18, 24),
      children: [
        _glassCard(
          index: 0,
          title: 'LAST SHIFT',
          icon: Icons.history_rounded,
          child: darkDataBlock(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _miniStat(
                  Icons.event,
                  Colors.lightBlueAccent,
                  DateFormat.MMMd().format(lastEnd),
                ),
                _miniStat(
                  Icons.schedule,
                  Colors.orangeAccent,
                  '${fmtHoursHM(lastHours)}',
                ),
                _miniStat(
                  Icons.attach_money,
                  Colors.greenAccent,
                  lastMoney.toStringAsFixed(2),
                ),
              ],
            ),
          ),

        ),

        _glassCard(
          index: 1,
          title: 'TOTALS',
          icon: Icons.summarize_rounded,
          warning: true,
          child: Column(
            children: [
              darkDataBlock(
                child: _rowLine(
                  Icons.timelapse_rounded,
                  Colors.orangeAccent,
                  'Total worked',
                  fmtHoursHM(totalHours),
                ),
              ),
              const SizedBox(height: 5),
              darkDataBlock(
                child: _rowLine(
                  Icons.paid_rounded,
                  Colors.greenAccent,
                  'Total earned',
                  '\$${totalEarned.toStringAsFixed(2)}',
                ),
              ),
              const SizedBox(height: 5),
              darkDataBlock(
                child: _rowLine(
                  Icons.calculate_rounded,
                  Colors.lightBlueAccent,
                  'Average rate',
                  '\$${avgRate.toStringAsFixed(2)} / h',
                ),
              ),
            ],
          ),

        ),

        _glassCard(
          index: 2,
          title: 'FORECAST',
          icon: Icons.trending_up_rounded,
          warning: true,
          child: Column(
            children: [
              darkDataBlock(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _rowLine(
                      Icons.schedule_rounded,
                      Colors.orangeAccent,
                      'Projected hours',
                      fmtHoursHM(projectedMonthHours),
                    ),
                    if (lastMonthHours != null)
                      _deltaLine(hoursDeltaPct),
                  ],
                ),
              ),

              const SizedBox(height: 1),

              darkDataBlock(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _rowLine(
                      Icons.attach_money_rounded,
                      Colors.orangeAccent,
                      'Estimated cost',
                      '\$${projectedMonthCost.toStringAsFixed(2)}',
                    ),
                    if (lastMonthCost != null)
                      _deltaLine(costDeltaPct),
                  ],
                ),
              ),

              const SizedBox(height: 1),

              darkDataBlock(
                child: _rowLine(
                  projectedDelta >= 0
                      ? Icons.trending_up
                      : Icons.trending_down,
                  projectedDelta >= 0
                      ? Colors.redAccent
                      : Colors.greenAccent,
                  projectedDelta >= 0
                      ? 'Projected LOSS'
                      : 'Projected SAVINGS',
                  '\$${projectedDelta.abs().toStringAsFixed(2)}',
                ),
              ),

              if (exceedsLimit) ...[
                const SizedBox(height: 10),
                Row(
                  children: const [
                    Icon(Icons.warning_amber_rounded,
                        color: Colors.amberAccent, size: 16),
                    SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Forecast exceeds admin safety limits',
                        style: TextStyle(
                          color: Colors.amberAccent,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ],

              const SizedBox(height: 8),
              Text(
                'Compared to last month · Estimate based on current activity',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.35),
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ),

        _glassCard(
          index: 2,
          title: 'BEST MONTH',
          icon: Icons.trending_up_rounded,
          success: true,
          child: darkDataBlock(
            child: Column(
              children: [
                _rowLine(
                  Icons.calendar_month_rounded,
                  Colors.white70,
                  'Month',
                  bestMonthLabel ?? '—',
                ),

                animatedRowDivider(Colors.greenAccent),

                _rowLine(
                  Icons.schedule_rounded,
                  Colors.orangeAccent,
                  'Hours',
                  fmtHoursHM(bestMonthHours),
                ),

                animatedRowDivider(Colors.greenAccent),

                _rowLine(
                  Icons.attach_money_rounded,
                  Colors.greenAccent,
                  'Earned',
                  '\$${bestMonthEarned.toStringAsFixed(2)}',
                ),
              ],
            ),

          ),
        ),

        _glassCard(
          index: 3,
          title: 'LOWEST MONTH',
          icon: Icons.trending_down_rounded,
          danger: true,
          child: darkDataBlock(
            child: Column(
              children: [
                _rowLine(
                  Icons.calendar_month_rounded,
                  Colors.white70,
                  'Month',
                  worstMonthLabel ?? '—',
                ),

                animatedRowDivider(Colors.redAccent),

                _rowLine(
                  Icons.schedule_rounded,
                  Colors.orangeAccent,
                  'Hours',
                  '${worstMonthHours.toStringAsFixed(1)} h',
                ),

                animatedRowDivider(Colors.redAccent),

                _rowLine(
                  Icons.attach_money_rounded,
                  Colors.redAccent,
                  'Earned',
                  '\$${worstMonthEarned.toStringAsFixed(2)}',
                ),
              ],
            ),

          ),
        ),

      ],
    );
  }


  Widget _glassCard({
    required int index,
    required String title,
    required IconData icon,
    required Widget child,
    bool warning = false,
    bool success = false,
    bool danger = false,
  }) {
    final bool isForecast = title == 'FORECAST';

    final Color accent = danger
        ? Colors.redAccent
        : success
        ? Colors.greenAccent
        : isForecast
        ? Colors.orangeAccent
        : warning
        ? Colors.amberAccent
        : Colors.white70;


    return StaggerItem(
      index: index,
      show: _appear,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),

          gradient: const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFF23222A),
              Color(0xFF23222B),
            ],
          ),

          // border: Border.all(
          //   color: danger
          //       ? Colors.redAccent.withOpacity(0.30)
          //       : warning
          //       ? Colors.amberAccent.withOpacity(0.30)
          //       : success
          //       ? Colors.greenAccent.withOpacity(0.30)
          //       : Colors.white.withOpacity(0.10),
          // ),

          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.45),
              blurRadius: 22,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 18, color: accent),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: TextStyle(
                    color: accent,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
// 👇 ВОТ ОНО — МИКРО-ОПИСАНИЕ
            if (title == 'LAST SHIFT')
              _cardHint('Shows the most recent completed shift'),
            if (title == 'TOTALS')
              _cardHint('Totals based on all completed shifts'),
            if (title == 'FORECAST')
              _cardHint('Estimated projection based on recent activity'),
            if (title == 'BEST MONTH')
              _cardHint('Highest earning month on record'),
            if (title == 'LOWEST MONTH')
              _cardHint('Lowest earning month on record'),

            gradientDivider(accent),
            child,
          ],
        ),
      ),
    );

  }

  Widget _miniStat(IconData icon, Color color, String text) {
    return Row(
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 6),
        Text(
          text,
          style: TextStyle(
            color: color,
            fontWeight: FontWeight.w900,
          ),
        ),
      ],
    );
  }

  Widget _rowLine(IconData icon, Color color, String label, String value) {
    return Row(
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            label,
            style: const TextStyle(color: Colors.white54, fontWeight: FontWeight.w700),
          ),
        ),
        Text(
          value,
          style: TextStyle(color: color, fontWeight: FontWeight.w900),
        ),
      ],
    );
  }
}

class _MonthAgg {
  double hours = 0;
  double earned = 0;
}
class GradientDivider extends StatelessWidget {
  final Color color;

  const GradientDivider({super.key, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 8, bottom: 14),
      height: 1.5,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [
            color.withOpacity(0.0),
            color.withOpacity(0.6),
            color.withOpacity(0.0),
          ],
        ),
      ),
    );
  }
}
Widget darkDataBlock({required Widget child}) {
  return Container(
    margin: const EdgeInsets.only(top: 12),
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    decoration: BoxDecoration(
      color: const Color(0xFF15141A), // 🔥 глубокий тёмный
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: Colors.white.withOpacity(0.06)),
    ),
    child: child,
  );
}

Widget _rowDivider(Color color) {
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Container(
      height: 1,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [
            Colors.transparent,
            color.withOpacity(0.5),
            Colors.transparent,
          ],
        ),
      ),
    ),
  );
}
Widget animatedRowDivider(Color color, {int delayMs = 0}) {
  return TweenAnimationBuilder<double>(
    tween: Tween(begin: 0, end: 1),
    duration: const Duration(milliseconds: 240),
    curve: Curves.easeOutCubic,
    builder: (context, value, _) {
      return Opacity(
        opacity: value,
        child: Transform.scale(
          scaleX: value,
          alignment: Alignment.center,
          child: Container(
            height: 1,
            margin: const EdgeInsets.symmetric(vertical: 6),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: [
                  Colors.transparent,
                  color.withOpacity(0.55),
                  Colors.transparent,
                ],
              ),
            ),
          ),
        ),
      );
    },
  );
}

class StaggerItem extends StatefulWidget {
  final int index;
  final bool show;
  final Widget child;

  const StaggerItem({
    super.key,
    required this.index,
    required this.show,
    required this.child,
  });

  @override
  State<StaggerItem> createState() => _StaggerItemState();
}

class _StaggerItemState extends State<StaggerItem> {
  bool visible = false;

  @override
  void initState() {
    super.initState();

    if (widget.show) {
      _trigger();
    }
  }

  @override
  void didUpdateWidget(covariant StaggerItem oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (widget.show && !visible) {
      _trigger();
    }
  }

  void _trigger() {
    Future.delayed(Duration(milliseconds: widget.index * 80), () {
      if (mounted) {
        setState(() => visible = true);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      opacity: visible ? 1 : 0,
      duration: const Duration(milliseconds: 420),
      curve: Curves.easeOutCubic,
      child: AnimatedSlide(
        offset: visible ? Offset.zero : const Offset(0, 0.05),
        duration: const Duration(milliseconds: 420),
        curve: Curves.easeOutCubic,
        child: widget.child,
      ),
    );
  }
}
class HoldToConfirmRow extends StatefulWidget {
  final Widget child;          // твоя капсула (softCapsuleRow)
  final Future<void> Function() onConfirmed; // что делать после удержания

  /// сколько держать до подтверждения
  final Duration holdDuration;

  /// можно отключать (например если sendingReset=true)
  final bool enabled;

  const HoldToConfirmRow({
    super.key,
    required this.child,
    required this.onConfirmed,
    this.holdDuration = const Duration(milliseconds: 900),
    this.enabled = true,
  });

  @override
  State<HoldToConfirmRow> createState() => _HoldToConfirmRowState();
}

class _HoldToConfirmRowState extends State<HoldToConfirmRow>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c =
  AnimationController(vsync: this, duration: widget.holdDuration);

  bool _running = false;

  @override
  void didUpdateWidget(covariant HoldToConfirmRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.holdDuration != widget.holdDuration) {
      _c.duration = widget.holdDuration;
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _start() {
    if (!widget.enabled) return;
    if (_running) return;

    _running = true;
    _c.forward(from: 0);

    HapticFeedback.selectionClick();
  }

  void _cancel() {
    if (!_running) return;
    _running = false;

    // плавно назад (можно сразу reset если хочешь)
    _c.animateBack(0, duration: const Duration(milliseconds: 120));
  }

  Future<void> _complete() async {
    if (!widget.enabled) return;
    if (!_running) return;

    _running = false;

    // маленький “щелчок”
    HapticFeedback.mediumImpact();

    // важный момент: чтобы прогресс не оставался на 100%,
    // сначала чуть подержим визуально и потом сбросим
    await Future.delayed(const Duration(milliseconds: 80));

    try {
      await widget.onConfirmed();
    } finally {
      if (mounted) {
        _c.animateBack(0, duration: const Duration(milliseconds: 160));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // GestureDetector даёт onLongPressStart/End – идеально для hold
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onLongPressStart: widget.enabled
          ? (_) {
        _start();
      }
          : null,
      onLongPressEnd: widget.enabled
          ? (_) {
        // если не дошло до конца — отмена
        if (_c.value < 1) _cancel();
      }
          : null,
      onLongPressCancel: widget.enabled ? _cancel : null,
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) {
          final v = _c.value; // 0..1

          // когда дошли до 1 — выполняем один раз
          if (v >= 1 && _running) {
            // чтобы не вызвать setState в build — запускаем после кадра
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) _complete();
            });
          }

          return ClipRRect(
            borderRadius: BorderRadius.circular(14), // 🔴 ВАЖНО
            child: Stack(
              children: [
                widget.child,
                // 2) прогресс-оверлей поверх (клип по скруглению)
                if (v > 0)
                  Positioned.fill(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(14), // как у softCapsuleRow
                      child: IgnorePointer(
                        ignoring: true,
                        child: Opacity(
                          opacity: 0.95,
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: FractionallySizedBox(
                              widthFactor: v,
                              child: Container(
                                decoration: BoxDecoration(
                                  color: Colors.redAccent.withOpacity(0.18),
                                  border: Border(
                                    right: BorderSide(
                                      color: Colors.redAccent.withOpacity(0.35),
                                      width: 1,
                                    ),
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

        },
      ),
    );
  }
}


String _rateHistoryDate(DateTime d) {
  const months = [
    'Jan','Feb','Mar','Apr','May','Jun',
    'Jul','Aug','Sep','Oct','Nov','Dec'
  ];
  return '${months[d.month - 1]} ${d.day} · '
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}
Widget _trendText(double percent) {
  final up = percent > 0;
  return Row(
    mainAxisAlignment: MainAxisAlignment.end,
    children: [
      Icon(
        up ? Icons.arrow_upward : Icons.arrow_downward,
        size: 12,
        color: up ? Colors.redAccent : Colors.greenAccent,
      ),
      const SizedBox(width: 4),
      Text(
        '${percent.abs().toStringAsFixed(1)}%',
        style: TextStyle(
          fontSize: 11,
          color: up ? Colors.redAccent : Colors.greenAccent,
          fontWeight: FontWeight.w700,
        ),
      ),
    ],
  );
}

Widget _deltaLine(double pct) {
  final up = pct >= 0;
  return Padding(
    padding: const EdgeInsets.only(top: 4),
    child: Row(
      children: [
        Icon(
          up ? Icons.arrow_upward : Icons.arrow_downward,
          size: 14,
          color: up ? Colors.redAccent : Colors.greenAccent,
        ),
        const SizedBox(width: 4),
        Text(
          '${pct.abs().toStringAsFixed(1)}% vs last month',
          style: TextStyle(
            color: up ? Colors.redAccent : Colors.greenAccent,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    ),
  );
}
Widget _cardHint(String text) {
  return Padding(
    padding: const EdgeInsets.only(top: 6),
    child: Row(
      children: [
        Icon(
          Icons.info_outline,
          size: 14,
          color: Colors.white.withOpacity(0.45),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              fontSize: 12,
              color: Colors.white.withOpacity(0.45),
              height: 1.3,
            ),
          ),
        ),
      ],
    ),
  );
}

String fmtHoursHM(num hours) {
  // hours может быть double: 13.6
  final totalMinutes = (hours.toDouble() * 60).round(); // 13.6*60=816 → 13:36
  final h = totalMinutes ~/ 60;
  final m = totalMinutes % 60;
  return '$h:${m.toString().padLeft(2, '0')}';
}

Widget _softGradientDivider(Color accent) {
  return Container(
    margin: const EdgeInsets.symmetric(vertical: 8),
    height: 1,
    decoration: BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
        colors: [
          Colors.transparent,
          accent.withOpacity(0.35),
          Colors.transparent,
        ],
      ),
    ),
  );
}

Widget rateHistoryRow({
  required int index,
  required double from,
  required double to,
  required DateTime at,
  required double lastMonthHours,
}) {
  final diff = to - from;
  final monthlyDiff = diff * lastMonthHours;
  final isUp = diff >= 0;
  final accent = isUp ? Colors.greenAccent : Colors.redAccent;

  final diffSign = isUp ? '+' : '-';
  final moneySign = monthlyDiff >= 0 ? '+' : '-';
  final hasRealMonthData = lastMonthHours > 0;

  return Container(
    margin: const EdgeInsets.only(bottom: 16),
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: const Color(0xFF2A2930), // 🔥 КАРТОЧКА (отделяется)
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: Colors.white.withOpacity(0.06)),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withOpacity(0.45),
          blurRadius: 18,
          offset: const Offset(0, 10),
        ),
      ],
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [

        // ===== HEADER =====
        Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.orange.withOpacity(0.18),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                '#${index + 1}',
                style: const TextStyle(
                  color: Colors.orange,
                  fontWeight: FontWeight.w900,
                  fontSize: 12,
                ),
              ),
            ),
            const Spacer(),
            Row(
              children: [
                const Icon(Icons.schedule, size: 14, color: Colors.white38),
                const SizedBox(width: 6),
                Text(
                  DateFormat.MMMd().add_Hm().format(at),
                  style: const TextStyle(
                    color: Colors.white38,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ],
        ),

        const SizedBox(height: 12),

        // ===== CORE BLOCK (ОБЪЕДИНЯЕТ ВСЁ) =====
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFF1B1A1F), // 🔥 ГЛУБОКИЙ ЧЁРНЫЙ
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withOpacity(0.08)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [

              // ===== RATE =====
              Row(
                children: [
                  Container(
                    child: Icon(
                      Icons.monitor_heart_rounded,
                      size: 18,
                      color: accent,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    '\$${from.toStringAsFixed(2)}',
                    style: const TextStyle(
                      color: Colors.white54,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 6),
                  const Icon(Icons.arrow_forward, size: 14, color: Colors.white38),
                  const SizedBox(width: 6),
                  Text(
                    '\$${to.toStringAsFixed(2)}',
                    style: TextStyle(
                      color: accent,
                      fontWeight: FontWeight.w900,
                      fontSize: 16,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 10),

              // ===== ANALYSIS =====
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        isUp ? Icons.trending_up : Icons.trending_down,
                        size: 18,
                        color: accent,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          hasRealMonthData
                              ? 'Analysis: $diffSign${diff.abs().toStringAsFixed(2)} / h   '
                              '$moneySign\$${monthlyDiff.abs().toStringAsFixed(0)} last month'
                              : 'Analysis: $diffSign${diff.abs().toStringAsFixed(2)} / h',
                          style: TextStyle(
                            color: accent,
                            fontWeight: FontWeight.w800,
                            fontSize: 14,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (hasRealMonthData) ...[
                    const SizedBox(height: 6),
                    Text(
                      'Based on ${fmtHoursHM(lastMonthHours)} worked last month',
                      style: TextStyle(
                        color: Colors.white54,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ],
              )
            ],
          ),
        ),
      ],
    ),
  );
}







