import 'dart:ui';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../services/worker_service.dart';
import '../widgets/worker_range_calendar_sheet.dart';
import '../widgets/quick_calculator_sheet.dart';

class WorkerHistoryScreen extends StatefulWidget {
  const WorkerHistoryScreen({super.key});

  @override
  State<WorkerHistoryScreen> createState() => _WorkerHistoryScreenState();
}

enum _HistoryFilter {
  all,
  paid,
  pending,
  active,
}

class _WorkerHistoryScreenState extends State<WorkerHistoryScreen>
    with TickerProviderStateMixin {
  final WorkerService _service = WorkerService();
  Timer? _liveTicker;
  late final AnimationController _topPanelController;

  static const double _topPanelExpandedHeight = 450;
  static const double _topPanelCollapsedHeight = 228;

  double get _topPanelProgress =>
      Curves.easeInOutCubic.transform(_topPanelController.value);

  double get _topPanelHeight => lerpDouble(
    _topPanelCollapsedHeight,
    _topPanelExpandedHeight,
    _topPanelProgress,
  )!;
  bool _isTopExtrasExpanded = true;
  bool _isHistoryPinned = true;
  bool _loading = true;
  List<Map<String, dynamic>> _rows = [];
  _HistoryFilter _filter = _HistoryFilter.all;
  DateTimeRange? _searchRange;
  final Map<int, bool> _expandedYears = {};
  final Map<String, bool> _expandedMonths = {};

  static const int _monthCardsPageSize = 5;
  final Map<String, int> _monthVisibleCounts = {};

  @override
  void initState() {
    super.initState();

    _topPanelController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
      value: 1.0,
    )..addListener(() {
      if (mounted) setState(() {});
    });

    _load();
  }

  @override
  void dispose() {
    _liveTicker?.cancel();
    _topPanelController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (mounted) {
      setState(() => _loading = true);
    }

    try {
      final rows = await _service.getHistory();

      if (!mounted) return;
      setState(() {
        _rows = List<Map<String, dynamic>>.from(rows);
        _expandedYears.clear();
        _expandedMonths.clear();
        _loading = false;
        _monthVisibleCounts.clear();
      });
      _syncLiveTicker();
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);

      _showGlassSnack(
        text: 'Failed to load history',
        icon: Icons.error_outline_rounded,
        accent: const Color(0xFFFF8A7A),
      );
    }
  }

  Future<void> _pickSearchRange() async {
    final picked = await showWorkerRangeCalendarSheet(
      context: context,
      initialRange: _searchRange,
      workDays: _historyWorkDays,
      isPayments: false,
    );

    if (picked == null) return;

    setState(() {
      _searchRange = picked;
      _monthVisibleCounts.clear();
    });
  }

  Future<void> _openQuickCalculator() async {
    await showQuickCalculatorSheet(context: context);
  }

  void _showGlassSnack({
    required String text,
    IconData icon = Icons.info_outline_rounded,
    Color accent = HistoryPalette.blue,
  }) {
    if (!mounted) return;

    final messenger = ScaffoldMessenger.of(context);

    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          elevation: 0,
          backgroundColor: Colors.transparent,
          margin: const EdgeInsets.fromLTRB(14, 0, 14, 18),
          padding: EdgeInsets.zero,
          duration: const Duration(milliseconds: 2400),
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

  double _num(dynamic v) {
    if (v == null) return 0;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? 0;
  }

  DateTime? _dt(dynamic v) {
    if (v == null) return null;
    try {
      return DateTime.parse(v.toString()).toLocal();
    } catch (_) {
      return null;
    }
  }

  Map<DateTime, List<Map<String, dynamic>>> get _historyWorkDays {
    final map = <DateTime, List<Map<String, dynamic>>>{};

    for (final row in _rows) {
      final start = _dt(row['start_time']);
      if (start == null) continue;

      final day = DateTime(start.year, start.month, start.day);
      map.putIfAbsent(day, () => []);
      map[day]!.add(row);
    }

    return map;
  }

  String _money(double v) => '\$${v.toStringAsFixed(2)}';

  String _statusOf(Map<String, dynamic> row) {
    final endTime = row['end_time'];
    final paidAt = row['paid_at'];
    final paymentStatus = (row['payment_status'] ?? '').toString().toLowerCase();

    if (endTime == null) return 'active';
    if (paidAt != null || paymentStatus == 'paid') return 'paid';
    return 'pending';
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'paid':
        return HistoryPalette.green;
      case 'pending':
        return HistoryPalette.pendingGray;
      case 'active':
        return HistoryPalette.blue;
      default:
        return Colors.white70;
    }
  }

  IconData _statusIcon(String status) {
    switch (status) {
      case 'paid':
        return Icons.check_circle_rounded;
      case 'pending':
        return Icons.schedule_rounded;
      case 'active':
        return Icons.play_circle_fill_rounded;
      default:
        return Icons.help_outline_rounded;
    }
  }

  String _statusText(String status) {
    switch (status) {
      case 'paid':
        return 'PAID';
      case 'pending':
        return 'PENDING';
      case 'active':
        return 'ACTIVE';
      default:
        return 'UNKNOWN';
    }
  }

  String _workedText(dynamic hoursValue) {
    final hours = _num(hoursValue);
    if (hours <= 0) return '0m';

    final totalSeconds = (hours * 3600).round();
    final d = Duration(seconds: totalSeconds);

    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60);

    if (h > 0) return '${h}h ${m}m';
    if (m > 0) return '${m}m ${s}s';
    return '${s}s';
  }

  String _clock(DateTime? dt) {
    if (dt == null) return '—';
    return DateFormat('HH:mm').format(dt);
  }

  String _dateShort(DateTime? dt) {
    if (dt == null) return 'Unknown date';
    return DateFormat('MMM d, yyyy').format(dt);
  }

  String _timeRange(Map<String, dynamic> row) {
    final start = _dt(row['start_time']);
    final end = _dt(row['end_time']);

    if (start == null) return '—';
    if (end == null) return '${_clock(start)} - LIVE';
    return '${_clock(start)} - ${_clock(end)}';
  }

  List<Map<String, dynamic>> get _filteredRows {
    return _rows.where((row) {
      final s = _statusOf(row);

      bool statusMatch;
      switch (_filter) {
        case _HistoryFilter.all:
          statusMatch = s != 'active';
          break;
        case _HistoryFilter.paid:
          statusMatch = s == 'paid';
          break;
        case _HistoryFilter.pending:
          statusMatch = s == 'pending';
          break;
        case _HistoryFilter.active:
          statusMatch = s == 'active';
          break;
      }

      if (!statusMatch) return false;

      if (_searchRange == null) return true;

      final start = _dt(row['start_time']);
      if (start == null) return false;

      final day = DateTime(start.year, start.month, start.day);
      final from = DateTime(
        _searchRange!.start.year,
        _searchRange!.start.month,
        _searchRange!.start.day,
      );
      final to = DateTime(
        _searchRange!.end.year,
        _searchRange!.end.month,
        _searchRange!.end.day,
      );

      return !day.isBefore(from) && !day.isAfter(to);
    }).toList();
  }

  int get _visibleShiftCount {
    return _filteredRows.where((row) => row['end_time'] != null).length;
  }

  int get _visiblePaidCount {
    return _filteredRows.where((row) => _statusOf(row) == 'paid').length;
  }

  int get _visibleUnpaidCount {
    return _filteredRows.where((row) => _statusOf(row) == 'pending').length;
  }

  double get _visibleShiftAmountTotal {
    double sum = 0;
    for (final row in _filteredRows) {
      if (row['end_time'] != null) {
        sum += _num(row['total_payment']);
      }
    }
    return sum;
  }

  double get _visiblePaidAmountTotal {
    double sum = 0;
    for (final row in _filteredRows) {
      if (_statusOf(row) == 'paid') {
        sum += _num(row['total_payment']);
      }
    }
    return sum;
  }

  double get _visibleUnpaidAmountTotal {
    double sum = 0;
    for (final row in _filteredRows) {
      if (_statusOf(row) == 'pending') {
        sum += _num(row['total_payment']);
      }
    }
    return sum;
  }

  double get _paidTotal {
    double sum = 0;
    for (final row in _rows) {
      if (_statusOf(row) == 'paid') {
        sum += _num(row['total_payment']);
      }
    }
    return sum;
  }

  double get _unpaidTotal {
    double sum = 0;
    for (final row in _rows) {
      if (_statusOf(row) == 'pending') {
        sum += _num(row['total_payment']);
      }
    }
    return sum;
  }

  int get _shiftCount {
    int c = 0;
    for (final row in _rows) {
      if (row['end_time'] != null) c++;
    }
    return c;
  }

  double get _hoursTotal {
    double sum = 0;
    for (final row in _rows) {
      if (row['end_time'] != null) {
        sum += _num(row['total_hours']);
      }
    }
    return sum;
  }

  String _summaryTimeRange(List<Map<String, dynamic>> rows) {
    if (rows.isEmpty) return '—';

    final sorted = [...rows];
    sorted.sort((a, b) {
      final ad = _dt(a['start_time']) ?? DateTime.fromMillisecondsSinceEpoch(0);
      final bd = _dt(b['start_time']) ?? DateTime.fromMillisecondsSinceEpoch(0);
      return ad.compareTo(bd);
    });

    final firstStart = _dt(sorted.first['start_time']);
    final lastEnd = _dt(sorted.last['end_time']);

    if (firstStart == null) return '—';
    if (lastEnd == null) return '${_clock(firstStart)} - LIVE';

    return '${_clock(firstStart)} - ${_clock(lastEnd)}';
  }

  List<String> _sessionLines(List<Map<String, dynamic>> rows) {
    final sorted = [...rows];
    sorted.sort((a, b) {
      final ad = _dt(a['start_time']) ?? DateTime.fromMillisecondsSinceEpoch(0);
      final bd = _dt(b['start_time']) ?? DateTime.fromMillisecondsSinceEpoch(0);
      return ad.compareTo(bd);
    });

    return List.generate(sorted.length, (i) {
      final row = sorted[i];
      return 'Session ${i + 1}: ${_timeRange(row)} · ${_money(_num(row['total_payment']))}';
    });
  }

  List<_HistoryStatusSummary> _buildStatusSummaries(
      List<Map<String, dynamic>> rows,
      ) {
    final map = <String, List<Map<String, dynamic>>>{};

    for (final row in rows) {
      final status = _statusOf(row);
      map.putIfAbsent(status, () => []);
      map[status]!.add(row);
    }

    const order = ['active', 'pending', 'paid'];
    final result = <_HistoryStatusSummary>[];

    for (final status in order) {
      final items = map[status];
      if (items == null || items.isEmpty) continue;

      items.sort((a, b) {
        final ad = _dt(a['start_time']) ?? DateTime.fromMillisecondsSinceEpoch(0);
        final bd = _dt(b['start_time']) ?? DateTime.fromMillisecondsSinceEpoch(0);
        return ad.compareTo(bd);
      });

      result.add(_HistoryStatusSummary(status: status, items: items));
    }

    return result;
  }

  double _rowsAmountTotal(List<Map<String, dynamic>> rows) {
    double sum = 0;
    for (final row in rows) {
      sum += _num(row['total_payment']);
    }
    return sum;
  }

  double _rowsHoursTotal(List<Map<String, dynamic>> rows) {
    double sum = 0;
    for (final row in rows) {
      sum += _num(row['total_hours']);
    }
    return sum;
  }

  String _monthTitle(DateTime date) {
    return DateFormat('MMMM').format(date);
  }

  String _dayTitle(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final d = DateTime(date.year, date.month, date.day);
    final diff = today.difference(d).inDays;

    if (diff == 0) return 'Today';
    if (diff == 1) return 'Yesterday';
    return DateFormat('MMMM d').format(date);
  }

  List<_HistoryYearGroup> _buildYearGroups(List<Map<String, dynamic>> rows) {
    final map = <int, Map<int, Map<DateTime, List<Map<String, dynamic>>>>>{};

    for (final row in rows) {
      final start = _dt(row['start_time']);
      if (start == null) continue;

      final day = DateTime(start.year, start.month, start.day);

      map.putIfAbsent(day.year, () => {});
      map[day.year]!.putIfAbsent(day.month, () => {});
      map[day.year]![day.month]!.putIfAbsent(day, () => []);
      map[day.year]![day.month]![day]!.add(row);
    }

    final years = map.keys.toList()..sort((a, b) => b.compareTo(a));

    return years.map((year) {
      final monthMap = map[year]!;
      final monthKeys = monthMap.keys.toList()..sort((a, b) => b.compareTo(a));

      final months = monthKeys.map((month) {
        final dayMap = monthMap[month]!;
        final dayKeys = dayMap.keys.toList()..sort((a, b) => b.compareTo(a));

        final days = dayKeys.map((day) {
          final items = List<Map<String, dynamic>>.from(dayMap[day]!);

          items.sort((a, b) {
            final ad = _dt(a['start_time']) ?? DateTime.fromMillisecondsSinceEpoch(0);
            final bd = _dt(b['start_time']) ?? DateTime.fromMillisecondsSinceEpoch(0);
            return ad.compareTo(bd);
          });

          return _HistoryGroup(
            title: _dayTitle(day),
            items: items,
          );
        }).toList();

        return _HistoryMonthGroup(
          title: _monthTitle(DateTime(year, month, 1)),
          days: days,
        );
      }).toList();

      return _HistoryYearGroup(
        year: year,
        months: months,
      );
    }).toList();
  }

  List<_HistoryGroup> _buildGroups(List<Map<String, dynamic>> rows) {
    final map = <String, List<Map<String, dynamic>>>{};

    for (final row in rows) {
      final start = _dt(row['start_time']);
      if (start == null) continue;

      final key = _groupTitle(start);
      map.putIfAbsent(key, () => []);
      map[key]!.add(row);
    }

    return map.entries
        .map((e) => _HistoryGroup(title: e.key, items: e.value))
        .toList();
  }

  String _groupTitle(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final d = DateTime(date.year, date.month, date.day);
    final diff = today.difference(d).inDays;

    if (diff == 0) return 'Today';
    if (diff == 1) return 'Yesterday';
    return DateFormat('MMMM d, yyyy').format(date);
  }

  String _addressValue(
      dynamic value, {
        required bool canViewAddress,
      }) {
    if (!canViewAddress) {
      return 'Ask admin for access';
    }

    final text = (value ?? '').toString().trim();

    if (text.isEmpty ||
        text == '—' ||
        text.toLowerCase() == 'null' ||
        text.toLowerCase() == 'location not available') {
      return 'Not available';
    }

    return text;
  }

  Future<void> _openDetails(
      Map<String, dynamic> row, {
        List<Map<String, dynamic>>? sessions,
      }) async {
    final detailRows = List<Map<String, dynamic>>.from(
      (sessions == null || sessions.isEmpty) ? [row] : sessions,
    )..sort((a, b) {
      final ad = _dt(a['start_time']) ?? DateTime.fromMillisecondsSinceEpoch(0);
      final bd = _dt(b['start_time']) ?? DateTime.fromMillisecondsSinceEpoch(0);
      return ad.compareTo(bd);
    });

    final primary = detailRows.last;
    final canViewAddress = primary['can_view_address'] == true;
    final status = _statusOf(primary);
    final color = _statusColor(status);

    final firstStart = _dt(detailRows.first['start_time']);
    final paidAt = _dt(primary['paid_at']);

    final isMultiSession = detailRows.length > 1;
    final totalAmount = _rowsAmountTotal(detailRows);
    final totalHours = _rowsHoursTotal(detailRows);

    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) {
        final maxSheetHeight = MediaQuery.of(context).size.height * 0.84;

        return SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
            child: Align(
              alignment: Alignment.bottomCenter,
              child: ConstrainedBox(
                constraints: BoxConstraints(maxHeight: maxSheetHeight),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(28),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            Color(0xFF2F3036),
                            Color(0xFF24252B),
                            Color(0xFF1B1D23),
                          ],
                        ),
                        borderRadius: BorderRadius.circular(28),
                        border: Border.all(
                          color: Colors.white.withOpacity(0.10),
                        ),
                      ),
                      child: Column(
                        children: [
                          Container(
                            padding: const EdgeInsets.fromLTRB(14, 8, 14, 14),
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [
                                  Color(0xFF2F3036),
                                  Color(0xFF24252B),
                                  Color(0xFF1B1D23),
                                ],
                              ),
                              border: Border(
                                bottom: BorderSide(
                                  color: Colors.white.withOpacity(0.08),
                                ),
                              ),
                            ),
                            child: Column(
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
                                _ShiftDetailsHeader(
                                  icon: Icons.work_history_rounded,
                                  iconColor: color.withOpacity(0.88),
                                  title: 'Shift details',
                                  onClose: () => Navigator.of(context).pop(),
                                ),
                                const SizedBox(height: 12),
                                _DetailHeroCard(
                                  amount: _money(totalAmount),
                                  color: color,
                                  subtitle: isMultiSession
                                      ? 'Total for ${detailRows.length} sessions'
                                      : 'Total for this shift',
                                ),
                              ],
                            ),
                          ),

                          Expanded(
                            child: SingleChildScrollView(
                              padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
                              child: Column(
                                children: [
                                  _DetailSectionBlock(
                                    title: 'SHIFT',
                                    child: Column(
                                      children: [
                                        _DetailSectionLine(
                                          icon: Icons.calendar_today_rounded,
                                          label: 'Date',
                                          value: _dateShort(firstStart),
                                        ),
                                        if (isMultiSession)
                                          _DetailSectionLine(
                                            icon: Icons.layers_rounded,
                                            label: 'Sessions',
                                            value: '${detailRows.length}',
                                          ),
                                        _DetailSectionLine(
                                          icon: Icons.schedule_rounded,
                                          label: isMultiSession ? 'Span' : 'Time',
                                          value: isMultiSession
                                              ? _summaryTimeRange(detailRows)
                                              : _timeRange(primary),
                                        ),
                                        _DetailSectionLine(
                                          icon: Icons.timer_rounded,
                                          label: 'Worked',
                                          value: _workedText(totalHours),
                                        ),
                                        if (!isMultiSession)
                                          _DetailSectionLine(
                                            icon: Icons.attach_money_rounded,
                                            label: 'Rate',
                                            value: _money(_num(primary['pay_rate'])),
                                          ),
                                      ],
                                    ),
                                  ),

                                  if (isMultiSession) ...[
                                    const SizedBox(height: 12),
                                    _DetailSectionBlock(
                                      title: 'SESSIONS',
                                      child: Column(
                                        children: [
                                          for (int i = 0; i < detailRows.length; i++) ...[
                                            _SessionDetailCard(
                                              index: i + 1,
                                              timeText: _timeRange(detailRows[i]),
                                              workedText: _workedText(detailRows[i]['total_hours']),
                                              amountText: _money(_num(detailRows[i]['total_payment'])),
                                              rateText: _money(_num(detailRows[i]['pay_rate'])),
                                            ),
                                            if (i != detailRows.length - 1)
                                              const SizedBox(height: 10),
                                          ],
                                        ],
                                      ),
                                    ),
                                  ],

                                  const SizedBox(height: 12),

                                  _DetailSectionBlock(
                                    title: 'ADDRESS',
                                    child: Column(
                                      children: [
                                        if (!canViewAddress) ...[
                                          const _AddressPermissionNote(),
                                          const SizedBox(height: 12),
                                        ],
                                        _DetailSectionLine(
                                          icon: Icons.login_rounded,
                                          label: 'Start',
                                          value: _addressValue(
                                            primary['address_start'],
                                            canViewAddress: canViewAddress,
                                          ),
                                        ),
                                        _DetailSectionLine(
                                          icon: Icons.logout_rounded,
                                          label: 'End',
                                          value: _addressValue(
                                            primary['address_end'],
                                            canViewAddress: canViewAddress,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),

                                  const SizedBox(height: 12),

                                  _DetailSectionBlock(
                                    title: 'PAYMENT',
                                    child: Column(
                                      children: [
                                        _DetailSectionLine(
                                          icon: Icons.payments_rounded,
                                          label: 'Payment',
                                          value: _statusText(status),
                                        ),
                                        _DetailSectionLine(
                                          icon: Icons.receipt_long_rounded,
                                          label: 'Paid at',
                                          value: paidAt == null
                                              ? 'Not paid yet'
                                              : DateFormat('MMM d, yyyy • HH:mm').format(paidAt),
                                        ),
                                      ],
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
          ),
        );
      },
    );
  }

  Widget _buildTopHistoryPanel() {
    return _SolidPanel(
        loading: false,
      header: _UnifiedHistoryHeader(
        title: 'Work history',
        subtitle: 'Shifts, payments, and live status',
        isPinned: _isHistoryPinned,
        onTogglePin: () {
          setState(() => _isHistoryPinned = !_isHistoryPinned);
        },
        onBack: () => Navigator.pop(context),
        onRefresh: _load,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _TopControlsPanel(
            selectedRange: _searchRange,
            onPick: _pickSearchRange,
            onClear: () => setState(() {
              _searchRange = null;
              _monthVisibleCounts.clear();
            }),
            onOpenCalculator: _openQuickCalculator,
            current: _filter,
            onChanged: (v) => setState(() {
              _filter = v;
              _monthVisibleCounts.clear();
            }),
          ),
          ClipRect(
            child: Align(
              alignment: Alignment.topCenter,
              heightFactor: _topPanelProgress == 0 ? 0.0001 : _topPanelProgress,
              child: Opacity(
                opacity: _topPanelProgress,
                child: Column(
                  children: [
                    const SizedBox(height: 10),
                    _HistoryTopFooter(
                      shifts: _visibleShiftCount,
                      shiftAmount: _visibleShiftAmountTotal,
                      paid: _visiblePaidCount,
                      paidAmount: _visiblePaidAmountTotal,
                      unpaid: _visibleUnpaidCount,
                      unpaidAmount: _visibleUnpaidAmountTotal,
                    ),
                    const SizedBox(height: 10),
                    _LiveStatusCapsule(
                      isActive: _activeRow != null,
                      amountText: _money(_liveAmount),
                      workedText: _liveWorkedText,
                      startedText: _liveStartedText,
                    ),
                    const SizedBox(height: 12),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
      footer: _TopPanelFooterBar(
        expanded: _isTopExtrasExpanded,
        onTap: () {
          final next = !_isTopExtrasExpanded;

          setState(() => _isTopExtrasExpanded = next);

          if (next) {
            _topPanelController.forward();
          } else {
            _topPanelController.reverse();
          }
        },
      ),
      );
  }

  Widget _buildHistoryList(List<_HistoryGroup> groups, {required bool includeTopPanel}) {
    return const SizedBox.shrink();
  }

  Widget _softDivider() {
    return Container(
      height: 1,
      margin: const EdgeInsets.symmetric(vertical: 10),
      color: Colors.white.withOpacity(0.07),
    );
  }

  Map<String, dynamic>? get _activeRow {
    final activeRows = _rows.where((row) => _statusOf(row) == 'active').toList();
    if (activeRows.isEmpty) return null;

    activeRows.sort((a, b) {
      final ad = _dt(a['start_time']) ?? DateTime.fromMillisecondsSinceEpoch(0);
      final bd = _dt(b['start_time']) ?? DateTime.fromMillisecondsSinceEpoch(0);
      return bd.compareTo(ad);
    });

    return activeRows.first;
  }

  Duration get _liveDuration {
    final row = _activeRow;
    if (row == null) return Duration.zero;

    final start = _dt(row['start_time']);
    if (start == null) return Duration.zero;

    final diff = DateTime.now().difference(start);
    return diff.isNegative ? Duration.zero : diff;
  }

  double get _liveHours {
    return _liveDuration.inSeconds / 3600.0;
  }

  double get _liveAmount {
    final row = _activeRow;
    if (row == null) return 0;

    final backendAmount = _num(row['total_payment']);
    if (backendAmount > 0) return backendAmount;

    final rate = _num(row['pay_rate']);
    return rate * _liveHours;
  }

  String get _liveWorkedText {
    return _workedText(_liveHours);
  }

  String get _liveStartedText {
    final row = _activeRow;
    if (row == null) return '—';
    return _clock(_dt(row['start_time']));
  }

  void _syncLiveTicker() {
    _liveTicker?.cancel();

    if (_activeRow != null) {
      _liveTicker = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
    }
  }

  Widget? _groupStatusCapsule() {
    switch (_filter) {
      case _HistoryFilter.paid:
        return _StatusChip(
          text: 'PAID',
          color: HistoryPalette.green,
        );
      case _HistoryFilter.pending:
        return _StatusChip(
          text: 'PENDING',
          color: HistoryPalette.blue,
        );
      case _HistoryFilter.active:
        return _StatusChip(
          text: 'ACTIVE',
          color: const Color(0xFFF4B544),
        );
      case _HistoryFilter.all:
        return null;
    }
  }

  int? get _latestVisibleYear {
    final years = _buildYearGroups(_filteredRows);
    if (years.isEmpty) return null;
    return years.first.year;
  }

  String? get _latestVisibleMonthKey {
    final years = _buildYearGroups(_filteredRows);
    if (years.isEmpty || years.first.months.isEmpty) return null;
    return '${years.first.year}-${years.first.months.first.title}';
  }

  bool _isYearExpanded(int year) {
    if (_expandedYears.containsKey(year)) {
      return _expandedYears[year]!;
    }
    return year == _latestVisibleYear;
  }

  bool _isMonthExpanded(String key) {
    if (_expandedMonths.containsKey(key)) {
      return _expandedMonths[key]!;
    }
    return key == _latestVisibleMonthKey;
  }

  void _toggleYear(int year) {
    setState(() {
      _expandedYears[year] = !(_isYearExpanded(year));
    });
  }

  void _toggleMonth(String key) {
    setState(() {
      _expandedMonths[key] = !(_isMonthExpanded(key));
    });
  }

  int _visibleMonthCardsLimit(String monthKey, int total) {
    final raw = _monthVisibleCounts[monthKey] ?? _monthCardsPageSize;

    if (raw < _monthCardsPageSize) {
      return total < _monthCardsPageSize ? total : _monthCardsPageSize;
    }

    if (raw > total) return total;
    return raw;
  }

  void _showMoreMonthCards(String monthKey, int total) {
    setState(() {
      final current = _monthVisibleCounts[monthKey] ?? _monthCardsPageSize;
      final next = current + _monthCardsPageSize;
      _monthVisibleCounts[monthKey] = next > total ? total : next;
    });
  }

  @override
  Widget build(BuildContext context) {
    final years = _buildYearGroups(_filteredRows);

    return Scaffold(
      backgroundColor: HistoryPalette.bg,
      body: Stack(
        children: [
          const _BackgroundBase(),
          SafeArea(
            child: CustomScrollView(
              physics: const BouncingScrollPhysics(
                parent: AlwaysScrollableScrollPhysics(),
              ),
              slivers: [
                const SliverToBoxAdapter(
                  child: SizedBox(height: 10),
                ),

                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  sliver: SliverPersistentHeader(
                    pinned: _isHistoryPinned,
                    delegate: _TopHistoryPanelDelegate(
                      extent: _topPanelHeight,
                      child: _buildTopHistoryPanel(),
                    ),
                  ),
                ),

                const SliverToBoxAdapter(
                  child: SizedBox(height: 0),
                ),

                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  sliver: SliverToBoxAdapter(
                    child: Transform.translate(
                      offset: const Offset(0, -10),
                      child: Column(
                        children: [
                        if (_loading)
                          const _LoadingHistoryPanel()
                        else if (_filteredRows.isEmpty)
                          _SolidPanel(
                            loading: false,
                            header: const SizedBox.shrink(),
                            child: const _EmptyHistoryState(),
                          )
                        else
                          _AnimatedHistoryContent(
                            filterKey:
                            '${_filter.name}_${_searchRange?.start.millisecondsSinceEpoch ?? 0}_${_searchRange?.end.millisecondsSinceEpoch ?? 0}',
                            child: ClipRRect(
                              borderRadius: const BorderRadius.only(
                                bottomLeft: Radius.circular(22),
                                bottomRight: Radius.circular(22),
                              ),
                              child: Container(
                                decoration: BoxDecoration(
                                  gradient: const LinearGradient(
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                    colors: [
                                      Color(0xFF2A2D34),
                                      Color(0xFF1E2128),
                                      Color(0xFF15181E),
                                    ],
                                  ),
                                  borderRadius: const BorderRadius.only(
                                    bottomLeft: Radius.circular(22),
                                    bottomRight: Radius.circular(22),
                                  ),
                                  border: Border.all(
                                    color: Colors.white.withOpacity(0.08),
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withOpacity(0.58),
                                      blurRadius: 30,
                                      offset: const Offset(0, 18),
                                    ),
                                    BoxShadow(
                                      color: Colors.white.withOpacity(0.02),
                                      blurRadius: 10,
                                      spreadRadius: -4,
                                      offset: const Offset(0, -3),
                                    ),
                                  ],
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.fromLTRB(12, 14, 12, 14),
                                  child: Column(
                                    children: [
                                      for (int i = 0; i < years.length; i++) ...[
                                        _YearHeader(
                                          title: '${years[i].year}',
                                          expanded: _isYearExpanded(years[i].year),
                                          onTap: () => _toggleYear(years[i].year),
                                        ),
                                        const SizedBox(height: 12),

                                        if (_isYearExpanded(years[i].year)) ...[
                                          for (final month in years[i].months) ...[
                                            Padding(
                                              padding: const EdgeInsets.only(left: 12),
                                              child: Builder(
                                                builder: (_) {
                                                  final monthKey = '${years[i].year}-${month.title}';
                                                  final monthCards = <Widget>[];

                                                  for (final group in month.days) {
                                                    final summaries = _buildStatusSummaries(group.items);

                                                    for (int s = 0; s < summaries.length; s++) {
                                                      final summary = summaries[s];

                                                      final card = summary.items.length == 1
                                                          ? _HistoryCard(
                                                        row: summary.items.first,
                                                        status: summary.status,
                                                        statusColor: _statusColor(summary.status),
                                                        statusLabel: _statusText(summary.status),
                                                        statusIcon: _statusIcon(summary.status),
                                                        dateText: group.title,
                                                        amountText: _money(
                                                          _num(summary.items.first['total_payment']),
                                                        ),
                                                        workedText: _workedText(
                                                          summary.items.first['total_hours'],
                                                        ),
                                                        timeText: _timeRange(summary.items.first),
                                                        rateText: _money(
                                                          _num(summary.items.first['pay_rate']),
                                                        ),
                                                        onTap: () => _openDetails(summary.items.first),
                                                      )
                                                          : _HistoryCard(
                                                        row: summary.items.last,
                                                        status: summary.status,
                                                        statusColor: _statusColor(summary.status),
                                                        statusLabel: _statusText(summary.status),
                                                        statusIcon: _statusIcon(summary.status),
                                                        dateText: group.title,
                                                        amountText: _money(
                                                          _rowsAmountTotal(summary.items),
                                                        ),
                                                        workedText: _workedText(
                                                          _rowsHoursTotal(summary.items),
                                                        ),
                                                        timeText: _summaryTimeRange(summary.items),
                                                        rateText: '',
                                                        bottomHintText:
                                                        '${summary.items.length} sessions in this day',
                                                        sessionLines: _sessionLines(summary.items),
                                                        onTap: () => _openDetails(
                                                          summary.items.last,
                                                          sessions: summary.items,
                                                        ),
                                                      );

                                                      monthCards.add(card);
                                                    }
                                                  }

                                                  final totalCards = monthCards.length;
                                                  final visibleCount = _visibleMonthCardsLimit(monthKey, totalCards);
                                                  final visibleCards = monthCards.take(visibleCount).toList();
                                                  final remaining = totalCards - visibleCount;

                                                  return _MonthGroupPanel(
                                                    title: month.title,
                                                    expanded: _isMonthExpanded(monthKey),
                                                    onTap: () => _toggleMonth(monthKey),
                                                    footer: remaining > 0
                                                        ? _MonthLoadMoreFooter(
                                                      hiddenCount: remaining,
                                                      onTap: () => _showMoreMonthCards(monthKey, totalCards),
                                                    )
                                                        : null,
                                                    children: [
                                                      Column(
                                                        children: [
                                                          for (int c = 0; c < visibleCards.length; c++) ...[
                                                            visibleCards[c],
                                                            if (c != visibleCards.length - 1)
                                                              const SizedBox(height: 10),
                                                          ],
                                                        ],
                                                      ),
                                                    ],
                                                  );
                                                },
                                              ),
                                            ),
                                            const SizedBox(height: 12),
                                          ],
                                        ],

                                        if (i != years.length - 1) const SizedBox(height: 16),
                                      ],
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
               ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HistoryDayPanel extends StatelessWidget {
  final String title;
  final int count;
  final List<Widget> children;

  const _HistoryDayPanel({
    required this.title,
    required this.count,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.035),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: Colors.white.withOpacity(0.08),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.calendar_month_rounded,
                size: 16,
                color: Colors.white.withOpacity(0.72),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    color: HistoryPalette.textMain,
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                  ),
                ),
              ),
              Text(
                '$count shift${count == 1 ? '' : 's'}',
                style: TextStyle(
                  color: HistoryPalette.textSoft.withOpacity(0.72),
                  fontWeight: FontWeight.w800,
                  fontSize: 12,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    );
  }
}

class _HistoryGroup {
  final String title;
  final List<Map<String, dynamic>> items;

  _HistoryGroup({
    required this.title,
    required this.items,
  });
}

class _HistoryStatusSummary {
  final String status;
  final List<Map<String, dynamic>> items;

  _HistoryStatusSummary({
    required this.status,
    required this.items,
  });
}

class _HistoryMonthGroup {
  final String title;
  final List<_HistoryGroup> days;

  _HistoryMonthGroup({
    required this.title,
    required this.days,
  });
}

class _HistoryYearGroup {
  final int year;
  final List<_HistoryMonthGroup> months;

  _HistoryYearGroup({
    required this.year,
    required this.months,
  });
}

class _TopControlsPanel extends StatelessWidget {
  final DateTimeRange? selectedRange;
  final VoidCallback onPick;
  final VoidCallback onClear;
  final _HistoryFilter current;
  final VoidCallback onOpenCalculator;
  final ValueChanged<_HistoryFilter> onChanged;

  const _TopControlsPanel({
    required this.selectedRange,
    required this.onPick,
    required this.onClear,
    required this.onOpenCalculator,
    required this.current,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF31343B),
            Color(0xFF272A31),
            Color(0xFF1D2027),
          ],
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: Colors.white.withOpacity(0.08),
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: _DateSearchBar(
                  selectedRange: selectedRange,
                  onPick: onPick,
                  onClear: onClear,
                ),
              ),
              const SizedBox(width: 8),
              _QuickCalculatorButton(
                onTap: onOpenCalculator,
              ),
            ],
          ),
          const SizedBox(height: 10),
          _HistoryFilterBar(
            current: current,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}

class _TopHistoryPanelDelegate extends SliverPersistentHeaderDelegate {
  final double extent;
  final Widget child;

  _TopHistoryPanelDelegate({
    required this.extent,
    required this.child,
  });

  @override
  double get minExtent => extent;

  @override
  double get maxExtent => extent;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return ClipRect(
      child: Stack(
        fit: StackFit.expand,
        children: [
          const ColoredBox(
            color: HistoryPalette.bg,
          ),
          child,
          IgnorePointer(
            child: Align(
              alignment: Alignment.bottomCenter,
              child: Container(
                height: 22,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      HistoryPalette.bg.withOpacity(0.0),
                      HistoryPalette.bg.withOpacity(0.82),
                      HistoryPalette.bg,
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

  @override
  bool shouldRebuild(covariant _TopHistoryPanelDelegate oldDelegate) {
    return oldDelegate.extent != extent || oldDelegate.child != child;
  }
}

class HistoryPalette {
  static const bg = Color(0xFF0B0D12);

  static const cardTop = Color(0xFF2F3036);
  static const cardBottom = Color(0xFF24252B);
  static const cardBorder = Color(0xFF3A3B42);

  static const pill = Color(0xFF1F2025);
  static const pillBorder = Color(0xFF34353C);

  static const textMain = Color(0xFFEDEFF6);
  static const textSoft = Color(0xFFB7BCCB);
  static const textMute = Color(0xFF8B90A0);

  static const pendingGray = Color(0xFF8B90A0);

  static const green = Color(0xFF34D399);
  static const orange = Color(0xFFF59E0B);
  static const blue = Color(0xFF38BDF8);
  static const red = Color(0xFFFB7185);
}

class _BackgroundBase extends StatelessWidget {
  const _BackgroundBase();

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

class _TopGlassBar extends StatelessWidget {
  final String title;
  final String subtitle;
  final VoidCallback onBack;
  final Future<void> Function() onRefresh;

  const _TopGlassBar({
    required this.title,
    required this.subtitle,
    required this.onBack,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: Stack(
        children: [
          BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
            child: Container(),
          ),
          Container(
            padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
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
              borderRadius: BorderRadius.circular(22),
              border: Border.all(
                color: Colors.white.withOpacity(0.10),
              ),
            ),
            child: Row(
              children: [
                _HistoryHeaderActionButton(
                  icon: Icons.arrow_back_ios_new_rounded,
                  onTap: onBack,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 18,
                          color: HistoryPalette.textMain,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                          color: HistoryPalette.textSoft.withOpacity(0.78),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                _TopBarIconBtn(
                  icon: Icons.refresh_rounded,
                  onTap: () {
                    onRefresh();
                  },
                ),
              ],
            ),
          ),
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

class _HistoryHeaderActionButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _HistoryHeaderActionButton({
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Color(0xFF31363E),
                Color(0xFF232830),
              ],
            ),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: Colors.white.withOpacity(0.05),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.24),
                blurRadius: 16,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Icon(
            icon,
            color: HistoryPalette.textMain,
            size: 20,
          ),
        ),
      ),
    );
  }
}

class _TopBarIconBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _TopBarIconBtn({
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(15),
        child: Ink(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Color(0xFF343941),
                Color(0xFF262B32),
              ],
            ),
            borderRadius: BorderRadius.circular(15),
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
          child: Icon(
            icon,
            color: Colors.white.withOpacity(0.84),
            size: 22,
          ),
        ),
      ),
    );
  }
}

class _SolidPanel extends StatelessWidget {
  final bool loading;
  final Widget header;
  final Widget child;
  final Widget? footer;

  const _SolidPanel({
    required this.loading,
    required this.header,
    required this.child,
    this.footer,
  });

  @override
  Widget build(BuildContext context) {
    final panelRadius = footer != null
        ? const BorderRadius.only(
      topLeft: Radius.circular(28),
      topRight: Radius.circular(28),
    )
        : BorderRadius.circular(28);
    return ClipRRect(
      borderRadius: panelRadius,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                const Color(0xFF31343B),
                const Color(0xFF272A31),
                const Color(0xFF1D2027),
              ],
              stops: const [0.0, 0.55, 1.0],
            ),
            borderRadius: panelRadius,
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
          child: Stack(
            children: [
              Positioned(
                left: -26,
                top: -30,
                child: Container(
                  width: 170,
                  height: 92,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(100),
                    gradient: RadialGradient(
                      colors: [
                        Colors.white.withOpacity(0.06),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),
              Column(
                children: [
                  Padding(
                    padding: EdgeInsets.fromLTRB(12, 10, 12, footer != null ? 0 : 12),
                    child: Column(
                      children: [
                        header,
                        const SizedBox(height: 10),
                        if (loading) ...[
                          ClipRRect(
                            borderRadius: BorderRadius.circular(999),
                            child: LinearProgressIndicator(
                              minHeight: 2.5,
                              backgroundColor: Colors.white.withOpacity(0.06),
                            ),
                          ),
                          const SizedBox(height: 10),
                        ],
                        child,
                      ],
                    ),
                  ),
                  if (footer != null) footer!,
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LoadingHistoryInline extends StatelessWidget {
  const _LoadingHistoryInline();

  @override
  Widget build(BuildContext context) {
    return const Column(
      children: [
        _GhostHistoryCard(),
        SizedBox(height: 10),
        _GhostHistoryCard(),
      ],
    );
  }
}

class _HistoryTopFooter extends StatelessWidget {
  final int shifts;
  final double shiftAmount;
  final int paid;
  final double paidAmount;
  final int unpaid;
  final double unpaidAmount;

  const _HistoryTopFooter({
    required this.shifts,
    required this.shiftAmount,
    required this.paid,
    required this.paidAmount,
    required this.unpaid,
    required this.unpaidAmount,
  });

  String _money(double v) => '\$${v.toStringAsFixed(2)}';

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF31343B),
            Color(0xFF272A31),
            Color(0xFF1D2027),
          ],
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: Colors.white.withOpacity(0.08),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: _TopMetricItem(
              icon: Icons.work_history_rounded,
              color: const Color(0xFFF4B544),
              label: 'Shift',
              count: '$shifts',
              amount: _money(shiftAmount),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _TopMetricItem(
              icon: Icons.check_circle_rounded,
              color: HistoryPalette.green,
              label: 'Paid',
              count: '$paid',
              amount: _money(paidAmount),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _TopMetricItem(
              icon: Icons.schedule_rounded,
              color: HistoryPalette.blue,
              label: 'Unpaid',
              count: '$unpaid',
              amount: _money(unpaidAmount),
            ),
          ),
        ],
      ),
    );
  }
}

class _TopMetricItem extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final String count;
  final String amount;

  const _TopMetricItem({
    required this.icon,
    required this.color,
    required this.label,
    required this.count,
    required this.amount,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 58),
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
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
            color: Colors.black.withOpacity(0.24),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Icon(icon, size: 15, color: color),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.w800,
                    fontSize: 11.3,
                  ),
                ),
              ),
              Text(
                count,
                style: const TextStyle(
                  color: HistoryPalette.textMain,
                  fontWeight: FontWeight.w900,
                  fontSize: 12,
                ),
              ),
            ],
          ),
          Center(
            child: Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                amount,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white.withOpacity(0.84),
                  fontWeight: FontWeight.w700,
                  fontSize: 11.6,
                  height: 1.05,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LiveStatusCapsule extends StatelessWidget {
  final bool isActive;
  final String amountText;
  final String workedText;
  final String startedText;

  const _LiveStatusCapsule({
    required this.isActive,
    required this.amountText,
    required this.workedText,
    required this.startedText,
  });

  @override
  Widget build(BuildContext context) {
    final Color liveColor = HistoryPalette.green;
    final Color offColor = HistoryPalette.textMute;
    final Color stateColor = isActive ? liveColor : offColor;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
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
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: Colors.white.withOpacity(0.08),
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              const SizedBox(width: 10),
              if (isActive)
                const _BlinkingLiveDot()
              else
                Icon(
                  Icons.power_settings_new_rounded,
                  size: 14,
                  color: stateColor,
                ),
              const SizedBox(width: 8),
              Text(
                'Active',
                style: TextStyle(
                  color: stateColor,
                  fontWeight: FontWeight.w800,
                  fontSize: 12.5,
                ),
              ),
              const Spacer(),
              Padding(
                padding: const EdgeInsets.only(right: 10),
                child: Text(
                  isActive ? 'LIVE' : 'OFF',
                  style: TextStyle(
                    color: stateColor,
                    fontWeight: FontWeight.w900,
                    fontSize: 11,
                    letterSpacing: 0.3,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
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
                color: Colors.white.withOpacity(0.06),
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
                Expanded(
                  child: _LiveInlineMetric(
                    icon: Icons.attach_money_rounded,
                    label: 'Online total',
                    value: isActive ? amountText : '\$0.00',
                  ),
                ),
                _liveDivider(),
                Expanded(
                  child: _LiveInlineMetric(
                    icon: Icons.timer_outlined,
                    label: 'Worked',
                    value: isActive ? workedText : '0m',
                  ),
                ),
                _liveDivider(),
                Expanded(
                  child: _LiveInlineMetric(
                    icon: Icons.login_rounded,
                    label: 'Started',
                    value: isActive ? startedText : '—',
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _liveDivider() {
    return Container(
      width: 1,
      height: 28,
      margin: const EdgeInsets.symmetric(horizontal: 8),
      color: Colors.white.withOpacity(0.08),
    );
  }
}

class _TopPanelFooterBar extends StatelessWidget {
  final bool expanded;
  final VoidCallback onTap;

  const _TopPanelFooterBar({
    required this.expanded,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.zero,
        child: Container(
          width: double.infinity,
          height: 24,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            border: Border(
              top: BorderSide(
                color: Colors.white.withOpacity(0.07),
                width: 0.8,
              ),
            ),
          ),
          child: AnimatedRotation(
            turns: expanded ? 0.0 : 0.5,
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            child: Icon(
              Icons.keyboard_arrow_up_rounded,
              size: 21,
              color: Colors.white.withOpacity(0.82),
            ),
          ),
        ),
      ),
    );
  }
}

class _LiveInlineMetric extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _LiveInlineMetric({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 13,
              color: HistoryPalette.textSoft.withOpacity(0.82),
            ),
            const SizedBox(width: 5),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: HistoryPalette.textSoft.withOpacity(0.78),
                  fontWeight: FontWeight.w700,
                  fontSize: 10.4,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: HistoryPalette.textMain,
            fontWeight: FontWeight.w800,
            fontSize: 11.6,
          ),
        ),
      ],
    );
  }
}

class _BlinkingLiveDot extends StatefulWidget {
  const _BlinkingLiveDot();

  @override
  State<_BlinkingLiveDot> createState() => _BlinkingLiveDotState();
}

class _BlinkingLiveDotState extends State<_BlinkingLiveDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 850),
      lowerBound: 0.35,
      upperBound: 1.0,
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const color = HistoryPalette.green;

    return FadeTransition(
      opacity: _controller,
      child: Container(
        width: 12,
        height: 12,
        decoration: const BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: color,
              blurRadius: 10,
              spreadRadius: 1,
            ),
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
  final Widget? trailing;

  const _SummaryHeader({
    required this.title,
    required this.subtitle,
    required this.icon,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 38,
      child: Row(
        children: [
          Icon(
            icon,
            size: 18,
            color: HistoryPalette.textSoft.withOpacity(0.85),
          ),
          const SizedBox(width: 8),
          Text(
            title,
            style: TextStyle(
              color: HistoryPalette.textMain.withOpacity(0.92),
              fontWeight: FontWeight.w900,
              fontSize: 14,
              letterSpacing: 0.2,
            ),
          ),
          const Spacer(),
          if (trailing != null)
            trailing!
          else
            Expanded(
              child: Align(
                alignment: Alignment.centerRight,
                child: Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: HistoryPalette.textSoft.withOpacity(0.75),
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

class _BigPanel extends StatelessWidget {
  final Widget child;

  const _BigPanel({
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.white.withOpacity(0.03),
            Colors.black.withOpacity(0.12),
          ],
        ),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: Colors.white.withOpacity(0.07),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.18),
            blurRadius: 14,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _InnerCapsule extends StatelessWidget {
  final Widget child;

  const _InnerCapsule({
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1D24).withOpacity(0.92),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: Colors.white.withOpacity(0.07),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.22),
            blurRadius: 14,
            offset: const Offset(0, 8),
          ),
          BoxShadow(
            color: Colors.white.withOpacity(0.025),
            blurRadius: 10,
            spreadRadius: -4,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _DateSearchBar extends StatelessWidget {
  final DateTimeRange? selectedRange;
  final VoidCallback onPick;
  final VoidCallback onClear;

  const _DateSearchBar({
    required this.selectedRange,
    required this.onPick,
    required this.onClear,
  });

  String _rangeText(DateTimeRange range) {
    final s = range.start;
    final e = range.end;

    final sameDay = s.year == e.year && s.month == e.month && s.day == e.day;
    if (sameDay) {
      return DateFormat('MMM d, yyyy').format(s);
    }

    final sameYear = s.year == e.year;
    if (sameYear) {
      return '${DateFormat('MMM d').format(s)} — ${DateFormat('MMM d, yyyy').format(e)}';
    }

    return '${DateFormat('MMM d, yyyy').format(s)} — ${DateFormat('MMM d, yyyy').format(e)}';
  }

  @override
  Widget build(BuildContext context) {
    final hasRange = selectedRange != null;
    final text = hasRange ? _rangeText(selectedRange!) : 'Find by date range';

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPick,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          height: 42,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Color(0xFF242A32),
                Color(0xFF171C23),
              ],
            ),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: Colors.white.withOpacity(0.06),
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
              Icon(
                Icons.calendar_month_rounded,
                size: 17,
                color: Colors.white.withOpacity(0.72),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  text,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: hasRange
                        ? HistoryPalette.textMain
                        : HistoryPalette.textSoft.withOpacity(0.76),
                    fontWeight: FontWeight.w800,
                    fontSize: 12.8,
                  ),
                ),
              ),
              GestureDetector(
                onTap: hasRange ? onClear : null,
                behavior: HitTestBehavior.opaque,
                child: Icon(
                  hasRange ? Icons.close_rounded : Icons.search_rounded,
                  size: 18,
                  color: Colors.white.withOpacity(hasRange ? 0.82 : 0.62),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _QuickCalculatorButton extends StatelessWidget {
  final VoidCallback onTap;

  const _QuickCalculatorButton({
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          width: 46,
          height: 42,
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
              color: Colors.white.withOpacity(0.06),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.22),
                blurRadius: 12,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Icon(
            Icons.calculate_rounded,
            size: 20,
            color: Colors.white.withOpacity(0.82),
          ),
        ),
      ),
    );
  }
}

class _HistoryFilterBar extends StatelessWidget {
  final _HistoryFilter current;
  final ValueChanged<_HistoryFilter> onChanged;

  const _HistoryFilterBar({
    required this.current,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _FilterChipBtn(
            text: 'All',
            icon: Icons.apps_rounded,
            active: current == _HistoryFilter.all,
            activeColor: const Color(0xFFF4B544),
            onTap: () => onChanged(_HistoryFilter.all),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _FilterChipBtn(
            text: 'Paid',
            icon: Icons.check_circle_rounded,
            active: current == _HistoryFilter.paid,
            activeColor: HistoryPalette.green,
            onTap: () => onChanged(_HistoryFilter.paid),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _FilterChipBtn(
            text: 'Pending',
            icon: Icons.schedule_rounded,
            active: current == _HistoryFilter.pending,
            activeColor: HistoryPalette.blue,
            onTap: () => onChanged(_HistoryFilter.pending),
          ),
        ),
      ],
    );
  }
}

class _FilterChipBtn extends StatelessWidget {
  final String text;
  final IconData icon;
  final bool active;
  final Color activeColor;
  final VoidCallback onTap;

  const _FilterChipBtn({
    required this.text,
    required this.icon,
    required this.active,
    required this.activeColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final iconTextColor = active
        ? activeColor
        : HistoryPalette.textMute.withOpacity(0.88);

    final borderColor = active
        ? Colors.white.withOpacity(0.10)
        : Colors.white.withOpacity(0.08);

    return AnimatedScale(
      scale: active ? 1.0 : 0.985,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(18),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            height: 44,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: active
                    ? [
                  const Color(0xFF3A4048),
                  const Color(0xFF2A2F37),
                ]
                    : [
                  const Color(0xFF353A42),
                  const Color(0xFF262B32),
                ],
              ),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: borderColor),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(active ? 0.26 : 0.22),
                  blurRadius: active ? 14 : 12,
                  offset: const Offset(0, 6),
                ),
                if (active)
                  BoxShadow(
                    color: activeColor.withOpacity(0.10),
                    blurRadius: 10,
                    spreadRadius: -4,
                    offset: const Offset(0, -2),
                  ),
              ],
            ),
            child: AnimatedDefaultTextStyle(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              style: TextStyle(
                color: iconTextColor,
                fontWeight: FontWeight.w800,
                fontSize: 12.5,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  AnimatedScale(
                    scale: active ? 1.0 : 0.94,
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeOutCubic,
                    child: Icon(
                      icon,
                      size: 16,
                      color: iconTextColor,
                      shadows: active
                          ? [
                        Shadow(
                          color: activeColor.withOpacity(0.25),
                          blurRadius: 8,
                        ),
                      ]
                          : null,
                    ),
                  ),
                  const SizedBox(width: 7),
                  Text(text),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DayGroupPanel extends StatelessWidget {
  final String title;
  final int count;
  final List<Widget> children;

  const _DayGroupPanel({
    required this.title,
    required this.count,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: children,
    );
  }
}

class _YearHeader extends StatelessWidget {
  final String title;
  final bool expanded;
  final VoidCallback onTap;

  const _YearHeader({
    required this.title,
    required this.expanded,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.white.withOpacity(0.045),
            Colors.white.withOpacity(0.018),
          ],
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: Colors.white.withOpacity(0.07),
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(18),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
            child: Row(
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.05),
                    borderRadius: BorderRadius.circular(9),
                    border: Border.all(
                      color: Colors.white.withOpacity(0.06),
                    ),
                  ),
                  child: AnimatedRotation(
                    turns: expanded ? 0.0 : -0.25,
                    duration: const Duration(milliseconds: 180),
                    child: Icon(
                      Icons.keyboard_arrow_down_rounded,
                      color: Colors.white.withOpacity(0.82),
                      size: 20,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  title,
                  style: const TextStyle(
                    color: HistoryPalette.textMain,
                    fontWeight: FontWeight.w900,
                    fontSize: 17,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Container(
                    height: 1,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Colors.white.withOpacity(0.14),
                          Colors.white.withOpacity(0.03),
                        ],
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
  }
}

class _MonthGroupPanel extends StatelessWidget {
  final String title;
  final bool expanded;
  final VoidCallback onTap;
  final List<Widget> children;
  final Widget? footer;

  const _MonthGroupPanel({
    required this.title,
    required this.expanded,
    required this.onTap,
    required this.children,
    this.footer,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: const Color(0xFF1A1E25),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color: Colors.white.withOpacity(0.07),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.28),
              blurRadius: 18,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          children: [
            Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: onTap,
                borderRadius: BorderRadius.circular(14),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                  child: Row(
                    children: [
                      AnimatedRotation(
                        turns: expanded ? 0.0 : -0.25,
                        duration: const Duration(milliseconds: 180),
                        child: Icon(
                          Icons.keyboard_arrow_down_rounded,
                          color: Colors.white.withOpacity(0.82),
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          title,
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.86),
                            fontWeight: FontWeight.w900,
                            fontSize: 15,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            if (expanded) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                child: Column(
                  children: children,
                ),
              ),
              if (footer != null) footer!,
            ],
          ],
        ),
      ),
    );
  }
}

class _MonthLoadMoreFooter extends StatelessWidget {
  final int hiddenCount;
  final VoidCallback onTap;

  const _MonthLoadMoreFooter({
    required this.hiddenCount,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Ink(
          width: double.infinity,
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.015),
            border: Border(
              top: BorderSide(
                color: Colors.white.withOpacity(0.08),
              ),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 13),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.keyboard_arrow_down_rounded,
                  size: 20,
                  color: Colors.white.withOpacity(0.82),
                ),
                const SizedBox(width: 6),
                Text(
                  '($hiddenCount)',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.82),
                    fontWeight: FontWeight.w800,
                    fontSize: 12.8,
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

class _HistoryCard extends StatelessWidget {
  final Map<String, dynamic> row;
  final String status;
  final Color statusColor;
  final String statusLabel;
  final IconData statusIcon;
  final String dateText;
  final String amountText;
  final String workedText;
  final String timeText;
  final String rateText;
  final String? bottomHintText;
  final List<String>? sessionLines;
  final VoidCallback onTap;

  const _HistoryCard({
    required this.row,
    required this.status,
    required this.statusColor,
    required this.statusLabel,
    required this.statusIcon,
    required this.dateText,
    required this.amountText,
    required this.workedText,
    required this.timeText,
    required this.rateText,
    this.bottomHintText,
    this.sessionLines,
    required this.onTap,
  });

  String _bottomText() {
    if (status == 'paid') return 'Tap to view full payment details';
    if (status == 'pending') return 'Tap to view full shift details';
    return 'Tap to view live shift details';
  }

  @override
  Widget build(BuildContext context) {
    final isActive = status == 'active';
    final isPending = status == 'pending';

    late final List<Color> cardColors;
    late final Color mainColor;

    if (isActive) {
      cardColors = [
        const Color(0xFF2A221D),
        const Color(0xFF211D1B),
        const Color(0xFF6F4314).withOpacity(0.72),
      ];
      mainColor = Colors.orangeAccent;
    } else if (isPending) {
      cardColors = [
        const Color(0xFF2B2C33),
        const Color(0xFF22242C),
        const Color(0xFF141822),
      ];
      mainColor = Colors.white70;
    } else {
      cardColors = [
        const Color(0xFF0E2A24),
        const Color(0xFF112820),
        const Color(0xFF3D5E1F).withOpacity(0.85),
      ];
      mainColor = Colors.greenAccent;
    }

    final bottomText = bottomHintText ?? _bottomText();

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(24),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(24),
        splashColor: Colors.white.withOpacity(0.04),
        highlightColor: Colors.white.withOpacity(0.02),
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: cardColors,
            ),
            border: Border.all(
              color: Colors.white.withOpacity(0.07),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        dateText,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.86),
                          fontWeight: FontWeight.w800,
                          fontSize: 13,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    _StatusChip(
                      text: statusLabel,
                      color: statusColor,
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 14),

              Center(
                child: Text(
                  amountText,
                  style: TextStyle(
                    color: mainColor,
                    fontWeight: FontWeight.w900,
                    fontSize: 34,
                    height: 1,
                  ),
                ),
              ),

              if (isActive) ...[
                const SizedBox(height: 10),
                Center(
                  child: Text(
                    workedText.replaceAll('h ', ':').replaceAll('m', ''),
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: mainColor,
                    ),
                  ),
                ),
              ],

              const SizedBox(height: 18),

              Padding(
                padding: const EdgeInsets.fromLTRB(18, 0, 18, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (isPending || status == 'paid')
                      _historyRow(
                        icon: Icons.timer_outlined,
                        label: 'Worked',
                        value: workedText,
                        color: mainColor,
                      ),

                    _historyRow(
                      icon: Icons.schedule_rounded,
                      label: 'Time',
                      value: timeText,
                      color: mainColor,
                    ),

                    if (sessionLines != null && sessionLines!.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      for (final line in sessionLines!) ...[
                        Padding(
                          padding: const EdgeInsets.only(left: 28, bottom: 4),
                          child: Text(
                            line,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.58),
                              fontSize: 11.3,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ],

                    const SizedBox(height: 8),

                    Row(
                      children: [
                        Icon(
                          Icons.touch_app_rounded,
                          size: 14,
                          color: Colors.white.withOpacity(0.34),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            bottomText,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.34),
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
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

  Widget _historyRow({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 10),
          Text(
            '$label: ',
            style: TextStyle(
              color: Colors.white.withOpacity(0.68),
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                color: color,
                fontSize: 13,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoMetricLine extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String text;
  final bool fullWidth;

  const _InfoMetricLine({
    required this.icon,
    required this.iconColor,
    required this.text,
    this.fullWidth = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: fullWidth ? double.infinity : null,
      height: 38,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.035),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withOpacity(0.10)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: iconColor),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: HistoryPalette.textMain,
                fontWeight: FontWeight.w800,
                fontSize: 12.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final String text;
  final Color color;

  const _StatusChip({
    required this.text,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 26,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withOpacity(0.24)),
      ),
      alignment: Alignment.center,
      child: Text(
        text,
        style: TextStyle(
          color: color.withOpacity(0.96),
          fontWeight: FontWeight.w900,
          fontSize: 10.5,
          letterSpacing: 0.25,
        ),
      ),
    );
  }
}

class _ShiftDetailsHeader extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final VoidCallback onClose;

  const _ShiftDetailsHeader({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(
          icon,
          size: 22,
          color: iconColor,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: HistoryPalette.textMain,
              fontWeight: FontWeight.w900,
              fontSize: 16,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onClose,
            borderRadius: BorderRadius.circular(16),
            child: Ink(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.04),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: Colors.white.withOpacity(0.10),
                ),
              ),
              child: Icon(
                Icons.close_rounded,
                size: 20,
                color: Colors.white.withOpacity(0.82),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _AddressPermissionNote extends StatelessWidget {
  const _AddressPermissionNote();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.04),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Colors.white.withOpacity(0.08),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.lock_outline_rounded,
            size: 18,
            color: HistoryPalette.textSoft.withOpacity(0.76),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Address visibility is limited. Ask your admin to enable access.',
              style: TextStyle(
                color: HistoryPalette.textSoft.withOpacity(0.78),
                fontWeight: FontWeight.w700,
                fontSize: 12.5,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DetailHeroCard extends StatelessWidget {
  final String amount;
  final Color color;
  final String subtitle;

  const _DetailHeroCard({
    required this.amount,
    required this.color,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 22, 16, 22),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            const Color(0xFF1F2430).withOpacity(0.98),
            const Color(0xFF171C25).withOpacity(0.97),
            const Color(0xFF10141C).withOpacity(0.99),
          ],
        ),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: Colors.white.withOpacity(0.08),
        ),
      ),
      child: Column(
        children: [
          Text(
            amount,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: color.withOpacity(0.90),
              fontWeight: FontWeight.w900,
              fontSize: 38,
              height: 1,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white.withOpacity(0.54),
              fontWeight: FontWeight.w700,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

class _SessionDetailCard extends StatelessWidget {
  final int index;
  final String timeText;
  final String workedText;
  final String amountText;
  final String rateText;

  const _SessionDetailCard({
    required this.index,
    required this.timeText,
    required this.workedText,
    required this.amountText,
    required this.rateText,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.04),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Colors.white.withOpacity(0.08),
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Text(
                'Session $index',
                style: const TextStyle(
                  color: HistoryPalette.textMain,
                  fontWeight: FontWeight.w900,
                  fontSize: 13.5,
                ),
              ),
              const Spacer(),
              Text(
                amountText,
                style: TextStyle(
                  color: Colors.white.withOpacity(0.84),
                  fontWeight: FontWeight.w900,
                  fontSize: 13.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _compactLine(
            icon: Icons.schedule_rounded,
            label: 'Time',
            value: timeText,
          ),
          const SizedBox(height: 8),
          _compactLine(
            icon: Icons.timer_rounded,
            label: 'Worked',
            value: workedText,
          ),
          const SizedBox(height: 8),
          _compactLine(
            icon: Icons.attach_money_rounded,
            label: 'Rate',
            value: rateText,
          ),
        ],
      ),
    );
  }

  Widget _compactLine({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Row(
      children: [
        Icon(
          icon,
          size: 15,
          color: HistoryPalette.textSoft.withOpacity(0.76),
        ),
        const SizedBox(width: 8),
        Text(
          '$label:',
          style: TextStyle(
            color: HistoryPalette.textSoft.withOpacity(0.72),
            fontWeight: FontWeight.w700,
            fontSize: 12,
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            value,
            textAlign: TextAlign.right,
            style: TextStyle(
              color: Colors.white.withOpacity(0.82),
              fontWeight: FontWeight.w800,
              fontSize: 12.2,
            ),
          ),
        ),
      ],
    );
  }
}

class _DetailSectionBlock extends StatelessWidget {
  final String title;
  final Widget child;

  const _DetailSectionBlock({
    required this.title,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            const Color(0xFF20242D).withOpacity(0.98),
            const Color(0xFF181C24).withOpacity(0.97),
            const Color(0xFF12161E).withOpacity(0.98),
          ],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.34),
            blurRadius: 24,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              color: HistoryPalette.textSoft.withOpacity(0.78),
              fontWeight: FontWeight.w900,
              fontSize: 13.5,
              letterSpacing: 0.25,
            ),
          ),
          const SizedBox(height: 10),
          Divider(
            height: 1,
            color: Colors.white.withOpacity(0.08),
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

class _DetailSectionLine extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _DetailSectionLine({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    final rowColor = Colors.white.withOpacity(0.52);

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              const Color(0xFF20242D).withOpacity(0.98),
              const Color(0xFF181C24).withOpacity(0.97),
              const Color(0xFF12161E).withOpacity(0.98),
            ],
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: Colors.white.withOpacity(0.08),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.20),
              blurRadius: 10,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 17,
              color: rowColor,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  color: rowColor,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 2,
              child: Align(
                alignment: Alignment.centerRight,
                child: Text(
                  value,
                  textAlign: TextAlign.right,
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.84),
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
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

class _LoadingHistoryPanel extends StatelessWidget {
  const _LoadingHistoryPanel();

  @override
  Widget build(BuildContext context) {
    return _SolidPanel(
      loading: false,
      header: const _SummaryHeader(
        title: 'History',
        subtitle: 'Loading',
        icon: Icons.history_rounded,
      ),
      child: const _BigPanel(
        child: Column(
          children: [
            _GhostHistoryCard(),
            SizedBox(height: 10),
            _GhostHistoryCard(),
          ],
        ),
      ),
    );
  }
}

class _GhostHistoryCard extends StatelessWidget {
  const _GhostHistoryCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        color: Colors.white.withOpacity(0.035),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: Column(
        children: [
          Container(
            height: 44,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.06),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(22),
                topRight: Radius.circular(22),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              children: [
                Container(
                  height: 64,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.05),
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: Container(
                        height: 38,
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.05),
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Container(
                        height: 38,
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.05),
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Container(
                  height: 38,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.05),
                    borderRadius: BorderRadius.circular(14),
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

class _EmptyHistoryState extends StatelessWidget {
  const _EmptyHistoryState();

  @override
  Widget build(BuildContext context) {
    return const _BigPanel(
      child: Column(
        children: [
          SizedBox(height: 8),
          Icon(
            Icons.history_toggle_off_rounded,
            size: 40,
            color: HistoryPalette.textMute,
          ),
          SizedBox(height: 12),
          Text(
            'No shifts found',
            style: TextStyle(
              color: HistoryPalette.textMain,
              fontWeight: FontWeight.w900,
              fontSize: 15,
            ),
          ),
          SizedBox(height: 6),
          Text(
            'Pull down to refresh after new updates.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: HistoryPalette.textSoft,
              fontWeight: FontWeight.w700,
              fontSize: 12.5,
            ),
          ),
          SizedBox(height: 8),
        ],
      ),
    );
  }
}

class _UnifiedHistoryHeader extends StatelessWidget {
  final String title;
  final String subtitle;
  final bool isPinned;
  final VoidCallback onTogglePin;
  final VoidCallback onBack;
  final Future<void> Function() onRefresh;

  const _UnifiedHistoryHeader({
    required this.title,
    required this.subtitle,
    required this.isPinned,
    required this.onTogglePin,
    required this.onBack,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 58,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _HistoryHeaderActionButton(
            icon: Icons.arrow_back_ios_new_rounded,
            onTap: onBack,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                      color: HistoryPalette.textMain,
                      letterSpacing: -0.2,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: HistoryPalette.textSoft.withOpacity(0.72),
                      fontWeight: FontWeight.w700,
                      fontSize: 11.5,
                      height: 1.2,
                    ),
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 12, top: 2),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                GestureDetector(
                  onTap: onTogglePin,
                  behavior: HitTestBehavior.opaque,
                  child: AnimatedRotation(
                    turns: isPinned ? 0.0 : 0.10,
                    duration: const Duration(milliseconds: 240),
                    curve: Curves.easeOutCubic,
                    child: AnimatedScale(
                      scale: isPinned ? 1.0 : 0.92,
                      duration: const Duration(milliseconds: 240),
                      curve: Curves.easeOutCubic,
                      child: Icon(
                        Icons.push_pin_outlined,
                        size: 22,
                        color: isPinned
                            ? const Color(0xFFFF5A5F)
                            : const Color(0xFFB6B6B6),
                        shadows: [
                          Shadow(
                            color: (isPinned
                                ? const Color(0xFFFF5A5F)
                                : const Color(0xFFB6B6B6))
                                .withOpacity(0.35),
                            blurRadius: 10,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                GestureDetector(
                  onTap: () => onRefresh(),
                  behavior: HitTestBehavior.opaque,
                  child: Icon(
                    Icons.refresh_rounded,
                    size: 25,
                    color: Colors.white.withOpacity(0.92),
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

class _AnimatedHistoryContent extends StatelessWidget {
  final String filterKey;
  final Widget child;

  const _AnimatedHistoryContent({
    required this.filterKey,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 180),
      switchInCurve: Curves.easeOut,
      switchOutCurve: Curves.easeIn,
      layoutBuilder: (currentChild, previousChildren) {
        return Stack(
          alignment: Alignment.topCenter,
          children: [
            ...previousChildren,
            if (currentChild != null) currentChild,
          ],
        );
      },
      transitionBuilder: (child, animation) {
        return FadeTransition(
          opacity: animation,
          child: child,
        );
      },
      child: KeyedSubtree(
        key: ValueKey(filterKey),
        child: child,
      ),
    );
  }
}

class _AnimatedHistoryItem extends StatelessWidget {
  final int index;
  final Widget child;

  const _AnimatedHistoryItem({
    required this.index,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final delay = (index * 35).clamp(0, 180);

    return TweenAnimationBuilder<double>(
      key: ValueKey('history-item-$index'),
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: 220 + delay),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) {
        return Opacity(
          opacity: value,
          child: Transform.translate(
            offset: Offset(0, (1 - value) * 10),
            child: child,
          ),
        );
      },
      child: child,
    );
  }
}

Widget _historyBottomNote(String text) {
  return Padding(
    padding: const EdgeInsets.only(top: 8),
    child: Align(
      alignment: Alignment.centerLeft,
      child: Text(
        text,
        style: TextStyle(
          color: Colors.white.withOpacity(0.34),
          fontSize: 12,
          fontWeight: FontWeight.w500,
        ),
      ),
    ),
  );
}

Widget _historyStatusPill({
  required String text,
  required Color color,
  IconData? icon,
}) {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
    decoration: BoxDecoration(
      color: color.withOpacity(0.14),
      borderRadius: BorderRadius.circular(999),
      border: Border.all(color: color.withOpacity(0.10)),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 6),
        ],
        Text(
          text,
          style: TextStyle(
            color: color,
            fontWeight: FontWeight.w800,
            fontSize: 12,
            letterSpacing: 0.2,
          ),
        ),
      ],
    ),
  );
}
class _NoGlowScrollBehavior extends ScrollBehavior {
  const _NoGlowScrollBehavior();

  @override
  Widget buildOverscrollIndicator(
      BuildContext context,
      Widget child,
      ScrollableDetails details,
      ) {
    return child;
  }

  @override
  Widget buildScrollbar(
      BuildContext context,
      Widget child,
      ScrollableDetails details,
      ) {
    return child;
  }
}

