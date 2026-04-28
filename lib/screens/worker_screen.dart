import 'dart:async';
import 'dart:ui';
import 'dart:math' as math;
import 'worker_history_screen.dart';
import 'package:flutter/material.dart';
import 'login_screen.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'worker_payments_screen.dart';

import '../services/worker_service.dart';
import '../services/message_service.dart';
import 'worker_chat_screen.dart';
import '../services/task_service.dart';
import 'worker_tasks_screen.dart';
import '../utils/company_logo_helper.dart';
import '../services/push_token_service.dart';

class WorkerScreen extends StatefulWidget {
  final String accessMode;

  const WorkerScreen({
    super.key,
    required this.accessMode,
  });

  @override
  State<WorkerScreen> createState() => _WorkerScreenState();
}

class _WorkerScreenState extends State<WorkerScreen>
    with WidgetsBindingObserver {

  String _workerName = 'Worker';
  String _accessMode = 'active';
  double? _lastPaymentAmount;
  double _hourlyRate = 0;
  String? _avatarUrl;
  final WorkerService _service = WorkerService();

  bool get canStartShift => _accessMode == 'active';

  bool get isViewOnly {
    final mode = _accessMode.trim().toLowerCase();
    return mode == 'readonly' ||
        mode == 'viewonly' ||
        mode == 'view_only' ||
        mode == 'view-only' ||
        mode == 'view';
  }

  bool _loading = true;
  bool _actionBusy = false;

  Map<String, dynamic>? _activeShift;
  Map<String, dynamic>? _lastCompleted;
  double _totalHours = 0;
  double _totalEarned = 0;

  Timer? _ticker;
  Duration _elapsed = Duration.zero;
  Timer? _presenceHeartbeat;

  RealtimeChannel? _appPresenceChannel;

  SupabaseClient get _db => Supabase.instance.client;

  String get _userEmail => _db.auth.currentUser?.email ?? 'Worker';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _accessMode = widget.accessMode;

    _initAppPresence();

    Future.microtask(() async {
      try {
        print('WORKER PUSH SYNC START');
        await PushTokenService().syncWorkerPushToken();
        print('WORKER PUSH SYNC OK');

        await _trackAppPresence();
      } catch (e) {
        print('WORKER INIT PUSH/PRESENCE ERROR = $e');
      }
    });

    _reload();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);

    _ticker?.cancel();
    _presenceHeartbeat?.cancel();

    final ch = _appPresenceChannel;
    _appPresenceChannel = null;

    if (ch != null) {
      ch.untrack();
      Supabase.instance.client.removeChannel(ch);
    }

    super.dispose();
  }

  Future<void> _trackAppPresence() async {
    final ch = _appPresenceChannel;
    final myId = _db.auth.currentUser?.id;

    print('PRESENCE TRY USER ID = $myId');

    if (myId == null) return;

    final nowIso = DateTime.now().toUtc().toIso8601String();

    try {
      if (ch != null) {
        await ch.track({
          'auth_user_id': myId,
          'role': 'worker',
          'online_at': nowIso,
        });
      }

      final updated = await _db
          .from('workers')
          .update({
        'in_app': true,
        'last_seen_at': nowIso,
      })
          .eq('auth_user_id', myId)
          .select('name, email, auth_user_id, in_app, last_seen_at')
          .maybeSingle();

      print('PRESENCE TRY USER ID = $myId');
      print('PRESENCE UPDATED ROW = $updated');

      if (updated == null) {
        print('PRESENCE WARNING: no worker row matched this auth_user_id');
      }

      _presenceHeartbeat?.cancel();
      _presenceHeartbeat = Timer.periodic(const Duration(seconds: 30), (_) async {
        final userId = _db.auth.currentUser?.id;
        if (userId == null) return;

        final updated = await _db
            .from('workers')
            .update({
          'in_app': true,
          'last_seen_at': DateTime.now().toUtc().toIso8601String(),
        })
            .eq('auth_user_id', userId)
            .select('name, email, auth_user_id, in_app, last_seen_at')
            .maybeSingle();

        print('PRESENCE HEARTBEAT USER ID = $userId');
        print('PRESENCE HEARTBEAT ROW = $updated');

        if (updated == null) {
          print('PRESENCE WARNING: heartbeat found no worker row');
        }
      });
    } catch (e) {
      print('PRESENCE UPDATE ERROR = $e');
    }
  }

  Future<void> _untrackAppPresence() async {
    _presenceHeartbeat?.cancel();

    final myId = _db.auth.currentUser?.id;
    final ch = _appPresenceChannel;

    if (ch != null) {
      await ch.untrack();
    }

    if (myId == null) return;

    await _db
        .from('workers')
        .update({
      'in_app': false,
      'last_seen_at': DateTime.now().toUtc().toIso8601String(),
    })
        .eq('auth_user_id', myId);
  }

  Future<void> _initAppPresence() async {
    final myId = Supabase.instance.client.auth.currentUser?.id;
    if (myId == null) return;

    final ch = Supabase.instance.client.channel(
      'app-presence',
      opts: const RealtimeChannelConfig(private: true),
    );

    ch.subscribe((status, [error]) async {
      if (status == RealtimeSubscribeStatus.subscribed) {
        await _trackAppPresence();
      }
    });

    _appPresenceChannel = ch;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _trackAppPresence();
    } else if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _untrackAppPresence();
    }
  }

  Future<void> _reload({bool silent = false}) async {
    if (!silent && mounted) {
      setState(() => _loading = true);
    }

    try {
      final results = await Future.wait([
        _service.getActiveShift(),
        _service.getLastCompletedShift(),
        _service.getTotals(),
        _service.getWorkerProfile(),
        _service.getLastPayment(),
      ]);

      final active = results[0] as Map<String, dynamic>?;
      final last = results[1] as Map<String, dynamic>?;
      final totals = results[2] as dynamic;
      final worker = results[3] as Map<String, dynamic>?;
      final lastPayment = results[4] as Map<String, dynamic>?;

      if (worker == null) {
        throw Exception('Worker profile not found');
      }

      _avatarUrl = worker['avatar_url'];
      _hourlyRate = ((worker['hourly_rate'] as num?) ?? 0).toDouble();
      _workerName = (worker['name'] ?? _userEmail).toString();

      final rawMode =
      (worker['access_mode'] ?? widget.accessMode).toString().trim().toLowerCase();

      _accessMode = (rawMode == 'readonly' || rawMode == 'viewonly')
          ? 'view_only'
          : rawMode;

      final lastAmountRaw = lastPayment?['total_amount'];
      _lastPaymentAmount = lastAmountRaw == null
          ? null
          : (lastAmountRaw as num).toDouble();

      _activeShift = active;
      _lastCompleted = last;
      _totalHours = totals.totalHours;
      _totalEarned = totals.totalEarned;

      _setupTicker();

      if (mounted) {
        setState(() {});
      }
    } catch (_) {
    } finally {
      if (!silent && mounted) {
        setState(() => _loading = false);
      }
    }
  }

  void _setupTicker() {
    _ticker?.cancel();
    _elapsed = Duration.zero;

    if (_activeShift == null) return;

    final shift = _activeShift;
    if (shift == null) return;

    final startUtc = _parseDate(shift['start_time']);
    if (startUtc == null) return;

    void tick() {
      final nowUtc = DateTime.now().toUtc();
      final d = nowUtc.difference(startUtc);
      if (mounted) setState(() => _elapsed = d);
    }

    tick();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => tick());
  }

  DateTime? _parseDate(dynamic v) {
    if (v == null) return null;
    try {
      return DateTime.parse(v.toString());
    } catch (_) {
      return null;
    }
  }

  String _fmtMoney(double v) => '\$${v.toStringAsFixed(2)}';

  String _fmtDuration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60);
    if (h > 0) return '${h}h ${m}m';
    if (m > 0) return '${m}m ${s}s';
    return '${s}s';
  }

  String _fmtClock(DateTime dtLocal) => DateFormat.Hm().format(dtLocal);
  String _fmtDate(DateTime dtLocal) => DateFormat.yMMMd().format(dtLocal);

  Future<void> _startShift() async {
    setState(() => _actionBusy = true);
    try {
      await _service.startShift();
      await _reload(silent: true);

      final startUtc =
          _parseDate(_activeShift?['start_time']) ?? DateTime.now().toUtc();
      final startLocal = startUtc.toLocal();

      if (mounted) {
        _toast(
          'Shift started',
          'Today • ${_fmtClock(startLocal)}',
          icon: Icons.play_circle_filled,
        );
      }
    } catch (e) {
      _toast('Error', e.toString(), icon: Icons.error_outline);
    } finally {
      if (mounted) setState(() => _actionBusy = false);
    }
  }

  Future<void> _endShiftConfirm() async {
    final shift = _activeShift;
    if (shift == null) {
      _toast('Error', 'No active shift', icon: Icons.error_outline);
      return;
    }

    final shiftId = shift['id']?.toString();
    final startUtc = _parseDate(shift['start_time']);
    if (shiftId == null || startUtc == null) {
      _toast('Error', 'Shift data is invalid', icon: Icons.error_outline);
      return;
    }

    final startLocal = startUtc.toLocal();
    final estHours = _elapsed.inSeconds / 3600.0;
    final activeRateRaw = shift['pay_rate'];
    final activeRate = activeRateRaw is num
        ? activeRateRaw.toDouble()
        : double.tryParse(activeRateRaw?.toString() ?? '') ?? _hourlyRate;
    final estPay = estHours * activeRate;

    final ok = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
        builder: (ctx) {
          Widget infoRow({
            required IconData icon,
            required Color color,
            required String label,
            required String value,
            bool highlight = false,
          }) {
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Colors.white.withOpacity(0.045),
                    Colors.white.withOpacity(0.018),
                  ],
                ),
                border: Border.all(
                  color: Colors.white.withOpacity(0.07),
                ),
              ),
              child: Row(
                children: [
                  Icon(icon, size: 18, color: color),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      label,
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.58),
                        fontWeight: FontWeight.w700,
                        fontSize: 13.4,
                      ),
                    ),
                  ),
                  Text(
                    value,
                    style: TextStyle(
                      color: highlight ? color : Colors.white.withOpacity(0.90),
                      fontWeight: FontWeight.w900,
                      fontSize: 14.4,
                    ),
                  ),
                ],
              ),
            );
          }

          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(30),
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Color(0xFF232830),
                      Color(0xFF171B22),
                      Color(0xFF10141A),
                    ],
                    stops: [0.0, 0.56, 1.0],
                  ),
                  border: Border.all(
                    color: Colors.white.withOpacity(0.08),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.50),
                      blurRadius: 28,
                      offset: const Offset(0, 16),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(height: 10),
                    Container(
                      width: 44,
                      height: 5,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.14),
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),

                    const SizedBox(height: 16),

                    Padding(
                      padding: const EdgeInsets.fromLTRB(18, 0, 18, 0),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.stop_circle_rounded,
                            color: Color(0xFFFF6B6B),
                            size: 22,
                          ),
                          const SizedBox(width: 10),
                          const Expanded(
                            child: Text(
                              'End shift',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w900,
                                fontSize: 20,
                              ),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 5,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFF6B6B).withOpacity(0.12),
                              borderRadius: BorderRadius.circular(999),
                              border: Border.all(
                                color: const Color(0xFFFF6B6B).withOpacity(0.18),
                              ),
                            ),
                            child: const Text(
                              'LIVE',
                              style: TextStyle(
                                color: Color(0xFFFF6B6B),
                                fontSize: 10.8,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 0.45,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 10),

                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 18),
                      child: Text(
                        'Are you sure you want to end the shift?',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.58),
                          fontWeight: FontWeight.w700,
                          fontSize: 13.2,
                          height: 1.3,
                        ),
                      ),
                    ),

                    const SizedBox(height: 16),

                    Container(
                      height: 1,
                      margin: const EdgeInsets.symmetric(horizontal: 18),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            Colors.transparent,
                            Colors.white.withOpacity(0.08),
                            Colors.transparent,
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 16),

                    Padding(
                      padding: const EdgeInsets.fromLTRB(18, 0, 18, 0),
                      child: Column(
                        children: [
                          infoRow(
                            icon: Icons.schedule_rounded,
                            color: const Color(0xFF66A8FF),
                            label: 'Started',
                            value: '${_fmtDate(startLocal)} • ${_fmtClock(startLocal)}',
                          ),
                          const SizedBox(height: 10),
                          infoRow(
                            icon: Icons.timelapse_rounded,
                            color: const Color(0xFF63F5C2),
                            label: 'Worked',
                            value: _fmtDuration(_elapsed),
                            highlight: true,
                          ),
                          const SizedBox(height: 10),
                          infoRow(
                            icon: Icons.attach_money_rounded,
                            color: const Color(0xFFFFC14D),
                            label: 'Estimated',
                            value: _fmtMoney(estPay),
                            highlight: true,
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 18),

                    Padding(
                      padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
                      child: Row(
                        children: [
                          Expanded(
                            child: Material(
                              color: Colors.transparent,
                              child: InkWell(
                                borderRadius: BorderRadius.circular(18),
                                onTap: () => Navigator.pop(ctx, false),
                                child: Container(
                                  height: 58,
                                  decoration: BoxDecoration(
                                    gradient: const LinearGradient(
                                      begin: Alignment.topCenter,
                                      end: Alignment.bottomCenter,
                                      colors: [
                                        Color(0xFF2B3038),
                                        Color(0xFF1C2027),
                                      ],
                                    ),
                                    borderRadius: BorderRadius.circular(18),
                                    border: Border.all(
                                      color: Colors.white.withOpacity(0.07),
                                    ),
                                  ),
                                  child: const Center(
                                    child: Text(
                                      'Cancel',
                                      style: TextStyle(
                                        color: Color(0xFFD7C6FF),
                                        fontWeight: FontWeight.w800,
                                        fontSize: 15.5,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Material(
                              color: Colors.transparent,
                              child: InkWell(
                                borderRadius: BorderRadius.circular(18),
                                onTap: () => Navigator.pop(ctx, true),
                                child: Container(
                                  height: 58,
                                  decoration: BoxDecoration(
                                    gradient: const LinearGradient(
                                      begin: Alignment.topCenter,
                                      end: Alignment.bottomCenter,
                                      colors: [
                                        Color(0xFFAF2438),
                                        Color(0xFF8A182B),
                                      ],
                                    ),
                                    borderRadius: BorderRadius.circular(18),
                                    border: Border.all(
                                      color: Colors.redAccent.withOpacity(0.20),
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: const Color(0xFFAF2438).withOpacity(0.22),
                                        blurRadius: 14,
                                        offset: const Offset(0, 8),
                                      ),
                                    ],
                                  ),
                                  child: const Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(
                                        Icons.stop_rounded,
                                        color: Colors.white,
                                        size: 20,
                                      ),
                                      SizedBox(width: 8),
                                      Text(
                                        'End shift',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.w900,
                                          fontSize: 15.5,
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
                    ),
                  ],
                ),
              ),
            ),
          );
        }

    );

    if (ok != true) return;

    setState(() => _actionBusy = true);
    try {
      final result = await _service.endShift(
        shiftId: shiftId,
        startUtc: startUtc,
      );

      await _reload(silent: true);

      if (mounted) {
        _toast(
          'Shift ended',
          'Worked ${_fmtDuration(result.duration)} • Earned ${_fmtMoney(result.payment)}',
          icon: Icons.verified,
          highlight: true,
        );
      }
    } catch (e) {
      _toast('Error', e.toString(), icon: Icons.error_outline);
    } finally {
      if (mounted) setState(() => _actionBusy = false);
    }
  }

  void _showAboutSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _WorkerAboutSheet(
        workerEmail: _userEmail,
      ),
    );
  }

  Future<void> _logout() async {
    await _service.logout();

    if (!mounted) return;

    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
          (_) => false,
    );
  }

  Future<void> _openWorkerChat() async {
    try {
      final thread = await MessageService.getOrCreateWorkerThread();

      if (!mounted) return;

      if ((thread['id'] ?? '').toString().trim().isEmpty) {
        throw Exception('Thread was not created');
      }

      print('ACCESS MODE = $_accessMode');
      print('IS VIEW ONLY = $isViewOnly');

      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => WorkerChatScreen(
            isViewOnly: isViewOnly,
          ),
        ),
      );

      if (mounted) {
        setState(() {});
      }
    } catch (e) {
      if (!mounted) return;
      _toast(
        'Messages error',
        e.toString(),
        icon: Icons.forum_rounded,
      );
    }
  }

  Future<void> _openWorkerTasks() async {
    try {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => WorkerTasksScreen(
            isViewOnly: isViewOnly,
          ),
        ),
      );

      if (mounted) {
        setState(() {});
      }
    } catch (e) {
      if (!mounted) return;
      _toast(
        'Tasks error',
        e.toString(),
        icon: Icons.assignment_rounded,
      );
    }
  }

  void _toast(
      String title,
      String msg, {
        IconData? icon,
        bool highlight = false,
        Color? accentColor,
      }) {
    final accent = accentColor ??
        (highlight
            ? const Color(0xFF63F5C2)
            : const Color(0xFF66A8FF));

    final snack = SnackBar(
      behavior: SnackBarBehavior.floating,
      backgroundColor: Colors.transparent,
      elevation: 0,
      margin: const EdgeInsets.fromLTRB(14, 0, 14, 14),
      duration: const Duration(seconds: 3),
      padding: EdgeInsets.zero,
      content: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: Container(
            padding: const EdgeInsets.fromLTRB(14, 13, 14, 13),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(22),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  const Color(0xFF2B313A).withOpacity(0.90),
                  const Color(0xFF1A1F27).withOpacity(0.88),
                  Colors.black.withOpacity(0.18),
                ],
              ),
              border: Border.all(
                color: Colors.white.withOpacity(0.10),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.34),
                  blurRadius: 18,
                  offset: const Offset(0, 10),
                ),
                BoxShadow(
                  color: accent.withOpacity(0.10),
                  blurRadius: 18,
                  spreadRadius: -6,
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    color: accent.withOpacity(0.14),
                    border: Border.all(
                      color: accent.withOpacity(0.22),
                    ),
                  ),
                  child: Icon(
                    icon ?? Icons.notifications_rounded,
                    size: 20,
                    color: accent,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                          fontSize: 13.8,
                          height: 1.1,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        msg,
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.72),
                          fontWeight: FontWeight.w700,
                          fontSize: 12.3,
                          height: 1.25,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(snack);
  }

  Widget _lineInfo(
      IconData icon,
      String label,
      String value, {
        bool highlight = false,
        Color? color,
      }) {
    final cs = Theme.of(context).colorScheme;
    final c = color ?? (highlight ? Colors.greenAccent : cs.onSurface);

    return Row(
      children: [
        Icon(icon, size: 18, color: c),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              color: cs.outline,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Text(
          value,
          style: TextStyle(
            color: c,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }


  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final onShift = _activeShift != null;

    final bg = HistoryPalette.bg;

    return Scaffold(
      backgroundColor: bg,
      body: Stack(
        children: [
          const _WorkerBaseBackground(),
          SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 250),
              child: _loading
                  ? const Padding(
                padding: EdgeInsets.all(30),
                child: Center(child: CircularProgressIndicator()),
              )
                  : SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(18, 10, 18, 22),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Header (avatar + status)
                    _HeaderCard(
                      onShift: onShift,
                      busy: _actionBusy,
                      hourlyRate: _hourlyRate,
                      avatarUrl: _avatarUrl,
                      workerName: _workerName,
                      workerEmail: _userEmail,
                      accessMode: _accessMode,
                      onTasksTap: _openWorkerTasks,
                      onMessagesTap: _openWorkerChat,
                      onPrimaryTap: onShift
                          ? _endShiftConfirm
                          : (canStartShift
                          ? _startShift
                          : () {
                        _toast(
                          'View-only mode',
                          'You can open chat and tasks, but cannot change anything.',
                          icon: Icons.visibility_rounded,
                          accentColor: const Color(0xFFFFC14D),
                        );
                      }),
                      onPaymentsTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => WorkerPaymentsScreen(
                              workerEmail: _userEmail,
                              avatarUrl: _avatarUrl,
                              hourlyRate: _hourlyRate,
                              workerId: _db.auth.currentUser!.id,
                            ),
                          ),
                        );
                      },
                      onHistoryTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const WorkerHistoryScreen(),
                          ),
                        );
                      },
                      onAboutTap: _showAboutSheet,
                      onLogout: _logout,
                    ),

                    const SizedBox(height: 14),

                    if (isViewOnly)
                      Container(
                        margin: const EdgeInsets.only(bottom: 14),
                        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(18),
                          gradient: const LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              Color(0xFF2D2416),
                              Color(0xFF1E1810),
                            ],
                          ),
                          border: Border.all(
                            color: const Color(0xFFFFC14D).withOpacity(0.20),
                          ),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.visibility_rounded,
                              color: Color(0xFFFFC14D),
                              size: 18,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'View-only mode: you can open chat and tasks, but cannot change anything.',
                                style: TextStyle(
                                  color: Colors.white.withOpacity(0.88),
                                  fontWeight: FontWeight.w700,
                                  fontSize: 12.7,
                                  height: 1.28,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),

                    _ShiftCard(
                      onShift: onShift,
                      activeShift: _activeShift,
                      lastCompleted: _lastCompleted,
                      elapsed: _elapsed,
                      hourlyRate: _hourlyRate,
                    ),
                    const SizedBox(height: 14),

                    _SummaryCard(
                      hourlyRate: _hourlyRate,
                      totalHours: _totalHours,
                      totalEarned: _totalEarned,
                      lastPaymentAmount: _lastPaymentAmount,
                      workerName: _workerName,
                      workerEmail: _userEmail,
                      accessMode: _accessMode,
                      onShift: onShift,
                      activeShift: _activeShift,
                      lastCompleted: _lastCompleted,
                      elapsed: _elapsed,
                    ),
                    const SizedBox(height: 6),


                  ],
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
}

class _WorkerBaseBackground extends StatelessWidget {
  const _WorkerBaseBackground();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0xFF0B0D12),
            Color(0xFF0A0C10),
            Color(0xFF07080C),
          ],
        ),
      ),
    );
  }
}

class _WorkerAboutSheet extends StatelessWidget {
  final String workerEmail;

  const _WorkerAboutSheet({
    required this.workerEmail,
  });

  @override
  Widget build(BuildContext context) {
    final h = MediaQuery.of(context).size.height;
    final kTextSecondary = Colors.white.withOpacity(0.65);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Material(
          color: Colors.transparent,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(26),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
              child: Container(
                height: h * 0.62,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      const Color(0xFF2F3036).withOpacity(0.92),
                      const Color(0xFF24252B).withOpacity(0.90),
                      Colors.black.withOpacity(0.22),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(26),
                  border: Border.all(color: Colors.white.withOpacity(0.10)),
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

                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Row(
                        children: [
                          Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.white.withOpacity(0.06),
                              border: Border.all(
                                color: Colors.white.withOpacity(0.10),
                              ),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(8),
                              child: Image.network(
                                CompanyLogoHelper.defaultLogoUrl,
                                fit: BoxFit.contain,
                                errorBuilder: (_, __, ___) => const Icon(
                                  Icons.broken_image_outlined,
                                  color: Colors.white54,
                                  size: 20,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Workio',
                                  style: TextStyle(
                                    color: Colors.white.withOpacity(0.92),
                                    fontWeight: FontWeight.w900,
                                    fontSize: 16,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'Worker panel',
                                  style: TextStyle(
                                    color: Colors.white.withOpacity(0.58),
                                    fontWeight: FontWeight.w700,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          InkWell(
                            onTap: () => Navigator.pop(context),
                            borderRadius: BorderRadius.circular(14),
                            child: SizedBox(
                              width: 36,
                              height: 36,
                              child: Icon(
                                Icons.close_rounded,
                                color: Colors.white.withOpacity(0.78),
                                size: 22,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 12),

                    Container(
                      height: 1,
                      margin: const EdgeInsets.symmetric(horizontal: 16),
                      color: Colors.white.withOpacity(0.08),
                    ),

                    Expanded(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                        child: Column(
                          children: [
                            _aboutBlock(
                              title: 'About',
                              icon: Icons.info_outline_rounded,
                              child: Text(
                                'Workio helps you track shifts, earnings, messages, and tasks.',
                                style: TextStyle(
                                  color: Colors.white.withOpacity(0.70),
                                  height: 1.35,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),

                            const SizedBox(height: 12),

                            _aboutBlock(
                              title: 'Account',
                              icon: Icons.person_outline_rounded,
                              child: Text(
                                'Signed in as: $workerEmail',
                                style: TextStyle(
                                  color: Colors.white.withOpacity(0.70),
                                  height: 1.35,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),

                            const SizedBox(height: 12),

                            _aboutBlock(
                              title: 'Technologies',
                              icon: Icons.settings_suggest_rounded,
                              child: Text(
                                'Flutter • Supabase\nDark glass UI • real-time logic',
                                style: TextStyle(
                                  color: Colors.white.withOpacity(0.70),
                                  height: 1.35,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),

                            const SizedBox(height: 12),

                            _aboutBlock(
                              title: 'Support',
                              icon: Icons.forum_rounded,
                              child: Text(
                                'If you want, we can add email/website/privacy policy here.\n'
                                    'We can also show the app version and build number.',
                                style: TextStyle(
                                  color: Colors.white.withOpacity(0.70),
                                  height: 1.35,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),

                            const SizedBox(height: 6),
                            Text(
                              '© Workio',
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.30),
                                fontWeight: FontWeight.w700,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
                      child: SizedBox(
                        width: double.infinity,
                        height: 46,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.white.withOpacity(0.10),
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                          onPressed: () => Navigator.pop(context),
                          child: Text(
                            'Close',
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.85),
                              fontWeight: FontWeight.w900,
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
      ),
    );
  }

  Widget _aboutBlock({
    required String title,
    required IconData icon,
    required Widget child,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.18),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                icon,
                size: 18,
                color: Colors.white.withOpacity(0.82),
              ),
              const SizedBox(width: 10),
              Text(
                title,
                style: TextStyle(
                  color: Colors.white.withOpacity(0.90),
                  fontWeight: FontWeight.w800,
                  fontSize: 15,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}

class _HeaderCard extends StatelessWidget {
  final bool onShift;
  final bool busy;
  final String? avatarUrl;
  final String workerName;
  final String workerEmail;
  final String accessMode;
  final double hourlyRate;
  final VoidCallback onPrimaryTap;
  final VoidCallback onPaymentsTap;
  final VoidCallback onHistoryTap;
  final VoidCallback onAboutTap;
  final VoidCallback onLogout;
  final VoidCallback onMessagesTap;
  final VoidCallback onTasksTap;

  const _HeaderCard({
    required this.onShift,
    required this.busy,
    required this.avatarUrl,
    required this.workerName,
    required this.workerEmail,
    required this.accessMode,
    required this.onPrimaryTap,
    required this.onPaymentsTap,
    required this.onHistoryTap,
    required this.onAboutTap,
    required this.onLogout,
    required this.onMessagesTap,
    required this.hourlyRate,
    required this.onTasksTap,
  });

  String get _accessValue {
    final mode = accessMode.trim().toLowerCase();
    if (mode == 'suspended') return 'Suspended';
    if (mode == 'readonly' ||
        mode == 'view-only' ||
        mode == 'view_only' ||
        mode == 'view') {
      return 'View only';
    }
    return 'Active';
  }

  Color get _accessColor {
    final mode = accessMode.trim().toLowerCase();
    if (mode == 'suspended') return const Color(0xFFFF6B6B);
    if (mode == 'readonly' ||
        mode == 'view-only' ||
        mode == 'view_only' ||
        mode == 'view') {
      return const Color(0xFFFFC14D);
    }
    return HistoryPalette.green;
  }

  IconData get _accessIcon {
    final mode = accessMode.trim().toLowerCase();
    if (mode == 'suspended') return Icons.block_rounded;
    if (mode == 'readonly' ||
        mode == 'view-only' ||
        mode == 'view_only' ||
        mode == 'view') {
      return Icons.visibility_rounded;
    }
    return Icons.verified_rounded;
  }

  bool get _isViewOnlyMode {
    final mode = accessMode.trim().toLowerCase();
    return mode == 'view_only' || mode == 'view-only' || mode == 'view';
  }

  String get _shiftValue => onShift ? 'On shift' : 'Off shift';

  Color get _shiftColor =>
      onShift ? HistoryPalette.green : const Color(0xFF9AA3AF);

  IconData get _shiftIcon =>
      onShift ? Icons.play_arrow_rounded : Icons.stop_rounded;

  String get _primaryLabel => onShift ? 'End' : 'Start';

  IconData get _primaryIcon =>
      onShift ? Icons.stop_circle_rounded : Icons.play_circle_fill_rounded;

  Color get _primaryColor => onShift
      ? const Color(0xFFFF7A59)
      : (_isViewOnlyMode
      ? const Color(0xFFFFC14D)
      : HistoryPalette.green);

  String get _hourlyRateValue {
    final hasDecimals = hourlyRate != hourlyRate.truncateToDouble();
    final rate = hasDecimals
        ? hourlyRate.toStringAsFixed(2)
        : hourlyRate.toStringAsFixed(0);
    return '\$$rate/h';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF31343B),
            Color(0xFF272A31),
            Color(0xFF1D2027),
          ],
          stops: [0.0, 0.55, 1.0],
        ),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(
          color: Colors.white.withOpacity(0.09),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.30),
            blurRadius: 24,
            offset: const Offset(0, 14),
          ),
          BoxShadow(
            color: Colors.white.withOpacity(0.045),
            blurRadius: 14,
            spreadRadius: -6,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0xFF262A31),
                  Color(0xFF1C2027),
                ],
              ),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(30),
                topRight: Radius.circular(30),
              ),
              border: Border(
                bottom: BorderSide(
                  color: Colors.white.withOpacity(0.05),
                ),
              ),
            ),
            child: SizedBox(
              height: 64,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned(
                    left: 0,
                    top: -24,
                    child: _AnimatedHeaderAvatar(
                      avatarUrl: avatarUrl,
                      ringColor: onShift
                          ? _shiftColor
                          : (_isViewOnlyMode
                          ? const Color(0xFFFFC14D)
                          : const Color(0xFF8E98A6)),
                      statusColor: _shiftColor,
                      statusIcon: _shiftIcon,
                      isActive: onShift,
                      isViewOnly: _isViewOnlyMode,
                    ),
                  ),
                  Positioned(
                    left: 104,
                    right: 128,
                    top: 8,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Worker panel',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: cs.onSurface,
                            fontSize: 13.5,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.12,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          'Access, contact and rate details',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.58),
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.08,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Positioned(
                    right: 0,
                    top: 2,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _HeaderTasksButton(onTap: onTasksTap),
                        const SizedBox(width: 8),
                        _HeaderMessagesButton(onTap: onMessagesTap),
                        const SizedBox(width: 8),
                        _HeaderLogoutButton(onTap: onLogout),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Column(
              children: [
                const _HeaderDivider(),
                const SizedBox(height: 7),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 35),
                  child: _HeaderInfoLine(
                    icon: Icons.person_rounded,
                    iconColor: const Color(0xFFFFC14D),
                    label: 'Name',
                    value: workerName.trim().isEmpty ? 'Worker' : workerName,
                  ),
                ),
                const SizedBox(height: 7),
                const _HeaderDivider(),
                const SizedBox(height: 7),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 35),
                  child: _HeaderInfoLine(
                    icon: Icons.mail_rounded,
                    iconColor: Colors.white,
                    label: 'Email',
                    value: workerEmail,
                  ),
                ),
                const SizedBox(height: 7),
                const _HeaderDivider(),
                const SizedBox(height: 7),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 35),
                  child: _HeaderInfoLine(
                    icon: _accessIcon,
                    iconColor: _accessColor,
                    label: 'Access',
                    value: _accessValue,
                    valueColor: _accessColor,
                  ),
                ),
                const SizedBox(height: 7),
                const _HeaderDivider(),
                const SizedBox(height: 7),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 35),
                  child: _HeaderInfoLine(
                    icon: Icons.attach_money_rounded,
                    iconColor: const Color(0xFF66A8FF),
                    label: 'Hourly rate',
                    value: _hourlyRateValue,
                    valueColor: const Color(0xFF66A8FF),
                  ),
                ),
                const SizedBox(height: 7),
                const _HeaderDivider(),
              ],
            ),
          ),

          const SizedBox(height: 16),

          Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0xFF262A31),
                  Color(0xFF1C2027),
                ],
              ),
              borderRadius: const BorderRadius.only(
                bottomLeft: Radius.circular(30),
                bottomRight: Radius.circular(30),
              ),
              border: Border(
                top: BorderSide(
                  color: Colors.white.withOpacity(0.05),
                ),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.22),
                  blurRadius: 14,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Row(
              children: [
                Expanded(
                  child: _HeaderFooterButton(
                    icon: _primaryIcon,
                    label: _primaryLabel,
                    color: _primaryColor,
                    filled: true,
                    loading: busy,
                    onTap: busy ? null : onPrimaryTap,
                  ),
                ),
                const SizedBox(width: 8),
                _HeaderFooterButton(
                  icon: Icons.account_balance_wallet_rounded,
                  label: 'Payments',
                  color: const Color(0xFFFFC14D),
                  compact: true,
                  tooltip: 'Payments',
                  onTap: onPaymentsTap,
                ),
                const SizedBox(width: 8),
                _HeaderFooterButton(
                  icon: Icons.history_rounded,
                  label: 'History',
                  color: const Color(0xFF66A8FF),
                  compact: true,
                  tooltip: 'History',
                  onTap: onHistoryTap,
                ),
                const SizedBox(width: 8),
                _HeaderFooterButton(
                  icon: Icons.info_outline_rounded,
                  label: 'About',
                  color: const Color(0xFFB38CFF),
                  compact: true,
                  tooltip: 'About',
                  onTap: onAboutTap,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HeaderDivider extends StatelessWidget {
  const _HeaderDivider();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 1,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [
            Colors.transparent,
            Colors.white.withOpacity(0.05),
            Colors.white.withOpacity(0.12),
            Colors.white.withOpacity(0.05),
            Colors.transparent,
          ],
        ),
      ),
    );
  }
}

class _HeaderLogoutButton extends StatelessWidget {
  final VoidCallback onTap;

  const _HeaderLogoutButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Color(0xFF343941),
                Color(0xFF262B32),
              ],
            ),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: Colors.white.withOpacity(0.05),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.22),
                blurRadius: 12,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: const Center(
            child: Icon(
              Icons.logout_rounded,
              color: Colors.white70,
              size: 16,
            ),
          ),
        ),
      ),
    );
  }
}

class _HeaderMessagesButton extends StatelessWidget {
  final VoidCallback onTap;

  const _HeaderMessagesButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Map<String, dynamic>?>(
      stream: MessageService.watchWorkerThread(),
      builder: (context, threadSnap) {
        final thread = threadSnap.data;
        final threadId = (thread?['id'] ?? '').toString().trim();

        Widget button({int unread = 0}) {
          return Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(18),
              onTap: onTap,
              child: Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Color(0xFF343941),
                      Color(0xFF262B32),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: Colors.white.withOpacity(0.05),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.22),
                      blurRadius: 12,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    const Center(
                      child: Icon(
                        Icons.forum_rounded,
                        color: Colors.white70,
                        size: 16,
                      ),
                    ),
                    if (unread > 0)
                      Positioned(
                        right: -3,
                        top: -3,
                        child: Container(
                          constraints: const BoxConstraints(
                            minWidth: 16,
                            minHeight: 16,
                          ),
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFF4D6D),
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(
                              color: const Color(0xFF1D2027),
                              width: 1.4,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFFFF4D6D).withOpacity(0.35),
                                blurRadius: 10,
                              ),
                            ],
                          ),
                          child: Center(
                            child: Text(
                              unread > 99 ? '99+' : '$unread',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 8.5,
                                fontWeight: FontWeight.w900,
                                height: 1.0,
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          );
        }

        if (threadId.isEmpty) {
          return button();
        }

        return StreamBuilder<List<Map<String, dynamic>>>(
          stream: MessageService.watchMessages(threadId),
          builder: (context, msgSnap) {
            final messages = msgSnap.data ?? const <Map<String, dynamic>>[];

            final unread = messages.where((m) {
              final senderRole = (m['sender_role'] ?? '').toString().trim().toLowerCase();
              final readAt = m['read_at'];
              return senderRole == 'admin' && readAt == null;
            }).length;

            return button(unread: unread);
          },
        );
      },
    );
  }
}

class _HeaderTasksButton extends StatelessWidget {
  final VoidCallback onTap;

  const _HeaderTasksButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<int>(
      stream: TaskService.watchWorkerTaskUnseenCount(),
      builder: (context, snapshot) {
        final unread = snapshot.data ?? 0;

        return Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: onTap,
            child: Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color(0xFF343941),
                    Color(0xFF262B32),
                  ],
                ),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: Colors.white.withOpacity(0.05),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.22),
                    blurRadius: 12,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  const Center(
                    child: Icon(
                      Icons.assignment_rounded,
                      color: Colors.white70,
                      size: 16,
                    ),
                  ),
                  if (unread > 0)
                    Positioned(
                      right: -3,
                      top: -3,
                      child: Container(
                        constraints: const BoxConstraints(
                          minWidth: 16,
                          minHeight: 16,
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFF4D6D),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(
                            color: const Color(0xFF1D2027),
                            width: 1.4,
                          ),
                        ),
                        child: Center(
                          child: Text(
                            unread > 99 ? '99+' : '$unread',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 8.5,
                              fontWeight: FontWeight.w900,
                              height: 1.0,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _AnimatedHeaderAvatar extends StatefulWidget {
  final String? avatarUrl;
  final Color ringColor;
  final Color statusColor;
  final IconData statusIcon;
  final bool isActive;
  final bool isViewOnly;

  const _AnimatedHeaderAvatar({
    required this.avatarUrl,
    required this.ringColor,
    required this.statusColor,
    required this.statusIcon,
    required this.isActive,
    required this.isViewOnly,
  });

  @override
  State<_AnimatedHeaderAvatar> createState() => _AnimatedHeaderAvatarState();
}

class _AnimatedHeaderAvatarState extends State<_AnimatedHeaderAvatar>
    with TickerProviderStateMixin {
  late final AnimationController _ringCtrl;
  late final AnimationController _pulseCtrl;
  late final Animation<double> _pulseOpacity;
  late final Animation<double> _pulseScale;
  late final Animation<double> _viewOnlyRingOpacity;

  @override
  void initState() {
    super.initState();

    _ringCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    );

    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 950),
    );

    _pulseOpacity = Tween<double>(
      begin: 0.55,
      end: 1.0,
    ).animate(
      CurvedAnimation(
        parent: _pulseCtrl,
        curve: Curves.easeInOut,
      ),
    );

    _pulseScale = Tween<double>(
      begin: 0.92,
      end: 1.05,
    ).animate(
      CurvedAnimation(
        parent: _pulseCtrl,
        curve: Curves.easeInOut,
      ),
    );

    _viewOnlyRingOpacity = Tween<double>(
      begin: 0.35,
      end: 1.0,
    ).animate(
      CurvedAnimation(
        parent: _pulseCtrl,
        curve: Curves.easeInOut,
      ),
    );

    if (widget.isActive) {
      _ringCtrl.repeat();
    }

    if (widget.isActive || widget.isViewOnly) {
      _pulseCtrl.repeat(reverse: true);
    }
  }

  @override
  void didUpdateWidget(covariant _AnimatedHeaderAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);

    final shouldAnimateRing = widget.isActive || widget.isViewOnly;
    final oldShouldAnimateRing = oldWidget.isActive || oldWidget.isViewOnly;

    if (shouldAnimateRing != oldShouldAnimateRing) {
      if (shouldAnimateRing) {
        _ringCtrl.repeat();
      } else {
        _ringCtrl.stop();
        _ringCtrl.value = 0;
      }
    }

    if (widget.isActive != oldWidget.isActive) {
      if (widget.isActive) {
        _ringCtrl.repeat();
      } else {
        _ringCtrl.stop();
        _ringCtrl.value = 0;
      }
    }

    final shouldPulse = widget.isActive || widget.isViewOnly;
    final oldShouldPulse = oldWidget.isActive || oldWidget.isViewOnly;

    if (shouldPulse != oldShouldPulse) {
      if (shouldPulse) {
        _pulseCtrl.repeat(reverse: true);
      } else {
        _pulseCtrl.stop();
        _pulseCtrl.value = 1;
      }
    }
  }

  @override
  void dispose() {
    _ringCtrl.dispose();
    _pulseCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final shouldAnimateRing = widget.isActive || widget.isViewOnly;
    return SizedBox(
      width: 86,
      height: 86,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: AnimatedBuilder(
              animation: Listenable.merge([_ringCtrl, _pulseCtrl]),
              builder: (context, child) {
                final ring = CustomPaint(
                  painter: _AvatarRingPainter(
                    color: widget.isViewOnly
                        ? const Color(0xFFFFC14D)
                        : widget.ringColor,
                    isActive: widget.isActive,
                    isViewOnly: widget.isViewOnly,
                  ),
                );

                if (widget.isActive) {
                  return Transform.rotate(
                    angle: _ringCtrl.value * 2 * math.pi,
                    child: ring,
                  );
                }

                if (widget.isViewOnly) {
                  return Opacity(
                    opacity: _viewOnlyRingOpacity.value,
                    child: ring,
                  );
                }

                return ring;
              },
            ),
          ),
          Positioned.fill(
            child: Padding(
              padding: const EdgeInsets.all(7),
              child: Container(
                padding: const EdgeInsets.all(2.2),
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Color(0xFF10151C),
                ),
                child: CircleAvatar(
                  backgroundColor: const Color(0xFF0E1218),
                  backgroundImage: widget.avatarUrl != null
                      ? NetworkImage(widget.avatarUrl!)
                      : const AssetImage(
                    'assets/images/avatar_placeholder.png',
                  ) as ImageProvider,
                ),
              ),
            ),
          ),
          Positioned(
            right: 4,
            bottom: 2,
            child: widget.isActive
                ? FadeTransition(
              opacity: _pulseOpacity,
              child: ScaleTransition(
                scale: _pulseScale,
                child: _buildStatusBadge(),
              ),
            )
                : _buildStatusBadge(),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusBadge() {
    return Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: const Color(0xFF252B33),
        border: Border.all(
          color: Colors.white.withOpacity(0.10),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.22),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Center(
        child: Icon(
          widget.statusIcon,
          size: 16,
          color: widget.statusColor,
        ),
      ),
    );
  }
}

class _AvatarRingPainter extends CustomPainter {
  final Color color;
  final bool isActive;
  final bool isViewOnly;

  _AvatarRingPainter({
    required this.color,
    required this.isActive,
    required this.isViewOnly,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = (size.width / 2) - 3;

    if (isViewOnly) {
      final ringPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.2
        ..color = const Color(0xFFFFC14D);

      canvas.drawCircle(center, radius, ringPaint);
      return;
    }

    final trackPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.2
      ..strokeCap = StrokeCap.round
      ..color = isActive
          ? color.withOpacity(0.12)
          : const Color(0xFF8E98A6).withOpacity(0.30);

    canvas.drawCircle(center, radius, trackPaint);

    if (isActive) {
      final arcPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.2
        ..strokeCap = StrokeCap.round
        ..color = color;

      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        -1.25,
        1.45,
        false,
        arcPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _AvatarRingPainter oldDelegate) {
    return oldDelegate.color != color ||
        oldDelegate.isActive != isActive ||
        oldDelegate.isViewOnly != isViewOnly;
  }
}

class _HeaderInfoLine extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String label;
  final String value;
  final Color? valueColor;

  const _HeaderInfoLine({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.value,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Row(
      children: [
        Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            color: iconColor.withOpacity(0.14),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            icon,
            size: 13,
            color: iconColor,
          ),
        ),
        const SizedBox(width: 8),
        Text(
          label,
          style: TextStyle(
            color: cs.outline.withOpacity(0.90),
            fontSize: 11.5,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.right,
            style: TextStyle(
              color: valueColor ?? cs.onSurface,
              fontSize: 12.5,
              fontWeight: FontWeight.w900,
              height: 1.0,
            ),
          ),
        ),
      ],
    );
  }
}

class _AvatarShiftCapsule extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String text;

  const _AvatarShiftCapsule({
    required this.icon,
    required this.color,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 31,
      padding: const EdgeInsets.symmetric(horizontal: 11),
      decoration: BoxDecoration(
        color: const Color(0xFF252B35),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: color.withOpacity(0.16),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.14),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Text(
            text,
            style: TextStyle(
              color: color,
              fontSize: 10.5,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.1,
            ),
          ),
        ],
      ),
    );
  }
}

class _HeaderSlimCapsule extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String? label;
  final String value;
  final bool showLabel;
  final bool dark;

  const _HeaderSlimCapsule({
    required this.icon,
    required this.iconColor,
    this.label,
    required this.value,
    this.showLabel = true,
    this.dark = false,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: dark
              ? const [
            Color(0xFF2A2F36),
            Color(0xFF181C22),
          ]
              : const [
            Color(0xFF31363E),
            Color(0xFF232830),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: dark
              ? Colors.white.withOpacity(0.045)
              : Colors.white.withOpacity(0.055),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(dark ? 0.22 : 0.12),
            blurRadius: dark ? 12 : 6,
            offset: Offset(0, dark ? 6 : 3),
          ),
          if (dark)
            BoxShadow(
              color: Colors.white.withOpacity(0.025),
              blurRadius: 8,
              spreadRadius: -4,
              offset: const Offset(0, -2),
            ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 22,
            height: 22,
            decoration: BoxDecoration(
              color: iconColor.withOpacity(0.14),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              icon,
              size: 12,
              color: iconColor,
            ),
          ),
          const SizedBox(width: 10),
          if (showLabel && label != null) ...[
            Text(
              label!,
              style: TextStyle(
                color: cs.outline.withOpacity(0.92),
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(width: 8),
          ],
          Expanded(
            child: Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: showLabel ? TextAlign.right : TextAlign.left,
              style: TextStyle(
                color: cs.onSurface,
                fontSize: 12.6,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.02,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HeaderFooterButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback? onTap;
  final bool filled;
  final bool compact;
  final bool loading;
  final String? tooltip;

  const _HeaderFooterButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
    this.filled = false,
    this.compact = false,
    this.loading = false,
    this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    final borderRadius = BorderRadius.circular(compact ? 18 : 20);

    final decoration = BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: filled
            ? [
          const Color(0xFF2A3139),
          const Color(0xFF1B2027),
        ]
            : [
          const Color(0xFF242A32),
          const Color(0xFF171C23),
        ],
      ),
      borderRadius: borderRadius,
      border: Border.all(
        color: Colors.white.withOpacity(filled ? 0.08 : 0.06),
      ),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withOpacity(0.34),
          blurRadius: 18,
          offset: const Offset(0, 8),
        ),
        BoxShadow(
          color: Colors.white.withOpacity(0.045),
          blurRadius: 10,
          spreadRadius: -4,
          offset: const Offset(0, -2),
        ),
      ],
    );

    final child = Container(
      height: compact ? 48 : 50,
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 14 : 16,
      ),
      decoration: decoration,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (loading) ...[
            SizedBox(
              width: 15,
              height: 15,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(color),
              ),
            ),
          ] else ...[
            Icon(
              icon,
              size: compact ? 18 : 20,
              color: color,
            ),
          ],
          if (!compact) const SizedBox(width: 8),
          if (!compact)
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: color,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
        ],
      ),
    );

    return Tooltip(
      message: tooltip ?? label,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: borderRadius,
          onTap: onTap,
          child: child,
        ),
      ),
    );
  }
}

class _HeaderSlimRow extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String label;
  final String value;

  const _HeaderSlimRow({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      height: 46,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF232831),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Colors.white.withOpacity(0.06),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.16),
            blurRadius: 10,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: iconColor.withOpacity(0.14),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              icon,
              size: 16,
              color: iconColor,
            ),
          ),
          const SizedBox(width: 10),
          Text(
            label,
            style: TextStyle(
              color: cs.outline.withOpacity(0.95),
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.right,
              style: TextStyle(
                color: cs.onSurface,
                fontSize: 14,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.1,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HeaderCapsuleRow extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String label;
  final String value;

  const _HeaderCapsuleRow({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF232831),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: Colors.white.withOpacity(0.06),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.20),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: iconColor.withOpacity(0.15),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: iconColor.withOpacity(0.18),
              ),
            ),
            child: Icon(
              icon,
              color: iconColor,
              size: 18,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: cs.outline.withOpacity(0.92),
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Flexible(
            child: Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.right,
              style: TextStyle(
                color: cs.onSurface,
                fontSize: 15,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.1,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HeaderInfoCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final Color color;

  const _HeaderInfoCard({
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.white.withOpacity(0.07),
            Colors.white.withOpacity(0.02),
          ],
        ),
        border: Border.all(
          color: Colors.white.withOpacity(0.10),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              color: color.withOpacity(0.16),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: cs.outline,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.4,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  value,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: color,
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                    height: 1.1,
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

class _SummaryCard extends StatelessWidget {
  final double hourlyRate;
  final double totalHours;
  final double totalEarned;
  final double? lastPaymentAmount;

  final String workerName;
  final String workerEmail;
  final String accessMode;
  final bool onShift;
  final Map<String, dynamic>? activeShift;
  final Map<String, dynamic>? lastCompleted;
  final Duration elapsed;

  const _SummaryCard({
    required this.hourlyRate,
    required this.totalHours,
    required this.totalEarned,
    required this.lastPaymentAmount,
    required this.workerName,
    required this.workerEmail,
    required this.accessMode,
    required this.onShift,
    required this.activeShift,
    required this.lastCompleted,
    required this.elapsed,
  });

  String _money(double v) => '\$${v.toStringAsFixed(2)}';

  String _hoursText(double v) {
    if (v == v.truncateToDouble()) {
      return '${v.toStringAsFixed(0)} h';
    }
    return '${v.toStringAsFixed(1)} h';
  }

  String _fmtClock(DateTime dt) => DateFormat.Hm().format(dt);
  String _fmtDate(DateTime dt) => DateFormat.yMMMd().format(dt);

  String _fmtElapsed(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60);

    if (h > 0) {
      return '${h.toString().padLeft(2, '0')}:'
          '${m.toString().padLeft(2, '0')}:'
          '${s.toString().padLeft(2, '0')}';
    }
    return '${m.toString().padLeft(2, '0')}:'
        '${s.toString().padLeft(2, '0')}';
  }

  String get _accessValue {
    final mode = accessMode.trim().toLowerCase();
    if (mode == 'suspended') return 'Suspended';
    if (mode == 'view-only' || mode == 'view_only' || mode == 'view') {
      return 'View only';
    }
    return 'Active';
  }

  Color get _accessColor {
    final mode = accessMode.trim().toLowerCase();
    if (mode == 'suspended') return const Color(0xFFFF6B6B);
    if (mode == 'view-only' || mode == 'view_only' || mode == 'view') {
      return const Color(0xFFFFC14D);
    }
    return const Color(0xFF63F5C2);
  }

  void _showSummarySheet(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final active = activeShift;
    final last = lastCompleted;

    final activeStart = active != null
        ? DateTime.tryParse(active['start_time'].toString())?.toLocal()
        : null;

    final lastStart = last != null
        ? DateTime.tryParse(last['start_time'].toString())?.toLocal()
        : null;

    final lastEnd = last != null && last['end_time'] != null
        ? DateTime.tryParse(last['end_time'].toString())?.toLocal()
        : null;

    final currentRateRaw = active?['pay_rate'];
    final currentRate = currentRateRaw is num
        ? currentRateRaw.toDouble()
        : double.tryParse(currentRateRaw?.toString() ?? '') ?? hourlyRate;

    final liveMoney = (elapsed.inSeconds / 3600.0) * currentRate;

    Widget detailRow({
      required IconData icon,
      required Color color,
      required String label,
      required String value,
    }) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          color: Colors.white.withOpacity(0.03),
          border: Border.all(
            color: Colors.white.withOpacity(0.06),
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.04),
                borderRadius: BorderRadius.circular(11),
                border: Border.all(
                  color: Colors.white.withOpacity(0.05),
                ),
              ),
              child: Icon(icon, color: color, size: 18),
            ),
            const SizedBox(width: 12),
            SizedBox(
              width: 110,
              child: Text(
                label,
                style: TextStyle(
                  color: Colors.white.withOpacity(0.62),
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(left: 20),
                child: Text(
                  value,
                  textAlign: TextAlign.left,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: cs.onSurface,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    Widget sectionTitle(String text) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Text(
          text,
          style: TextStyle(
            color: Colors.white.withOpacity(0.72),
            fontSize: 12,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.5,
          ),
        ),
      );
    }

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
            child: Container(
              padding: EdgeInsets.zero,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(28),
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color(0xFF232830),
                    Color(0xFF171B22),
                    Color(0xFF10141A),
                  ],
                  stops: [0.0, 0.56, 1.0],
                ),
                border: Border.all(
                  color: Colors.white.withOpacity(0.08),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.45),
                    blurRadius: 24,
                    offset: const Offset(0, 14),
                  ),
                ],
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                  Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        Color(0xFF171C23),
                        Color(0xFF0F141A),
                      ],
                    ),
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(28),
                      topRight: Radius.circular(28),
                    ),
                    border: Border(
                      bottom: BorderSide(
                        color: Colors.white.withOpacity(0.05),
                      ),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Center(
                        child: Container(
                          width: 46,
                          height: 5,
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.14),
                            borderRadius: BorderRadius.circular(999),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          const Icon(
                            Icons.grid_view_rounded,
                            color: Color(0xFFB38CFF),
                            size: 20,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Summary details',
                              style: TextStyle(
                                color: cs.onSurface,
                                fontWeight: FontWeight.w900,
                                fontSize: 18,
                              ),
                            ),
                          ),
                          Material(
                            color: Colors.transparent,
                            child: InkWell(
                              borderRadius: BorderRadius.circular(14),
                              onTap: () => Navigator.pop(ctx),
                              child: Container(
                                width: 34,
                                height: 34,
                                decoration: BoxDecoration(
                                  gradient: const LinearGradient(
                                    begin: Alignment.topCenter,
                                    end: Alignment.bottomCenter,
                                    colors: [
                                      Color(0xFF343941),
                                      Color(0xFF262B32),
                                    ],
                                  ),
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(
                                    color: Colors.white.withOpacity(0.05),
                                  ),
                                ),
                                child: const Icon(
                                  Icons.close_rounded,
                                  color: Colors.white70,
                                  size: 18,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Detailed overview of your profile, totals and shift information',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.58),
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                ),

                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                    sectionTitle('PROFILE'),
                    detailRow(
                      icon: Icons.person_rounded,
                      color: const Color(0xFFFFC14D),
                      label: 'Worker',
                      value: workerName,
                    ),
                    const SizedBox(height: 10),
                    detailRow(
                      icon: Icons.mail_rounded,
                      color: Colors.white,
                      label: 'Email',
                      value: workerEmail,
                    ),
                    const SizedBox(height: 10),
                    detailRow(
                      icon: Icons.verified_rounded,
                      color: _accessColor,
                      label: 'Access',
                      value: _accessValue,
                    ),

                    const SizedBox(height: 18),
                    sectionTitle('TOTALS'),
                    detailRow(
                      icon: Icons.payments_outlined,
                      color: const Color(0xFF66A8FF),
                      label: 'Hourly rate',
                      value: _money(hourlyRate),
                    ),
                    const SizedBox(height: 10),
                    detailRow(
                      icon: Icons.timer_outlined,
                      color: Colors.orangeAccent,
                      label: 'Total hours',
                      value: _hoursText(totalHours),
                    ),
                    const SizedBox(height: 10),
                    detailRow(
                      icon: Icons.attach_money_rounded,
                      color: const Color(0xFF63F5C2),
                      label: 'Total earned',
                      value: _money(totalEarned),
                    ),
                    const SizedBox(height: 10),
                    detailRow(
                      icon: Icons.credit_card_outlined,
                      color: Colors.amberAccent,
                      label: 'Last payout',
                      value: lastPaymentAmount == null
                          ? 'Not recorded'
                          : _money(lastPaymentAmount!),
                    ),

                    const SizedBox(height: 18),
                    sectionTitle(onShift ? 'CURRENT SHIFT' : 'LAST SHIFT'),

                    if (onShift && activeStart != null) ...[
                      detailRow(
                        icon: Icons.play_arrow_rounded,
                        color: const Color(0xFF63F5C2),
                        label: 'Status',
                        value: 'On shift',
                      ),
                      const SizedBox(height: 10),
                      detailRow(
                        icon: Icons.schedule_rounded,
                        color: const Color(0xFF66A8FF),
                        label: 'Started',
                        value: '${_fmtDate(activeStart)} • ${_fmtClock(activeStart)}',
                      ),
                      const SizedBox(height: 10),
                      detailRow(
                        icon: Icons.timelapse_rounded,
                        color: const Color(0xFFB38CFF),
                        label: 'Worked',
                        value: _fmtElapsed(elapsed),
                      ),
                      const SizedBox(height: 10),
                      detailRow(
                        icon: Icons.attach_money_rounded,
                        color: const Color(0xFFFFC14D),
                        label: 'Live earned',
                        value: _money(liveMoney),
                      ),
                    ] else if (!onShift && last != null && lastStart != null) ...[
                      detailRow(
                        icon: Icons.check_circle_rounded,
                        color: Colors.orangeAccent,
                        label: 'Status',
                        value: 'Completed',
                      ),
                      const SizedBox(height: 10),
                      detailRow(
                        icon: Icons.login_rounded,
                        color: const Color(0xFF66A8FF),
                        label: 'Started',
                        value: '${_fmtDate(lastStart)} • ${_fmtClock(lastStart)}',
                      ),
                      const SizedBox(height: 10),
                      detailRow(
                        icon: Icons.logout_rounded,
                        color: const Color(0xFFB38CFF),
                        label: 'Ended',
                        value: lastEnd != null
                            ? '${_fmtDate(lastEnd)} • ${_fmtClock(lastEnd)}'
                            : '--',
                      ),
                      const SizedBox(height: 10),
                      detailRow(
                        icon: Icons.attach_money_rounded,
                        color: const Color(0xFFFFC14D),
                        label: 'Shift earned',
                        value: _money(
                          ((last['total_payment'] as num?) ?? 0).toDouble(),
                        ),
                      ),
                      const SizedBox(height: 10),
                      detailRow(
                        icon: Icons.timelapse_rounded,
                        color: const Color(0xFF63F5C2),
                        label: 'Shift hours',
                        value: '${(((last['total_hours'] as num?) ?? 0).toDouble()).toStringAsFixed(1)} h',
                      ),
                    ] else ...[
                      detailRow(
                        icon: Icons.info_outline_rounded,
                        color: Colors.white70,
                        label: 'Shift info',
                        value: 'No details available yet',
                      ),
                    ],
                    ],
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
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    Widget row({
      required IconData icon,
      required Color color,
      required String label,
      required String value,
    }) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          color: Colors.white.withOpacity(0.03),
          border: Border.all(
            color: Colors.white.withOpacity(0.08),
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(11),
                color: Colors.white.withOpacity(0.04),
                border: Border.all(
                  color: Colors.white.withOpacity(0.05),
                ),
              ),
              child: Icon(icon, color: color, size: 18),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  color: cs.outline,
                  fontWeight: FontWeight.w700,
                  fontSize: 13.5,
                ),
              ),
            ),
            Text(
              value,
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.w900,
                fontSize: 14.5,
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF1D2229),
            Color(0xFF13181F),
            Color(0xFF0C1015),
          ],
          stops: [0.0, 0.56, 1.0],
        ),
        border: Border.all(
          color: Colors.white.withOpacity(0.07),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.50),
            blurRadius: 26,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0xFF1A1F26),
                  Color(0xFF11161D),
                ],
              ),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(24),
                topRight: Radius.circular(24),
              ),
              border: Border(
                bottom: BorderSide(
                  color: Colors.white.withOpacity(0.05),
                ),
              ),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.analytics_outlined,
                  color: Color(0xFF66A8FF),
                  size: 22,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Summary',
                        style: TextStyle(
                          color: cs.onSurface,
                          fontWeight: FontWeight.w900,
                          fontSize: 17,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Overview of your hours, earnings and payouts',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.56),
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                row(
                  icon: Icons.timer_outlined,
                  label: 'Total hours',
                  value: _hoursText(totalHours),
                  color: Colors.orangeAccent,
                ),
                const SizedBox(height: 10),
                row(
                  icon: Icons.attach_money_rounded,
                  label: 'Total earned',
                  value: _money(totalEarned),
                  color: const Color(0xFF63F5C2),
                ),
                const SizedBox(height: 10),
                row(
                  icon: Icons.credit_card_outlined,
                  label: 'Last payout',
                  value: lastPaymentAmount == null
                      ? 'Not recorded'
                      : _money(lastPaymentAmount!),
                  color: Colors.amberAccent,
                ),
                const SizedBox(height: 12),
                Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: () => _showSummarySheet(context),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 13,
                      ),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Color(0xFF262C34),
                            Color(0xFF181D24),
                          ],
                        ),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: Colors.white.withOpacity(0.08),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.22),
                            blurRadius: 12,
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.grid_view_rounded,
                            size: 18,
                            color: Color(0xFFB38CFF),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'More details',
                              style: TextStyle(
                                color: cs.onSurface,
                                fontWeight: FontWeight.w800,
                                fontSize: 14,
                              ),
                            ),
                          ),
                          Icon(
                            Icons.chevron_right_rounded,
                            color: Colors.white.withOpacity(0.62),
                          ),
                        ],
                      ),
                    ),
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


class _ShiftCard extends StatefulWidget {
  final bool onShift;
  final Map<String, dynamic>? activeShift;
  final Map<String, dynamic>? lastCompleted;
  final Duration elapsed;
  final double hourlyRate;

  const _ShiftCard({
    required this.onShift,
    required this.activeShift,
    required this.lastCompleted,
    required this.elapsed,
    required this.hourlyRate,
  });

  @override
  State<_ShiftCard> createState() => _ShiftCardState();
}

class _ShiftCardState extends State<_ShiftCard> {
  bool _blink = true;
  int _lastWholeDollar = 0;
  bool _moneyFlash = false;
  Timer? _blinkTimer;

  @override
  void initState() {
    super.initState();
    _blinkTimer = Timer.periodic(const Duration(milliseconds: 700), (_) {
      if (!mounted) return;
      setState(() => _blink = !_blink);
    });
  }

  @override
  void dispose() {
    _blinkTimer?.cancel();
    super.dispose();
  }

  DateTime? _parse(dynamic v) {
    if (v == null) return null;
    try {
      return DateTime.parse(v.toString());
    } catch (_) {
      return null;
    }
  }

  String _fmtClock(DateTime dt) => DateFormat.Hm().format(dt);
  String _fmtDate(DateTime dt) => DateFormat.yMMMd().format(dt);

  String _fmtElapsed(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60);
    if (h > 0) {
      return '${h.toString().padLeft(2, '0')}:'
          '${m.toString().padLeft(2, '0')}:'
          '${s.toString().padLeft(2, '0')}';
    }
    return '${m.toString().padLeft(2, '0')}:'
        '${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final onShift = widget.onShift;
    final activeShift = widget.activeShift;
    final lastCompleted = widget.lastCompleted;
    final elapsed = widget.elapsed;

// === STEP 1: ACTIVE SHIFT BLOCK START =====================================================================
    if (onShift && widget.activeShift != null) {
      return _buildActiveShift(context);
    }

    if (!onShift && widget.lastCompleted != null) {
      return _buildLastShift(context);
    }

    return _buildEmptyState();

  }
  Widget _buildEmptyState() {
    final cs = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        color: cs.surface,
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Text(
        'No shifts yet',
        style: TextStyle(
          color: cs.outline,
          fontWeight: FontWeight.w600,
        ),
        textAlign: TextAlign.center,
      ),
    );
  }
  Widget _buildLastShift(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final shift = widget.lastCompleted!;

    final start = DateTime.parse(shift['start_time']).toLocal();
    final end = shift['end_time'] != null
        ? DateTime.parse(shift['end_time']).toLocal()
        : null;

    final hours = (shift['total_hours'] as num?)?.toDouble() ?? 0.0;
    final payment = (shift['total_payment'] as num?)?.toDouble() ?? 0.0;

    String workedText() {
      if (hours == hours.truncateToDouble()) {
        return '${hours.toStringAsFixed(0)}h';
      }
      return '${hours.toStringAsFixed(1)}h';
    }

    String rateText() {
      final rate = widget.hourlyRate;
      if (rate == rate.truncateToDouble()) {
        return '\$${rate.toStringAsFixed(0)}/h';
      }
      return '\$${rate.toStringAsFixed(2)}/h';
    }

    Widget stat({
      required IconData icon,
      required Color color,
      required String label,
      required String value,
    }) {
      return Expanded(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 14, color: color),
                const SizedBox(width: 6),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.58),
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: cs.onSurface,
                fontSize: 14,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF2B2F36),
            Color(0xFF1F232A),
            Color(0xFF171A20),
          ],
          stops: [0.0, 0.58, 1.0],
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: Colors.white.withOpacity(0.07),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.32),
            blurRadius: 20,
            offset: const Offset(0, 12),
          ),
          BoxShadow(
            color: Colors.white.withOpacity(0.025),
            blurRadius: 10,
            spreadRadius: -5,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Last shift',
                      style: TextStyle(
                        color: cs.onSurface,
                        fontWeight: FontWeight.w900,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      DateFormat.yMMMd().format(start),
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.58),
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(999),
                  color: Colors.orangeAccent.withOpacity(0.10),
                  border: Border.all(
                    color: Colors.orangeAccent.withOpacity(0.18),
                  ),
                ),
                child: const Text(
                  'Completed',
                  style: TextStyle(
                    color: Colors.orangeAccent,
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),

          Container(
            height: 1,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: [
                  Colors.transparent,
                  Colors.orangeAccent.withOpacity(0.10),
                  Colors.white.withOpacity(0.10),
                  Colors.orangeAccent.withOpacity(0.10),
                  Colors.transparent,
                ],
              ),
            ),
          ),

          const SizedBox(height: 14),

          Center(
            child: Column(
              children: [
                Text(
                  '\$${payment.toStringAsFixed(2)}',
                  style: TextStyle(
                    color: cs.onSurface,
                    fontWeight: FontWeight.w900,
                    fontSize: 30,
                    letterSpacing: -0.8,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Worked ${workedText()}',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.64),
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 14),

          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0xFF2C3138),
                  Color(0xFF1D2128),
                ],
              ),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: Colors.white.withOpacity(0.05),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.24),
                  blurRadius: 12,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Row(
              children: [
                stat(
                  icon: Icons.login_rounded,
                  color: const Color(0xFF66A8FF),
                  label: 'Started',
                  value: _fmtClock(start),
                ),
                Container(
                  width: 1,
                  height: 34,
                  color: Colors.white.withOpacity(0.07),
                ),
                stat(
                  icon: Icons.logout_rounded,
                  color: const Color(0xFFB38CFF),
                  label: 'Ended',
                  value: end != null ? _fmtClock(end) : '--',
                ),
                Container(
                  width: 1,
                  height: 34,
                  color: Colors.white.withOpacity(0.07),
                ),
                stat(
                  icon: Icons.attach_money_rounded,
                  color: const Color(0xFFFFC14D),
                  label: 'Rate',
                  value: rateText(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActiveShift(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final shift = widget.activeShift!;
    final elapsed = widget.elapsed;

    final startUtc = DateTime.parse(shift['start_time']).toUtc();
    final startLocal = startUtc.toLocal();

    final activeRateRaw = shift['pay_rate'];
    final activeRate = activeRateRaw is num
        ? activeRateRaw.toDouble()
        : double.tryParse(activeRateRaw?.toString() ?? '') ?? widget.hourlyRate;

    final hours = elapsed.inSeconds / 3600.0;
    final money = hours * activeRate;

    final currentDollar = money.floor();
    if (currentDollar > _lastWholeDollar) {
      _lastWholeDollar = currentDollar;
      _moneyFlash = true;

      Future.delayed(const Duration(seconds: 1), () {
        if (mounted) {
          setState(() => _moneyFlash = false);
        }
      });
    }

    String rateText() {
      if (activeRate == activeRate.truncateToDouble()) {
        return '\$${activeRate.toStringAsFixed(0)}/h';
      }
      return '\$${activeRate.toStringAsFixed(2)}/h';
    }

    Widget stat({
      required IconData icon,
      required Color color,
      required String label,
      required String value,
    }) {
      return Expanded(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 14, color: color),
                const SizedBox(width: 6),
                Text(
                  label,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.58),
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              value,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: cs.onSurface,
                fontSize: 14,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF0F1318),
            Color(0xFF0B0F14),
            Color(0xFF070A0E),
          ],
          stops: [0.0, 0.55, 1.0],
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: Colors.white.withOpacity(0.07),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.34),
            blurRadius: 22,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.calendar_today_outlined,
                    size: 16,
                    color: Color(0xFF63F5C2),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    DateFormat.yMMMd().format(startLocal),
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.68),
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
              const Spacer(),
              Row(
                children: [
                  AnimatedOpacity(
                    opacity: _blink ? 1 : 0.28,
                    duration: const Duration(milliseconds: 320),
                    child: Container(
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(
                        color: Color(0xFFFF5A6B),
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                  const SizedBox(width: 7),
                  const Text(
                    'LIVE',
                    style: TextStyle(
                      color: Color(0xFF63F5C2),
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.7,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ],
          ),

          const SizedBox(height: 12),
          const _LiveDivider(color: Color(0xFF63F5C2)),
          const SizedBox(height: 18),

          const SizedBox(height: 18),

          Column(
            children: [
              AnimatedDefaultTextStyle(
                duration: const Duration(milliseconds: 260),
                curve: Curves.easeInOut,
                style: TextStyle(
                  color: _moneyFlash
                      ? const Color(0xFFFFC14D)
                      : const Color(0xFF63F5C2),
                  fontWeight: FontWeight.w900,
                  fontSize: 40,
                  letterSpacing: -1.0,
                ),
                child: Text('\$${money.toStringAsFixed(2)}'),
              ),
              const SizedBox(height: 4),
              AnimatedDefaultTextStyle(
                duration: const Duration(milliseconds: 260),
                curve: Curves.easeInOut,
                style: TextStyle(
                  color: _moneyFlash
                      ? const Color(0xFFFFC14D).withOpacity(0.85)
                      : Colors.white.withOpacity(0.58),
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
                child: const Text('Earned so far'),
              ),
            ],
          ),

          const SizedBox(height: 16),

          Container(
            height: 1,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Colors.transparent,
                  const Color(0xFF63F5C2).withOpacity(0.42),
                  Colors.transparent,
                ],
              ),
            ),
          ),

          const SizedBox(height: 14),

          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0xFF151A21),
                  Color(0xFF0D1117),
                ],
              ),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: Colors.white.withOpacity(0.05),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.22),
                  blurRadius: 12,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Row(
              children: [
                stat(
                  icon: Icons.play_arrow_rounded,
                  color: const Color(0xFF63F5C2),
                  label: 'Started',
                  value: _fmtClock(startLocal),
                ),
                Container(
                  width: 1,
                  height: 34,
                  color: Colors.white.withOpacity(0.07),
                ),
                const SizedBox(width: 10),
                stat(
                  icon: Icons.timelapse_rounded,
                  color: const Color(0xFF66A8FF),
                  label: 'Worked',
                  value: _fmtElapsed(elapsed),
                ),
                Container(
                  width: 1,
                  height: 34,
                  color: Colors.white.withOpacity(0.07),
                ),
                const SizedBox(width: 10),
                stat(
                  icon: Icons.attach_money_rounded,
                  color: const Color(0xFFFFC14D),
                  label: 'Rate',
                  value: rateText(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}


class _ActionButtons extends StatelessWidget {
  final bool onShift;
  final bool busy;
  final VoidCallback onStart;
  final VoidCallback onEnd;

  const _ActionButtons({
    required this.onShift,
    required this.busy,
    required this.onStart,
    required this.onEnd,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    // Start button = surface (same vibe as history), with icon
    Widget startBtn() {
      return InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: busy ? null : onStart,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
          decoration: BoxDecoration(
            color: Colors.green,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: cs.outlineVariant.withOpacity(0.24)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.play_arrow_rounded, size: 26, color: Colors.white),
              const SizedBox(width: 10),
              Text(
                busy ? 'Starting...' : 'Start shift',
                style: TextStyle(color: cs.onSurface, fontWeight: FontWeight.w900, fontSize: 16),
              ),
            ],
          ),
        ),
      );
    }

    // End button = burgundy, with icon
    Widget endBtn() {
      const burgundy = Color(0xFF7A1E2B);
      return InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: busy ? null : onEnd,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
          decoration: BoxDecoration(
            color: burgundy,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: burgundy.withOpacity(0.6)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.stop_rounded, size: 26, color: Colors.white),
              const SizedBox(width: 10),
              Text(
                busy ? 'Ending...' : 'End shift',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 16),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      children: [
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 220),
          child: onShift ? endBtn() : startBtn(),
        ),
      ],
    );
  }
}

class _HistoryButton extends StatelessWidget {
  final VoidCallback onTap;

  const _HistoryButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 14),
        decoration: BoxDecoration(
          color: Colors.deepPurpleAccent,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: cs.outlineVariant.withOpacity(0.24)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.history, color: cs.onSurface, size: 22),
            const SizedBox(width: 6),
            Text(
              'Work history',
              style: TextStyle(color: cs.onSurface, fontWeight: FontWeight.w900, fontSize: 15),
            ),
            const SizedBox(width: 6),
            Icon(Icons.chevron_right, color: cs.outline, size: 20),
          ],
        ),
      ),
    );
  }
}

class _PaymentsButton extends StatelessWidget {
  final VoidCallback onTap;

  const _PaymentsButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 14),
        decoration: BoxDecoration(
          color: const Color(0xFF1F9D74),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: cs.outlineVariant.withOpacity(0.24),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.account_balance_wallet_rounded,
              color: cs.onSurface,
              size: 22,
            ),
            const SizedBox(width: 6),
            Text(
              'Payments',
              style: TextStyle(
                color: cs.onSurface,
                fontWeight: FontWeight.w900,
                fontSize: 15,
              ),
            ),
            const SizedBox(width: 6),
            Icon(
              Icons.chevron_right,
              color: cs.outline,
              size: 20,
            ),
          ],
        ),
      ),
    );
  }
}
class _LiveDivider extends StatefulWidget {
  final Color color;

  const _LiveDivider({required this.color});

  @override
  State<_LiveDivider> createState() => _LiveDividerState();
}

class _LiveDividerState extends State<_LiveDivider>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 1,
      child: AnimatedBuilder(
        animation: _c,
        builder: (_, __) {
          return ShaderMask(
            shaderCallback: (rect) {
              return LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                stops: [
                  (_c.value - 0.3).clamp(0.0, 1.0),
                  _c.value,
                  (_c.value + 0.3).clamp(0.0, 1.0),
                ],
                colors: [
                  Colors.transparent,
                  widget.color,
                  Colors.transparent,
                ],
              ).createShader(rect);
            },
            blendMode: BlendMode.srcATop,
            child: Container(
              color: widget.color.withOpacity(0.25),
            ),
          );
        },
      ),
    );
  }
}
