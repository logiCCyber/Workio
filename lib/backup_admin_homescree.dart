import 'dart:async';
import 'package:flutter/material.dart';
import '../widgets/glass_appbar.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:ui';

class AdminHomeScreen extends StatelessWidget {
  final String adminEmail;
  final void Function(BuildContext context, Map<String, dynamic> worker) onOpenWorker;
  final List<Map<String, dynamic>> workers;
  final Map<String, dynamic>? dashboard;
  final bool loadingDashboard;
  final bool loadingOnline;
  final List<Map<String, dynamic>> onlineShifts;
  final DateTime now;
  final List<Map<String, dynamic>> todayShiftEvents;
  final bool loadingShiftEvents;


  final VoidCallback onAddWorker;
  final Future<void> Function() onLogout;

  const AdminHomeScreen({
    super.key,
    required this.adminEmail,
    required this.workers,
    required this.dashboard,
    required this.loadingDashboard,
    required this.onAddWorker,
    required this.onLogout,
    required this.onOpenWorker,
    required this.loadingOnline,
    required this.onlineShifts,
    required this.now,
    required this.todayShiftEvents,
    required this.loadingShiftEvents,
  });

  @override
  Widget build(BuildContext context) {
    String _normId(Object? v) => (v ?? '').toString().trim();

    final onlineIds = onlineShifts
        .map((s) {
      final wid = s['worker_id'] ??
          s['workerId'] ??
          (s['workers'] is Map
              ? (s['workers']['id'] ?? s['workers']['worker_id'])
              : null);
      return _normId(wid);
    })
        .where((id) => id.isNotEmpty)
        .toSet();

    final workersUi = workers.map((w) {
      final id = _normId(w['id'] ?? w['worker_id'] ?? w['workerId']);
      return {
        ...w,
        'on_shift': onlineIds.contains(id),
      };
    }).toList();


    return Scaffold(
      backgroundColor: AppPalette.bg,
      extendBodyBehindAppBar: false,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        automaticallyImplyLeading: false,
        titleSpacing: 0,
        title: GlassAppBarTitle(
          title: 'Admin panel',
          titleIcon: Icons.admin_panel_settings_rounded,
          actions: [
            IconButton(
              icon: const Icon(Icons.person_add_alt_1_rounded),
              onPressed: onAddWorker,
            ),
            IconButton(
              icon: const Icon(Icons.logout_rounded),
              onPressed: () async {
                final ok = await showLogoutDialog(context);
                if (ok == true) {
                  await onLogout();
                }
              },
            ),
          ],
        ),
      ),
      body: Stack(
        clipBehavior: Clip.hardEdge, // ✅ важно: режет всё что “вылазит”
        children: [
          const _BackgroundBase(),

          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(12, 16, 12, 24),
              child: Column(
                children: [
                  AdminTopPanel(
                    adminEmail: adminEmail,
                    workers: workersUi,
                    dashboard: dashboard,
                    loading: loadingDashboard,

                    loadingOnline: loadingOnline,
                    onlineShifts: onlineShifts,
                    now: now,

                    loadingShiftEvents: loadingShiftEvents,
                    todayShiftEvents: todayShiftEvents,
                  ),
                  const SizedBox(height: 12),
                  _WorkersListCard(
                    workers: workersUi,
                    onOpenWorker: onOpenWorker,
                  ),
                  const SizedBox(height: 14),
                ],
              ),
            ),
          ),
        ],
      ),

    );
  }
}

// =================== THEME ===================

class AppPalette {
  static const bg = Color(0xFF0B0D12);

  // card like Worker details
  static const cardTop = Color(0xFF2F3036);
  static const cardBottom = Color(0xFF24252B);
  static const cardBorder = Color(0xFF3A3B42);

  // inner rows/pills
  static const pill = Color(0xFF1F2025);
  static const pillBorder = Color(0xFF34353C);

  // text
  static const textMain = Color(0xFFEDEFF6);
  static const textSoft = Color(0xFFB7BCCB);
  static const textMute = Color(0xFF8B90A0);

  // accents
  static const green = Color(0xFF34D399);
  static const orange = Color(0xFFF59E0B);
  static const blue = Color(0xFF38BDF8);
  static const red = Color(0xFFFB7185);
}

// =================== TOP PANEL ===================

class AdminTopPanel extends StatelessWidget {
  final String adminEmail;
  final List<Map<String, dynamic>> workers;
  final Map<String, dynamic>? dashboard;
  final bool loading;
  final bool loadingOnline;
  final List<Map<String, dynamic>> onlineShifts;
  final DateTime now;
  final bool loadingShiftEvents;
  final List<Map<String, dynamic>> todayShiftEvents;

  const AdminTopPanel({
    super.key,
    required this.adminEmail,
    required this.workers,
    required this.dashboard,
    required this.loading,
    required this.loadingOnline,
    required this.onlineShifts,
    required this.now,
    required this.loadingShiftEvents,
    required this.todayShiftEvents,
  });



  double _num(Object? v) => (v is num) ? v.toDouble() : 0.0;
  int _workedSecondsFromDashboard() {
    final v = dashboard?['worked_seconds']; // ✅ вместо unpaid_seconds
    if (v is int) return v;
    if (v is num) return v.toInt();
    return 0;
  }

  String _lastPaidTextPretty() {
    final total = dashboard?['last_paid_total'];
    final at = dashboard?['last_paid_at'];

    if (total == null || at == null) return 'No payments yet';

    final amount = (total is num) ? total.toDouble() : 0.0;

    DateTime? dt;
    try {
      dt = DateTime.parse(at.toString()).toLocal();
    } catch (_) {}

    // формат: 2026 • Jan 29 • $194.19
    final dateText = (dt == null)
        ? at.toString()
        : DateFormat('yyyy • MMM d').format(dt);

    return '$dateText • \$${amount.toStringAsFixed(2)}';
  }

  String _modeOf(Map<String, dynamic> w) {
    final raw = (w['access_mode'] ?? 'active').toString().toLowerCase().trim();
    if (raw == 'readonly') return 'view_only';
    if (raw == 'viewonly') return 'view_only';
    if (raw == 'view_only') return 'view_only';
    return raw;
  }

  int _countOnShift() => workers.where((w) => w['on_shift'] == true).length;
  int _countViewOnly() => workers.where((w) => _modeOf(w) == 'view_only').length;
  int _countSuspended() => workers.where((w) => _modeOf(w) == 'suspended').length;
  int _countViewOrSusp() => _countViewOnly() + _countSuspended();



  String _formatSeconds(int sec) {
    final h = sec ~/ 3600;
    final m = (sec % 3600) ~/ 60;
    return '${h}h ${m}m';
  }


  // suspended не показываем в warnings (и не считаем)
  // int _countSusp() => workers.where((w) => _modeOf(w) == 'suspended').length;

  double _unpaidTotal() => _num(dashboard?['unpaid_total']);
  double _unpaidFromWorkers() {
    double sum = 0;
    for (final w in workers) {
      sum += _num(w['unpaid_total']);
    }
    return sum;
  }

  double _onlineSum() {
    double sum = 0;
    for (final w in workers) {
      if (w['on_shift'] == true) {
        sum += _num(w['unpaid_total']); // <-- если надо другое поле, скажи какое
      }
    }
    return sum;
  }

  String _money(double v) => '\$${v.toStringAsFixed(2)}';


  String _lastPaidText() {
    final amount = dashboard?['last_paid_amount'];
    final at = dashboard?['last_paid_at'];
    if (amount == null || at == null) return '--';
    final v = (amount is num) ? amount.toDouble() : 0.0;
    final dt = at.toString();
    return '\$${v.toStringAsFixed(2)} • $dt';
  }

  Color _pickAccentByKey(String key) {
    final k = key.trim().toLowerCase();
    if (k.isEmpty) return _warningAccentPool.first;

    int hash = 0;
    for (final code in k.codeUnits) {
      hash = (hash * 31 + code) & 0x7fffffff;
    }
    return _warningAccentPool[hash % _warningAccentPool.length];
  }


  List<_WarningItem> _buildWarnings() {
    final items = <_WarningItem>[];

    // гарантирует РАЗНЫЕ цвета для каждого warning
    int ci = 0;
    Color nextAccent() {
      final c = _warningAccentPool[ci % _warningAccentPool.length];
      ci++;
      return c;
    }

    // unpaid workers
    for (final w in workers) {
      final unpaid = _num(w['unpaid_total']);
      if (unpaid > 0) {
        final email = (w['email'] ?? 'worker').toString();
        items.add(
          _WarningItem(
            icon: Icons.payments_rounded,
            accent: nextAccent(),
            title: 'Payment pending',
            message: '$email has unpaid balance: \$${unpaid.toStringAsFixed(2)}',
          ),
        );
      }
    }

    // view-only workers
    for (final w in workers) {
      if (_modeOf(w) == 'view_only') {
        final email = (w['email'] ?? 'worker').toString();
        items.add(
          _WarningItem(
            icon: Icons.visibility_rounded,
            accent: nextAccent(),
            title: 'View-only access',
            message: '$email is in view-only mode. Review permissions.',
          ),
        );
      }
    }

    // ===============================
    // MULTIPLE STARTS TODAY
    // ===============================

    // если данные ещё грузятся — просто не считаем (чтобы не было фальшивых предупреждений)
    if (!loadingShiftEvents && todayShiftEvents.isNotEmpty) {
      // worker_id -> количество start-событий
      final Map<String, int> startsByWorker = {};

      bool isStartEvent(String t) {
        final x = t.toLowerCase().trim();
        return x == 'start' ||
            x == 'started' ||
            x == 'shift_start' ||
            x == 'shift_started' ||
            x == 'clock_in' ||
            x == 'check_in' ||
            x == 'on' ||
            x == 'shift_on';
      }

      for (final e in todayShiftEvents) {
        final wid = (e['worker_id'] ?? '').toString().trim();
        if (wid.isEmpty) continue;

        final type = (e['event_type'] ?? '').toString();
        if (!isStartEvent(type)) continue;

        startsByWorker[wid] = (startsByWorker[wid] ?? 0) + 1;
      }

      // ✅ 1) делаем map: workerAuthId -> worker
      final Map<String, Map<String, dynamic>> byAuth = {};
      for (final w in workers) {
        final auth = (w['auth_user_id'] ?? '').toString().trim();
        if (auth.isNotEmpty) byAuth[auth] = w;
      }

      for (final entry in startsByWorker.entries) {
        final authId = entry.key;     // ✅ shift_events.worker_id (скорее всего auth_user_id)
        final starts = entry.value;

        if (starts < 2) continue;

        final w = byAuth[authId] ?? <String, dynamic>{};
        final email = (w['email'] ?? 'worker $authId').toString();

        items.add(
          _WarningItem(
            icon: Icons.timer_off_rounded,
            accent: nextAccent(),
            title: 'Multiple starts today',
            message: '$email started shift $starts times today. Check shift logs.',
          ),
        );
      }

    }


    return items;
  }


  @override
  Widget build(BuildContext context) {
    final liveOnlineTotal = _liveTotalOnline(onlineShifts, now);

    DateTime? lastPaidAt;
    double? lastPaidTotal;

    try {
      final at = dashboard?['last_paid_at'];
      if (at != null) lastPaidAt = DateTime.parse(at.toString()).toLocal();
    } catch (_) {}

    final t = dashboard?['last_paid_total'];
    if (t is num) lastPaidTotal = t.toDouble();


    final total = workers.length;
    final online = workers.where((w) => w['on_shift'] == true).length;
    final viewOnly = _countViewOnly();
    final susp = _countSuspended();
    final unpaid = _unpaidFromWorkers();
    final lastPaid = _lastPaidText();

    final warnings = _buildWarnings();

    final hasOnline = online > 0;           // есть онлайн (по workersUi)
    final isLive = onlineShifts.isNotEmpty; // есть LIVE смена (по onlineShifts)

    return _SolidPanel(
      loading: loading,
      header: _SummaryHeader(
        title: 'Summary',
        subtitle: adminEmail.isEmpty ? '--' : adminEmail,
      ),

      // ✅ тут оставляем только основной контент
      child: _BigPanel(
        child: Column(
          children: [
            // ✅ КАПСУЛА 1: Total / Online / View-only
            const _SummaryFilters(),
            const SizedBox(height: 10),
            _InnerCapsule(
              child: Row(
                children: [
                  _MiniMetric(
                    icon: Icons.groups_2_rounded,
                    iconColor: Colors.white,
                    label: 'Total',
                    value: '$total',
                  ),
                  const SizedBox(width: 8),
                  _MiniMetric(
                    icon: Icons.play_circle_fill_rounded,
                    iconColor: AppPalette.green,
                    label: 'Online',
                    value: '$online',
                  ),
                  const SizedBox(width: 8),
                  _CyclingMiniMetric(
                    viewCount: viewOnly,
                    suspCount: susp,
                  ),
                ],
              ),
            ),


            const SizedBox(height: 10),

            // ✅ КАПСУЛА 2: 4 метрики (2 ряда)
            _InnerCapsule(
              child: Column(
                children: [
                  _FullWidthMetricRow(
                    tint: isLive ? AppPalette.green : null, // ✅ вот это
                    leading: isLive
                        ? const _PulsingDot(color: AppPalette.green, size: 10)
                        : (hasOnline
                        ? const Icon(Icons.flash_on_rounded, size: 16, color: AppPalette.green)
                        : Icon(Icons.flash_on_rounded, size: 16, color: Colors.white.withOpacity(0.35))),

                    left: isLive
                        ? const _LiveTextPulse()
                        : Text(
                      'Total online',
                      style: TextStyle(
                        color: AppPalette.textSoft.withOpacity(0.80),
                        fontWeight: FontWeight.w800,
                        fontSize: 12,
                      ),
                    ),

                    right: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 220),
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerRight,
                        child: Text(
                          _money(liveOnlineTotal),
                          style: const TextStyle(
                            color: AppPalette.textSoft,
                            fontWeight: FontWeight.w900,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 8),

                  _FullWidthMetricRow(
                    leading: const Icon(Icons.money_off_rounded, size: 16, color: AppPalette.red),
                    left: const Text('Total unpaid'),
                    right: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 220),
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerRight,
                        child: Text(
                          _money(unpaid),
                          style: const TextStyle(
                            color: AppPalette.textMain,
                            fontWeight: FontWeight.w900,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 8),

// ✅ Last paid — FULL WIDTH
                  _FullWidthMetricRow(
                    leading: const Icon(Icons.receipt_long_rounded, size: 16, color: AppPalette.orange),
                    left: const Text('Last paid'),
                    right: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 220),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerRight,
                            child: Text(
                              (lastPaidTotal == null) ? '—' : '\$${lastPaidTotal!.toStringAsFixed(2)}',
                              style: const TextStyle(
                                color: AppPalette.green,
                                fontWeight: FontWeight.w900,
                                fontSize: 13.5,
                                height: 1.0,
                              ),
                            ),
                          ),
                          const SizedBox(height: 2),
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerRight,
                            child: Text(
                              (lastPaidAt == null) ? '—' : DateFormat('yyyy • MMM d').format(lastPaidAt!),
                              style: TextStyle(
                                color: AppPalette.textMain.withOpacity(0.78),
                                fontWeight: FontWeight.w800,
                                fontSize: 9,
                                height: 1.0,
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
          ],
        ),
      ),

      // ✅ а footer выносим отдельно
      footer: _FooterWarningsBar(items: warnings),
    );

  }
}

// =================== BACKGROUND ===================

class _BackgroundBase extends StatelessWidget {
  const _BackgroundBase();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF0B0D12), Color(0xFF0A0C10), Color(0xFF07080C)],
        ),
      ),
    );
  }
}

// =================== SOLID PANEL (like Worker details) ===================

class _SolidPanel extends StatelessWidget {
  final bool loading;
  final Widget header;
  final Widget child;

  // ✅ footer добавляем отдельно
  final Widget? footer;

  const _SolidPanel({
    required this.loading,
    required this.header,
    required this.child,
    this.footer,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: Container(
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [AppPalette.cardTop, AppPalette.cardBottom],
          ),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: AppPalette.cardBorder.withOpacity(0.55)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.50),
              blurRadius: 26,
              offset: const Offset(0, 14),
            ),
          ],
        ),
        child: Column(
          children: [
            // ✅ контент с padding
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  header,
                  const SizedBox(height: 10),
                  if (loading) ...[
                    ClipRRect(
                      borderRadius: BorderRadius.circular(999),
                      child: LinearProgressIndicator(
                        minHeight: 3,
                        backgroundColor: Colors.white.withOpacity(0.08),
                      ),
                    ),
                    const SizedBox(height: 10),
                  ],
                  child,
                ],
              ),
            ),

            // ✅ footer без padding, во всю ширину
            if (footer != null) footer!,
          ],
        ),
      ),
    );
  }

}

class _SummaryHeader extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;

  const _SummaryHeader({
    required this.title,
    required this.subtitle,
    this.icon = Icons.summarize_rounded,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 38,
      child: Row(
        children: [
          Icon(icon, size: 18, color: AppPalette.textSoft.withOpacity(0.85)),
          const SizedBox(width: 8),
          Text(
            title,
            style: TextStyle(
              color: AppPalette.textMain.withOpacity(0.92),
              fontWeight: FontWeight.w900,
              fontSize: 14,
              letterSpacing: 0.2,
            ),
          ),
          const Spacer(),
          Expanded(
            child: Align(
              alignment: Alignment.centerRight,
              child: Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: AppPalette.textSoft.withOpacity(0.75),
                  fontWeight: FontWeight.w800,
                  fontSize: 12,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MiniMetric extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String label;
  final String value;

  const _MiniMetric({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        height: 46,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.035),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white.withOpacity(0.10)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.25),
              blurRadius: 14,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Row(
          children: [
            Icon(icon, size: 16, color: iconColor),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: AppPalette.textSoft.withOpacity(0.80),
                  fontWeight: FontWeight.w800,
                  fontSize: 11,
                ),
              ),
            ),
            Text(
              value,
              style: const TextStyle(
                color: AppPalette.textMain,
                fontWeight: FontWeight.w900,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CyclingMiniMetric extends StatefulWidget {
  final int viewCount;
  final int suspCount;

  const _CyclingMiniMetric({
    super.key,
    required this.viewCount,
    required this.suspCount,
  });

  @override
  State<_CyclingMiniMetric> createState() => _CyclingMiniMetricState();
}

class _CyclingMiniMetricState extends State<_CyclingMiniMetric> {
  Timer? _timer;
  bool _showSusp = false; // false = View, true = Susp

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!mounted) return;
      setState(() => _showSusp = !_showSusp);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final label = _showSusp ? 'Susp' : 'View';
    final value = _showSusp ? widget.suspCount : widget.viewCount;

    final icon = _showSusp ? Icons.block_rounded : Icons.visibility_rounded;
    final iconColor = _showSusp ? AppPalette.red : AppPalette.orange;

    return Expanded(
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 320),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeInCubic,
        transitionBuilder: (child, anim) {
          final fade = CurvedAnimation(parent: anim, curve: Curves.easeOut);

          final scale = Tween<double>(begin: 0.98, end: 1.0).animate(
            CurvedAnimation(parent: anim, curve: Curves.easeOutCubic),
          );

          return FadeTransition(
            opacity: fade,
            child: ScaleTransition(scale: scale, child: child),
          );
        },

        child: KeyedSubtree(
          key: ValueKey(_showSusp ? 'susp' : 'view'),
          child: _MiniMetric(
            icon: icon,
            iconColor: iconColor,
            label: label,
            value: '$value',
          ),
        ),
      ),
    );
  }
}

class _FullWidthMetricRow extends StatelessWidget {
  final Widget leading;
  final Widget left;
  final Widget right;

  final Color? tint; // ✅ добавили

  const _FullWidthMetricRow({
    required this.leading,
    required this.left,
    required this.right,
    this.tint,
  });

  @override
  Widget build(BuildContext context) {
    final base = Colors.white.withOpacity(0.035);

    // очень мягкий зелёный тинт сверху базы
    final bg = (tint == null) ? base : Color.lerp(base, tint!.withOpacity(0.12), 0.55)!;

    final border = (tint == null)
        ? Colors.white.withOpacity(0.10)
        : Color.lerp(Colors.white.withOpacity(0.10), tint!.withOpacity(0.22), 0.65)!;

    return Container(
      height: 46,
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.25),
            blurRadius: 14,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Row(
        children: [
          leading,
          const SizedBox(width: 10),
          DefaultTextStyle(
            style: TextStyle(
              color: AppPalette.textSoft.withOpacity(0.80),
              fontWeight: FontWeight.w800,
              fontSize: 12,
            ),
            child: left,
          ),
          const Spacer(),
          right,
        ],
      ),
    );
  }
}

class _LastPaidRow extends StatelessWidget {
  final DateTime? paidAt;
  final double? amount;

  const _LastPaidRow({
    required this.paidAt,
    required this.amount,
  });

  String _fmtDate(DateTime? dt) {
    if (dt == null) return '—';
    return DateFormat('yyyy • MMM d').format(dt);
  }

  @override
  Widget build(BuildContext context) {
    final amountText = (amount == null) ? '—' : '\$${amount!.toStringAsFixed(2)}';
    final dateText = _fmtDate(paidAt);

    return Container(
      height: 46, // ✅ такая же высота как у _FinanceRow
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: AppPalette.pill,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppPalette.pillBorder.withOpacity(0.55)),
      ),
      child: Row(
        children: [
          Icon(Icons.receipt_long_rounded, size: 16, color: AppPalette.orange),
          const SizedBox(width: 10),

          Text(
            'Last paid',
            style: TextStyle(
              color: AppPalette.textSoft.withOpacity(0.80),
              fontWeight: FontWeight.w800,
              fontSize: 12,
            ),
          ),

          const Spacer(),

          // ✅ справа 2 строки: сумма сверху, дата снизу
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 220),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  amountText,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppPalette.green,
                    fontWeight: FontWeight.w900,
                    fontSize: 13.5,
                    height: 1.0,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  dateText,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: AppPalette.textMain.withOpacity(0.78),
                    fontWeight: FontWeight.w800,
                    fontSize: 11.0,
                    height: 1.0,
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

class _SoftDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      height: 1,
      margin: const EdgeInsets.only(bottom: 10),
      color: Colors.white.withOpacity(0.08),
    );
  }
}

// =================== FOOTER WARNINGS (carousel) ===================
const _warningAccentPool = <Color>[
  Color(0xFFFB7185), // pink/red
  Color(0xFFF97316), // orange
  Color(0xFFF59E0B), // amber
  Color(0xFF34D399), // green
  Color(0xFF22C55E), // emerald
  Color(0xFF38BDF8), // sky
  Color(0xFF60A5FA), // blue
  Color(0xFFA78BFA), // violet
  Color(0xFFF472B6), // fuchsia
  Color(0xFF2DD4BF), // teal
];


class _WarningItem {
  final IconData icon;
  final Color accent;
  final String title;
  final String message;

  _WarningItem({
    required this.icon,
    required this.accent,
    required this.title,
    required this.message,
  });
}

class _FooterWarningsCarousel extends StatefulWidget {
  final List<_WarningItem> items;
  final ValueChanged<int>? onIndexChanged;
  const _FooterWarningsCarousel({required this.items, this.onIndexChanged});

  @override
  State<_FooterWarningsCarousel> createState() => _FooterWarningsCarouselState();
}

class _FooterWarningsCarouselState extends State<_FooterWarningsCarousel> {
  int index = 0;
  Timer? timer;

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void didUpdateWidget(covariant _FooterWarningsCarousel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.items.length != widget.items.length) {
      index = 0;
      widget.onIndexChanged?.call(index);
      _start();
    }
  }

  void _start() {
    timer?.cancel();
    if (widget.items.length <= 1) return;

    timer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (!mounted) return;
      setState(() => index = (index + 1) % widget.items.length);
      widget.onIndexChanged?.call(index);
    });
  }

  void _restartAuto() {
    // чтобы после клика не дергалось авто-переключение
    _start();
  }

  void _next() {
    if (widget.items.length <= 1) return;
    setState(() => index = (index + 1) % widget.items.length);
    widget.onIndexChanged?.call(index);
    _restartAuto();
  }

  void _prev() {
    if (widget.items.length <= 1) return;
    setState(() => index = (index - 1 + widget.items.length) % widget.items.length);
    widget.onIndexChanged?.call(index);
    _restartAuto();
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Widget child;

    if (widget.items.isEmpty) {
      child = _OkFooter();
    } else {
      final item = widget.items[index];
      child = _WarningFooter(
        item: item,
        showArrow: widget.items.length > 1,
        onNext: _next,
        onPrev: _prev,
      );
    }

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onHorizontalDragEnd: (d) {
        final v = d.primaryVelocity ?? 0;

        // свайп влево -> следующий
        if (v < -120) _next();

        // свайп вправо -> предыдущий
        if (v > 120) _prev();
      },
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 320),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeInCubic,
        child: KeyedSubtree(
          key: ValueKey(widget.items.isEmpty ? 'ok' : '${index}_${widget.items.length}'),
          child: child,
        ),
        transitionBuilder: (w, anim) {
          final fade = CurvedAnimation(parent: anim, curve: Curves.easeOut);
          final scale = Tween<double>(begin: 0.98, end: 1.0).animate(
            CurvedAnimation(parent: anim, curve: Curves.easeOutCubic),
          );
          return FadeTransition(
            opacity: fade,
            child: ScaleTransition(scale: scale, child: w),
          );
        },
      ),
    );

  }
}

class _OkFooter extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: AppPalette.green.withOpacity(0.16),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppPalette.green.withOpacity(0.20)),
            ),
            child: Icon(Icons.check_circle_rounded, color: AppPalette.green.withOpacity(0.95), size: 18),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'All good — no warnings',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: AppPalette.textMain.withOpacity(0.92),
                fontWeight: FontWeight.w900,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _WarningFooter extends StatelessWidget {
  final _WarningItem item;

  final VoidCallback onNext;
  final VoidCallback onPrev;
  final bool showArrow;

  const _WarningFooter({
    required this.item,
    required this.onNext,
    required this.onPrev,
    required this.showArrow,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 46,
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: item.accent.withOpacity(0.16),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: item.accent.withOpacity(0.20)),
            ),
            child: Icon(item.icon, color: item.accent.withOpacity(0.95), size: 18),
          ),
          const SizedBox(width: 10),

          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: AppPalette.textMain.withOpacity(0.95),
                    fontWeight: FontWeight.w900,
                    fontSize: 12.5,
                  ),
                ),
                const SizedBox(height: 2),
                Tooltip(
                  message: item.message,
                  triggerMode: TooltipTriggerMode.longPress,
                  child: Text(
                    item.message,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: AppPalette.textSoft.withOpacity(0.85),
                      fontWeight: FontWeight.w700,
                      fontSize: 11.5,
                    ),
                  ),
                ),
              ],
            ),
          ),

          if (showArrow)
            InkWell(
              onTap: onNext,
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.all(6),
                child: Icon(Icons.chevron_right_rounded, color: Colors.white.withOpacity(0.40)),
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.all(6),
              child: Icon(Icons.chevron_right_rounded, color: Colors.white.withOpacity(0.20)),
            ),
        ],
      ),
    );
  }


}

class _FooterWarningsBar extends StatefulWidget {
  final List<_WarningItem> items;
  const _FooterWarningsBar({required this.items});

  @override
  State<_FooterWarningsBar> createState() => _FooterWarningsBarState();
}

class _FooterWarningsBarState extends State<_FooterWarningsBar> {
  int _index = 0;

  @override
  void didUpdateWidget(covariant _FooterWarningsBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_index >= widget.items.length) _index = 0;
  }

  @override
  Widget build(BuildContext context) {
    final has = widget.items.isNotEmpty;
    final accent = has ? widget.items[_index].accent : AppPalette.green;

    return Container(
      width: double.infinity,

      // ✅ ВЕСЬ ФУТЕР красится этим цветом
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            accent.withOpacity(0.22),
            Colors.black.withOpacity(0.10),
          ],
        ),
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(22),
          bottomRight: Radius.circular(22),
        ),
        border: Border(
          top: BorderSide(color: Colors.white.withOpacity(0.06)),
        ),
      ),

      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      child: _FooterWarningsCarousel(
        items: widget.items,
        onIndexChanged: (i) {
          if (!mounted) return;
          if (i == _index) return;

          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            setState(() => _index = i);
          });
        },
      ),

    );
  }
}

// =================== WORKERS LIST ===================


class _WorkersListCard extends StatelessWidget {
  final List<Map<String, dynamic>> workers;
  final void Function(BuildContext context, Map<String, dynamic> worker) onOpenWorker;

  const _WorkersListCard({
    required this.workers,
    required this.onOpenWorker,
  });

  double _num(Object? v) => (v is num) ? v.toDouble() : 0.0;

  String _modeOf(Map<String, dynamic> w) {
    final raw = (w['access_mode'] ?? 'active').toString().toLowerCase().trim();
    if (raw == 'readonly' || raw == 'viewonly' || raw == 'view_only') return 'view_only';
    return raw; // active / suspended / etc
  }

  int _priority(Map<String, dynamic> w, double unpaid) {
    final onShift = w['on_shift'] == true;
    final mode = _modeOf(w);

    if (onShift) return 0;          // ON SHIFT first
    if (unpaid > 0) return 1;       // UNPAID second
    if (mode == 'view_only') return 2;
    if (mode == 'suspended') return 4;
    return 3;                       // others
  }


  @override
  Widget build(BuildContext context) {
    // ✅ копия + сортировка (ВАЖНО: тут можно final)
    final sorted = [...workers]..sort((a, b) {
      final ua = _num(a['unpaid_total']);
      final ub = _num(b['unpaid_total']);

      final pa = _priority(a, ua);
      final pb = _priority(b, ub);

      if (pa != pb) return pa.compareTo(pb);

      final ea = (a['email'] ?? '').toString();
      final eb = (b['email'] ?? '').toString();
      return ea.compareTo(eb);
    });

    return _SolidPanel(
      loading: false,
      header: const _SummaryHeader(
        icon: Icons.groups_2_rounded, // ✅ человечки
        title: 'Workers',
        subtitle: 'Tap to open',
      ),
      child: Column(
        children: [
          if (sorted.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: Text(
                'No workers yet',
                style: TextStyle(
                  color: AppPalette.textSoft.withOpacity(0.70),
                  fontWeight: FontWeight.w700,
                ),
              ),
            )
          else
            for (int i = 0; i < sorted.length; i++) ...[
              _WorkerRow(
                worker: sorted[i],
                mode: _modeOf(sorted[i]),
                unpaid: _num(sorted[i]['unpaid_total']),
                onTap: () {
                  try {
                    onOpenWorker(context, sorted[i]);
                  } catch (e, st) {
                    debugPrint('onOpenWorker ERROR: $e');
                    debugPrint('$st');
                  }
                },
              ),
              if (i != sorted.length - 1) const SizedBox(height: 10),
            ],
        ],
      ),


    );
  }

}

class _WorkerRow extends StatelessWidget {
  final Map<String, dynamic> worker;
  final String mode; // active / suspended / view_only
  final double unpaid;
  final VoidCallback onTap;

  const _WorkerRow({
    required this.worker,
    required this.unpaid,
    required this.onTap,
    required this.mode,
  });

  String _statusText() {
    if (mode == 'view_only') return 'view';
    if (mode == 'suspended') return 'suspended';
    return 'active';
  }

  Color _statusColor() {
    if (mode == 'view_only') return AppPalette.orange;
    if (mode == 'suspended') return AppPalette.red;
    return AppPalette.green;
  }

  Future<bool> _fetchOnShift(String workerId) async {
    if (workerId.isEmpty) return false;

    final supa = Supabase.instance.client;

    // берём последнее событие
    final rows = await supa
        .from('shift_events')
        .select('event_type, created_at')
        .eq('worker_id', workerId)
        .order('created_at', ascending: false)
        .limit(1);

    if (rows is List && rows.isNotEmpty) {
      final t = (rows.first['event_type'] ?? '').toString().toLowerCase().trim();

      // ✅ ВАЖНО: под твои значения (самые частые варианты)
      if (t == 'start' || t == 'started' || t == 'shift_start' || t == 'on') return true;
      return false;
    }

    return false;
  }

  Widget workerCardStatus(Map<String, dynamic> worker, String mode) {
    final onShift = worker['on_shift'] == true;

    final statusColor = (mode == 'view_only')
        ? AppPalette.orange
        : (mode == 'suspended')
        ? AppPalette.red
        : AppPalette.green;

    return Row(
      children: [
        onShift
            ? const _OnShiftPlayPulse(color: AppPalette.green, size: 16)
            : Icon(
          Icons.play_circle_fill_rounded,
          size: 16,
          color: Colors.white.withOpacity(0.45),
        ),
        const SizedBox(width: 8),
        Text(
          onShift ? 'ON SHIFT' : 'OFF SHIFT',
          style: TextStyle(
            color: onShift
                ? AppPalette.green.withOpacity(0.95)
                : Colors.white.withOpacity(0.92),
            fontWeight: FontWeight.w900,
            fontSize: 12.5,
            letterSpacing: 0.2,
          ),
        ),
        const Spacer(),
        Text(
          mode == 'view_only'
              ? 'view'
              : mode == 'suspended'
              ? 'suspended'
              : 'active',
          style: TextStyle(
            color: statusColor.withOpacity(0.95),
            fontWeight: FontWeight.w900,
            fontSize: 12,
            letterSpacing: 0.2,
          ),
        ),
        const SizedBox(width: 6),
        Icon(
          Icons.chevron_right_rounded,
          size: 22,
          color: Colors.white.withOpacity(0.40),
        ),
      ],
    );
  }



  @override
  Widget build(BuildContext context) {
    final name = (worker['name'] ?? '').toString().trim();
    final email = (worker['email'] ?? '').toString().trim();
    final avatarUrl = (worker['avatar_url'] ?? '').toString().trim();
    final lastWorkedAt = worker['last_work_at']; // <-- ЭТО ПОЛЕ С ДАТОЙ
    final workerId = (worker['id'] ?? worker['worker_id'] ?? '').toString();

    final hasUnpaid = unpaid > 0;
    final statusColor = _statusColor();

    const r = 22.0; // ✅ красивее чем 20

    // ✅ header тон: серый, но с оттенком статуса
    final onShift = worker['on_shift'] == true;
    final headerTint = (onShift ? AppPalette.green : statusColor).withOpacity(0.10);

    // ✅ body светлее
    const bodyTop = Color(0xFF191D25);
    const bodyBottom = Color(0xFF151820);

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(r),

        // ✅ тень ДОЛЖНА быть на Material, не внутри Ink
        elevation: 0,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(r),
          ),
          child: Material(
            // ✅ это Material задаёт форму + клип
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(r),
            clipBehavior: Clip.antiAlias, // ✅ режет углы идеально

            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(r),
              splashColor: Colors.white.withOpacity(0.06),
              highlightColor: Colors.white.withOpacity(0.03),

              child: Ink(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(r),
                  border: Border.all(
                    color: Colors.white.withOpacity(0.10),
                    width: 1,
                  ),
                  gradient: const LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      bodyTop,
                      bodyBottom,
                    ],
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // ================= HEADER (FULL WIDTH) =================
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.fromLTRB(16, 12, 14, 12),
                      decoration: BoxDecoration(
                        // ✅ серый градиент + легкий статусный тинт
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            Color(0xFF3A3F4B).withOpacity(0.97),
                            Color(0xFF2E3340).withOpacity(0.95),
                          ],
                        ),
                        color: headerTint, // поверх чуть оттенок
                        border: Border(
                          bottom: BorderSide(
                            color: Colors.white.withOpacity(0.10),
                            width: 1,
                          ),
                        ),
                      ),
                      child: workerCardStatus(worker, mode),
                    ),

                    // ================= BODY =================
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _Avatar(
                            avatarUrl: avatarUrl,
                            borderColor: statusColor, // ✅ active/view/suspended
                          ),
                          const SizedBox(width: 12),

                          // ✅ твой inner card НЕ трогаем
                          Expanded(
                            child: _InnerInfoCard(
                              name: name,
                              email: email,
                              hasUnpaid: hasUnpaid,
                              unpaid: unpaid,
                            ),
                          ),
                        ],
                      ),
                    ),
                    _WorkerFooter(lastWorkedAt: lastWorkedAt),
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

class _Avatar extends StatelessWidget {
  final String avatarUrl;
  final Color borderColor;

  const _Avatar({
    required this.avatarUrl,
    required this.borderColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        color: Colors.white.withOpacity(0.05),

        // ✅ тонкий бордер по статусу
        border: Border.all(
          color: borderColor.withOpacity(0.85),
          width: 1.2,
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: avatarUrl.isEmpty
            ? Icon(Icons.person_rounded, color: Colors.white.withOpacity(0.55), size: 22)
            : Image.network(
          avatarUrl,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) =>
              Icon(Icons.person_rounded, color: Colors.white.withOpacity(0.55), size: 22),
        ),
      ),
    );
  }
}

class _StatusDot extends StatelessWidget {
  final bool on;
  const _StatusDot({required this.on});

  @override
  Widget build(BuildContext context) {
    final c = on ? AppPalette.green : const Color(0xFF94A3B8);
    return Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(
        color: c.withOpacity(0.95),
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: c.withOpacity(0.25),
            blurRadius: 8,
            spreadRadius: 1,
          ),
        ],
      ),
    );
  }
}

class _UnpaidPill extends StatelessWidget {
  final double amount;
  const _UnpaidPill({required this.amount});

  @override
  Widget build(BuildContext context) {
    final text = 'UNPAID \$${amount.toStringAsFixed(2)}';

    return Tooltip(
      message: text,
      triggerMode: TooltipTriggerMode.longPress,
      child: Container(
        height: 28,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: const Color(0xFFFBBF24).withOpacity(0.12),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: const Color(0xFFFBBF24).withOpacity(0.22)),
        ),
        child: Center(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Color(0xFFFBBF24),
              fontWeight: FontWeight.w900,
              fontSize: 10.5,
              letterSpacing: 0.2,
            ),
          ),
        ),
      ),
    );
  }
}

class _BigPanel extends StatelessWidget {
  final Widget child;
  const _BigPanel({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.10),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: child,
    );
  }
}

class _InnerCapsule extends StatelessWidget {
  final Widget child;
  const _InnerCapsule({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        // ✅ стало светлее (чуть больше “плитка”)
        color: Colors.white.withOpacity(0.035),

        borderRadius: BorderRadius.circular(18),

        // ✅ бордер чуть заметнее
        border: Border.all(
          color: Colors.white.withOpacity(0.10),
        ),

        // ✅ лёгкий внутренний свет (очень аккуратно)
        boxShadow: [
          BoxShadow(
            color: Colors.white.withOpacity(0.04),
            blurRadius: 18,
            spreadRadius: -8,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _SummaryFilters extends StatefulWidget {
  const _SummaryFilters();

  @override
  State<_SummaryFilters> createState() => _SummaryFiltersState();
}

class _SummaryFiltersState extends State<_SummaryFilters> {
  DateTime? start;
  DateTime? end;

  bool calendarOpen = false;

  Timer? _clockTimer;
  String _timeText = '';

  String _nowHHmm() {
    final now = DateTime.now();
    final h = now.hour.toString().padLeft(2, '0');
    final m = now.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  @override
  void initState() {
    super.initState();
    _timeText = _nowHHmm();

    _clockTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      final newText = _nowHHmm();
      if (!mounted) return;
      if (newText != _timeText) setState(() => _timeText = newText);
    });
  }

  @override
  void dispose() {
    _clockTimer?.cancel();
    super.dispose();
  }

  void _onSelectDate(DateTime picked) {
    if (start == null || (start != null && end != null)) {
      setState(() {
        start = DateTime(picked.year, picked.month, picked.day);
        end = null;
      });
      return;
    }

    final s = start!;
    final p = DateTime(picked.year, picked.month, picked.day);

    if (p.isBefore(s)) {
      setState(() {
        start = p;
        end = null;
      });
      return;
    }

    setState(() => end = p);
  }

  String _dateLabel() {
    final now = DateTime.now();

    // ✅ no selection -> today (Mon • Feb 9 • 2026)
    if (start == null && end == null) {
      return DateFormat('EEE • MMM d • yyyy').format(now);
    }

    // ✅ single day
    if (start != null && end == null) {
      return DateFormat('EEE • MMM d • yyyy').format(start!);
    }

    // ✅ range
    final s = start!;
    final e = end!;

    // same month + same year: Feb 2–9 • 2026
    if (s.month == e.month && s.year == e.year) {
      final left = DateFormat('MMM d').format(s);
      final right = DateFormat('d').format(e);
      return '$left–$right • ${s.year}';
    }

    // different month/year: Feb 28 → Mar 3 • 2026 (or • 2026–2027 if years differ)
    final left = DateFormat('MMM d').format(s);
    final right = DateFormat('MMM d').format(e);

    if (s.year == e.year) {
      return '$left → $right • ${s.year}';
    }

    return '$left • ${s.year} → $right • ${e.year}';
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _TimeDateCapsule(
          timeText: _timeText,
          dateText: _dateLabel(),
          open: calendarOpen,
          onTap: () => setState(() => calendarOpen = !calendarOpen),
        ),

        const SizedBox(height: 10),

        AnimatedCrossFade(
          duration: const Duration(milliseconds: 220),
          crossFadeState: calendarOpen ? CrossFadeState.showFirst : CrossFadeState.showSecond,
          firstChild: _InlineCalendar(
            start: start,
            end: end,
            onPick: _onSelectDate,
          ),
          secondChild: const SizedBox.shrink(),
        ),
      ],
    );
  }
}


class _FilterCard extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String value;
  final VoidCallback onTap;
  final Widget? trailing;
  final double height;

  const _FilterCard({
    required this.icon,
    required this.iconColor,
    required this.value,
    required this.onTap,
    this.trailing,
    this.height = 46,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        height: height,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.035),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.white.withOpacity(0.10)),
        ),
        child: Row(
          children: [
            // ✅ icon without capsule background (как ты просил)
            Icon(icon, color: iconColor.withOpacity(0.95), size: 18),
            const SizedBox(width: 10),

            Expanded(
              child: Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppPalette.textMain,
                  fontWeight: FontWeight.w900,
                  fontSize: 16,
                ),
              ),
            ),

            if (trailing != null) ...[
              const SizedBox(width: 8),
              trailing!,
            ],
          ],
        ),
      ),
    );
  }
}

class _TinyBtn extends StatelessWidget {
  final String text;
  final VoidCallback onTap;
  const _TinyBtn({required this.text, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.04),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: Colors.white.withOpacity(0.10)),
        ),
        child: Text(
          text,
          style: TextStyle(
            color: AppPalette.textSoft.withOpacity(0.80),
            fontWeight: FontWeight.w800,
            fontSize: 11,
          ),
        ),
      ),
    );
  }
}

class _InlineCalendar extends StatelessWidget {
  final DateTime? start;
  final DateTime? end;
  final void Function(DateTime day) onPick;

  const _InlineCalendar({
    required this.start,
    required this.end,
    required this.onPick,
  });

  bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  bool _inRange(DateTime d, DateTime s, DateTime e) {
    final dd = DateTime(d.year, d.month, d.day);
    final ss = DateTime(s.year, s.month, s.day);
    final ee = DateTime(e.year, e.month, e.day);
    return !dd.isBefore(ss) && !dd.isAfter(ee);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(10, 6, 10, 10), // меньше сверху
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.14),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
        boxShadow: [
          BoxShadow(
            color: Colors.white.withOpacity(0.03),
            blurRadius: 16,
            spreadRadius: -10,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Theme(
        data: Theme.of(context).copyWith(
          colorScheme: Theme.of(context).colorScheme.copyWith(
            primary: AppPalette.green, // кружок выбранного дня
            onPrimary: Colors.black,   // текст на выбранном дне
            surface: Colors.transparent,
            onSurface: AppPalette.textMain,
          ),
          textButtonTheme: TextButtonThemeData(
            style: TextButton.styleFrom(
              foregroundColor: AppPalette.textMain.withOpacity(0.85),
            ),
          ),
        ),
        child: CalendarDatePicker(
          initialDate: start ?? DateTime.now(),
          firstDate: DateTime(2023),
          lastDate: DateTime.now().add(const Duration(days: 365)),
          onDateChanged: onPick,
        ),
      ),
    );

  }

}

class _ModeChip extends StatelessWidget {
  final String text;
  final Color accent;
  const _ModeChip({required this.text, required this.accent});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 20,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: accent.withOpacity(0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: accent.withOpacity(0.22)),
      ),
      child: Center(
        child: Text(
          text,
          style: TextStyle(
            color: accent.withOpacity(0.95),
            fontWeight: FontWeight.w900,
            fontSize: 10,
            letterSpacing: 0.4,
          ),
        ),
      ),
    );
  }
}

class _AvatarIOS extends StatelessWidget {
  final String avatarUrl;
  const _AvatarIOS({required this.avatarUrl});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 46,
      height: 46,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: Colors.white.withOpacity(0.06),
        border: Border.all(color: Colors.white.withOpacity(0.12)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.35),
            blurRadius: 16,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: avatarUrl.isEmpty
            ? Icon(Icons.person_rounded, color: Colors.white.withOpacity(0.55), size: 20)
            : Image.network(
          avatarUrl,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) =>
              Icon(Icons.person_rounded, color: Colors.white.withOpacity(0.55), size: 20),
        ),
      ),
    );
  }
}


class _RowHeader extends StatelessWidget {
  final String title;
  final String statusText;
  final Color statusColor;

  const _RowHeader({
    required this.title,
    required this.statusText,
    required this.statusColor,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 28, // ✅ фиксируем высоту, стрелка точно по центру
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppPalette.textMain,
                fontWeight: FontWeight.w900,
                fontSize: 13.5,
                letterSpacing: 0.2,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Text(
            statusText,
            style: TextStyle(
              color: statusColor.withOpacity(0.95),
              fontWeight: FontWeight.w900,
              fontSize: 11,
              letterSpacing: 0.2,
            ),
          ),
          const SizedBox(width: 8),
          Center(
            child: Icon(
              Icons.chevron_right_rounded,
              size: 26,
              color: AppPalette.textMute.withOpacity(0.70),
            ),
          ),
        ],
      ),
    );
  }
}


class _CardShell extends StatelessWidget {
  final Widget child;
  final VoidCallback onTap;
  final Color? accent;

  const _CardShell({
    required this.child,
    required this.onTap,
    this.accent,
  });

  @override
  Widget build(BuildContext context) {
    final base = Colors.white.withOpacity(0.045);     // ✅ iOS glass
    final border = Colors.white.withOpacity(0.10);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
        decoration: BoxDecoration(
          color: base,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: accent?.withOpacity(0.22) ?? border,
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.45),
              blurRadius: 22,
              offset: const Offset(0, 14),
            ),
            // ✅ лёгкий “glow” только когда unpaid
            if (accent != null)
              BoxShadow(
                color: accent!.withOpacity(0.0),
                blurRadius: 26,
                offset: const Offset(0, 10),
              ),
          ],
        ),
        child: child,
      ),
    );
  }
}

class _InfoLine extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String text;
  final TextStyle textStyle;
  final Color? background;
  final Color? border;

  const _InfoLine({
    required this.icon,
    required this.iconColor,
    required this.text,
    required this.textStyle,
    this.background,
    this.border,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: background ?? Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: (border ?? Colors.transparent)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: iconColor),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: textStyle,
            ),
          ),
        ],
      ),
    );
  }
}

class _InnerInfoCard extends StatelessWidget {
  final String name;
  final String email;
  final bool hasUnpaid;
  final double unpaid;

  const _InnerInfoCard({
    required this.name,
    required this.email,
    required this.hasUnpaid,
    required this.unpaid,
  });

  @override
  Widget build(BuildContext context) {
    final nameText = name.isEmpty ? '—' : name;
    final emailText = email.isEmpty ? '—' : email;

    final unpaidText = hasUnpaid
        ? 'unpaid \$${unpaid.toStringAsFixed(2)}'
        : 'unpaid \$0.00';

    final unpaidColor = hasUnpaid
        ? AppPalette.orange.withOpacity(0.95) // >0 оранжевый (как было)
        : Colors.white.withOpacity(0.55);     // 0 серый

    return Container(
      width: double.infinity,

      // ✅ общая подложка (одна)
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.035),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.10)),
      ),

      child: Column(
        children: [
          _SlimCapsuleLine(
            icon: Icons.badge_rounded,
            iconColor: Colors.white.withOpacity(0.90), // name icon белый
            text: nameText,
            textStyle: const TextStyle(
              color: AppPalette.textMain,
              fontWeight: FontWeight.w900,
              fontSize: 13.5,
              height: 1.0,
            ),
          ),
          const SizedBox(height: 8),

          _SlimCapsuleLine(
            icon: Icons.alternate_email_rounded,
            iconColor: AppPalette.blue.withOpacity(0.95), // email icon синий
            text: emailText,
            textStyle: TextStyle(
              color: Colors.white.withOpacity(0.82),
              fontWeight: FontWeight.w800,
              fontSize: 12.5,
              height: 1.0,
            ),
          ),
          const SizedBox(height: 8),

          _SlimCapsuleLine(
            icon: Icons.account_balance_wallet_rounded,
            iconColor: hasUnpaid
                ? AppPalette.orange.withOpacity(0.95)   // ✅ горит оранжевым
                : Colors.white.withOpacity(0.35),       // ✅ серый если 0
            text: unpaidText,
            textStyle: TextStyle(
              color: unpaidColor,
              fontWeight: FontWeight.w900,
              fontSize: 12.5,
              height: 1.0,
            ),
          ),

        ],
      ),
    );
  }
}

/// ✅ Строка: иконка СНАРУЖИ + узкая капсула внутри
class _SlimCapsuleLine extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String text;
  final TextStyle textStyle;

  const _SlimCapsuleLine({
    required this.icon,
    required this.iconColor,
    required this.text,
    required this.textStyle,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: iconColor), // ✅ иконка НЕ в капсуле
        const SizedBox(width: 10),

        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(13),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
              child: Container(
                height: 30, // узкие
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  // ✅ стекло: полупрозрачное + чуть градиент
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Colors.white.withOpacity(0.08),
                      Colors.white.withOpacity(0.03),
                    ],
                  ),
                  // ✅ тонкий "стеклянный" кант
                  border: Border.all(color: Colors.white.withOpacity(0.06)),
                  borderRadius: BorderRadius.circular(13),
                ),
                alignment: Alignment.centerLeft,
                child: Text(
                  text,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: textStyle,
                ),
              ),
            ),
          ),
        ),

      ],
    );
  }
}


class _WorkerFooter extends StatelessWidget {
  final Object? lastWorkedAt;
  const _WorkerFooter({required this.lastWorkedAt});

  String _fmt(Object? v) {
    if (v == null) return '—';
    try {
      final dt = DateTime.parse(v.toString()).toLocal();
      return DateFormat('EEE, MMM d').format(dt); // Fri, Feb 6
    } catch (_) {
      return v.toString();
    }
  }

  @override
  Widget build(BuildContext context) {
    final dateText = _fmt(lastWorkedAt);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.02),
        border: Border(
          top: BorderSide(color: Colors.white.withOpacity(0.08)),
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.history_rounded, size: 16, color: Colors.white.withOpacity(0.35)),
          const SizedBox(width: 8),
          Text(
            'Last work',
            style: TextStyle(
              color: Colors.white.withOpacity(0.60),
              fontWeight: FontWeight.w800,
              fontSize: 12,
            ),
          ),
          const Spacer(),

          // ✅ БЕЗ капсулы + ✅ синий текст
          Text(
            dateText,
            style: TextStyle(
              color: AppPalette.blue.withOpacity(0.95),
              fontWeight: FontWeight.w900,
              fontSize: 12.5,
            ),
          ),
        ],
      ),
    );
  }
}

double _asDouble(dynamic v) {
  if (v == null) return 0.0;
  if (v is num) return v.toDouble();
  final s = v.toString().trim();
  return double.tryParse(s) ?? 0.0;
}

DateTime? _parseDt(dynamic v) {
  if (v == null) return null;
  if (v is DateTime) return v;
  return DateTime.tryParse(v.toString());
}

/// workers может прийти как Map (обычно) или как List (на всякий случай)
Map<String, dynamic>? _workerFromShift(Map<String, dynamic> shift) {
  final w = shift['workers'];
  if (w == null) return null;
  if (w is Map<String, dynamic>) return w;
  if (w is Map) return Map<String, dynamic>.from(w);
  if (w is List && w.isNotEmpty) {
    final first = w.first;
    if (first is Map<String, dynamic>) return first;
    if (first is Map) return Map<String, dynamic>.from(first);
  }
  return null;
}

/// Сколько денег заработано в текущей активной смене (LIVE)
double _liveAmountForShift(Map<String, dynamic> shift, DateTime now) {
  final start = _parseDt(shift['start_time']);
  if (start == null) return 0.0;

  final worker = _workerFromShift(shift);
  final rate = _asDouble(worker?['hourly_rate']);

  final secs = now.difference(start.toLocal()).inSeconds;
  if (secs <= 0 || rate <= 0) return 0.0;

  final hours = secs / 3600.0;
  return hours * rate;
}

/// LIVE total по всем online сменам
double _liveTotalOnline(List<Map<String, dynamic>> onlineShifts, DateTime now) {
  double sum = 0.0;
  for (final s in onlineShifts) {
    sum += _liveAmountForShift(s, now);
  }
  return sum;
}

class _PulsingIcon extends StatefulWidget {
  final IconData icon;
  final Color color;
  final double size;

  const _PulsingIcon({
    required this.icon,
    required this.color,
    this.size = 16,
  });

  @override
  State<_PulsingIcon> createState() => _PulsingIconState();
}

class _PulsingIconState extends State<_PulsingIcon>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 850),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (_, __) {
        final t = _c.value; // 0..1

        // было очень мягко -> делаем заметнее
        final scale = 0.88 + (t * 0.32);          // 0.88 -> 1.20
        final iconOpacity = 0.55 + (t * 0.45);    // 0.55 -> 1.00
        final glowOpacity = 0.20 + (t * 0.55);    // 0.20 -> 0.75
        final blur = 10.0 + (t * 18.0);          // 10 -> 28

        return Transform.scale(
          scale: scale,
          child: Icon(
            widget.icon,
            size: widget.size,
            color: widget.color.withOpacity(iconOpacity),
            shadows: [
              Shadow(
                color: widget.color.withOpacity(glowOpacity),
                blurRadius: blur,
              ),
              Shadow(
                color: widget.color.withOpacity(glowOpacity * 0.6),
                blurRadius: blur * 1.6,
              ),
            ],
          ),
        );
      },
    );
  }

}

class _LiveChip extends StatelessWidget {
  final Color color;
  const _LiveChip({required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 18,
      padding: const EdgeInsets.symmetric(horizontal: 7),
      decoration: BoxDecoration(
        color: color.withOpacity(0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withOpacity(0.22), width: 1),
      ),
      alignment: Alignment.center,
      child: Text(
        'LIVE',
        style: TextStyle(
          color: color.withOpacity(0.95),
          fontWeight: FontWeight.w800, // тоньше чем w900
          fontSize: 10,
          letterSpacing: 0.6,
          height: 1.0,
        ),
      ),
    );
  }
}

class _LiveChipPulse extends StatefulWidget {
  final Color color;
  const _LiveChipPulse({required this.color});

  @override
  State<_LiveChipPulse> createState() => _LiveChipPulseState();
}

class _LiveChipPulseState extends State<_LiveChipPulse>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (_, __) {
        final t = _c.value; // 0..1

        final bg = 0.16 + t * 0.24;        // 0.16 -> 0.40
        final br = 0.28 + t * 0.30;        // 0.28 -> 0.58
        final glow = 0.18 + t * 0.35;      // 0.18 -> 0.53
        final blur = 10.0 + t * 18.0;      // 10 -> 28

        return Container(
          height: 18,
          padding: const EdgeInsets.symmetric(horizontal: 7),
          decoration: BoxDecoration(
            color: widget.color.withOpacity(bg),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: widget.color.withOpacity(br), width: 1),
            boxShadow: [
              BoxShadow(
                color: widget.color.withOpacity(glow),
                blurRadius: blur,
                spreadRadius: 0.5,
              ),
            ],
          ),
          alignment: Alignment.center,
          child: Text(
            'LIVE',
            style: TextStyle(
              color: Colors.white.withOpacity(0.90), // <- чтобы “вырезалось” на фоне
              fontWeight: FontWeight.w900,
              fontSize: 10,
              letterSpacing: 0.8,
              height: 1.0,
            ),
          ),
        );

      },
    );
  }
}

class _TimeDateCapsule extends StatelessWidget {
  final String timeText;
  final String dateText;
  final bool open;
  final VoidCallback onTap;

  const _TimeDateCapsule({
    required this.timeText,
    required this.dateText,
    required this.open,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        height: 44,
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.035),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.white.withOpacity(0.10)),
        ),
        child: Row(
          children: [
            Icon(Icons.schedule_rounded, color: AppPalette.blue.withOpacity(0.95), size: 18),
            const SizedBox(width: 10),

            Text(
              timeText,
              style: const TextStyle(
                color: AppPalette.textMain,
                fontWeight: FontWeight.w800,
                fontSize: 15,
                height: 1.0,
                letterSpacing: 0.2,
              ),
            ),

            const SizedBox(width: 12),

            // ✅ мягкий разделитель
            Container(
              width: 1,
              height: 18,
              color: Colors.white.withOpacity(0.10),
            ),

            const SizedBox(width: 12),

            Icon(Icons.calendar_month_rounded, color: AppPalette.orange.withOpacity(0.95), size: 18),
            const SizedBox(width: 10),

            Expanded(
              child: Text(
                dateText,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: AppPalette.textMain.withOpacity(0.82),
                  fontWeight: FontWeight.w800,
                  fontSize: 13.5,
                  height: 1.0,
                  letterSpacing: 0.1,
                ),
              ),
            ),

            const SizedBox(width: 8),
            Icon(
              open ? Icons.expand_less_rounded : Icons.expand_more_rounded,
              color: Colors.white.withOpacity(0.45),
            ),
          ],
        ),
      ),
    );
  }
}


class _PulsingDot extends StatefulWidget {
  final Color color;
  final double size;
  const _PulsingDot({required this.color, this.size = 10, super.key});

  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 850),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (_, __) {
        final t = _c.value; // 0..1

        final dotOpacity = 0.45 + t * 0.55;     // 0.45 -> 1.00
        final glowOpacity = 0.10 + t * 0.35;    // 0.10 -> 0.45
        final glowBlur = 6.0 + t * 12.0;        // 6 -> 18

        return Container(
          width: widget.size,
          height: widget.size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: widget.color.withOpacity(dotOpacity),
            boxShadow: [
              BoxShadow(
                color: widget.color.withOpacity(glowOpacity),
                blurRadius: glowBlur,
                spreadRadius: 1.0,
              ),
              BoxShadow(
                color: widget.color.withOpacity(glowOpacity * 0.6),
                blurRadius: glowBlur * 1.6,
                spreadRadius: 0.5,
              ),
            ],
          ),
        );
      },
    );
  }
}

class _OnShiftPlayPulse extends StatefulWidget {
  final Color color;
  final double size;

  const _OnShiftPlayPulse({
    super.key,
    required this.color,
    this.size = 16,
  });

  @override
  State<_OnShiftPlayPulse> createState() => _OnShiftPlayPulseState();
}

class _OnShiftPlayPulseState extends State<_OnShiftPlayPulse>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (_, __) {
        final t = _c.value; // 0..1

        final iconOpacity = 0.60 + t * 0.40;   // 0.60 -> 1.00
        final glowOpacity = 0.08 + t * 0.22;   // 0.08 -> 0.30
        final blur = 8.0 + t * 10.0;           // 8 -> 18

        return Icon(
          Icons.play_circle_fill_rounded,
          size: widget.size,
          color: widget.color.withOpacity(iconOpacity),
          shadows: [
            Shadow(
              color: widget.color.withOpacity(glowOpacity),
              blurRadius: blur,
            ),
            Shadow(
              color: widget.color.withOpacity(glowOpacity * 0.7),
              blurRadius: blur * 1.6,
            ),
          ],
        );
      },
    );
  }
}


class _LiveTextPulse extends StatefulWidget {
  const _LiveTextPulse({super.key});

  @override
  State<_LiveTextPulse> createState() => _LiveTextPulseState();
}

class _LiveTextPulseState extends State<_LiveTextPulse>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (_, __) {
        final t = _c.value; // 0..1

        // только ярче/тусклее, без scale
        final opacity = 0.60 + t * 0.40; // 0.60 -> 1.00

        // можно чуть “сдвигать” цвет: белый -> слегка зеленоватый
        final greenMix = 0.10 + t * 0.18; // 0.10 -> 0.28

        return Text(
          'LIVE',
          style: TextStyle(
            color: Color.lerp(
              AppPalette.textMain.withOpacity(opacity),
              AppPalette.green.withOpacity(opacity),
              greenMix,
            ),
            fontWeight: FontWeight.w900,
            fontSize: 12.5,
            letterSpacing: 0.8,
            height: 1.0,
          ),
        );
      },
    );
  }
}

Future<bool?> showLogoutDialog(BuildContext context) {
  return showGeneralDialog<bool>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Logout',
    barrierColor: Colors.black.withOpacity(0.55),
    transitionDuration: const Duration(milliseconds: 180),
    pageBuilder: (_, __, ___) => const _LogoutDialog(),
    transitionBuilder: (_, anim, __, child) {
      final curved = CurvedAnimation(parent: anim, curve: Curves.easeOutCubic);
      return FadeTransition(
        opacity: curved,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.98, end: 1.0).animate(curved),
          child: child,
        ),
      );
    },
  );
}

// ===== UI =====

class _LogoutDialog extends StatelessWidget {
  const _LogoutDialog();

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18),
          child: Material(
            type: MaterialType.transparency, // ✅ важно: Ink/тени/клип работают корректно
            child: ClipRRect(
              borderRadius: BorderRadius.circular(22),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                child: Container(
                  width: 340,
                  padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        const Color(0xFF2F3036).withOpacity(0.92),
                        const Color(0xFF24252B).withOpacity(0.90),
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
                  child: Column(
                    mainAxisSize: MainAxisSize.min, // ✅ чтобы не было overflow
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Are you sure you want to logout?',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.80),
                          fontWeight: FontWeight.w800,
                          fontSize: 13.5,
                          height: 1.25,
                        ),
                      ),
                      const SizedBox(height: 6),

                      Text(
                        'You can sign in again anytime.',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.60),
                          fontWeight: FontWeight.w700,
                          fontSize: 12.5,
                          height: 1.25,
                        ),
                      ),

                      const SizedBox(height: 14),

                      // ✅ divider между текстом и кнопками
                      Container(
                        height: 1,
                        width: double.infinity,
                        color: Colors.white.withOpacity(0.06),
                      ),

                      const SizedBox(height: 14),

                      // ✅ кнопки снизу (как на iOS)
                      Row(
                        children: [
                          Expanded(
                            child: _DialogBtn(
                              text: 'Cancel',
                              icon: Icons.close_rounded,
                              variant: _BtnVariant.neutral,
                              onTap: () => Navigator.of(context).pop(false),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _DialogBtn(
                              text: 'Logout',
                              icon: Icons.logout_rounded,
                              variant: _BtnVariant.danger,
                              onTap: () => Navigator.of(context).pop(true),
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
    );
  }
}

enum _BtnVariant { neutral, danger }

class _DialogBtn extends StatelessWidget {
  final String text;
  final IconData icon;
  final VoidCallback onTap;
  final _BtnVariant variant;

  const _DialogBtn({
    required this.text,
    required this.icon,
    required this.onTap,
    required this.variant,
  });

  @override
  Widget build(BuildContext context) {
    final isDanger = variant == _BtnVariant.danger;

    final border = isDanger
        ? Colors.white.withOpacity(0.10)
        : Colors.white.withOpacity(0.10);

    final bg = isDanger
        ? const LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [
        Color(0xFFFF6B7A),
        Color(0xFFE11D2E),
      ],
    )
        : LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [
        Colors.white.withOpacity(0.07),
        Colors.white.withOpacity(0.03),
      ],
    );

    final textColor = isDanger
        ? Colors.white.withOpacity(0.95)
        : Colors.white.withOpacity(0.82);

    final iconColor = isDanger
        ? Colors.white.withOpacity(0.95)
        : Colors.white.withOpacity(0.75);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Ink(
          height: 44,
          decoration: BoxDecoration(
            gradient: bg,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: border),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.25),
                blurRadius: 18,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 18, color: iconColor),
              const SizedBox(width: 8),
              Text(
                text,
                style: TextStyle(
                  color: textColor,
                  fontWeight: FontWeight.w900,
                  fontSize: 13,
                  letterSpacing: 0.2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}


