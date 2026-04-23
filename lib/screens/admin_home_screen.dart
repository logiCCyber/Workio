import 'dart:async';
import 'dart:ui';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/cupertino.dart';

import '../widgets/glass_appbar.dart';
import '../app_keys.dart'; // или путь где лежит rootMessengerKey
import '../ui/app_toast.dart';
import 'admin_inbox_screen.dart';
import '../services/message_service.dart';
import 'admin_tasks_screen.dart';
import '../services/task_service.dart';
import '../services/push_token_service.dart';
import 'estimate_list_screen.dart';
import 'estimate_templates_screen.dart';
import 'ai_estimate_screen.dart';
import 'company_settings_screen.dart';
import 'clients_screen.dart';
import 'properties_screen.dart';
import 'invoice_list_screen.dart';
import 'global_search_screen.dart';
import 'price_rules_screen.dart';
import '../utils/company_logo_helper.dart';

class AdminHomeScreen extends StatelessWidget {
  final String adminEmail;
  final int warningsSeed;
  final String adminId;
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
    required this.adminId,
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
    required this.warningsSeed,
  });

  void _showAboutSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _AboutWorkioSheet(
        adminEmail: adminEmail,
        subtitle: 'Admin panel',
        aboutText: 'Workio helps you manage workers, shifts, and payouts.',
      ),
    );
  }

  void _openCompanySettings(BuildContext context) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const CompanySettingsScreen(),
      ),
    );
  }

  Future<void> _openEstimateSystemScreen(
      BuildContext context,
      Widget screen,
      ) async {
    Navigator.pop(context);

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => screen,
      ),
    );

    if (!context.mounted) return;

    _showEstimateSystemSheet(context);
  }

  void _openGlobalSearch(BuildContext context) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const GlobalSearchScreen(),
      ),
    );
  }

  void _showEstimateSystemSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        decoration: BoxDecoration(
          color: const Color(0xFF1F2025),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          border: Border.all(color: Colors.white.withOpacity(0.08)),
        ),
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                Center(
                  child: Container(
                    width: 42,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 14),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.16),
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),

                const Padding(
                  padding: EdgeInsets.fromLTRB(8, 0, 8, 6),
                  child: Text(
                    'Estimate System',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                  ListTile(
                    dense: true,
                    leading: const Icon(CupertinoIcons.search, color: Colors.white70),
                    title: const Text('Search'),
                    onTap: () => _openEstimateSystemScreen(
                      context,
                      const GlobalSearchScreen(),
                    ),
                  ),
                ListTile(
                  dense: true,
                  leading: const Icon(Icons.calculate_rounded, color: Colors.white70),
                  title: const Text('Estimates'),
                  onTap: () => _openEstimateSystemScreen(
                    context,
                    const EstimateListScreen(),
                  ),
                ),
                ListTile(
                  dense: true,
                  leading: const Icon(Icons.receipt_long_rounded, color: Colors.white70),
                  title: const Text('Invoices'),
                  onTap: () => _openEstimateSystemScreen(
                    context,
                    const InvoiceListScreen(),
                  ),
                ),
                ListTile(
                  dense: true,
                  leading: const Icon(Icons.content_copy_rounded, color: Colors.white70),
                  title: const Text('Templates'),
                  onTap: () => _openEstimateSystemScreen(
                    context,
                    const EstimateTemplatesScreen(),
                  ),
                ),
                ListTile(
                  dense: true,
                  leading: const Icon(Icons.auto_awesome_rounded, color: Colors.white70),
                  title: const Text('AI Estimate'),
                  onTap: () => _openEstimateSystemScreen(
                    context,
                    const AiEstimateScreen(),
                  ),
                ),
                  ListTile(
                    dense: true,
                    leading: const Icon(CupertinoIcons.slider_horizontal_3, color: Colors.white70),
                    title: const Text('Price Rules'),
                    onTap: () => _openEstimateSystemScreen(
                      context,
                      const PriceRulesScreen(),
                    ),
                  ),

                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
                  child: Text(
                    'Mini CRM',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.55),
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),

                Padding(
                  padding: const EdgeInsets.only(left: 18),
                  child: ListTile(
                    dense: true,
                    leading: const Icon(CupertinoIcons.person_2, color: Colors.white54, size: 18),
                    title: const Text(
                      'Clients',
                      style: TextStyle(fontSize: 14),
                    ),
                    onTap: () => _openEstimateSystemScreen(
                      context,
                      const ClientsScreen(),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(left: 18),
                  child: ListTile(
                    dense: true,
                    leading: const Icon(CupertinoIcons.location_solid, color: Colors.white54, size: 18),
                    title: const Text(
                      'Properties',
                      style: TextStyle(fontSize: 14),
                    ),
                    onTap: () => _openEstimateSystemScreen(
                      context,
                      const PropertiesScreen(),
                    ),
                  ),
                ),

                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
                  child: Text(
                    'Business',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.55),
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),

                ListTile(
                  dense: true,
                  leading: const Icon(Icons.business_rounded, color: Colors.white70),
                  title: const Text('Company Settings'),
                  onTap: () => _openEstimateSystemScreen(
                    context,
                    const CompanySettingsScreen(),
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

  @override
  Widget build(BuildContext context) {
    String _normId(Object? v) => (v ?? '').toString().trim();

    // ✅ onlineShifts приходит из work_logs и там есть user_id (это auth_user_id)
    final onlineAuthIds = onlineShifts
        .map((s) => _normId(s['user_id']))
        .where((id) => id.isNotEmpty)
        .toSet();

// ✅ workersUi: сравниваем workers.auth_user_id с onlineAuthIds
    final workersUi = workers.map((w) {
      final authId = _normId(w['auth_user_id']);
      return {
        ...w,
        'on_shift': onlineAuthIds.contains(authId),
      };
    }).toList();

    return Scaffold(
      backgroundColor: AppPalette.bg,
      extendBodyBehindAppBar: false,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,

        // ✅ ВАЖНО для Material 3 (убирает лишний "тинт"/скрим)
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.transparent,
        scrolledUnderElevation: 0,

        automaticallyImplyLeading: false,
        titleSpacing: 0,

        title: ClipRRect(
          child: Stack(
            children: [
              // ===== BLUR =====
              BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                child: Container(),
              ),

              // ===== PANEL (точно как в Worker details) =====
              Container(
                height: kToolbarHeight + 10,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.white.withOpacity(0.14),
                      Colors.white.withOpacity(0.06),
                      Colors.black.withOpacity(0.22),
                    ],
                  ),
                  border: Border(
                    bottom: BorderSide(
                      color: Colors.white.withOpacity(0.12),
                      width: 1,
                    ),
                  ),
                ),
                child: SafeArea(
                  bottom: false,
                  child: Row(
                    children: [
                      const Icon(
                        Icons.admin_panel_settings_rounded,
                        color: Colors.white70,
                      ),
                      const SizedBox(width: 10),

                      const Expanded(
                        child: Text(
                          'Admin panel',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 18,
                            color: Colors.white70,
                          ),
                        ),
                      ),

                      const SizedBox(width: 6),

                      _AdminTasksButton(
                        onTap: () async {
                          await Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const AdminTasksScreen(),
                            ),
                          );
                        },
                      ),

                      const SizedBox(width: 4),

                      _AdminMailButton(
                        onTap: () async {
                          await Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const AdminInboxScreen(),
                            ),
                          );
                        },
                      ),

                      const SizedBox(width: 4),

                      // ✅ твои три точки (то же меню что было)
                      PopupMenuButton<String>(
                        icon: const Icon(Icons.more_vert_rounded, color: Colors.white70),
                        color: const Color(0xFF1F2025),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        onSelected: (v) async {
                          if (v == 'add') {
                            onAddWorker();
                          } else if (v == 'estimate_system') {
                            _showEstimateSystemSheet(context);
                          } else if (v == 'pass') {
                            await showChangePasswordDialog(context);
                          } else if (v == 'about') {
                            _showAboutSheet(context);
                          } else if (v == 'logout') {
                            final ok = await showLogoutDialog(context);
                            if (ok == true) await onLogout();
                          }
                        },
                        itemBuilder: (_) => const [
                          PopupMenuItem(
                            value: 'add',
                            child: ListTile(
                              dense: true,
                              leading: Icon(Icons.person_add_alt_1_rounded),
                              title: Text('Add worker'),
                            ),
                          ),
                          PopupMenuItem(
                            value: 'estimate_system',
                            child: ListTile(
                              dense: true,
                              leading: Icon(Icons.request_quote_rounded),
                              title: Text('Estimate System'),
                              trailing: Icon(
                                Icons.chevron_right_rounded,
                                size: 18,
                                color: Colors.white54,
                              ),
                            ),
                          ),
                          PopupMenuItem(
                            value: 'pass',
                            child: ListTile(
                              dense: true,
                              leading: Icon(Icons.lock_reset_rounded),
                              title: Text('Change password'),
                            ),
                          ),
                          const PopupMenuDivider(),
                          PopupMenuItem(
                            value: 'about',
                            child: ListTile(
                              dense: true,
                              leading: Icon(Icons.info_outline_rounded),
                              title: Text('About Workio'),
                            ),
                          ),
                          const PopupMenuDivider(),
                          PopupMenuItem(
                            value: 'logout',
                            child: ListTile(
                              dense: true,
                              leading: Icon(Icons.logout_rounded, color: Colors.redAccent),
                              title: Text('Logout'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),

              // ===== TOP HIGHLIGHT (как у Worker details) =====
              Positioned(
                left: 0,
                right: 0,
                top: 0,
                child: Container(
                  height: 1,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Colors.transparent,
                        Colors.white.withOpacity(0.35),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      body: Stack(
        clipBehavior: Clip.hardEdge, // ✅ важно: режет всё что “вылазит”
        children: [
          const _BackgroundBase(),

          ListView(
            padding: const EdgeInsets.fromLTRB(12, 16, 12, 24), // ✅ ровно как payments
            children: [
              AdminTopPanel(
                adminId: adminId,
                warningsSeed: warningsSeed,
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

              // ❌ ВАЖНО: НЕТ SizedBox(height: 14) В КОНЦЕ
            ],
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
  final String adminId;
  final int warningsSeed;
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
    required this.adminId,
    required this.adminEmail,
    required this.workers,
    required this.dashboard,
    required this.loading,
    required this.loadingOnline,
    required this.onlineShifts,
    required this.now,
    required this.loadingShiftEvents,
    required this.todayShiftEvents,
    required this.warningsSeed,
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

  bool _withinHours(Object? iso, int hours) {
    if (iso == null) return false; // ✅ нет даты -> НЕ показываем (чтобы не висело вечно)
    try {
      final dt = DateTime.parse(iso.toString()).toUtc();
      final diff = now.toUtc().difference(dt);
      if (diff.isNegative) return true; // на всякий случай
      return diff <= Duration(hours: hours);
    } catch (_) {
      return false; // ✅ если дата битая -> НЕ показываем
    }
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

  String makeWarningKey(String type, String entityId) =>
      '$adminId::$type::$entityId';


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
    final shuffledAccents = [..._warningAccentPool]..shuffle(Random(warningsSeed));
    int ci = 0;
    Color nextAccent() {
      final c = shuffledAccents[ci % shuffledAccents.length];
      ci++;
      return c;
    }

    // unpaid workers
    for (final w in workers) {
      final unpaid = _num(w['unpaid_total']);
      if (unpaid > 0) {
        final email = (w['email'] ?? 'worker').toString();
        final authId = (w['auth_user_id'] ?? '').toString().trim();
        if (authId.isNotEmpty) {
          items.add(
            _WarningItem(
              warningKey: makeWarningKey('unpaid_14d', authId),
              icon: Icons.payments_rounded,
              accent: nextAccent(),
              title: 'Payment pending',
              message: '$email has unpaid balance: \$${unpaid.toStringAsFixed(2)}',
              workerData: w,
              details: {
                'type': 'unpaid',
                'balance': unpaid,
              },
            ),
          );
        }
      }
    }

    // view-only workers (✅ показываем только первые 24 часа)
    for (final w in workers) {
      if (_modeOf(w) != 'view_only') continue;

      // ✅ view_only_at должно быть в worker
      if (!_withinHours(w['view_only_at'], 24)) continue;

      final email = (w['email'] ?? 'worker').toString();
      final authId = (w['auth_user_id'] ?? '').toString().trim();
      if (authId.isEmpty) continue;

      items.add(
        _WarningItem(
          warningKey: makeWarningKey('view_only', authId),
          icon: Icons.visibility_rounded,
          accent: nextAccent(),
          title: 'View-only access',
          message: '$email is in view-only mode. Review permissions.',
          workerData: w,
          details: {
            'type': 'view_only',
            'access_mode': w['access_mode'],
            'view_only_at': w['view_only_at'],
          },
        ),
      );
    }

    // suspended workers (✅ показываем только первые 24 часа)
    for (final w in workers) {
      if (_modeOf(w) != 'suspended') continue;

      // ✅ suspended_at должно быть в worker
      if (!_withinHours(w['suspended_at'], 24)) continue;

      final email = (w['email'] ?? 'worker').toString();
      final authId = (w['auth_user_id'] ?? '').toString().trim();
      if (authId.isEmpty) continue;

      items.add(
        _WarningItem(
          warningKey: makeWarningKey('suspended', authId),
          icon: Icons.block_rounded,
          accent: nextAccent(),
          title: 'Suspended',
          message: '$email was suspended. Review access.',
          workerData: w,
          details: {
            'type': 'suspended',
            'access_mode': w['access_mode'],
            'suspended_at': w['suspended_at'],
          },
        ),
      );
    }

    // ===============================
    // MULTIPLE STARTS TODAY
    // ===============================

    // если данные ещё грузятся — просто не считаем (чтобы не было фальшивых предупреждений)
    // ===============================
// MULTIPLE STARTS TODAY (FIXED)
// ===============================
    if (!loadingShiftEvents && todayShiftEvents.isNotEmpty) {
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

      // ✅ индексы workers
      final Map<String, Map<String, dynamic>> byWorkerId = {};
      final Map<String, Map<String, dynamic>> byAuthId = {};

      for (final w in workers) {
        final wid = (w['id'] ?? '').toString().trim();
        final auth = (w['auth_user_id'] ?? '').toString().trim();
        if (wid.isNotEmpty) byWorkerId[wid] = w;
        if (auth.isNotEmpty) byAuthId[auth] = w;
      }

      // ✅ считаем starts уже по "каноническому" ключу (auth_user_id если есть, иначе id)
      final Map<String, int> startsByCanonical = {};
      final Map<String, Map<String, dynamic>> workerByCanonical = {};

      for (final e in todayShiftEvents) {
        final rawKey = (e['worker_id'] ?? '').toString().trim();
        if (rawKey.isEmpty) continue;

        final type = (e['event_type'] ?? '').toString();
        if (!isStartEvent(type)) continue;

        final w = byWorkerId[rawKey] ?? byAuthId[rawKey];
        if (w == null) continue; // если реально нет worker в списке — не показываем warning

        final canonical = (w['auth_user_id'] ?? w['id'] ?? '').toString().trim();
        if (canonical.isEmpty) continue;

        startsByCanonical[canonical] = (startsByCanonical[canonical] ?? 0) + 1;
        workerByCanonical[canonical] = w;
      }

      for (final entry in startsByCanonical.entries) {
        final starts = entry.value;
        if (starts < 2) continue;

        final w = workerByCanonical[entry.key]!;
        final email = (w['email'] ?? 'worker').toString();

        final day = DateFormat('yyyy-MM-dd').format(now);
        items.add(
          _WarningItem(
            warningKey: makeWarningKey('multi_starts_today', '${entry.key}|$day'),
            icon: Icons.multiple_stop_rounded,
            accent: nextAccent(),
            title: 'Multiple starts today',
            message: '$email started shift $starts times today. Check shift logs.',
            workerData: w,
            details: {
              'type': 'multi_starts_today',
              'starts_today': starts,
              'day': day,
            },
          ),
        );
      }
    }

    // overtime workers (more than 8h 30m)
    for (final s in onlineShifts) {
      final userId = (s['user_id'] ?? '').toString().trim();
      if (userId.isEmpty) continue;

      final startRaw = s['start_time'];
      if (startRaw == null) continue;

      DateTime? start;
      try {
        start = DateTime.parse(startRaw.toString()).toUtc();
      } catch (_) {
        continue;
      }

      final worked = now.toUtc().difference(start);
      if (worked < const Duration(hours: 8, minutes: 30)) continue;

      Map<String, dynamic>? w;
      for (final worker in workers) {
        final authId = (worker['auth_user_id'] ?? '').toString().trim();
        if (authId == userId) {
          w = worker;
          break;
        }
      }
      if (w == null) continue;

      final email = (w['email'] ?? 'worker').toString();

      items.add(
        _WarningItem(
          warningKey: makeWarningKey('overtime_8h30', userId),
          icon: Icons.timer_rounded,
          accent: nextAccent(),
          title: 'Long shift',
          message: '$email has been on shift for more than 8h 30m.',
          workerData: w,
          details: {
            'type': 'long_shift',
            'worked_minutes': worked.inMinutes,
            'start_time': startRaw,
          },
        ),
      );
    }

    return items;
  }


  @override
  Widget build(BuildContext context) {
    final online = workers.where((w) => w['on_shift'] == true).length;
    final hasOnline = online > 0;
    final isLive = hasOnline; // есть LIVE смена (по onlineShifts)
    final liveOnlineTotal = isLive ? _liveTotalOnline(onlineShifts, now) : 0.0;

    DateTime? lastPaidAt;
    double? lastPaidTotal;

    try {
      final at = dashboard?['last_paid_at'];
      if (at != null) lastPaidAt = DateTime.parse(at.toString()).toLocal();
    } catch (_) {}

    final t = dashboard?['last_paid_total'];
    if (t is num) lastPaidTotal = t.toDouble();


    final total = workers.length;
    final viewOnly = _countViewOnly();
    final susp = _countSuspended();
    final unpaid = _unpaidFromWorkers();
    final lastPaid = _lastPaidText();

    final warnings = _buildWarnings();

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
                  Expanded(
                    child: _MiniMetric(
                      icon: Icons.groups_2_rounded,
                      iconColor: Colors.white,
                      label: 'Total',
                      value: '$total',
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _MiniMetric(
                      icon: Icons.play_circle_fill_rounded,
                      iconColor: AppPalette.green,
                      label: 'Online',
                      value: '$online',
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _CyclingMiniMetric(
                      viewCount: viewOnly,
                      suspCount: susp,
                    ),
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
      footer: _FooterWarningsBar(
        adminId: adminId,
        items: warnings,
      ),
    );

  }
}

void _showRootGlassSnack(
    String text, {
      IconData icon = Icons.info_outline_rounded,
      Color accent = const Color(0xFF7AB8FF),
    }) {
  final messenger = rootMessengerKey.currentState;
  if (messenger == null) return;

  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: Colors.transparent,
        elevation: 0,
        margin: const EdgeInsets.fromLTRB(14, 0, 14, 18),
        padding: EdgeInsets.zero,
        duration: const Duration(milliseconds: 2600),
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
                    const Color(0xFF2B313A).withOpacity(0.92),
                    const Color(0xFF1A1F27).withOpacity(0.90),
                    Colors.black.withOpacity(0.22),
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
                      icon,
                      size: 20,
                      color: accent,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      text,
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.92),
                        fontWeight: FontWeight.w800,
                        fontSize: 13.2,
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
    );
}

class _ChangePasswordDialog extends StatefulWidget {
  const _ChangePasswordDialog();

  @override
  State<_ChangePasswordDialog> createState() => _ChangePasswordDialogState();
}

class _ChangePasswordDialogState extends State<_ChangePasswordDialog> {
  final pass1 = TextEditingController();
  final pass2 = TextEditingController();

  bool saving = false;
  bool show1 = false;
  bool show2 = false;

  @override
  void dispose() {
    pass1.dispose();
    pass2.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext ctx) {
    Future<void> save() async {
      FocusScope.of(ctx).unfocus(); // ✅ важно, сначала закрыть клаву

      final p1 = pass1.text.trim();
      final p2 = pass2.text.trim();

      void toast(String t) {
        _showRootGlassSnack(
          t,
          icon: Icons.error_outline_rounded,
          accent: const Color(0xFFFF8A7A),
        );
      }

      if (p1.isEmpty || p2.isEmpty) return toast('Please fill both fields');
      if (p1.length < 6) return toast('Password must be at least 6 characters');
      if (p1 != p2) return toast('Passwords do not match');

      setState(() => saving = true);
      try {
        await Supabase.instance.client.auth.updateUser(UserAttributes(password: p1));
        if (!mounted) return;

        WidgetsBinding.instance.addPostFrameCallback((_) {
          _showRootGlassSnack(
            'Password updated',
            icon: Icons.check_circle_rounded,
            accent: const Color(0xFF63F5C2),
          );
        });
      } catch (e) {
        toast('Error: $e');
      } finally {
        if (mounted) setState(() => saving = false);
      }
    }

    // тут твой UI контейнер + поля + кнопки, только controllers = pass1/pass2
    return SafeArea(
      child: Center(
        child: Text("Your current UI goes here, using save() and pass1/pass2."),
      ),
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
                  if (footer != null) const SizedBox(height: 8),
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
    return Container(
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

const _warningBgPool = <Color>[
  Color(0xFF1B1D23),
  Color(0xFF1C1F26),
  Color(0xFF1E2028),
  Color(0xFF20222A),
  Color(0xFF1A1C22),
  Color(0xFF21242C),
];


class _WarningItem {
  final String warningKey;
  final IconData icon;
  final Color accent;
  final String title;
  final String message;

  // ✅ новые поля
  final Map<String, dynamic>? workerData;
  final Map<String, dynamic>? details;

  _WarningItem({
    required this.warningKey,
    required this.icon,
    required this.accent,
    required this.title,
    required this.message,
    this.workerData,
    this.details,
  });
}

class _FooterWarningsCarousel extends StatefulWidget {
  final List<_WarningItem> items;
  final ValueChanged<int>? onIndexChanged;
  final Future<void> Function(_WarningItem item)? onAck;
  final Future<void> Function(_WarningItem item)? onDetails;
  final Future<void> Function(_WarningItem item)? onDismiss;
  final bool expanded;
  final bool autoplay;

  const _FooterWarningsCarousel({
    required this.items,
    this.onIndexChanged,
    this.onAck,
    this.onDetails,
    this.onDismiss,
    this.expanded = false,
    this.autoplay = true,
  });

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
      return;
    }

    if (oldWidget.autoplay != widget.autoplay) {
      _start();
    }
  }

  void _start() {
    timer?.cancel();
    if (!widget.autoplay) return;
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
        index: index,
        total: widget.items.length,
        expanded: widget.expanded,
        onAck: widget.onAck,
        onDetails: widget.onDetails,
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
  final bool canRestoreAll;
  final VoidCallback? onRestoreAll;

  const _OkFooter({
    super.key,
    this.canRestoreAll = false,
    this.onRestoreAll,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 50,
      child: Row(
        children: [
          SizedBox(
            width: 22,
            height: 22,
            child: Icon(
              Icons.check_circle_rounded,
              color: AppPalette.green.withOpacity(0.95),
              size: 18,
            ),
          ),
          const SizedBox(width: 12),

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

          if (canRestoreAll) ...[
            const SizedBox(width: 8),
            _RestoreAllButton(
              onTap: onRestoreAll,
            ),
          ],
        ],
      ),
    );
  }
}

class _RestoreAllButton extends StatefulWidget {
  final VoidCallback? onTap;

  const _RestoreAllButton({
    super.key,
    required this.onTap,
  });

  @override
  State<_RestoreAllButton> createState() => _RestoreAllButtonState();
}

class _RestoreAllButtonState extends State<_RestoreAllButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 260),
  );

  late final Animation<double> _scale = Tween<double>(
    begin: 1.0,
    end: 0.88,
  ).animate(
    CurvedAnimation(parent: _c, curve: Curves.easeOutCubic),
  );

  late final Animation<double> _turns = Tween<double>(
    begin: 0.0,
    end: -0.08,
  ).animate(
    CurvedAnimation(parent: _c, curve: Curves.easeOutCubic),
  );

  Future<void> _handleTap() async {
    if (widget.onTap == null) return;

    await _c.forward();
    await _c.reverse();

    widget.onTap!();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: _handleTap,
      borderRadius: BorderRadius.circular(10),
      child: AnimatedBuilder(
        animation: _c,
        builder: (_, __) {
          return Transform.scale(
            scale: _scale.value,
            child: RotationTransition(
              turns: AlwaysStoppedAnimation(_turns.value),
              child: Padding(
                padding: const EdgeInsets.all(6),
                child: Icon(
                  Icons.undo_rounded,
                  size: 18,
                  color: Colors.white.withOpacity(0.72),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

DateTime? _warningDateFromItem(_WarningItem item) {
  final d = item.details ?? <String, dynamic>{};
  final w = item.workerData ?? <String, dynamic>{};

  final candidates = [
    d['view_only_at'],
    d['suspended_at'],
    d['start_time'],
    d['reminder_at'],
    d['entry_date'],
    w['last_work_at'],
    w['first_work_at'],
    d['day'],
  ];

  for (final raw in candidates) {
    if (raw == null) continue;

    try {
      return DateTime.parse(raw.toString()).toLocal();
    } catch (_) {}
  }

  return null;
}

String _warningDateShort(_WarningItem item) {
  final dt = _warningDateFromItem(item);
  if (dt == null) return 'No date';
  return DateFormat('yyyy • MMM d').format(dt);
}

String _warningDateFull(_WarningItem item) {
  final dt = _warningDateFromItem(item);
  if (dt == null) return 'No date';
  return DateFormat('yyyy • MMM d • HH:mm').format(dt);
}

class _WarningFooter extends StatelessWidget {
  final Future<void> Function(_WarningItem item)? onAck;
  final _WarningItem item;
  final Future<void> Function(_WarningItem item)? onDetails;
  final int index;
  final int total;
  final bool expanded;

  const _WarningFooter({
    required this.item,
    required this.index,
    required this.total,
    this.onAck,
    this.onDetails,
    this.expanded = true,
  });

  String _workerName() {
    final w = item.workerData ?? <String, dynamic>{};
    return (w['name'] ?? '').toString().trim();
  }

  String _workerEmail() {
    final w = item.workerData ?? <String, dynamic>{};
    return (w['email'] ?? '').toString().trim();
  }

  String _personLine() {
    final name = _workerName();
    final email = _workerEmail();

    if (name.isNotEmpty && email.isNotEmpty) {
      return '$name • $email';
    }
    if (name.isNotEmpty) return name;
    if (email.isNotEmpty) return email;
    return item.message;
  }

  String _reasonLine() {
    final d = item.details ?? <String, dynamic>{};
    final type = (d['type'] ?? '').toString().trim();

    switch (type) {
      case 'unpaid':
        final raw = d['balance'];
        final balance = raw is num
            ? raw.toDouble()
            : double.tryParse(raw?.toString() ?? '');
        if (balance != null) {
          return 'Unpaid balance • \$${balance.toStringAsFixed(2)}';
        }
        return 'Unpaid balance';

      case 'view_only':
        return 'Worker has view-only access';

      case 'suspended':
        return 'Worker access is suspended';

      case 'multi_starts_today':
        final starts = d['starts_today'];
        if (starts != null) {
          return 'Started shift $starts times today';
        }
        return 'Multiple starts detected today';

      case 'long_shift':
        final workedMinutes = d['worked_minutes'];
        if (workedMinutes is int) {
          final h = workedMinutes ~/ 60;
          final m = workedMinutes % 60;
          return 'Worked time • ${h}h ${m}m';
        }
        return 'Long shift detected';

      case 'calendar_note':
        final note = (d['note_text'] ?? item.message ?? '').toString().trim();
        return note.isNotEmpty ? note : 'Note item';

      case 'calendar_reminder':
        final note = (d['note_text'] ?? '').toString().trim();
        if (note.isNotEmpty) return note;
        return 'Reminder item';

      default:
        return item.message;
    }
  }

  IconData _reasonIcon() {
    final type = (item.details?['type'] ?? '').toString().trim();

    switch (type) {
      case 'unpaid':
        return Icons.payments_outlined;
      case 'view_only':
        return Icons.visibility_outlined;
      case 'suspended':
        return Icons.block_outlined;
      case 'multi_starts_today':
        return Icons.multiple_stop_rounded;
      case 'long_shift':
        return Icons.timer_outlined;
      case 'calendar_note':
        return Icons.notes_rounded;
      case 'calendar_reminder':
        return Icons.notifications_active_outlined;
      default:
        return Icons.info_outline_rounded;
    }
  }

  String _statusChipText() {
    final type = (item.details?['type'] ?? '').toString().trim();

    switch (type) {
      case 'unpaid':
        return 'Pending';
      case 'view_only':
        return 'Review';
      case 'suspended':
        return 'Locked';
      case 'multi_starts_today':
        return 'Urgent';
      case 'long_shift':
        return '8h30+';
      case 'calendar_reminder':
        return 'Due';
      case 'calendar_note':
        return 'Note';
      default:
        return 'Info';
    }
  }

  Color _statusChipColor() {
    final type = (item.details?['type'] ?? '').toString().trim();

    switch (type) {
      case 'unpaid':
        return const Color(0xFFF59E0B);
      case 'view_only':
        return const Color(0xFF38BDF8);
      case 'suspended':
        return const Color(0xFFFB7185);
      case 'multi_starts_today':
        return const Color(0xFFFF8A00);
      case 'long_shift':
        return const Color(0xFFA78BFA);
      case 'calendar_reminder':
        return const Color(0xFF60A5FA);
      case 'calendar_note':
        return const Color(0xFF34D399);
      default:
        return Colors.white54;
    }
  }

  Widget _statusTag() {
    final color = _statusChipColor();

    return Text(
      _statusChipText(),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      textAlign: TextAlign.right,
      style: TextStyle(
        color: color,
        fontWeight: FontWeight.w900,
        fontSize: 9.6,
        letterSpacing: 0.15,
        height: 1.0,
      ),
    );
  }

  Widget _ackButton() {
    return InkWell(
      onTap: (onAck == null) ? null : () => onAck!(item),
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: 4,
          vertical: 3,
        ),
        child: Icon(
          Icons.check_rounded,
          size: 18,
          color: (onAck == null)
              ? Colors.white.withOpacity(0.18)
              : Colors.white.withOpacity(0.55),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedSize(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 36,
                height: 36,
                child: Icon(
                  item.icon,
                  color: item.accent.withOpacity(0.95),
                  size: 18,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  item.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: AppPalette.textMain.withOpacity(0.95),
                    fontWeight: FontWeight.w900,
                    fontSize: 12.8,
                    height: 1.0,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              if (expanded)
                Text(
                  _warningDateShort(item),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.45),
                    fontWeight: FontWeight.w800,
                    fontSize: 10.2,
                    height: 1.0,
                  ),
                )
              else
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _statusTag(),
                    const SizedBox(width: 8),
                    Text(
                      '${index + 1}/$total',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.right,
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.45),
                        fontWeight: FontWeight.w900,
                        fontSize: 10.5,
                        letterSpacing: 0.5,
                        height: 1.0,
                      ),
                    ),
                  ],
                ),
              const SizedBox(width: 8),
              _ackButton(),
            ],
          ),

          if (expanded) ...[
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.only(left: 48),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.person_outline_rounded,
                        size: 12,
                        color: Colors.white.withOpacity(0.42),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          _personLine(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.74),
                            fontWeight: FontWeight.w700,
                            fontSize: 11,
                            height: 1.0,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        _reasonIcon(),
                        size: 12,
                        color: Colors.white.withOpacity(0.38),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          _reasonLine(),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.48),
                            fontWeight: FontWeight.w700,
                            fontSize: 10.4,
                            height: 1.15,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _FooterWarningsBar extends StatefulWidget {
  final String adminId;
  final List<_WarningItem> items;

  const _FooterWarningsBar({
    required this.adminId,
    required this.items,
  });

  @override
  State<_FooterWarningsBar> createState() => _FooterWarningsBarState();
}

class _FooterWarningsBarState extends State<_FooterWarningsBar>
    with SingleTickerProviderStateMixin {
  final Set<String> _ackedLocal = {};
  final Map<String, Map<String, dynamic>> _dbState = {};

  final _db = Supabase.instance.client;

  List<_WarningItem> _calendarWarningItems = [];
  Timer? _calendarWarningsTimer;
  Timer? _autoCollapseTimer;

  bool _loadingDb = false;
  int _index = 0;
  bool _expanded = false;
  late final int _bgSeed;
  late final List<Color> _bgShuffled;

  late final AnimationController _restoreFx = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
  );

  late final Animation<double> _panelScale = Tween<double>(
    begin: 1.0,
    end: 0.985,
  ).animate(
    CurvedAnimation(parent: _restoreFx, curve: Curves.easeOutCubic),
  );

  late final Animation<double> _panelGlow = Tween<double>(
    begin: 0.0,
    end: 1.0,
  ).animate(
    CurvedAnimation(parent: _restoreFx, curve: Curves.easeOutCubic),
  );

  String _typeFromKey(String key) {
    final p = key.split('::');
    return (p.length >= 2) ? p[1] : '';
  }

  DateTime? _dt(Object? v) {
    if (v == null) return null;
    try {
      return DateTime.parse(v.toString()).toUtc();
    } catch (_) {
      return null;
    }
  }

  List<_WarningItem> _allItems() {
    return [
      ...widget.items,
      ..._calendarWarningItems,
    ];
  }

  String _fmtReminderAt(Object? iso) {
    if (iso == null) return '—';
    try {
      final dt = DateTime.parse(iso.toString()).toLocal();
      return DateFormat('MMM d • HH:mm').format(dt);
    } catch (_) {
      return '—';
    }
  }

  void _restartAutoCollapse() {
    _autoCollapseTimer?.cancel();

    if (!_expanded) return;

    _autoCollapseTimer = Timer(const Duration(seconds: 10), () {
      if (!mounted) return;
      setState(() {
        _expanded = false;
      });
    });
  }

  void _stopAutoCollapse() {
    _autoCollapseTimer?.cancel();
  }

  Future<void> _loadCalendarWarningItems() async {
    try {
      final rows = await _db
          .from('admin_calendar_items')
          .select('id, kind, title, note_text, reminder_at, is_done, notify_in_app, entry_date')
          .eq('admin_id', widget.adminId)
          .eq('notify_in_app', true)
          .eq('is_done', false)
          .order('created_at', ascending: false);

      final nowUtc = DateTime.now().toUtc();
      final items = <_WarningItem>[];

      for (final row in List<Map<String, dynamic>>.from(rows)) {
        final id = (row['id'] ?? '').toString().trim();
        if (id.isEmpty) continue;

        final kind = (row['kind'] ?? '').toString().trim().toLowerCase();
        final title = (row['title'] ?? '').toString().trim();
        final noteText = (row['note_text'] ?? '').toString().trim();
        final reminderAtRaw = row['reminder_at'];

        if (kind == 'note') {
          items.add(
            _WarningItem(
              warningKey: '${widget.adminId}::calendar_note::$id',
              icon: Icons.sticky_note_2_rounded,
              accent: const Color(0xFFF59E0B),
              title: title.isEmpty ? 'Note' : title,
              message: noteText.isEmpty ? 'Tap to view...' : noteText,
              details: {
                'type': 'calendar_note',
                'calendar_item_id': id,
                'kind': kind,
                'title': title,
                'note_text': noteText,
                'entry_date': row['entry_date'],
              },
            ),
          );
          continue;
        }

        if (kind == 'reminder') {
          if (reminderAtRaw == null) continue;

          DateTime? reminderAt;
          try {
            reminderAt = DateTime.parse(reminderAtRaw.toString()).toUtc();
          } catch (_) {
            reminderAt = null;
          }
          if (reminderAt == null) continue;

          // ✅ если время reminder прошло — warning больше не показываем
          if (!reminderAt.isAfter(nowUtc)) continue;

          items.add(
            _WarningItem(
              warningKey: '${widget.adminId}::calendar_reminder::$id',
              icon: Icons.notifications_active_rounded,
              accent: const Color(0xFF38BDF8),
              title: title.isEmpty ? 'Reminder' : title,
              message: 'Due ${_fmtReminderAt(reminderAtRaw)}',
              details: {
                'type': 'calendar_reminder',
                'calendar_item_id': id,
                'kind': kind,
                'title': title,
                'note_text': noteText,
                'reminder_at': reminderAtRaw,
                'entry_date': row['entry_date'],
              },
            ),
          );
        }
      }

      if (!mounted) return;

      setState(() {
        _calendarWarningItems = items;
      });
    } catch (_) {}
  }

  Future<void> _reloadAllWarnings() async {
    await _loadCalendarWarningItems();
    await _loadDbStateForKeys(_allItems().map((e) => e.warningKey).toList());
  }

  @override
  void dispose() {
    _calendarWarningsTimer?.cancel();
    _restoreFx.dispose();
    _autoCollapseTimer?.cancel();
    super.dispose();
  }

  Future<void> _showWarningDetailsDialog(
      BuildContext context,
      _WarningItem item,
      ) async {
    final w = item.workerData ?? <String, dynamic>{};
    final d = item.details ?? <String, dynamic>{};

    final name = (w['name'] ?? '—').toString().trim();
    final email = (w['email'] ?? '—').toString().trim();
    final type = (d['type'] ?? '').toString().trim();
    final accessMode = (d['access_mode'] ?? '').toString().trim();
    final startsToday = d['starts_today'];
    final balance = d['balance'];
    final workedMinutes = d['worked_minutes'];
    final warningDate = _warningDateFull(item);

    final titleText = (d['title'] ?? item.title).toString().trim();
    final noteText = (d['note_text'] ?? '').toString().trim();
    final reminderAt = d['reminder_at'];

    final isCalendarNote = type == 'calendar_note';
    final isCalendarReminder = type == 'calendar_reminder';

    String fmtIso(Object? iso) {
      if (iso == null) return '—';
      try {
        return DateFormat('yyyy • MMM d • HH:mm')
            .format(DateTime.parse(iso.toString()).toLocal());
      } catch (_) {
        return iso.toString();
      }
    }

    String workedText() {
      if (workedMinutes is! int) return '—';
      final h = workedMinutes ~/ 60;
      final m = workedMinutes % 60;
      return '${h}h ${m}m';
    }

    await showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'warning_details',
      barrierColor: Colors.black.withOpacity(0.58),
      transitionDuration: const Duration(milliseconds: 180),
      pageBuilder: (_, __, ___) {
        final media = MediaQuery.of(context);

        return Center(
          child: Material(
            color: Colors.transparent,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: 300,
                maxHeight: media.size.height * 0.62,
              ),
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 16),
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                decoration: BoxDecoration(
                  color: const Color(0xFF2A2C34),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: Colors.white.withOpacity(0.08)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.34),
                      blurRadius: 18,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Icon(
                            item.icon,
                            size: 17,
                            color: item.accent.withOpacity(0.95),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              item.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.94),
                                fontWeight: FontWeight.w900,
                                fontSize: 13.5,
                                height: 1.0,
                              ),
                            ),
                          ),
                          InkWell(
                            onTap: () => Navigator.of(context).pop(),
                            borderRadius: BorderRadius.circular(10),
                            child: Padding(
                              padding: const EdgeInsets.all(4),
                              child: Icon(
                                Icons.close_rounded,
                                size: 17,
                                color: Colors.white.withOpacity(0.56),
                              ),
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 10),

                      if (isCalendarNote || isCalendarReminder) ...[
                        _detailTile(
                          icon: isCalendarReminder
                              ? Icons.notifications_active_rounded
                              : Icons.sticky_note_2_rounded,
                          label: 'Type',
                          value: isCalendarReminder ? 'Reminder' : 'Note',
                          valueColor: isCalendarReminder
                              ? const Color(0xFF60A5FA)
                              : const Color(0xFFFB7185),
                        ),

                        if (titleText.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          _detailTile(
                            icon: Icons.title_rounded,
                            label: 'Title',
                            value: titleText,
                          ),
                        ],

                        if (noteText.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          _detailTile(
                            icon: Icons.notes_rounded,
                            label: 'Text',
                            value: noteText,
                          ),
                        ],

                        if (isCalendarReminder) ...[
                          const SizedBox(height: 8),
                          _detailTile(
                            icon: Icons.schedule_rounded,
                            label: 'Reminder',
                            value: fmtIso(reminderAt),
                            valueColor: const Color(0xFF60A5FA),
                          ),
                        ],

                        const SizedBox(height: 8),
                        _detailTile(
                          icon: Icons.event_rounded,
                          label: 'Created',
                          value: warningDate,
                        ),
                      ] else ...[
                        _compactDetailRow(
                          icon: Icons.person_outline_rounded,
                          label: 'Name',
                          value: name.isEmpty ? '—' : name,
                        ),

                        _compactDetailRow(
                          icon: Icons.alternate_email_rounded,
                          label: 'Email',
                          value: email.isEmpty ? '—' : email,
                        ),

                        _compactDetailRow(
                          icon: Icons.event_rounded,
                          label: 'Date',
                          value: warningDate,
                        ),

                        if (balance != null)
                          _compactDetailRow(
                            icon: Icons.attach_money_rounded,
                            label: 'Balance',
                            value: '\$${(balance as num).toStringAsFixed(2)}',
                            valueColor: AppPalette.green,
                          ),

                        if (type.isNotEmpty)
                          _compactDetailRow(
                            icon: Icons.info_outline_rounded,
                            label: 'Type',
                            value: type,
                          ),

                        if (accessMode.isNotEmpty)
                          _compactDetailRow(
                            icon: Icons.lock_outline_rounded,
                            label: 'Access',
                            value: accessMode,
                          ),

                        if (startsToday != null)
                          _compactDetailRow(
                            icon: Icons.repeat_rounded,
                            label: 'Starts',
                            value: '$startsToday',
                          ),

                        if (workedMinutes != null)
                          _compactDetailRow(
                            icon: Icons.schedule_rounded,
                            label: 'Worked',
                            value: workedText(),
                          ),
                      ]
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
      transitionBuilder: (_, animation, __, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
        );

        return FadeTransition(
          opacity: curved,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.97, end: 1.0).animate(curved),
            child: child,
          ),
        );
      },
    );
  }


  Widget _compactDetailRow({
    required IconData icon,
    required String label,
    required String value,
    Color? valueColor,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF32343C),
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: Colors.white.withOpacity(0.06)),
      ),
      child: Row(
        children: [
          Icon(
            icon,
            size: 15,
            color: Colors.white.withOpacity(0.46),
          ),
          const SizedBox(width: 8),

          SizedBox(
            width: 58,
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Colors.white.withOpacity(0.56),
                fontWeight: FontWeight.w700,
                fontSize: 11,
                height: 1.0,
              ),
            ),
          ),

          const SizedBox(width: 10),

          Expanded(
            child: Align(
              alignment: Alignment.centerRight,
              child: Text(
                value,
                textAlign: TextAlign.right,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: valueColor ?? Colors.white.withOpacity(0.92),
                  fontWeight: FontWeight.w800,
                  fontSize: 12,
                  height: 1.0,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  bool _isHiddenByDb(_WarningItem item) {
    final row = _dbState[item.warningKey];
    if (row == null) return false;

    final now = DateTime.now().toUtc();

    final ackExp = _dt(row['ack_expires_at']);
    if (ackExp != null && ackExp.isAfter(now)) return true;

    final mutedUntil = _dt(row['muted_until']);
    if (mutedUntil != null && mutedUntil.isAfter(now)) return true;

    final mutedForever = row['muted_forever'] == true;
    final type = _typeFromKey(item.warningKey);

    if (mutedForever && type != 'unpaid_14d') return true;

    return false;
  }

  Widget _detailTile({
    required IconData icon,
    required String label,
    required String value,
    Color? valueColor,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.035),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: Row(
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.05),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              icon,
              size: 16,
              color: Colors.white.withOpacity(0.72),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: AppPalette.textSoft.withOpacity(0.78),
                fontWeight: FontWeight.w800,
                fontSize: 11.5,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: valueColor ?? AppPalette.textMain.withOpacity(0.95),
                fontWeight: FontWeight.w900,
                fontSize: 12.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _loadDbStateForKeys(List<String> keys) async {
    if (keys.isEmpty) return;
    if (_loadingDb) return;

    _loadingDb = true;
    final supa = Supabase.instance.client;

    try {
      final rows = await supa
          .from('admin_warning_state')
          .select('warning_key, ack_expires_at, muted_until, muted_forever')
          .eq('admin_id', widget.adminId)
          .inFilter('warning_key', keys);

      if (!mounted) return;

      setState(() {
        _dbState.clear();
        for (final r in List<Map<String, dynamic>>.from(rows)) {
          final key = (r['warning_key'] ?? '').toString();
          if (key.isNotEmpty) {
            _dbState[key] = r;
          }
        }
      });
    } catch (_) {
    } finally {
      _loadingDb = false;
    }
  }

  Future<void> _restoreAllHiddenWarnings() async {
    final supa = Supabase.instance.client;

    final hiddenNow = _allItems().where((i) {
      return _ackedLocal.contains(i.warningKey) || _isHiddenByDb(i);
    }).toList();

    if (hiddenNow.isEmpty) return;

    try {
      await _restoreFx.forward();
      await _restoreFx.reverse();

      for (final item in hiddenNow) {
        await supa.rpc(
          'admin_undo_warning',
          params: {
            'p_warning_key': item.warningKey,
          },
        );
      }

      if (!mounted) return;

      setState(() {
        for (final item in hiddenNow) {
          _ackedLocal.remove(item.warningKey);
        }
        _index = 0;
      });

      await _loadDbStateForKeys(
          _allItems().map((e) => e.warningKey).toList()
      );

      AppToast.success('All warnings restored');
    } catch (e) {
      AppToast.error('Restore failed: $e');
    }
  }

  @override
  void initState() {
    super.initState();
    _bgSeed = Random().nextInt(0x7fffffff);
    _bgShuffled = [..._warningBgPool]..shuffle(Random(_bgSeed));

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _reloadAllWarnings();
    });

    _calendarWarningsTimer = Timer.periodic(const Duration(seconds: 30), (_) async {
      if (!mounted) return;
      await _reloadAllWarnings();
    });
  }

  @override
  void didUpdateWidget(covariant _FooterWarningsBar oldWidget) {
    super.didUpdateWidget(oldWidget);

    final newKeys = _allItems().map((e) => e.warningKey).toList();
    final oldKeys = oldWidget.items.map((e) => e.warningKey).toList();

    if (oldWidget.adminId != widget.adminId ||
        newKeys.join('|') != oldKeys.join('|')) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _loadDbStateForKeys(newKeys);
      });
    }

    if (_index >= _allItems().length) _index = 0;
  }

  Future<void> _openWarningActionsSheet(
      BuildContext context,
      _WarningItem item,
      ) async {
    final supa = Supabase.instance.client;
    final type = _typeFromKey(item.warningKey);
    final canForever = type != 'unpaid_14d';

    Future<void> applyAndHideLocal(Future<void> Function() action) async {
      if (!mounted) return;

      // ✅ сразу прячем warning в UI
      setState(() {
        _ackedLocal.add(item.warningKey);
        _index = 0;
      });

      try {
        // ✅ потом сохраняем в БД
        await action();

        // ✅ потом обновляем состояние из БД
        await _loadDbStateForKeys(
            _allItems().map((e) => e.warningKey).toList()
        );

        if (!mounted) return;
        AppToast.success('Done');
      } catch (e) {
        // ❌ если БД не сохранила — возвращаем warning обратно
        if (!mounted) return;
        setState(() {
          _ackedLocal.remove(item.warningKey);
        });

        AppToast.error('Action failed: $e');
      }
    }

    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetContext) {
        return ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
            child: Container(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 16),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    AppPalette.cardTop,
                    AppPalette.cardBottom,
                  ],
                ),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
                border: Border.all(
                  color: AppPalette.cardBorder.withOpacity(0.55),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.50),
                    blurRadius: 26,
                    offset: const Offset(0, -10),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 44,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.18),
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Icon(
                        item.icon,
                        color: item.accent,
                        size: 24,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          item.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.92),
                            fontWeight: FontWeight.w900,
                            fontSize: 14,
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: () {
                          FocusScope.of(sheetContext).unfocus();
                          Navigator.pop(sheetContext);
                        },
                        icon: Icon(
                          Icons.close_rounded,
                          color: Colors.white.withOpacity(0.65),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      item.message,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.55),
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                        height: 1.25,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Divider(color: Colors.white.withOpacity(0.08), height: 1),
                  const SizedBox(height: 12),

                  _actionTile(
                    icon: Icons.check_circle_rounded,
                    color: AppPalette.green,
                    title: 'Hide for 24 hours',
                    subtitle: 'It may come back later',
                    onTap: () async {
                      Navigator.pop(sheetContext);
                      await applyAndHideLocal(() => supa.rpc(
                        'admin_ack_warning',
                        params: {
                          'p_warning_key': item.warningKey,
                          'p_minutes': 1440,
                        },
                      ));
                    },
                  ),
                  const SizedBox(height: 10),

                  _actionTile(
                    icon: Icons.notifications_off_rounded,
                    color: AppPalette.orange,
                    title: 'Mute for 2 hours',
                    subtitle: 'Temporarily hide',
                    onTap: () async {
                      Navigator.pop(sheetContext);
                      await applyAndHideLocal(() => supa.rpc(
                        'admin_mute_warning',
                        params: {
                          'p_warning_key': item.warningKey,
                          'p_minutes': 120,
                        },
                      ));
                    },
                  ),
                  const SizedBox(height: 8),

                  _actionTile(
                    icon: Icons.notifications_off_rounded,
                    color: AppPalette.orange,
                    title: 'Mute for 8 hours',
                    subtitle: 'Temporarily hide',
                    onTap: () async {
                      Navigator.pop(sheetContext);
                      await applyAndHideLocal(() => supa.rpc(
                        'admin_mute_warning',
                        params: {
                          'p_warning_key': item.warningKey,
                          'p_minutes': 480,
                        },
                      ));
                    },
                  ),
                  const SizedBox(height: 8),

                  _actionTile(
                    icon: Icons.notifications_off_rounded,
                    color: AppPalette.orange,
                    title: 'Mute for 24 hours',
                    subtitle: 'Temporarily hide',
                    onTap: () async {
                      Navigator.pop(sheetContext);
                      await applyAndHideLocal(() => supa.rpc(
                        'admin_mute_warning',
                        params: {
                          'p_warning_key': item.warningKey,
                          'p_minutes': 1440,
                        },
                      ));
                    },
                  ),

                  if (canForever) ...[
                    const SizedBox(height: 12),
                    Divider(color: Colors.white.withOpacity(0.08), height: 1),
                    const SizedBox(height: 12),
                    _actionTile(
                      icon: Icons.block_rounded,
                      color: AppPalette.red,
                      title: 'Mute forever',
                      subtitle: 'Hidden until Undo',
                      onTap: () async {
                        Navigator.pop(sheetContext);
                        await applyAndHideLocal(() => supa.rpc(
                          'admin_mute_forever_warning',
                          params: {
                            'p_warning_key': item.warningKey,
                            'p_value': true,
                          },
                        ));
                      },
                    ),
                  ],
                  const SizedBox(height: 6),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _actionTile({
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.035),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withOpacity(0.08)),
        ),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: color.withOpacity(0.14),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: color.withOpacity(0.22)),
              ),
              child: Icon(icon, color: color, size: 18),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.90),
                      fontWeight: FontWeight.w900,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.55),
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
              color: Colors.white.withOpacity(0.25),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final sourceItems = _allItems();

    final visible = sourceItems
        .where((i) => !_ackedLocal.contains(i.warningKey))
        .where((i) => !_isHiddenByDb(i))
        .toList();

    final hiddenNow = sourceItems.where((i) {
      return _ackedLocal.contains(i.warningKey) || _isHiddenByDb(i);
    }).toList();

    if (_index >= visible.length) _index = 0;

    final has = visible.isNotEmpty;
    final bgBase = has
        ? _bgShuffled[_index % _bgShuffled.length]
        : Color.lerp(AppPalette.cardBottom, Colors.black, 0.12)!;

    final canRestoreAll = visible.isEmpty && hiddenNow.isNotEmpty;


    final warningBadgeText = has
        ? (visible.length == 1 ? 'WARNING' : 'WARNINGS')
        : 'ALL GOOD';

    final warningBadgeColor = has ? AppPalette.orange : AppPalette.green;

    return AnimatedBuilder(
      animation: _restoreFx,
      builder: (context, child) {
        final glow = _panelGlow.value;

        return Transform.scale(
          scale: _panelScale.value,
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.topCenter,
            children: [
              Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Color.lerp(bgBase, Colors.white, 0.04)!,
                      Color.lerp(bgBase, Colors.black, 0.06)!,
                    ],
                  ),
                  borderRadius: const BorderRadius.only(
                    bottomLeft: Radius.circular(22),
                    bottomRight: Radius.circular(22),
                  ),
                  border: Border(
                    top: BorderSide(
                      color: Color.lerp(
                        Colors.white.withOpacity(0.06),
                        AppPalette.green.withOpacity(0.30),
                        glow,
                      )!,
                    ),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: AppPalette.green.withOpacity(0.10 * glow),
                      blurRadius: 18 + (18 * glow),
                      spreadRadius: 0.5 + (0.8 * glow),
                      offset: const Offset(0, 0),
                    ),
                  ],
                ),
                padding: const EdgeInsets.fromLTRB(16, 18, 16, 8),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: visible.isEmpty
                          ? _OkFooter(
                        canRestoreAll: canRestoreAll,
                        onRestoreAll:
                        canRestoreAll ? _restoreAllHiddenWarnings : null,
                      )
                          : _FooterWarningsCarousel(
                        items: visible,
                        expanded: _expanded,
                        autoplay: !_expanded,
                        onIndexChanged: (i) {
                          if (!mounted) return;
                          if (i == _index) return;

                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            if (!mounted) return;
                            setState(() {
                              _index = i;
                              _expanded = false;
                            });
                            _stopAutoCollapse();
                          });
                        },
                        onAck: (item) async {
                          if (mounted) {
                            setState(() {
                              _expanded = false;
                            });
                          }
                          _stopAutoCollapse();
                          await _openWarningActionsSheet(context, item);
                        },
                        onDetails: (item) async {
                          await _showWarningDetailsDialog(context, item);
                        },
                        onDismiss: (item) async {
                          if (!mounted) return;
                          setState(() {
                            _ackedLocal.add(item.warningKey);
                            _index = 0;
                            _expanded = false;
                          });
                          _stopAutoCollapse();
                        },
                      ),
                    ),
                    if (has) ...[
                      const SizedBox(height: 8),
                      InkWell(
                        onTap: () {
                          setState(() {
                            _expanded = !_expanded;
                          });

                          if (_expanded) {
                            _restartAutoCollapse();
                          } else {
                            _stopAutoCollapse();
                          }
                        },
                        borderRadius: BorderRadius.circular(999),
                        child: SizedBox(
                          width: double.infinity,
                          height: 18,
                          child: Center(
                            child: Icon(
                              _expanded
                                  ? Icons.keyboard_arrow_up_rounded
                                  : Icons.keyboard_arrow_down_rounded,
                              size: 18,
                              color: Colors.white.withOpacity(0.42),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Positioned(
                top: -10,
                child: IgnorePointer(
                  child: Container(
                    padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
                    decoration: BoxDecoration(
                      color: AppPalette.cardBottom,
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        color: warningBadgeColor.withOpacity(0.24),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.20),
                          blurRadius: 10,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Text(
                      warningBadgeText,
                      style: TextStyle(
                        color: warningBadgeColor.withOpacity(0.94),
                        fontSize: 10.2,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.0,
                        height: 1.0,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// =================== WORKERS LIST ===================


class _WorkersListCard extends StatefulWidget {
  final List<Map<String, dynamic>> workers;
  final void Function(BuildContext context, Map<String, dynamic> worker) onOpenWorker;

  const _WorkersListCard({
    required this.workers,
    required this.onOpenWorker,
  });

  @override
  State<_WorkersListCard> createState() => _WorkersListCardState();
}

class _WorkersListCardState extends State<_WorkersListCard> {
  bool _showRestricted = false;
  bool _switching = false;

  Future<void> _toggleMode() async {
    if (_switching) return;

    setState(() => _switching = true);

    // 1. показываем preparation
    await Future.delayed(const Duration(milliseconds: 260));
    if (!mounted) return;

    // 2. переключаем данные, пока loading еще виден
    setState(() {
      _showRestricted = !_showRestricted;
    });

    // 3. небольшая пауза, потом показываем новые карточки
    await Future.delayed(const Duration(milliseconds: 140));
    if (!mounted) return;

    setState(() => _switching = false);
  }


  double _num(Object? v) => (v is num) ? v.toDouble() : 0.0;

  String _modeOf(Map<String, dynamic> w) {
    final raw = (w['access_mode'] ?? 'active').toString().toLowerCase().trim();
    if (raw == 'readonly' || raw == 'viewonly' || raw == 'view_only') {
      return 'view_only';
    }
    return raw;
  }

  bool _isRestricted(Map<String, dynamic> w) {
    final mode = _modeOf(w);
    return mode == 'view_only' || mode == 'suspended';
  }

  int _priority(Map<String, dynamic> w, double unpaid) {
    final mode = _modeOf(w);
    final onShift = w['on_shift'] == true;

    if (_showRestricted) {
      if (mode == 'view_only') return 0;
      if (mode == 'suspended') return 1;
      return 2;
    }

    if (onShift) return 0;
    if (unpaid > 0) return 1;
    return 2;
  }

  List<Map<String, dynamic>> _buildVisibleWorkers() {
    final list = widget.workers.where((w) {
      if (_showRestricted) {
        return _isRestricted(w);
      } else {
        return !_isRestricted(w);
      }
    }).toList();

    list.sort((a, b) {
      final ua = _num(a['unpaid_total']);
      final ub = _num(b['unpaid_total']);

      final pa = _priority(a, ua);
      final pb = _priority(b, ub);

      if (pa != pb) return pa.compareTo(pb);

      final ea = ((a['name'] ?? a['email'] ?? '')).toString().toLowerCase();
      final eb = ((b['name'] ?? b['email'] ?? '')).toString().toLowerCase();
      return ea.compareTo(eb);
    });

    return list;
  }

  @override
  Widget build(BuildContext context) {
    final visibleWorkers = _buildVisibleWorkers();

    return _SolidPanel(
      loading: false,
      header: _WorkersPanelHeader(
        showRestricted: _showRestricted,
        switching: _switching,
        onToggle: _toggleMode,
      ),
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 320),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeInCubic,
        transitionBuilder: (child, animation) {
          final fade = CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
          );

          final slide = Tween<Offset>(
            begin: const Offset(0, 0.035),
            end: Offset.zero,
          ).animate(fade);

          return FadeTransition(
            opacity: fade,
            child: SlideTransition(
              position: slide,
              child: SizeTransition(
                sizeFactor: fade,
                axisAlignment: -1,
                child: child,
              ),
            ),
          );
        },
        child: _switching
            ? const _WorkersLoadingState(
          key: ValueKey('workers_loading'),
        )
            : KeyedSubtree(
          key: ValueKey(_showRestricted ? 'restricted' : 'active'),
          child: Column(
            children: [
              if (visibleWorkers.isEmpty)
                _WorkersEmptyState(
                  restrictedMode: _showRestricted,
                )
              else
                for (int i = 0; i < visibleWorkers.length; i++) ...[
                  _WorkerReveal(
                    index: i,
                    token: _showRestricted ? 'restricted' : 'active',
                    child: _WorkerRow(
                      worker: visibleWorkers[i],
                      mode: _modeOf(visibleWorkers[i]),
                      unpaid: _num(visibleWorkers[i]['unpaid_total']),
                      onTap: () {
                        try {
                          widget.onOpenWorker(context, visibleWorkers[i]);
                        } catch (e, st) {
                          debugPrint('onOpenWorker ERROR: $e');
                          debugPrint('$st');
                        }
                      },
                    ),
                  ),
                  if (i != visibleWorkers.length - 1)
                    const SizedBox(height: 10),
                ],
            ],
          ),
        ),
      ),

    );
  }
}

class _WorkersEmptyState extends StatelessWidget {
  final bool restrictedMode;

  const _WorkersEmptyState({
    super.key,
    required this.restrictedMode,
  });

  @override
  Widget build(BuildContext context) {
    final icon = restrictedMode
        ? Icons.visibility_off_rounded
        : Icons.group_off_rounded;

    final title = restrictedMode
        ? 'No restricted workers yet'
        : 'No workers yet';

    final subtitle = restrictedMode
        ? 'There are no suspended or view-only workers.'
        : 'Create the first worker to get started.';

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 4, bottom: 6),
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 22),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            AppPalette.cardTop,
            AppPalette.cardBottom,
          ],
        ),
        border: Border.all(
          color: AppPalette.cardBorder.withOpacity(0.42),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Colors.white.withOpacity(0.08),
                  Colors.white.withOpacity(0.03),
                ],
              ),
              border: Border.all(
                color: Colors.white.withOpacity(0.10),
              ),
            ),
            child: Icon(
              icon,
              size: 30,
              color: Colors.white.withOpacity(0.78),
            ),
          ),
          const SizedBox(height: 18),
          Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white.withOpacity(0.95),
              fontSize: 17,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppPalette.textSoft.withOpacity(0.82),
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }
}

class _WorkersPanelHeader extends StatelessWidget {
  final bool showRestricted;
  final bool switching;
  final VoidCallback onToggle;

  const _WorkersPanelHeader({
    required this.showRestricted,
    required this.switching,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 38,
      child: Row(
        children: [
          Icon(
            Icons.groups_2_rounded,
            size: 18,
            color: AppPalette.textSoft.withOpacity(0.85),
          ),
          const SizedBox(width: 8),
          Text(
            'Workers',
            style: TextStyle(
              color: AppPalette.textMain.withOpacity(0.92),
              fontWeight: FontWeight.w900,
              fontSize: 14,
              letterSpacing: 0.2,
            ),
          ),
          const Spacer(),
          _WorkersToggleButton(
            showRestricted: showRestricted,
            switching: switching,
            onTap: onToggle,
          ),
        ],
      ),
    );
  }
}

class _WorkersToggleButton extends StatelessWidget {
  final bool showRestricted;
  final bool switching;
  final VoidCallback onTap;

  const _WorkersToggleButton({
    required this.showRestricted,
    required this.switching,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      ignoring: switching,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(11),
          child: AnimatedOpacity(
            duration: const Duration(milliseconds: 180),
            opacity: switching ? 0.88 : 1,
            child: Ink(
              width: 124, // fixed size
              height: 28,
              decoration: BoxDecoration(
                color: const Color(0xFF4A4D56).withOpacity(0.82),
                borderRadius: BorderRadius.circular(11),
                border: Border.all(
                  color: Colors.white.withOpacity(0.09),
                  width: 1,
                ),
              ),
              child: Center(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 220),
                  switchInCurve: Curves.easeOutCubic,
                  switchOutCurve: Curves.easeInCubic,
                  transitionBuilder: (child, animation) {
                    return FadeTransition(
                      opacity: animation,
                      child: SlideTransition(
                        position: Tween<Offset>(
                          begin: const Offset(0, 0.12),
                          end: Offset.zero,
                        ).animate(animation),
                        child: child,
                      ),
                    );
                  },
                  child: switching
                      ? Row(
                    key: const ValueKey('loading_btn'),
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 12,
                        height: 12,
                        child: CircularProgressIndicator(
                          strokeWidth: 1.7,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            Colors.white.withOpacity(0.82),
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'Loading',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.86),
                          fontWeight: FontWeight.w800,
                          fontSize: 10.6,
                          letterSpacing: 0.02,
                          height: 1.0,
                        ),
                      ),
                    ],
                  )
                      : Row(
                    key: ValueKey(
                      showRestricted ? 'active_btn' : 'restricted_btn',
                    ),
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        showRestricted
                            ? Icons.check_circle_outline_rounded
                            : Icons.visibility_off_rounded,
                        size: 13,
                        color: Colors.white.withOpacity(0.82),
                      ),
                      const SizedBox(width: 5),
                      Text(
                        showRestricted ? 'Active' : 'Restricted',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.86),
                          fontWeight: FontWeight.w800,
                          fontSize: 10.8,
                          letterSpacing: 0.02,
                          height: 1.0,
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
  }
}

class _WorkersLoadingState extends StatelessWidget {
  const _WorkersLoadingState({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 1.8,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    Colors.white.withOpacity(0.70),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                'Preparing workers...',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.68),
                  fontWeight: FontWeight.w800,
                  fontSize: 12,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          const _WorkersGhostCard(),
          const SizedBox(height: 10),
          const _WorkersGhostCard(),
        ],
      ),
    );
  }
}

class _WorkersGhostCard extends StatelessWidget {
  const _WorkersGhostCard({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 136),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        color: Colors.white.withOpacity(0.035),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              height: 18,
              width: double.infinity,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                color: Colors.white.withOpacity(0.07),
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Container(

                  width: 54,
                  height: 54,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(18),
                    color: Colors.white.withOpacity(0.07),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    children: [
                      Container(
                        height: 18,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(10),
                          color: Colors.white.withOpacity(0.07),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        height: 18,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(10),
                          color: Colors.white.withOpacity(0.05),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        height: 18,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(10),
                          color: Colors.white.withOpacity(0.05),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _WorkerReveal extends StatelessWidget {
  final int index;
  final String token;
  final Widget child;

  const _WorkerReveal({
    super.key,
    required this.index,
    required this.token,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      key: ValueKey('$token-$index'),
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: 220 + (index * 60)),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) {
        return Opacity(
          opacity: value,
          child: Transform.translate(
            offset: Offset(0, (1 - value) * 18),
            child: Transform.scale(
              scale: 0.985 + (value * 0.015),
              child: child,
            ),
          ),
        );
      },
      child: child,
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

    if (mode == 'view_only') {
      return Row(
        children: [
          Icon(
            Icons.visibility_rounded,
            size: 18,
            color: AppPalette.orange.withOpacity(0.95),
          ),
          const SizedBox(width: 8),
          Text(
            'LIMITED ACCESS',
            style: TextStyle(
              color: AppPalette.orange.withOpacity(0.95),
              fontWeight: FontWeight.w900,
              fontSize: 12.3,
              letterSpacing: 0.18,
            ),
          ),
          const Spacer(),
          Text(
            'view',
            style: TextStyle(
              color: AppPalette.orange.withOpacity(0.92),
              fontWeight: FontWeight.w900,
              fontSize: 11.8,
              letterSpacing: 0.16,
            ),
          ),
          const SizedBox(width: 6),
          Icon(
            Icons.chevron_right_rounded,
            size: 22,
            color: Colors.white.withOpacity(0.32),
          ),
        ],
      );
    }

    if (mode == 'suspended') {
      return Row(
        children: [
          Icon(
            Icons.block_rounded,
            size: 18,
            color: AppPalette.red.withOpacity(0.95),
          ),
          const SizedBox(width: 8),
          Text(
            'SUSPENDED',
            style: TextStyle(
              color: AppPalette.red.withOpacity(0.95),
              fontWeight: FontWeight.w900,
              fontSize: 12.5,
              letterSpacing: 0.22,
            ),
          ),
          const Spacer(),
          Text(
            'blocked',
            style: TextStyle(
              color: AppPalette.red.withOpacity(0.92),
              fontWeight: FontWeight.w900,
              fontSize: 11.5,
              letterSpacing: 0.16,
            ),
          ),
          const SizedBox(width: 6),
          Icon(
            Icons.chevron_right_rounded,
            size: 22,
            color: Colors.white.withOpacity(0.28),
          ),
        ],
      );
    }

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
        onShift
            ? const _OnShiftTextPulse()
            : Text(
          'OFF SHIFT',
          style: TextStyle(
            color: Colors.white.withOpacity(0.92),
            fontWeight: FontWeight.w900,
            fontSize: 12.5,
            letterSpacing: 0.2,
          ),
        ),
        const Spacer(),
        Text(
          'active',
          style: TextStyle(
            color: AppPalette.green.withOpacity(0.95),
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
    final viewOnlyAt = worker['view_only_at'];
    final firstWorkAt = worker['first_work_at'];
    final suspendedAt = worker['suspended_at'];
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
                    _WorkerFooter(
                      mode: mode,
                      lastWorkedAt: lastWorkedAt,
                      viewOnlyAt: viewOnlyAt,
                      firstWorkAt: firstWorkAt,
                      suspendedAt: suspendedAt,
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

  String _dayKey(DateTime d) {
    final x = DateTime(d.year, d.month, d.day);
    return DateFormat('yyyy-MM-dd').format(x);
  }

  String _selectedDayKey() {
    final d = start ?? DateTime.now();
    return DateFormat('yyyy-MM-dd').format(DateTime(d.year, d.month, d.day));
  }

  List<Map<String, dynamic>> _selectedDayMarks() {
    return _itemsByDay[_selectedDayKey()] ?? const [];
  }

  bool _selectedDayHasNote() {
    return _selectedDayMarks().any((e) => (e['kind'] ?? '').toString() == 'note');
  }

  bool _selectedDayHasPending() {
    return _selectedDayMarks().any((e) =>
    (e['kind'] ?? '').toString() == 'reminder' &&
        e['is_done'] != true &&
        e['is_cancelled'] != true &&
        e['is_sent'] != true);
  }

  bool _selectedDayHasTriggered() {
    return _selectedDayMarks().any((e) =>
    (e['kind'] ?? '').toString() == 'reminder' &&
        e['is_sent'] == true &&
        e['is_done'] != true &&
        e['is_cancelled'] != true);
  }

  bool _selectedDayHasCancelled() {
    return _selectedDayMarks().any((e) =>
    (e['kind'] ?? '').toString() == 'reminder' &&
        e['is_cancelled'] == true);
  }

  bool _selectedDayAllDone() {
    final items = _selectedDayMarks();
    if (items.isEmpty) return false;
    return items.every((e) => e['is_done'] == true);
  }

  Color? _selectedDayBadgeColor() {
    if (_selectedDayHasNote()) return const Color(0xFFFB7185);
    if (_selectedDayHasPending()) return const Color(0xFF60A5FA);
    if (_selectedDayHasTriggered()) return const Color(0xFFF59E0B);
    if (_selectedDayHasCancelled()) return const Color(0xFF9CA3AF);
    if (_selectedDayAllDone()) return const Color(0xFF34D399);
    return null;
  }

  Future<void> _loadMonthItems() async {
    final adminId = _db.auth.currentUser?.id;
    if (adminId == null) return;

    setState(() => _calendarItemsLoading = true);

    try {
      final from = DateTime(_calendarMonth.year, _calendarMonth.month, 1);
      final to = DateTime(_calendarMonth.year, _calendarMonth.month + 1, 1);

      final rows = await _db
          .from('admin_calendar_items')
          .select()
          .eq('admin_id', adminId)
          .gte('entry_date', DateFormat('yyyy-MM-dd').format(from))
          .lt('entry_date', DateFormat('yyyy-MM-dd').format(to))
          .order('entry_date')
          .order('created_at');

      final map = <String, List<Map<String, dynamic>>>{};

      for (final row in List<Map<String, dynamic>>.from(rows)) {
        final key = (row['entry_date'] ?? '').toString();
        map.putIfAbsent(key, () => []);
        map[key]!.add(row);
      }

      if (!mounted) return;

      setState(() {
        _itemsByDay = map;
      });

      if (start != null) {
        await _loadSelectedDayItems(start!);
      }
    } finally {
      if (mounted) {
        setState(() => _calendarItemsLoading = false);
      }
    }
  }

  Future<void> _saveCalendarItem({
    required DateTime day,
    required String kind, // note | reminder
    required String title,
    required String noteText,
    required bool notifyInApp,
    TimeOfDay? reminderTime,
  }) async {
    final adminId = _db.auth.currentUser?.id;
    if (adminId == null) return;

    DateTime? reminderAt;
    if (kind == 'reminder' && reminderTime != null) {
      reminderAt = DateTime(
        day.year,
        day.month,
        day.day,
        reminderTime.hour,
        reminderTime.minute,
      ).toUtc();
    }

    await _db.from('admin_calendar_items').insert({
      'admin_id': adminId,
      'entry_date': DateFormat('yyyy-MM-dd').format(day),
      'kind': kind,
      'title': title.trim(),
      'note_text': noteText.trim(),
      'reminder_at': reminderAt?.toIso8601String(),
      'notify_in_app': notifyInApp,
    });

    await _loadMonthItems();
    await _loadSelectedDayItems(day);
  }

  Future<void> _toggleCalendarItemDone(Map<String, dynamic> item, DateTime day) async {
    final id = (item['id'] ?? '').toString();
    if (id.isEmpty) return;

    await _db
        .from('admin_calendar_items')
        .update({
      'is_done': !(item['is_done'] == true),
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    })
        .eq('id', id);

    await _loadMonthItems();
    await _loadSelectedDayItems(day);
  }

  Future<void> _deleteCalendarItem(String id, DateTime day) async {
    if (id.isEmpty) return;

    await _db
        .from('admin_calendar_items')
        .delete()
        .eq('id', id);

    await _loadMonthItems();
    await _loadSelectedDayItems(day);
  }

  Future<void> _updateCalendarItem({
    required String id,
    required DateTime day,
    required String kind,
    required String title,
    required String noteText,
    required bool notifyInApp,
    required bool isCancelled,
    TimeOfDay? reminderTime,
  }) async {
    if (id.isEmpty) return;

    DateTime? reminderAt;
    if (kind == 'reminder' && reminderTime != null) {
      reminderAt = DateTime(
        day.year,
        day.month,
        day.day,
        reminderTime.hour,
        reminderTime.minute,
      ).toUtc();
    }

    await _db
        .from('admin_calendar_items')
        .update({
      'kind': kind,
      'title': title.trim(),
      'note_text': noteText.trim(),
      'reminder_at': kind == 'reminder'
          ? reminderAt?.toIso8601String()
          : null,
      'notify_in_app': notifyInApp,
      'is_cancelled': isCancelled,
      'is_sent': false,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    })
        .eq('id', id);

    await _loadMonthItems();
    await _loadSelectedDayItems(day);
  }

  Future<void> _openEditCalendarItemSheet(
      Map<String, dynamic> item,
      DateTime day,
      ) async {
    final titleCtrl = TextEditingController(
      text: (item['title'] ?? '').toString(),
    );
    final noteCtrl = TextEditingController(
      text: (item['note_text'] ?? '').toString(),
    );

    String kind = (item['kind'] ?? 'note').toString();
    bool notifyInApp = item['notify_in_app'] == true;
    bool isCancelled = item['is_cancelled'] == true;

    TimeOfDay? pickedTime;
    final reminderRaw = item['reminder_at'];
    if (reminderRaw != null) {
      try {
        final dt = DateTime.parse(reminderRaw.toString()).toLocal();
        pickedTime = TimeOfDay(hour: dt.hour, minute: dt.minute);
      } catch (_) {}
    }

    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setLocal) {
            return ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                child: Container(
                  padding: EdgeInsets.fromLTRB(
                    14,
                    10,
                    14,
                    MediaQuery.of(context).viewInsets.bottom + 16,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E1C22),
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
                    border: Border.all(color: Colors.white.withOpacity(0.08)),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 44,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.18),
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                      const SizedBox(height: 12),

                      Row(
                        children: [
                          const Icon(
                            Icons.edit_calendar_rounded,
                            color: Color(0xFFF59E0B),
                            size: 22,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Edit item',
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.92),
                                fontWeight: FontWeight.w900,
                                fontSize: 14,
                              ),
                            ),
                          ),
                          IconButton(
                            onPressed: () {
                              FocusScope.of(sheetContext).unfocus();
                              Navigator.pop(sheetContext);
                            },
                            icon: Icon(
                              Icons.close_rounded,
                              color: Colors.white.withOpacity(0.65),
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 10),

                      _KindSegmentedSwitch(
                        value: kind,
                        onChanged: (v) => setLocal(() => kind = v),
                      ),

                      const SizedBox(height: 12),

                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(26),
                          gradient: const LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              Color(0xFF232B39),
                              Color(0xFF1C2431),
                              Color(0xFF141B26),
                            ],
                          ),
                          border: Border.all(
                            color: Colors.white.withOpacity(0.07),
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.28),
                              blurRadius: 18,
                              offset: const Offset(0, 10),
                            ),
                            BoxShadow(
                              color: const Color(0xFF5EA8FF).withOpacity(0.05),
                              blurRadius: 10,
                              spreadRadius: 0.5,
                            ),
                            BoxShadow(
                              color: Colors.white.withOpacity(0.035),
                              blurRadius: 8,
                              spreadRadius: -4,
                              offset: const Offset(0, -2),
                            ),
                          ],
                        ),
                        child: Column(
                          children: [
                            TextField(
                              controller: titleCtrl,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                              ),
                              decoration: const InputDecoration(
                                hintText: 'Title',
                                hintStyle: TextStyle(
                                  color: Color(0xFF8B93A3),
                                  fontWeight: FontWeight.w700,
                                ),
                                contentPadding: EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 14,
                                ),
                                prefixIcon: Icon(
                                  Icons.title_rounded,
                                  size: 19,
                                  color: Color(0xFFF5C542),
                                ),
                                border: InputBorder.none,
                                enabledBorder: InputBorder.none,
                                focusedBorder: InputBorder.none,
                              ),
                            ),

                            Container(
                              height: 1,
                              margin: const EdgeInsets.symmetric(horizontal: 6),
                              color: Colors.white.withOpacity(0.06),
                            ),

                            TextField(
                              controller: noteCtrl,
                              minLines: 4,
                              maxLines: 5,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                              ),
                              decoration: const InputDecoration(
                                hintText: 'Write note...',
                                alignLabelWithHint: true,
                                hintStyle: TextStyle(
                                  color: Color(0xFF8B93A3),
                                  fontWeight: FontWeight.w700,
                                ),
                                contentPadding: EdgeInsets.fromLTRB(12, 16, 12, 14),
                                prefixIcon: Padding(
                                  padding: EdgeInsets.only(left: 12, right: 10, bottom: 56),
                                  child: Icon(
                                    Icons.edit_note_rounded,
                                    size: 20,
                                    color: Colors.white,
                                  ),
                                ),
                                prefixIconConstraints: BoxConstraints(
                                  minWidth: 0,
                                  minHeight: 0,
                                ),
                                border: InputBorder.none,
                                enabledBorder: InputBorder.none,
                                focusedBorder: InputBorder.none,
                              ),
                            ),

                            if (kind == 'reminder') ...[
                              Container(
                                height: 1,
                                margin: const EdgeInsets.symmetric(horizontal: 6),
                                color: Colors.white.withOpacity(0.06),
                              ),
                              InkWell(
                                borderRadius: BorderRadius.circular(16),
                                onTap: () async {
                                  final result = await _pickBlueTime(sheetContext, pickedTime);
                                  if (result != null) {
                                    setLocal(() => pickedTime = result);
                                  }
                                },
                                child: Container(
                                  height: 56,
                                  padding: const EdgeInsets.symmetric(horizontal: 12),
                                  child: Row(
                                    children: [
                                      const Icon(
                                        Icons.schedule_rounded,
                                        size: 19,
                                        color: Color(0xFF7C8CFF),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Text(
                                          pickedTime == null
                                              ? '--:--'
                                              : '${pickedTime!.hourOfPeriod == 0 ? 12 : pickedTime!.hourOfPeriod.toString().padLeft(2, '0')}:${pickedTime!.minute.toString().padLeft(2, '0')} ${pickedTime!.period == DayPeriod.am ? 'AM' : 'PM'}',
                                          style: TextStyle(
                                            color: pickedTime == null
                                                ? const Color(0xFF8B93A3)
                                                : Colors.white,
                                            fontWeight: FontWeight.w900,
                                            fontSize: 18,
                                            letterSpacing: 0.4,
                                          ),
                                        ),
                                      ),
                                      const Icon(
                                        Icons.edit_rounded,
                                        size: 18,
                                        color: Colors.orange,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),

                      const SizedBox(height: 10),

                      if (kind == 'reminder') ...[
                        Row(
                          children: [
                            Expanded(
                              child: InkWell(
                                onTap: () => setLocal(() => isCancelled = !isCancelled),
                                borderRadius: BorderRadius.circular(14),
                                child: Container(
                                  height: 42,
                                  padding: const EdgeInsets.symmetric(horizontal: 12),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withOpacity(0.035),
                                    borderRadius: BorderRadius.circular(14),
                                    border: Border.all(color: Colors.white.withOpacity(0.08)),
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(
                                        isCancelled
                                            ? Icons.notifications_off_rounded
                                            : Icons.notifications_active_rounded,
                                        size: 18,
                                        color: isCancelled
                                            ? AppPalette.red
                                            : AppPalette.orange,
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          isCancelled ? 'Cancelled' : 'Active reminder',
                                          style: TextStyle(
                                            color: Colors.white.withOpacity(0.86),
                                            fontWeight: FontWeight.w800,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                      ],

                      SizedBox(
                        width: double.infinity,
                        height: 46,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF7A2E45),
                            foregroundColor: Colors.white,
                            elevation: 0,
                            shadowColor: Colors.transparent,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(18),
                            ),
                            side: BorderSide(
                              color: Colors.white.withOpacity(0.10),
                            ),
                          ).copyWith(
                            overlayColor: WidgetStatePropertyAll(
                              Colors.white.withOpacity(0.05),
                            ),
                          ),
                          onPressed: () async {
                            await _updateCalendarItem(
                              id: (item['id'] ?? '').toString(),
                              day: day,
                              kind: kind,
                              title: titleCtrl.text,
                              noteText: noteCtrl.text,
                              notifyInApp: notifyInApp,
                              isCancelled: kind == 'reminder' ? isCancelled : false,
                              reminderTime: kind == 'reminder' ? pickedTime : null,
                            );

                            if (!mounted) return;
                            FocusScope.of(sheetContext).unfocus();
                            Navigator.pop(sheetContext);
                          },
                          child: const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.check_rounded,
                                size: 18,
                                color: Colors.white,
                              ),
                              SizedBox(width: 8),
                              Text(
                                'Update',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ],
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
      },
    );
  }



  Future<void> _cancelCalendarReminder(String id, DateTime day) async {
    if (id.isEmpty) return;

    await _db
        .from('admin_calendar_items')
        .update({
      'is_cancelled': true,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    })
        .eq('id', id);

    await _loadMonthItems();
    await _loadSelectedDayItems(day);
  }

  String _calendarItemStatus(Map<String, dynamic> item) {
    final kind = (item['kind'] ?? '').toString();
    final isCancelled = item['is_cancelled'] == true;
    final isSent = item['is_sent'] == true;
    final isDone = item['is_done'] == true;

    if (kind != 'reminder') {
      return isDone ? 'Done' : 'Note';
    }

    if (isCancelled) return 'Cancelled';
    if (isDone) return 'Done';
    if (isSent) return 'Triggered';
    return 'Pending';
  }

  DateTime? _hiddenStatusAnchor(Map<String, dynamic> item) {
    final status = _calendarItemStatus(item);

    Object? raw;

    if (status == 'Triggered') {
      raw = item['updated_at'] ?? item['reminder_at'];
    } else if (status == 'Cancelled' || status == 'Done') {
      raw = item['updated_at'];
    } else {
      return null;
    }

    if (raw == null) return null;

    try {
      return DateTime.parse(raw.toString()).toUtc();
    } catch (_) {
      return null;
    }
  }

  bool _shouldHideAfter4Hours(Map<String, dynamic> item) {
    final status = _calendarItemStatus(item);

    if (status != 'Triggered' && status != 'Cancelled' && status != 'Done') {
      return false;
    }

    final anchor = _hiddenStatusAnchor(item);
    if (anchor == null) return false;

    return DateTime.now().toUtc().difference(anchor) >= const Duration(hours: 4);
  }

  Color _calendarItemStatusColor(Map<String, dynamic> item) {
    final status = _calendarItemStatus(item);

    switch (status) {
      case 'Cancelled':
        return AppPalette.red;
      case 'Triggered':
        return AppPalette.orange;
      case 'Done':
        return AppPalette.green;
      case 'Pending':
        return const Color(0xFF60A5FA);
      default:
        return const Color(0xFFFB7185);
    }
  }

  IconData _calendarItemStatusIcon(Map<String, dynamic> item) {
    final status = _calendarItemStatus(item);

    switch (status) {
      case 'Cancelled':
        return Icons.notifications_off_rounded;
      case 'Triggered':
        return Icons.notifications_active_rounded;
      case 'Done':
        return Icons.check_circle_rounded;
      case 'Pending':
        return Icons.schedule_rounded;
      default:
        return Icons.sticky_note_2_rounded;
    }
  }

  int _calendarItemSortWeight(Map<String, dynamic> item) {
    final status = _calendarItemStatus(item);

    switch (status) {
      case 'Pending':
        return 0;
      case 'Note':
        return 1;
      case 'Triggered':
        return 2;
      case 'Cancelled':
        return 3;
      case 'Done':
        return 4;
      default:
        return 9;
    }
  }

  List<Map<String, dynamic>> _sortedDayItems() {
    final list = List<Map<String, dynamic>>.from(_selectedDayItems)
        .where((item) => !_shouldHideAfter4Hours(item))
        .toList();

    list.sort((a, b) {
      final wa = _calendarItemSortWeight(a);
      final wb = _calendarItemSortWeight(b);

      if (wa != wb) return wa.compareTo(wb);

      final ra = (a['reminder_at'] ?? '').toString();
      final rb = (b['reminder_at'] ?? '').toString();
      return ra.compareTo(rb);
    });

    return list;
  }

  BoxDecoration _convexDarkField({
    Color base = const Color(0xFF161A22),
    Color border = const Color(0xFF2B3140),
  }) {
    return BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Color.lerp(base, Colors.white, 0.045)!,
          base,
          Color.lerp(base, Colors.black, 0.10)!,
        ],
      ),
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: border),
      boxShadow: [
        BoxShadow(
          color: Colors.white.withOpacity(0.04),
          blurRadius: 8,
          spreadRadius: -6,
          offset: const Offset(0, -2),
        ),
        BoxShadow(
          color: Colors.black.withOpacity(0.34),
          blurRadius: 14,
          spreadRadius: -8,
          offset: const Offset(0, 8),
        ),
      ],
    );
  }

  Future<void> _openDaySheet(DateTime day) async {
    final titleCtrl = TextEditingController();
    final noteCtrl = TextEditingController();

    String kind = 'note';
    bool notifyInApp = true;
    TimeOfDay? pickedTime;

    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setLocal) {
            final bottomInset = MediaQuery.of(context).viewInsets.bottom;
            final sorted = _sortedDayItems();

            return ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
              child: AnimatedPadding(
                duration: const Duration(milliseconds: 120),
                padding: EdgeInsets.only(bottom: bottomInset),
                child: Container(
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        AppPalette.cardTop,
                        AppPalette.cardBottom,
                      ],
                    ),
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(28),
                    ),
                    border: Border.all(
                      color: AppPalette.cardBorder.withOpacity(0.55),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.50),
                        blurRadius: 26,
                        offset: const Offset(0, -10),
                      ),
                    ],
                  ),
                  child: SafeArea(
                    top: false,
                    child: SingleChildScrollView(
                      keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 18),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Center(
                              child: Container(
                                width: 42,
                                height: 4,
                                decoration: BoxDecoration(
                                  color: const Color(0xFF555861),
                                  borderRadius: BorderRadius.circular(999),
                                ),
                              ),
                            ),
                            const SizedBox(height: 14),

                            Row(
                              children: [
                                const Icon(
                                  Icons.calendar_today_rounded,
                                  size: 18,
                                  color: Color(0xFFF59E0B),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    DateFormat('EEE • MMM d • yyyy').format(day),
                                    style: const TextStyle(
                                      color: Color(0xFFF3F4F6),
                                      fontWeight: FontWeight.w900,
                                      fontSize: 14.5,
                                    ),
                                  ),
                                ),
                                InkWell(
                                  onTap: () => Navigator.pop(sheetContext),
                                  borderRadius: BorderRadius.circular(10),
                                  child: const Padding(
                                    padding: EdgeInsets.all(4),
                                    child: Icon(
                                      Icons.close_rounded,
                                      color: Color(0xFFB6BBC7),
                                      size: 22,
                                    ),
                                  ),
                                ),
                              ],
                            ),

                            const SizedBox(height: 14),

                            Container(
                              height: 1,
                              width: double.infinity,
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.centerLeft,
                                  end: Alignment.centerRight,
                                  colors: [
                                    Colors.transparent,
                                    const Color(0xFFF59E0B).withOpacity(0.55),
                                    Colors.white.withOpacity(0.10),
                                    Colors.transparent,
                                  ],
                                ),
                              ),
                            ),

                            const SizedBox(height: 12),

                            _KindSegmentedSwitch(
                              value: kind,
                              onChanged: (v) => setLocal(() => kind = v),
                            ),

                            const SizedBox(height: 12),

                            Divider(
                              color: const Color(0xFF343742),
                              height: 20,
                            ),

                            if (sorted.isEmpty)
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF23262E),
                                  borderRadius: BorderRadius.circular(22),
                                  border: Border.all(
                                    color: Colors.white.withOpacity(0.07),
                                  ),
                                ),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Container(
                                      width: 38,
                                      height: 38,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: Colors.white.withOpacity(0.03),
                                        border: Border.all(
                                          color: Colors.white.withOpacity(0.16),
                                        ),
                                      ),
                                      child: Icon(
                                        Icons.check_circle_outline_rounded,
                                        color: Colors.white.withOpacity(0.65),
                                        size: 22,
                                      ),
                                    ),
                                    const SizedBox(height: 10),
                                    const Text(
                                      'No items yet',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        color: Color(0xFFF3F4F6),
                                        fontWeight: FontWeight.w900,
                                        fontSize: 15,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      'Create the first item for this day.',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        color: Colors.white.withOpacity(0.55),
                                        fontWeight: FontWeight.w700,
                                        fontSize: 11.5,
                                        height: 1.25,
                                      ),
                                    ),
                                  ],
                                ),
                              )
                            else
                              Builder(
                                builder: (_) {
                                  const double oneCardHeight = 144;
                                  const double gap = 12;

                                  final bool shouldScroll = sorted.length > 2;
                                  final double listHeight =
                                  sorted.length == 1 ? oneCardHeight : (oneCardHeight * 2) + gap;

                                  return SizedBox(
                                    height: listHeight,
                                    child: ListView.separated(
                                      padding: EdgeInsets.zero,
                                      physics: shouldScroll
                                          ? const ClampingScrollPhysics()
                                          : const NeverScrollableScrollPhysics(),
                                      itemCount: sorted.length,
                                      separatorBuilder: (_, __) => const SizedBox(height: gap),
                                      itemBuilder: (context, index) {
                                        final item = sorted[index];

                                        final itemId = (item['id'] ?? '').toString().trim();
                                        final kindRaw = (item['kind'] ?? '').toString().trim().toLowerCase();

                                        final isReminder = kindRaw == 'reminder';
                                        final isNote = !isReminder;
                                        final isCancelled = item['is_cancelled'] == true;
                                        final isDone = item['is_done'] == true;

                                        final rawTitle = (item['title'] ?? '').toString().trim();
                                        final rawBody = (item['note_text'] ?? '').toString().trim();
                                        final reminderAt = (item['reminder_at'] ?? '').toString().trim();

                                        final title = rawTitle.isEmpty
                                            ? (isReminder ? 'Reminder' : 'Note')
                                            : rawTitle;

                                        String timeText = '';
                                        if (isReminder && reminderAt.isNotEmpty) {
                                          try {
                                            timeText = DateFormat('HH:mm').format(
                                              DateTime.parse(reminderAt).toLocal(),
                                            );
                                          } catch (_) {
                                            timeText = '';
                                          }
                                        }

                                        return _DaySheetItemCard(
                                          isNote: isNote,
                                          leadingIcon: isReminder
                                              ? Icons.notifications_rounded
                                              : Icons.sticky_note_2_rounded,
                                          leadingColor: isReminder
                                              ? const Color(0xFFFFB020)
                                              : const Color(0xFFFB7185),
                                          title: title,
                                          timeText: timeText,
                                          status: _calendarItemStatus(item),
                                          statusIcon: _calendarItemStatusIcon(item),
                                          statusColor: _calendarItemStatusColor(item),
                                          body: rawBody,
                                          done: isDone,
                                          showCancel: isReminder && !isCancelled,
                                          onEdit: () async {
                                            Navigator.pop(sheetContext);
                                            await _openEditCalendarItemSheet(item, day);
                                          },
                                          onDone: () async {
                                            await _toggleCalendarItemDone(item, day);
                                            if (!mounted) return;
                                            Navigator.pop(sheetContext);
                                            await _openDaySheet(day);
                                          },
                                          onCancel: isReminder && !isCancelled
                                              ? () async {
                                            await _cancelCalendarReminder(itemId, day);
                                            if (!mounted) return;
                                            Navigator.pop(sheetContext);
                                            await _openDaySheet(day);
                                          }
                                              : null,
                                          onDelete: () async {
                                            await _deleteCalendarItem(itemId, day);
                                            if (!mounted) return;
                                            Navigator.pop(sheetContext);
                                            await _openDaySheet(day);
                                          },
                                        );
                                      },
                                    ),
                                  );
                                },
                              ),

                            const SizedBox(height: 4),

                            Divider(
                              color: const Color(0xFF343742),
                              height: 20,
                            ),

                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(26),
                                gradient: const LinearGradient(
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  colors: [
                                    Color(0xFF232B39),
                                    Color(0xFF1C2431),
                                    Color(0xFF141B26),
                                  ],
                                ),
                                border: Border.all(
                                  color: Colors.white.withOpacity(0.07),
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.28),
                                    blurRadius: 18,
                                    offset: const Offset(0, 10),
                                  ),
                                  BoxShadow(
                                    color: const Color(0xFF5EA8FF).withOpacity(0.05),
                                    blurRadius: 10,
                                    spreadRadius: 0.5,
                                  ),
                                  BoxShadow(
                                    color: Colors.white.withOpacity(0.035),
                                    blurRadius: 8,
                                    spreadRadius: -4,
                                    offset: const Offset(0, -2),
                                  ),
                                ],
                              ),
                              child: Column(
                                children: [
                                  TextField(
                                    controller: titleCtrl,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w800,
                                    ),
                                    decoration: const InputDecoration(
                                      hintText: 'Title',
                                      hintStyle: TextStyle(
                                        color: Color(0xFF8B93A3),
                                        fontWeight: FontWeight.w700,
                                      ),
                                      contentPadding: EdgeInsets.symmetric(
                                        horizontal: 12,
                                        vertical: 14,
                                      ),
                                      prefixIcon: Icon(
                                        Icons.title_rounded,
                                        size: 19,
                                        color: Color(0xFFF5C542),
                                      ),
                                      border: InputBorder.none,
                                      enabledBorder: InputBorder.none,
                                      focusedBorder: InputBorder.none,
                                    ),
                                  ),

                                  Container(
                                    height: 1,
                                    margin: const EdgeInsets.symmetric(horizontal: 6),
                                    color: Colors.white.withOpacity(0.06),
                                  ),

                                  TextField(
                                    controller: noteCtrl,
                                    minLines: 4,
                                    maxLines: 5,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w800,
                                    ),
                                    decoration: const InputDecoration(
                                      hintText: 'Write note...',
                                      alignLabelWithHint: true,
                                      hintStyle: TextStyle(
                                        color: Color(0xFF8B93A3),
                                        fontWeight: FontWeight.w700,
                                      ),
                                      contentPadding: EdgeInsets.fromLTRB(12, 16, 12, 14),
                                      prefixIcon: Padding(
                                        padding: EdgeInsets.only(left: 12, right: 10, bottom: 56),
                                        child: Icon(
                                          Icons.edit_note_rounded,
                                          size: 20,
                                          color: Colors.white,
                                        ),
                                      ),
                                      prefixIconConstraints: BoxConstraints(
                                        minWidth: 0,
                                        minHeight: 0,
                                      ),
                                      border: InputBorder.none,
                                      enabledBorder: InputBorder.none,
                                      focusedBorder: InputBorder.none,
                                    ),
                                  ),

                                  if (kind == 'reminder') ...[
                                    Container(
                                      height: 1,
                                      margin: const EdgeInsets.symmetric(horizontal: 6),
                                      color: Colors.white.withOpacity(0.06),
                                    ),
                                    InkWell(
                                      borderRadius: BorderRadius.circular(16),
                                      onTap: () async {
                                        final result = await _pickBlueTime(sheetContext, pickedTime);
                                        if (result != null) {
                                          setLocal(() => pickedTime = result);
                                        }
                                      },
                                      child: Container(
                                        height: 56,
                                        padding: const EdgeInsets.symmetric(horizontal: 12),
                                        child: Row(
                                          children: [
                                            const Icon(
                                              Icons.schedule_rounded,
                                              size: 19,
                                              color: Color(0xFF7C8CFF),
                                            ),
                                            const SizedBox(width: 12),
                                            Expanded(
                                              child: Text(
                                                pickedTime == null
                                                    ? '--:--'
                                                    : '${pickedTime!.hourOfPeriod == 0 ? 12 : pickedTime!.hourOfPeriod.toString().padLeft(2, '0')}:${pickedTime!.minute.toString().padLeft(2, '0')} ${pickedTime!.period == DayPeriod.am ? 'AM' : 'PM'}',
                                                style: TextStyle(
                                                  color: pickedTime == null
                                                      ? const Color(0xFF8B93A3)
                                                      : Colors.white,
                                                  fontWeight: FontWeight.w900,
                                                  fontSize: 18,
                                                  letterSpacing: 0.4,
                                                ),
                                              ),
                                            ),
                                            const Icon(
                                              Icons.edit_rounded,
                                              size: 18,
                                              color: Colors.orange,
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),

                            const SizedBox(height: 14),

                            SizedBox(
                              width: double.infinity,
                              height: 48,
                              child: ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF26906F),
                                  foregroundColor: Colors.white,
                                  elevation: 0,
                                  shadowColor: Colors.transparent,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(18),
                                  ),
                                  side: BorderSide(
                                    color: Colors.white.withOpacity(0.10),
                                  ),
                                ).copyWith(
                                  overlayColor: WidgetStatePropertyAll(
                                    Colors.white.withOpacity(0.05),
                                  ),
                                ),
                                onPressed: () async {
                                  await _saveCalendarItem(
                                    day: day,
                                    kind: kind,
                                    title: titleCtrl.text,
                                    noteText: noteCtrl.text,
                                    notifyInApp: notifyInApp,
                                    reminderTime: pickedTime,
                                  );

                                  if (!mounted) return;
                                  Navigator.pop(sheetContext);
                                },
                                child: const Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.save_rounded,
                                      size: 18,
                                      color: Colors.white,
                                    ),
                                    SizedBox(width: 8),
                                    Text(
                                      'Save',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w900,
                                      ),
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
          },
        );
      },
    );
  }

  Future<void> _loadSelectedDayItems(DateTime day) async {
    final key = _dayKey(day);

    if (!mounted) return;
    setState(() {
      _selectedDayItems = _itemsByDay[key] ?? [];
    });
  }

  Future<void> _loadInAppNotifications() async {
    final adminId = _db.auth.currentUser?.id;
    if (adminId == null) return;

    setState(() => _notificationsLoading = true);

    try {
      final rows = await _db
          .from('admin_in_app_notifications')
          .select()
          .eq('admin_id', adminId)
          .eq('is_read', false)
          .order('created_at', ascending: false)
          .limit(20);

      if (!mounted) return;

      setState(() {
        _inAppNotifications = List<Map<String, dynamic>>.from(rows);
      });
    } finally {
      if (mounted) {
        setState(() => _notificationsLoading = false);
      }
    }
  }

  Future<void> _markInAppNotificationRead(String id) async {
    if (id.isEmpty) return;

    await _db
        .from('admin_in_app_notifications')
        .update({'is_read': true})
        .eq('id', id);

    await _loadInAppNotifications();
  }

  final _db = Supabase.instance.client;

  DateTime _calendarMonth = DateTime(DateTime.now().year, DateTime.now().month, 1);
  bool _calendarItemsLoading = false;

  Map<String, List<Map<String, dynamic>>> _itemsByDay = {};
  List<Map<String, dynamic>> _selectedDayItems = [];

  List<Map<String, dynamic>> _inAppNotifications = [];
  bool _notificationsLoading = false;

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

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    _timeText = _nowHHmm();
    start = today;
    end = null;
    _calendarMonth = DateTime(today.year, today.month, 1);

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await PushTokenService().syncAdminPushToken();
      await _loadMonthItems();
      await _loadSelectedDayItems(today);

      if (!mounted) return;
      setState(() {});
    });

    _clockTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      final newText = _nowHHmm();
      if (!mounted) return;
      if (newText != _timeText) {
        setState(() => _timeText = newText);
      }
    });
  }

  @override
  void dispose() {
    _clockTimer?.cancel();
    super.dispose();
  }

  Future<void> _onSelectDate(DateTime picked) async {
    final day = DateTime(picked.year, picked.month, picked.day);

    setState(() {
      start = day;
      end = null;
      calendarOpen = false;
    });

    await _loadSelectedDayItems(day);

    if (!mounted) return;

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      await _openDaySheet(day);
    });
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
          badgeColor: _selectedDayBadgeColor(),
          onTap: () => setState(() => calendarOpen = !calendarOpen),
        ),

        const SizedBox(height: 10),

        AnimatedCrossFade(
          duration: const Duration(milliseconds: 220),
          crossFadeState: calendarOpen ? CrossFadeState.showFirst : CrossFadeState.showSecond,
          firstChild: Column(
            children: [
              _InlineCalendar(
                start: start,
                end: end,
                onPick: _onSelectDate,
                markedDays: _itemsByDay,
                visibleMonth: _calendarMonth,
                onMonthChanged: (month) async {
                  setState(() {
                    _calendarMonth = DateTime(month.year, month.month, 1);
                  });
                  await _loadMonthItems();
                  if (mounted) setState(() {});
                },
              ),

              const SizedBox(height: 8),

              if (_notificationsLoading)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.035),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.white.withOpacity(0.08)),
                  ),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 1.8,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            Colors.white.withOpacity(0.70),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        'Loading reminders...',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.72),
                          fontWeight: FontWeight.w800,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),

              if (!_notificationsLoading && _inAppNotifications.isNotEmpty) ...[
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.035),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: Colors.white.withOpacity(0.08)),
                  ),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.notifications_active_rounded,
                            size: 16,
                            color: AppPalette.orange,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Triggered reminders',
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.90),
                                fontWeight: FontWeight.w900,
                                fontSize: 12.5,
                              ),
                            ),
                          ),
                          Text(
                            '${_inAppNotifications.length}',
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.55),
                              fontWeight: FontWeight.w800,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),

                      for (final n in _inAppNotifications.take(3)) ...[
                        InkWell(
                          onTap: () async {
                            final id = (n['id'] ?? '').toString();
                            await _markInAppNotificationRead(id);
                          },
                          borderRadius: BorderRadius.circular(14),
                          child: Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.03),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: Colors.white.withOpacity(0.07)),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  width: 28,
                                  height: 28,
                                  decoration: BoxDecoration(
                                    color: AppPalette.orange.withOpacity(0.14),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Icon(
                                    Icons.notifications_rounded,
                                    size: 15,
                                    color: AppPalette.orange,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        (n['title'] ?? 'Reminder').toString(),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          color: Colors.white.withOpacity(0.92),
                                          fontWeight: FontWeight.w900,
                                          fontSize: 11.8,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        (n['body'] ?? '').toString(),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          color: Colors.white.withOpacity(0.62),
                                          fontWeight: FontWeight.w700,
                                          fontSize: 10.8,
                                          height: 1.2,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Icon(
                                  Icons.check_rounded,
                                  size: 17,
                                  color: Colors.white.withOpacity(0.35),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ],
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

class _InlineCalendar extends StatefulWidget {
  final DateTime? start;
  final DateTime? end;
  final void Function(DateTime day) onPick;
  final Map<String, List<Map<String, dynamic>>> markedDays;

  final DateTime visibleMonth;
  final ValueChanged<DateTime> onMonthChanged;

  const _InlineCalendar({
    super.key,
    required this.start,
    required this.end,
    required this.onPick,
    required this.markedDays,
    required this.visibleMonth,
    required this.onMonthChanged,
  });

  @override
  State<_InlineCalendar> createState() => _InlineCalendarState();
}

class _InlineCalendarState extends State<_InlineCalendar> {
  int _monthDirection = 1;

  bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  String _dayKey(DateTime d) {
    final x = DateTime(d.year, d.month, d.day);
    return DateFormat('yyyy-MM-dd').format(x);
  }

  bool _hasNote(DateTime d) {
    final items = widget.markedDays[_dayKey(d)] ?? const [];
    return items.any((e) => (e['kind'] ?? '').toString() == 'note');
  }

  bool _hasPendingReminder(DateTime d) {
    final items = widget.markedDays[_dayKey(d)] ?? const [];
    return items.any((e) =>
    (e['kind'] ?? '') == 'reminder' &&
        e['is_done'] != true &&
        e['is_cancelled'] != true &&
        e['is_sent'] != true);
  }

  bool _hasTriggeredReminder(DateTime d) {
    final items = widget.markedDays[_dayKey(d)] ?? const [];
    return items.any((e) =>
    (e['kind'] ?? '') == 'reminder' &&
        e['is_sent'] == true &&
        e['is_done'] != true &&
        e['is_cancelled'] != true);
  }

  bool _hasCancelledReminder(DateTime d) {
    final items = widget.markedDays[_dayKey(d)] ?? const [];
    return items.any((e) =>
    (e['kind'] ?? '') == 'reminder' &&
        e['is_cancelled'] == true);
  }

  bool _allDone(DateTime d) {
    final items = widget.markedDays[_dayKey(d)] ?? const [];
    if (items.isEmpty) return false;
    return items.every((e) => e['is_done'] == true);
  }

  List<Widget> _statusDots(DateTime d) {
    final dots = <Widget>[];

    void addDot(Color color) {
      if (dots.isNotEmpty) {
        dots.add(const SizedBox(width: 3));
      }
      dots.add(
        Container(
          width: 4,
          height: 4,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
        ),
      );
    }

    if (_hasNote(d)) addDot(const Color(0xFFFB7185));
    if (_hasPendingReminder(d)) addDot(const Color(0xFF60A5FA));
    if (_hasTriggeredReminder(d)) addDot(const Color(0xFFF59E0B));
    if (_hasCancelledReminder(d)) addDot(const Color(0xFF9CA3AF));
    if (_allDone(d)) addDot(const Color(0xFF34D399));

    return dots;
  }

  void _prevMonth() {
    setState(() => _monthDirection = -1);
    widget.onMonthChanged(
      DateTime(widget.visibleMonth.year, widget.visibleMonth.month - 1, 1),
    );
  }

  void _nextMonth() {
    setState(() => _monthDirection = 1);
    widget.onMonthChanged(
      DateTime(widget.visibleMonth.year, widget.visibleMonth.month + 1, 1),
    );
  }

  @override
  Widget build(BuildContext context) {
    final year = widget.visibleMonth.year;
    final month = widget.visibleMonth.month;

    final firstDay = DateTime(year, month, 1);
    final daysInMonth = DateUtils.getDaysInMonth(year, month);
    final firstWeekday = firstDay.weekday % 7;

    final cells = <Widget>[];

    for (int i = 0; i < firstWeekday; i++) {
      cells.add(const SizedBox.shrink());
    }

    for (int day = 1; day <= daysInMonth; day++) {
      final date = DateTime(year, month, day);
      final isSelected = widget.start != null && _isSameDay(widget.start!, date);

      final hasNote = _hasNote(date);
      final hasReminder =
          _hasPendingReminder(date) ||
              _hasTriggeredReminder(date) ||
              _hasCancelledReminder(date);
      final allDone = _allDone(date);

      cells.add(
        InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: () => widget.onPick(date),
          child: Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isSelected
                  ? Colors.white.withOpacity(0.08)
                  : Colors.transparent,
              border: isSelected
                  ? Border.all(color: Colors.white.withOpacity(0.14))
                  : null,
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  '$day',
                  style: TextStyle(
                    color: isSelected
                        ? Colors.white
                        : (hasNote || hasReminder || allDone)
                        ? Colors.white.withOpacity(0.96)
                        : Colors.white.withOpacity(0.88),
                    fontWeight: isSelected ? FontWeight.w900 : FontWeight.w800,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: _statusDots(date),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.10),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  DateFormat('MMMM yyyy').format(widget.visibleMonth),
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.92),
                    fontWeight: FontWeight.w900,
                    fontSize: 14,
                  ),
                ),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _MonthNavCapsuleButton(
                    icon: Icons.chevron_left_rounded,
                    onTap: _prevMonth,
                  ),
                  const SizedBox(width: 8),
                  Container(
                    width: 1,
                    height: 22,
                    color: Colors.white.withOpacity(0.10),
                  ),
                  const SizedBox(width: 8),
                  _MonthNavCapsuleButton(
                    icon: Icons.chevron_right_rounded,
                    onTap: _nextMonth,
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            height: 1,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: [
                  Colors.transparent,
                  Colors.white.withOpacity(0.05),
                  Colors.white.withOpacity(0.14),
                  Colors.white.withOpacity(0.05),
                  Colors.transparent,
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: const [
              Expanded(child: Center(child: Text('S', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w700)))),
              Expanded(child: Center(child: Text('M', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w700)))),
              Expanded(child: Center(child: Text('T', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w700)))),
              Expanded(child: Center(child: Text('W', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w700)))),
              Expanded(child: Center(child: Text('T', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w700)))),
              Expanded(child: Center(child: Text('F', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w700)))),
              Expanded(child: Center(child: Text('S', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w700)))),
            ],
          ),
          const SizedBox(height: 8),

          AnimatedSwitcher(
            duration: const Duration(milliseconds: 280),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            transitionBuilder: (child, animation) {
              final offsetAnimation = Tween<Offset>(
                begin: Offset(_monthDirection * 0.18, 0),
                end: Offset.zero,
              ).animate(
                CurvedAnimation(
                  parent: animation,
                  curve: Curves.easeOutCubic,
                ),
              );

              return FadeTransition(
                opacity: animation,
                child: SlideTransition(
                  position: offsetAnimation,
                  child: child,
                ),
              );
            },
            child: GridView.count(
              key: ValueKey('${widget.visibleMonth.year}-${widget.visibleMonth.month}'),
              crossAxisCount: 7,
              childAspectRatio: 0.88,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              children: cells,
            ),
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
                  Colors.white.withOpacity(0.05),
                  Colors.white.withOpacity(0.14),
                  Colors.white.withOpacity(0.05),
                  Colors.transparent,
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          const _CalendarLegendInline(),
        ],
      ),
    );
  }
}

class _DayActionCapsuleButton extends StatelessWidget {
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _DayActionCapsuleButton({
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 6),
        child: Icon(
          icon,
          size: 17,
          color: color,
        ),
      ),
    );
  }
}

class _DaySheetItemCard extends StatelessWidget {
  final bool isNote;
  final IconData leadingIcon;
  final Color leadingColor;
  final String title;
  final String timeText;
  final String status;
  final IconData statusIcon;
  final Color statusColor;
  final String body;
  final bool done;
  final bool showCancel;
  final VoidCallback onEdit;
  final VoidCallback onDone;
  final VoidCallback? onCancel;
  final VoidCallback onDelete;

  const _DaySheetItemCard({
    required this.isNote,
    required this.leadingIcon,
    required this.leadingColor,
    required this.title,
    required this.timeText,
    required this.status,
    required this.statusIcon,
    required this.statusColor,
    required this.body,
    required this.done,
    required this.showCancel,
    required this.onEdit,
    required this.onDone,
    required this.onDelete,
    this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    final headerText = isNote ? 'Note' : 'Reminder';

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF3A3D46),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: const Color(0xFF555A66),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.30),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
          BoxShadow(
            color: Colors.white.withOpacity(0.03),
            blurRadius: 2,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 9),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // HEADER
            Row(
              children: [
                Icon(
                  leadingIcon,
                  size: 18,
                  color: leadingColor,
                ),
                const SizedBox(width: 8),
                Text(
                  headerText,
                  style: const TextStyle(
                    color: Color(0xFFF3F4F6),
                    fontWeight: FontWeight.w900,
                    fontSize: 13.5,
                  ),
                ),
                const Spacer(),

                Container(
                  height: 34,
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFF2E3139),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: Colors.white.withOpacity(0.08),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _DayActionCapsuleButton(
                        icon: Icons.edit_rounded,
                        color: Colors.white.withOpacity(0.86),
                        onTap: onEdit,
                      ),
                      _DayActionCapsuleButton(
                        icon: done ? Icons.undo_rounded : Icons.check_rounded,
                        color: const Color(0xFF34D399),
                        onTap: onDone,
                      ),
                      if (showCancel && onCancel != null)
                        _DayActionCapsuleButton(
                          icon: Icons.notifications_off_rounded,
                          color: const Color(0xFFF59E0B),
                          onTap: onCancel!,
                        ),
                      _DayActionCapsuleButton(
                        icon: Icons.delete_outline_rounded,
                        color: const Color(0xFFFB7185),
                        onTap: onDelete,
                      ),
                    ],
                  ),
                ),
              ],
            ),

            const SizedBox(height: 8),

            Container(
              width: double.infinity,
              height: 1,
              color: const Color(0xFF5A5F6A),
            ),

            const SizedBox(height: 8),

            // TITLE
            Padding(
              padding: const EdgeInsets.only(left: 30),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 1),
                    child: Icon(
                      Icons.title_rounded,
                      size: 15,
                      color: Color(0xFFB8BEC9),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      title.isEmpty ? 'No title' : title,
                      style: const TextStyle(
                        color: Color(0xFFF3F4F6),
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                        height: 1.2,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            if (body.isNotEmpty) ...[
              const SizedBox(height: 8),

              // NOTE TEXT
              Padding(
                padding: const EdgeInsets.only(left: 30),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Padding(
                      padding: EdgeInsets.only(top: 1),
                      child: Icon(
                        Icons.notes_rounded,
                        size: 15,
                        color: Color(0xFFB8BEC9),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        body,
                        style: const TextStyle(
                          color: Color(0xFFD4D8E1),
                          fontWeight: FontWeight.w700,
                          fontSize: 12.4,
                          height: 1.25,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 10),

            // BOTTOM ROW
            Row(
              children: [
                if (timeText.isNotEmpty)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(left: 30),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.schedule_rounded,
                            size: 15,
                            color: Color(0xFFB8BEC9),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'At: $timeText',
                            style: const TextStyle(
                              color: Color(0xFFAEB4C0),
                              fontWeight: FontWeight.w800,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                else
                  const Spacer(),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _DaySheetOrderChip extends StatelessWidget {
  final String text;
  final Color color;

  const _DaySheetOrderChip({
    required this.text,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 24,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: color.withOpacity(0.11),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withOpacity(0.28)),
      ),
      child: Center(
        child: Text(
          text,
          style: TextStyle(
            color: color,
            fontWeight: FontWeight.w900,
            fontSize: 10.8,
            height: 1.0,
          ),
        ),
      ),
    );
  }
}

class _DaySheetModeButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool active;
  final Color activeColor;
  final VoidCallback onTap;

  const _DaySheetModeButton({
    required this.label,
    required this.icon,
    required this.active,
    required this.activeColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        height: 52,
        decoration: BoxDecoration(
          color: active
              ? const Color(0xFF30323C)
              : const Color(0xFF23242C),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: active
                ? const Color(0xFF505461)
                : const Color(0xFF3A3C46),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 17,
              color: active ? activeColor : const Color(0xFFE5E7EB),
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: const TextStyle(
                color: Color(0xFFF3F4F6),
                fontWeight: FontWeight.w900,
                fontSize: 13.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _KindSegmentedSwitch extends StatelessWidget {
  final String value; // note | reminder
  final ValueChanged<String> onChanged;
  final Color noteAccent;
  final Color reminderAccent;

  const _KindSegmentedSwitch({
    required this.value,
    required this.onChanged,
    this.noteAccent = const Color(0xFFFB7185),
    this.reminderAccent = const Color(0xFF60A5FA),
  });

  bool get _isNote => value == 'note';
  bool get _isReminder => value == 'reminder';

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 54,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF2B2E36),
            Color(0xFF1F222A),
          ],
        ),
        border: Border.all(
          color: Colors.white.withOpacity(0.08),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.32),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
          BoxShadow(
            color: Colors.white.withOpacity(0.03),
            blurRadius: 10,
            spreadRadius: -6,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: LayoutBuilder(
        builder: (context, c) {
          final segmentWidth = (c.maxWidth - 8) / 2;

          return Stack(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 280),
                curve: Curves.easeOutCubic,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(15),
                  child: Stack(
                    children: [
                      Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(15),
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            stops: const [0.0, 0.22, 0.62, 1.0],
                            colors: _isNote
                                ? [
                              noteAccent.withOpacity(0.34),
                              noteAccent.withOpacity(0.20),
                              const Color(0xFF4A4450).withOpacity(0.55),
                              const Color(0xFF2F333B),
                            ]
                                : [
                              const Color(0xFF2F333B),
                              const Color(0xFF444C59).withOpacity(0.55),
                              reminderAccent.withOpacity(0.18),
                              reminderAccent.withOpacity(0.30),
                            ],
                          ),
                          border: Border(
                            top: BorderSide(
                              color: Colors.white.withOpacity(0.18),
                              width: 1,
                            ),
                            left: BorderSide(
                              color: Colors.white.withOpacity(0.10),
                              width: 1,
                            ),
                            right: BorderSide(
                              color: Colors.black.withOpacity(0.24),
                              width: 1,
                            ),
                            bottom: BorderSide(
                              color: Colors.black.withOpacity(0.34),
                              width: 1,
                            ),
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.white.withOpacity(0.05),
                              blurRadius: 10,
                              spreadRadius: -6,
                              offset: const Offset(0, -2),
                            ),
                            BoxShadow(
                              color: (_isNote ? noteAccent : reminderAccent).withOpacity(0.10),
                              blurRadius: 16,
                              spreadRadius: -5,
                            ),
                            BoxShadow(
                              color: Colors.black.withOpacity(0.28),
                              blurRadius: 16,
                              spreadRadius: -8,
                              offset: const Offset(0, 8),
                            ),
                          ],
                        ),
                      ),

                      Positioned(
                        left: 8,
                        right: 8,
                        top: 5,
                        child: IgnorePointer(
                          child: Container(
                            height: 12,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(999),
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [
                                  Colors.white.withOpacity(0.18),
                                  Colors.white.withOpacity(0.07),
                                  Colors.transparent,
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),

                      Positioned(
                        left: 12,
                        right: 12,
                        bottom: 4,
                        child: IgnorePointer(
                          child: Container(
                            height: 10,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(999),
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [
                                  Colors.transparent,
                                  Colors.black.withOpacity(0.10),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              Row(
                children: [
                  Expanded(
                    child: _KindSegmentButton(
                      label: 'Note',
                      icon: Icons.sticky_note_2_rounded,
                      active: _isNote,
                      activeColor: noteAccent,
                      onTap: () => onChanged('note'),
                    ),
                  ),
                  Expanded(
                    child: _KindSegmentButton(
                      label: 'Reminder',
                      icon: Icons.notifications_active_rounded,
                      active: _isReminder,
                      activeColor: reminderAccent,
                      onTap: () => onChanged('reminder'),
                    ),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

class _KindSegmentButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool active;
  final Color activeColor;
  final VoidCallback onTap;

  const _KindSegmentButton({
    required this.label,
    required this.icon,
    required this.active,
    required this.activeColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final iconColor = active
        ? Colors.white
        : Colors.white.withOpacity(0.46);

    final textColor = active
        ? Colors.white
        : Colors.white.withOpacity(0.54);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(15),
        splashColor: activeColor.withOpacity(0.08),
        highlightColor: activeColor.withOpacity(0.04),
        child: SizedBox(
          height: 46,
          child: Center(
            child: AnimatedDefaultTextStyle(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              style: TextStyle(
                color: textColor,
                fontWeight: FontWeight.w900,
                fontSize: 13.2,
                letterSpacing: 0.05,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  AnimatedScale(
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeOutCubic,
                    scale: active ? 1.0 : 0.92,
                    child: Icon(
                      icon,
                      size: 18,
                      color: iconColor,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(label),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}


Future<TimeOfDay?> _pickBlueTime(BuildContext context, TimeOfDay? initial) async {
  TimeOfDay temp = initial ?? TimeOfDay.now();

  final result = await showModalBottomSheet<TimeOfDay>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (sheetContext) {
      return _BlueTimePickerSheet(
        initial: temp,
        onChanged: (v) => temp = v,
      );
    },
  );

  return result;
}

class _BlueTimePickerSheet extends StatefulWidget {
  final TimeOfDay initial;
  final ValueChanged<TimeOfDay> onChanged;

  const _BlueTimePickerSheet({
    required this.initial,
    required this.onChanged,
  });

  @override
  State<_BlueTimePickerSheet> createState() => _BlueTimePickerSheetState();
}

class _BlueTimePickerSheetState extends State<_BlueTimePickerSheet> {
  late int hour24;
  late int minute;

  @override
  void initState() {
    super.initState();
    hour24 = widget.initial.hour;
    minute = widget.initial.minute;
  }

  TimeOfDay _value() {
    return TimeOfDay(hour: hour24, minute: minute);
  }

  BoxDecoration _glassConvexWheelDecoration() {
    return BoxDecoration(
      borderRadius: BorderRadius.circular(18),
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        stops: const [0.0, 0.18, 0.55, 1.0],
        colors: [
          Colors.white.withOpacity(0.16),
          const Color(0xFF465066).withOpacity(0.82),
          const Color(0xFF273041).withOpacity(0.88),
          const Color(0xFF161C27).withOpacity(0.96),
        ],
      ),
      border: Border.all(
        color: Colors.white.withOpacity(0.18),
        width: 1.0,
      ),
      boxShadow: [
        BoxShadow(
          color: Colors.white.withOpacity(0.05),
          blurRadius: 10,
          spreadRadius: -6,
          offset: const Offset(0, -2),
        ),
        BoxShadow(
          color: const Color(0xFF60A5FA).withOpacity(0.10),
          blurRadius: 18,
          spreadRadius: -7,
        ),
        BoxShadow(
          color: Colors.black.withOpacity(0.30),
          blurRadius: 18,
          spreadRadius: -8,
          offset: const Offset(0, 10),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                AppPalette.cardTop,
                AppPalette.cardBottom,
              ],
            ),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            border: Border.all(
              color: AppPalette.cardBorder.withOpacity(0.55),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.50),
                blurRadius: 26,
                offset: const Offset(0, -10),
              ),
            ],
          ),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 44,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.18),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                const SizedBox(height: 14),

                Row(
                  children: [
                    Text(
                      'Select time',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.94),
                        fontWeight: FontWeight.w900,
                        fontSize: 15,
                      ),
                    ),
                    const Spacer(),
                    const Icon(
                      Icons.schedule_rounded,
                      color: Color(0xFF60A5FA),
                      size: 19,
                    ),
                  ],
                ),

                const SizedBox(height: 14),

                Container(
                  width: double.infinity,
                  height: 76,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF23242C),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: const Color(0xFF3A3C46)),
                  ),
                  child: Center(
                    child: Text(
                      '${hour24.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        fontSize: 24,
                        letterSpacing: 0.8,
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 14),

                SizedBox(
                  height: 230,
                  child: Row(
                    children: [
                      Expanded(
                        child: Container(
                          margin: const EdgeInsets.only(right: 8),
                          decoration: _glassConvexWheelDecoration(),
                          child: Column(
                            children: [
                              Padding(
                                padding: const EdgeInsets.only(top: 12, bottom: 6),
                                child: Text(
                                  'Hour',
                                  style: TextStyle(
                                    color: Colors.white.withOpacity(0.60),
                                    fontWeight: FontWeight.w800,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                              Expanded(
                                child: CupertinoPicker(
                                  scrollController: FixedExtentScrollController(
                                    initialItem: hour24,
                                  ),
                                  itemExtent: 40,
                                  onSelectedItemChanged: (i) {
                                    setState(() => hour24 = i);
                                    widget.onChanged(_value());
                                  },
                                  children: List.generate(
                                    24,
                                        (i) => Center(
                                      child: Text(
                                        i.toString().padLeft(2, '0'),
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 20,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      Expanded(
                        child: Container(
                          margin: const EdgeInsets.only(left: 8),
                          decoration: _glassConvexWheelDecoration(),
                          child: Column(
                            children: [
                              Padding(
                                padding: const EdgeInsets.only(top: 12, bottom: 6),
                                child: Text(
                                  'Minute',
                                  style: TextStyle(
                                    color: Colors.white.withOpacity(0.60),
                                    fontWeight: FontWeight.w800,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                              Expanded(
                                child: CupertinoPicker(
                                  scrollController: FixedExtentScrollController(
                                    initialItem: minute,
                                  ),
                                  itemExtent: 40,
                                  onSelectedItemChanged: (i) {
                                    setState(() => minute = i);
                                    widget.onChanged(_value());
                                  },
                                  children: List.generate(
                                    60,
                                        (i) => Center(
                                      child: Text(
                                        i.toString().padLeft(2, '0'),
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 20,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ),
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

                const SizedBox(height: 16),

                Row(
                  children: [
                    Expanded(
                      child: SizedBox(
                        height: 52,
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            backgroundColor: const Color(0xFF262B35),
                            side: const BorderSide(color: Color(0xFF3A4250)),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(18),
                            ),
                          ),
                          onPressed: () => Navigator.pop(context),
                          icon: Icon(
                            Icons.close_rounded,
                            color: Colors.white.withOpacity(0.72),
                          ),
                          label: Text(
                            'Cancel',
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.86),
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: SizedBox(
                        height: 52,
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF26906F),
                            foregroundColor: Colors.white,
                            elevation: 0,
                            shadowColor: Colors.transparent,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(18),
                            ),
                            side: BorderSide(
                              color: Colors.white.withOpacity(0.10),
                            ),
                          ).copyWith(
                            overlayColor: WidgetStatePropertyAll(
                              Colors.white.withOpacity(0.05),
                            ),
                          ),
                          onPressed: () => Navigator.pop(context, _value()),
                          icon: const Icon(
                            Icons.check_circle_rounded,
                            size: 18,
                            color: Colors.white,
                          ),
                          label: const Text(
                            'Apply',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w900,
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
    );
  }
}

class _MonthNavCapsuleButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _MonthNavCapsuleButton({
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Container(
          width: 32,
          height: 28,
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.035),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: Colors.white.withOpacity(0.10),
            ),
          ),
          child: Icon(
            icon,
            size: 18,
            color: Colors.white.withOpacity(0.82),
          ),
        ),
      ),
    );
  }
}

class _CalendarLegendInline extends StatelessWidget {
  const _CalendarLegendInline();

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: const [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            _LegendPlainItem(color: Color(0xFFFB7185), text: 'Note'),
            SizedBox(width: 14),
            _LegendPlainItem(color: Color(0xFF60A5FA), text: 'Pending'),
            SizedBox(width: 14),
            _LegendPlainItem(color: Color(0xFFF59E0B), text: 'Triggered'),
          ],
        ),
        SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            _LegendPlainItem(color: Color(0xFF9CA3AF), text: 'Cancelled'),
            SizedBox(width: 14),
            _LegendPlainItem(color: Color(0xFF34D399), text: 'Done'),
          ],
        ),
      ],
    );
  }
}

class _LegendPlainItem extends StatelessWidget {
  final Color color;
  final String text;

  const _LegendPlainItem({
    required this.color,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 6),
        Text(
          text,
          style: TextStyle(
            color: Colors.white.withOpacity(0.70),
            fontWeight: FontWeight.w800,
            fontSize: 11.5,
          ),
        ),
      ],
    );
  }
}

class _LegendChip extends StatelessWidget {
  final Color color;
  final String text;

  const _LegendChip({
    super.key,
    required this.color,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.04),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withOpacity(0.10)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 7),
          Text(
            text,
            style: TextStyle(
              color: AppPalette.textSoft.withOpacity(0.82),
              fontWeight: FontWeight.w800,
              fontSize: 11,
            ),
          ),
        ],
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
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 14),
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
  final String mode;
  final Object? lastWorkedAt;
  final Object? viewOnlyAt;
  final Object? firstWorkAt;
  final Object? suspendedAt;

  const _WorkerFooter({
    required this.mode,
    required this.lastWorkedAt,
    this.viewOnlyAt,
    this.firstWorkAt,
    this.suspendedAt,
  });

  String _fmtShort(Object? v) {
    if (v == null) return '—';
    try {
      final dt = DateTime.parse(v.toString()).toLocal();
      return DateFormat('EEE, MMM d').format(dt);
    } catch (_) {
      return v.toString();
    }
  }

  String _fmtLong(Object? v) {
    if (v == null) return '—';
    try {
      final dt = DateTime.parse(v.toString()).toLocal();
      return DateFormat('d MMM yyyy').format(dt);
    } catch (_) {
      return v.toString();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isViewOnly = mode == 'view_only';
    final isSuspended = mode == 'suspended';

    final leftIcon = isSuspended
        ? Icons.info_outline_rounded
        : isViewOnly
        ? Icons.visibility_rounded
        : Icons.history_rounded;

    final leftText = isSuspended
        ? 'Worked'
        : isViewOnly
        ? 'View only since'
        : 'Last work';

    final rightText = isSuspended
        ? '${_fmtLong(firstWorkAt)} → ${_fmtLong(suspendedAt)}'
        : isViewOnly
        ? _fmtShort(viewOnlyAt)
        : _fmtShort(lastWorkedAt);

    return ClipRRect(
      borderRadius: const BorderRadius.only(
        bottomLeft: Radius.circular(22),
        bottomRight: Radius.circular(22),
      ),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.02),
          border: Border(
            top: BorderSide(color: Colors.white.withOpacity(0.08)),
          ),
          borderRadius: const BorderRadius.only(
            bottomLeft: Radius.circular(22),
            bottomRight: Radius.circular(22),
          ),
        ),
        child: Row(
          children: [
            Icon(
              leftIcon,
              size: 16,
              color: Colors.white.withOpacity(0.38),
            ),
            const SizedBox(width: 8),
            Text(
              leftText,
              style: TextStyle(
                color: Colors.white.withOpacity(0.62),
                fontWeight: FontWeight.w800,
                fontSize: 12,
              ),
            ),
            const Spacer(),
            Text(
              rightText,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Colors.white.withOpacity(0.64),
                fontWeight: FontWeight.w900,
                fontSize: isSuspended ? 11.8 : 12.5,
              ),
            ),
          ],
        ),
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

class _CapsuleBadgePulse extends StatefulWidget {
  final Color color;
  final double size;

  const _CapsuleBadgePulse({
    super.key,
    required this.color,
    this.size = 10,
  });

  @override
  State<_CapsuleBadgePulse> createState() => _CapsuleBadgePulseState();
}

class _CapsuleBadgePulseState extends State<_CapsuleBadgePulse>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 950),
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
        final t = _c.value;

        final scale = 0.92 + (t * 0.16);
        final glowOpacity = 0.18 + (t * 0.22);
        final blur = 4.0 + (t * 7.0);
        final spread = 0.2 + (t * 0.6);

        return SizedBox(
          width: widget.size + 2,
          height: widget.size + 2,
          child: Center(
            child: Transform.scale(
              scale: scale,
              child: Container(
                width: widget.size,
                height: widget.size,
                decoration: BoxDecoration(
                  color: widget.color,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: widget.color.withOpacity(glowOpacity),
                      blurRadius: blur,
                      spreadRadius: spread,
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
}

class _TimeDateCapsule extends StatelessWidget {
  final String timeText;
  final String dateText;
  final bool open;
  final VoidCallback onTap;
  final Color? badgeColor;

  const _TimeDateCapsule({
    required this.timeText,
    required this.dateText,
    required this.open,
    required this.onTap,
    this.badgeColor,
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
              style: TextStyle(
                color: AppPalette.textMain.withOpacity(0.80),
                fontWeight: FontWeight.w800,
                fontSize: 13.2,
                height: 1.0,
                letterSpacing: 0.1,
              ),
            ),

            const SizedBox(width: 12),

            Container(
              width: 1,
              height: 18,
              color: Colors.white.withOpacity(0.10),
            ),

            const SizedBox(width: 12),

            Icon(Icons.calendar_month_rounded, color: AppPalette.orange.withOpacity(0.95), size: 18),
            const SizedBox(width: 10),

            Expanded(
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      dateText,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppPalette.textMain,
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                        height: 1.0,
                      ),
                    ),
                  ),

                  const SizedBox(width: 8),

                  SizedBox(
                    width: 14,
                    child: Center(
                      child: badgeColor != null
                          ? _CapsuleBadgePulse(
                        color: badgeColor!,
                        size: 10,
                      )
                          : null,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(width: 8),
            Icon(
              open ? Icons.expand_less_rounded : Icons.expand_more_rounded,
              color: Colors.white.withOpacity(0.45),
              size: 20,
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

class _OnShiftTextPulse extends StatefulWidget {
  const _OnShiftTextPulse({super.key});

  @override
  State<_OnShiftTextPulse> createState() => _OnShiftTextPulseState();
}

class _OnShiftTextPulseState extends State<_OnShiftTextPulse>
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
        final opacity = 0.58 + t * 0.42;
        final glow = 0.10 + t * 0.24;
        final blur = 6.0 + t * 10.0;

        return Text(
          'ON SHIFT',
          style: TextStyle(
            color: AppPalette.green.withOpacity(opacity),
            fontWeight: FontWeight.w900,
            fontSize: 12.5,
            letterSpacing: 0.22,
            shadows: [
              Shadow(
                color: AppPalette.green.withOpacity(glow),
                blurRadius: blur,
              ),
              Shadow(
                color: AppPalette.green.withOpacity(glow * 0.7),
                blurRadius: blur * 1.6,
              ),
            ],
          ),
        );
      },
    );
  }
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

Future<void> showChangePasswordDialog(BuildContext context) async {
  final pass1 = TextEditingController();
  final pass2 = TextEditingController();

  bool saving = false;
  bool show1 = false;
  bool show2 = false;

  await showGeneralDialog(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Change password',
    barrierColor: Colors.black.withOpacity(0.55),
    transitionDuration: const Duration(milliseconds: 180),

    pageBuilder: (ctx, __, ___) {
      return StatefulBuilder(
        builder: (ctx, setState) {
          Future<void> save() async {
            FocusScope.of(ctx).unfocus();

            final p1 = pass1.text.trim();
            final p2 = pass2.text.trim();

            if (p1.isEmpty || p2.isEmpty) {
              AppToast.warning('Please fill both fields');
              return;
            }
            if (p1.length < 6) {
              AppToast.warning('Password must be at least 6 characters');
              return;
            }
            if (p1 != p2) {
              AppToast.error('Passwords do not match');
              return;
            }

            setState(() => saving = true);

            try {
              await Supabase.instance.client.auth.updateUser(
                UserAttributes(password: p1),
              );
              if (!ctx.mounted) return;

              Navigator.of(ctx).pop(); // закрыли диалог

              // ✅ показываем уже после закрытия
              WidgetsBinding.instance.addPostFrameCallback((_) {
                AppToast.success('Password updated');
              });
            } catch (e) {
              AppToast.error('Error: $e');
            } finally {
              if (ctx.mounted) setState(() => saving = false);
            }
          }

          return SafeArea(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 18),
                child: Material(
                  type: MaterialType.transparency,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(22),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                      child: Container(
                        width: 360,
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
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // ===== HEADER =====
                            Row(
                              children: [
                                Icon(
                                  Icons.lock_reset_rounded,
                                  size: 18,
                                  color: AppPalette.green.withOpacity(0.95),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  'Change password',
                                  style: TextStyle(
                                    color: Colors.white.withOpacity(0.92),
                                    fontWeight: FontWeight.w900,
                                    fontSize: 14.5,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),

                            // ===== BULLETS =====
                            _Bullets(items: const [
                              'This updates the current admin account password.',
                              'Use at least 6 characters.',
                              'You may need to sign in again after updating.',
                            ]),

                            const SizedBox(height: 12),

                            // ===== FIELDS =====
                            _PwdField(
                              hint: 'New password',
                              controller: pass1,
                              obscure: !show1,
                              onToggle: () => setState(() => show1 = !show1),
                            ),
                            const SizedBox(height: 10),
                            _PwdField(
                              hint: 'Confirm password',
                              controller: pass2,
                              obscure: !show2,
                              onToggle: () => setState(() => show2 = !show2),
                            ),

                            const SizedBox(height: 14),

                            // divider
                            Container(
                              height: 1,
                              width: double.infinity,
                              color: Colors.white.withOpacity(0.06),
                            ),
                            const SizedBox(height: 14),

                            // ===== BUTTONS =====
                            Row(
                              children: [
                                Expanded(
                                  child: _DialogBtn(
                                    text: 'Cancel',
                                    icon: Icons.close_rounded,
                                    variant: _BtnVariant.neutral,
                                    onTap: saving ? () {} : () => Navigator.of(ctx).pop(),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: _DialogBtn(
                                    text: saving ? 'Saving...' : 'Save',
                                    icon: Icons.check_rounded,
                                    variant: _BtnVariant.success,
                                    onTap: saving ? () {} : save,
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
        },
      );
    },

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

class _Bullets extends StatelessWidget {
  final List<String> items;
  const _Bullets({required this.items});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: items.map((t) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '•  ',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.55),
                  fontWeight: FontWeight.w900,
                  height: 1.2,
                ),
              ),
              Expanded(
                child: Text(
                  t,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.60),
                    fontWeight: FontWeight.w700,
                    fontSize: 12.5,
                    height: 1.25,
                  ),
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }
}

class _PwdField extends StatelessWidget {
  final String hint;
  final TextEditingController controller;
  final bool obscure;
  final VoidCallback onToggle;

  const _PwdField({
    required this.hint,
    required this.controller,
    required this.obscure,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 46,
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withOpacity(0.10)),
      ),
      child: TextField(
        controller: controller,
        obscureText: obscure,
        style: TextStyle(
          color: Colors.white.withOpacity(0.90),
          fontWeight: FontWeight.w800,
        ),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(color: Colors.white.withOpacity(0.35)),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          suffixIcon: IconButton(
            onPressed: onToggle,
            icon: Icon(
              obscure ? Icons.visibility_off_rounded : Icons.visibility_rounded,
              color: Colors.white.withOpacity(0.35),
            ),
          ),
        ),
      ),
    );
  }
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
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.logout_rounded,
                            size: 18,
                            color: Colors.redAccent.withOpacity(0.95),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Are you sure you want to logout?',
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.80),
                                fontWeight: FontWeight.w800,
                                fontSize: 13.5,
                                height: 1.25,
                              ),
                            ),
                          ),
                        ],
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

enum _BtnVariant { neutral, danger, success }

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
    final isSuccess = variant == _BtnVariant.success;

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
        : isSuccess
        ? const LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [
        Color(0xFF34D399),
        Color(0xFF16A34A),
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

    final useBlack = isSuccess || isDanger;

    final textColor = useBlack
        ? Colors.black
        : Colors.white.withOpacity(0.82);

    final iconColor = useBlack
        ? Colors.black
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

class _WorkioAppBarBg extends StatelessWidget {
  const _WorkioAppBarBg();

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      child: Stack(
        children: [
          // BLUR
          BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
            child: Container(color: Colors.transparent),
          ),

          // GLASS GRADIENT (как в Worker details)
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.white.withOpacity(0.14),
                  Colors.white.withOpacity(0.06),
                  Colors.black.withOpacity(0.22),
                ],
              ),
              border: Border(
                bottom: BorderSide(
                  color: Colors.white.withOpacity(0.12),
                  width: 1,
                ),
              ),
            ),
          ),

          // TOP HIGHLIGHT
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            child: Container(
              height: 1,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Colors.transparent,
                    Colors.white.withOpacity(0.35),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
class _AboutWorkioSheet extends StatelessWidget {
  final String adminEmail;
  final String subtitle;
  final String aboutText;

  const _AboutWorkioSheet({
    required this.adminEmail,
    required this.subtitle,
    required this.aboutText,
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
                                  subtitle,
                                  style: TextStyle(
                                    color: Colors.white.withOpacity(0.55),
                                    fontWeight: FontWeight.w700,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            onPressed: () => Navigator.pop(context),
                            icon: Icon(
                              Icons.close_rounded,
                              color: kTextSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 8),
                    Divider(color: Colors.white.withOpacity(0.10), height: 1),

                    Expanded(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _aboutBlock(
                              title: 'About',
                              icon: Icons.info_outline_rounded,
                              child: Text(
                                aboutText,
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
                                adminEmail.isEmpty
                                    ? 'You are not signed in.'
                                    : 'Signed in as: $adminEmail',
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

class _AdminMailButton extends StatelessWidget {
  final VoidCallback onTap;

  const _AdminMailButton({
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<int>(
      stream: MessageService.watchAdminUnreadCount(),
      builder: (context, snapshot) {
        final unread = snapshot.data ?? 0;

        return Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: onTap,
            child: SizedBox(
              width: 42,
              height: 42,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  const Center(
                    child: Icon(
                      Icons.forum_rounded,
                      color: Colors.white70,
                      size: 20,
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
      },
    );
  }
}

class _AdminTasksButton extends StatelessWidget {
  final VoidCallback onTap;

  const _AdminTasksButton({
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<int>(
      stream: TaskService.watchAdminTaskUnseenCount(),
      builder: (context, snapshot) {
        final unread = snapshot.data ?? 0;

        return Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: onTap,
            child: SizedBox(
              width: 42,
              height: 42,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  const Center(
                    child: Icon(
                      Icons.assignment_rounded,
                      color: Colors.white70,
                      size: 20,
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