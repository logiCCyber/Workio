import 'dart:math';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';

import 'admin_worker_details_screen.dart';
import '../dialogs/add_worker_dialog.dart';
import 'login_screen.dart';
import 'admin_home_screen.dart';


class AdminPanel extends StatefulWidget {
  const AdminPanel({super.key});

  @override
  State<AdminPanel> createState() => _AdminPanelState();
}

class _AdminPanelState extends State<AdminPanel> {

  final supabase = Supabase.instance.client;
  late final int _warningsSeed;
  List<Map<String, dynamic>> workers = [];
  Map<String, dynamic>? dashboard;
  bool loadingDashboard = true;
  bool loadingShiftEvents = false;
  List<Map<String, dynamic>> todayShiftEvents = [];
  Timer? _shiftEventsRefresher;

  // === LIVE / ONLINE (Step 1) ===
  Timer? _ticker;
  Timer? _onlineRefresher;
  DateTime _now = DateTime.now();

  bool _loadingOnline = true;
  List<Map<String, dynamic>> _onlineShifts = []; // active work_logs + worker


  @override
  void initState() {
    super.initState();
    _warningsSeed = Random().nextInt(0x7fffffff);
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    await _loadWorkers();       // ✅ сначала workers
    await _loadOnlineShifts();  // ✅ потом online
    _loadTodayShiftEvents(); // ✅ добавь

    _loadDashboard();           // можно не ждать

    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _now = DateTime.now());
    });

    _onlineRefresher = Timer.periodic(const Duration(seconds: 15), (_) async {
      if (!mounted) return;
      await _loadOnlineShifts();
    });

    _shiftEventsRefresher = Timer.periodic(const Duration(seconds: 25), (_) async {
      if (!mounted) return;
      await _loadTodayShiftEvents();
    });

  }

  Future<void> _reloadAll() async {
    await _loadWorkers();          // workers cards + unpaid + access_mode warnings
    await _loadOnlineShifts();     // live/online
    await _loadTodayShiftEvents(); // multiple starts warnings
    await _loadDashboard();        // summary totals: total unpaid, last paid, etc
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _onlineRefresher?.cancel();
    _shiftEventsRefresher?.cancel();
    super.dispose();
  }

  Future<void> _openAddWorkerDialog() async {
    await showDialog(
      context: context,
      barrierDismissible: true, // ✅ нельзя закрыть тапом снаружи
      builder: (_) => AddWorkerDialog(onCreated: _reloadAll),
    );
  }


  Future<void> _loadWorkers() async {
    final data = await supabase.rpc('admin_workers_list');

    setState(() {
      workers = List<Map<String, dynamic>>.from(data as List);
    });
  }

  Future<void> _loadOnlineShifts() async {
    setState(() => _loadingOnline = true);

    try {
      final data = await supabase
          .from('work_logs')
          .select('id, start_time, user_id')
          .filter('end_time', 'is', null)
          .order('start_time', ascending: true);

      final rows = List<Map<String, dynamic>>.from(data as List);

      // ✅ map: auth_user_id -> worker
      final byAuthId = <String, Map<String, dynamic>>{};
      for (final w in workers) {
        final authId = (w['auth_user_id'] ?? '').toString();
        if (authId.isNotEmpty) byAuthId[authId] = w;
      }

      final merged = rows.map((s) {
        final uid = (s['user_id'] ?? '').toString();
        return {
          ...s,
          'workers': byAuthId[uid] ?? {}, // ✅ тут будет hourly_rate, avatar_url, access_mode
        };
      }).toList();

      setState(() {
        _onlineShifts = merged;
        _loadingOnline = false;
      });
    } catch (e) {
      setState(() {
        _onlineShifts = [];
        _loadingOnline = false;
      });
    }
  }

  Future<void> _loadTodayShiftEvents() async {
    setState(() => loadingShiftEvents = true);

    try {
      final now = DateTime.now();
      final startLocal = DateTime(now.year, now.month, now.day);
      final endLocal = startLocal.add(const Duration(days: 1));

      final startUtc = startLocal.toUtc();
      final endUtc = endLocal.toUtc();

      debugPrint('SHIFT_EVENTS RANGE local: $startLocal -> $endLocal');
      debugPrint('SHIFT_EVENTS RANGE utc  : $startUtc -> $endUtc');

      final data = await supabase
          .from('shift_events')
          .select('id, worker_id, event_type, created_at')
          .gte('created_at', startUtc)
          .lt('created_at', endUtc)
          .order('created_at', ascending: false);

      final list = List<Map<String, dynamic>>.from(data as List);

      debugPrint('SHIFT_EVENTS TODAY count = ${list.length}');
      if (list.isNotEmpty) {
        debugPrint('SHIFT_EVENTS TODAY first = ${list.first}');
      }

      setState(() {
        todayShiftEvents = list;
        loadingShiftEvents = false;
      });
    } catch (e, st) {
      debugPrint('SHIFT_EVENTS ERROR: $e');
      debugPrint('$st');

      setState(() {
        todayShiftEvents = [];
        loadingShiftEvents = false;
      });
    }
  }



  Future<void> _loadDashboard() async {
    setState(() => loadingDashboard = true);

    final res = await supabase.rpc('admin_dashboard_summary');

    setState(() {
      dashboard = Map<String, dynamic>.from(res as Map);
      loadingDashboard = false;
    });
  }

  int _countUnpaidWorkers() {
    int c = 0;
    for (final w in workers) {
      final unpaid = (w['unpaid_total'] ?? 0).toDouble();
      if (unpaid > 0) c++;
    }
    return c;
  }

  int _countOnShiftNow() {
    int c = 0;
    for (final w in workers) {
      if (w['on_shift'] == true) c++;
    }
    return c;
  }

  /// IMPORTANT:
  /// тут я использую поле w['access_mode']
  /// если у тебя другое имя — скажи как называется, поменяем.
  String _modeOf(Map<String, dynamic> w) {
    return (w['access_mode'] ?? 'active').toString().toLowerCase().trim();
  }

  int _countViewOnlyWorkers() {
    int c = 0;
    for (final w in workers) {
      if (_modeOf(w) == 'view_only') c++;
    }
    return c;
  }

  int _countSuspendedWorkers() {
    int c = 0;
    for (final w in workers) {
      if (_modeOf(w) == 'suspended') c++;
    }
    return c;
  }

  /// Full access = active
  int _countFullAccessWorkers() {
    int c = 0;
    for (final w in workers) {
      if (_modeOf(w) == 'active') c++;
    }
    return c;
  }

  /// Общие warnings (как цифра на синей карточке)
  int _warningsTotal() {
    return _countUnpaidWorkers() + _countViewOnlyWorkers() + _countSuspendedWorkers();
  }

  double _avgHoursPerOnShiftToday() {
    final onShift = _countOnShiftNow();
    final hoursToday = ((dashboard?['hours_today'] ?? 0) as num).toDouble();
    if (onShift == 0) return 0.0;
    return hoursToday / onShift;
  }


  int _countNoAvatarWorkers() {
    int c = 0;
    for (final w in workers) {
      final a = (w['avatar_url'] ?? '').toString().trim();
      if (a.isEmpty) c++;
    }
    return c;
  }

  /// Общий счётчик проблем (можешь расширять)
  int _problemsTotal() {
    return _countUnpaidWorkers() + _countNoAvatarWorkers();
  }

  Future<void> _logout() async {
    await supabase.auth.signOut();
    if (!mounted) return;

    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
          (route) => false,
    );
  }

  Future<void> openPayCalendarForWorker(Map<String, dynamic> worker) async {
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2023),
      lastDate: DateTime.now(),
    );

    if (range == null) return;

    final fromUtc = DateTime(
      range.start.year,
      range.start.month,
      range.start.day,
    ).toUtc();

    final toUtc = DateTime(
      range.end.year,
      range.end.month,
      range.end.day,
      23,
      59,
      59,
    ).toUtc();

    // ⬇️ ВМЕСТО PAY — PREVIEW
    await _previewPayWorker(
      worker: worker,
      fromUtc: fromUtc,
      toUtc: toUtc,
    );
  }

  void _showPaymentSuccessDialog({
    required int paidShifts,
    required num totalAmount,
  }) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: const [
            Icon(Icons.check_circle, color: Colors.green),
            SizedBox(width: 8),
            Text('Payment successful'),
          ],
        ),
        content: Text(
          'Paid shifts: $paidShifts\n'
              'Total amount: \$${totalAmount.toStringAsFixed(2)}',
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }


  Future<void> _previewPayWorker({
    required Map<String, dynamic> worker,
    required DateTime fromUtc,
    required DateTime toUtc,
  }) async {
    final session = supabase.auth.currentSession;
    if (session == null) return;

    final res = await supabase.functions.invoke(
      'preview-pay-worker-period',
      body: {
        'user_id': worker['auth_user_id'],
        'from': fromUtc.toIso8601String(),
        'to': toUtc.toIso8601String(),
      },
      headers: {
        'Authorization': 'Bearer ${session.accessToken}',
      },
    );

    if (res.status != 200) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(res.data.toString())),
      );
      return;
    }

    _showPayPreviewDialog(
      worker: worker,
      preview: Map<String, dynamic>.from(res.data),
      fromUtc: fromUtc,
      toUtc: toUtc,
    );
  }



  void _showPayPreviewDialog({
    required Map<String, dynamic> worker,
    required Map<String, dynamic> preview,
    required DateTime fromUtc,
    required DateTime toUtc,
  }) {
    final rows = List<Map<String, dynamic>>.from(preview['rows'] ?? []);
    final totalAmount = (preview['total_amount'] ?? 0).toDouble();
    final totalHours = (preview['total_hours'] ?? 0).toDouble();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Payment preview'),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(worker['email'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                Text('${DateFormat.yMMMd().format(fromUtc.toLocal())} → ${DateFormat.yMMMd().format(toUtc.toLocal())}'),
                const Divider(),
                Text('Shifts: ${rows.length}'),
                Text('Hours: ${totalHours.toStringAsFixed(2)}'),
                Text('Total: \$${totalAmount.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.bold)),
                const Divider(),
                ...rows.map((r) {
                  final start = DateTime.parse(r['start_time']).toLocal();
                  final end = DateTime.parse(r['end_time']).toLocal();
                  final hours = (r['total_hours'] ?? 0).toDouble();
                  final amount = (r['total_payment'] ?? 0).toDouble();
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      '${DateFormat.yMMMd().format(start)} '
                          '${DateFormat.Hm().format(start)}–${DateFormat.Hm().format(end)} • '
                          '${hours.toStringAsFixed(2)}h • \$${amount.toStringAsFixed(2)}',
                    ),
                  );
                }),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await _payWorkerPeriod(
                workerAuthId: worker['auth_user_id'],
                fromUtc: fromUtc,
                toUtc: toUtc,
              );

            },
            child: const Text('PAY'),
          ),
        ],
      ),
    );
  }


  Future<void> _payWorkerPeriod({
    required String workerAuthId,
    required DateTime fromUtc,
    required DateTime toUtc,
  }) async {
    final session = supabase.auth.currentSession;
    if (session == null) return;

    final res = await supabase.functions.invoke(
      'pay-worker-period',
      body: {
        'user_id': workerAuthId,
        'from': fromUtc.toIso8601String(),
        'to': toUtc.toIso8601String(),
      },
      headers: {
        'Authorization': 'Bearer ${session.accessToken}',
      },
    );

    if (res.status != 200) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(res.data.toString())),
      );
      return;
    }

    _showPaymentSuccessDialog(
      paidShifts: res.data['paid_shifts'],
      totalAmount: res.data['total_amount'],
    );

    await _reloadAll(); // ✅ чтобы Total unpaid / Last paid / warnings обновились
  }

  @override
  Widget build(BuildContext context) {
    final adminEmail = supabase.auth.currentUser?.email ?? '';
    final adminId = supabase.auth.currentUser?.id ?? ''; // ✅ ADD

    return AdminHomeScreen(
      adminId: adminId, // ✅ ADD
      adminEmail: adminEmail,
      warningsSeed: _warningsSeed,
      workers: workers,
      dashboard: dashboard,
      loadingDashboard: loadingDashboard,

      loadingOnline: _loadingOnline,
      onlineShifts: _onlineShifts,
      loadingShiftEvents: loadingShiftEvents,
      todayShiftEvents: todayShiftEvents,
      now: _now,

      onAddWorker: _openAddWorkerDialog,
      onLogout: _logout,
      onOpenWorker: (ctx, worker) async {
        final changed = await Navigator.of(ctx).push(
          MaterialPageRoute(
            builder: (_) => AdminWorkerDetailsScreen(worker: worker),
          ),
        );

        if (changed == true) {
          await _reloadAll();
        }
      },
    );
  }
}

