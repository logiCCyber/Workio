import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

enum WorkerHistoryFilter { all, active, unpaid, paid }
enum WorkerPaymentsFilter { all, thisMonth, thisYear }
enum WorkerCalendarDayState { none, active, unpaid, paid, mixed }

class WorkerRangeCalendarResult {
  final DateTimeRange? range;
  final WorkerHistoryFilter historyFilter;
  final WorkerPaymentsFilter paymentsFilter;

  const WorkerRangeCalendarResult({
    required this.range,
    required this.historyFilter,
    required this.paymentsFilter,
  });
}

Future<WorkerRangeCalendarResult?> showWorkerRangeCalendarSheet({
  required BuildContext context,
  required DateTimeRange? initialRange,
  required Map<DateTime, List<Map<String, dynamic>>> workDays,
  required bool isPayments,
  required WorkerHistoryFilter historyFilter,
  required WorkerPaymentsFilter paymentsFilter,
}) {
  return showModalBottomSheet<WorkerRangeCalendarResult>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.70),
    builder: (_) => _WorkerRangeCalendarSheet(
      initialRange: initialRange,
      workDays: workDays,
      isPayments: isPayments,
      historyFilter: historyFilter,
      paymentsFilter: paymentsFilter,
    ),
  );
}

class _WorkerRangeCalendarSheet extends StatefulWidget {
  final DateTimeRange? initialRange;
  final Map<DateTime, List<Map<String, dynamic>>> workDays;
  final bool isPayments;
  final WorkerHistoryFilter historyFilter;
  final WorkerPaymentsFilter paymentsFilter;

  const _WorkerRangeCalendarSheet({
    required this.initialRange,
    required this.workDays,
    required this.isPayments,
    required this.historyFilter,
    required this.paymentsFilter,
  });

  @override
  State<_WorkerRangeCalendarSheet> createState() =>
      _WorkerRangeCalendarSheetState();
}

class _WorkerRangeCalendarSheetState extends State<_WorkerRangeCalendarSheet> {
  bool _slideToNext = true;
  late DateTime _visibleMonth;
  DateTime? _start;
  DateTime? _end;
  late WorkerHistoryFilter _historyFilter;
  late WorkerPaymentsFilter _paymentsFilter;

  @override
  void initState() {
    super.initState();
    final base = widget.initialRange?.start ?? DateTime.now();
    _visibleMonth = DateTime(base.year, base.month, 1);
    _start = widget.initialRange?.start;
    _end = widget.initialRange?.end;
    _historyFilter = widget.historyFilter;
    _paymentsFilter = widget.paymentsFilter;
  }

  DateTime _dayOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  bool _sameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  bool _isInRange(DateTime day) {
    if (_start == null || _end == null) return false;

    final d = _dayOnly(day);
    final s = _dayOnly(_start!);
    final e = _dayOnly(_end!);

    return !d.isBefore(s) && !d.isAfter(e);
  }

  void _onDayTap(DateTime day) {
    final d = _dayOnly(day);

    setState(() {
      if (_start == null || (_start != null && _end != null)) {
        _start = d;
        _end = null;
        return;
      }

      final start = _dayOnly(_start!);

      if (_sameDay(d, start)) {
        _end = d;
        return;
      }

      if (d.isBefore(start)) {
        _start = d;
        return;
      }

      _end = d;
    });
  }

  void _goPrevMonth() {
    setState(() {
      _slideToNext = false;
      _visibleMonth = DateTime(_visibleMonth.year, _visibleMonth.month - 1, 1);
    });
  }

  void _goNextMonth() {
    setState(() {
      _slideToNext = true;
      _visibleMonth = DateTime(_visibleMonth.year, _visibleMonth.month + 1, 1);
    });
  }

  void _resetAll() {
    setState(() {
      _start = null;
      _end = null;
      if (widget.isPayments) {
        _paymentsFilter = WorkerPaymentsFilter.all;
      } else {
        _historyFilter = WorkerHistoryFilter.all;
      }
    });
  }

  void _save() {
    final DateTimeRange? range;
    if (_start == null) {
      range = null;
    } else {
      range = DateTimeRange(
        start: _dayOnly(_start!),
        end: _dayOnly(_end ?? _start!),
      );
    }

    Navigator.pop(
      context,
      WorkerRangeCalendarResult(
        range: range,
        historyFilter: _historyFilter,
        paymentsFilter: _paymentsFilter,
      ),
    );
  }

  List<DateTime> _buildGridDays(DateTime month) {
    final first = DateTime(month.year, month.month, 1);
    final weekdayOffset = first.weekday % 7;
    final gridStart = first.subtract(Duration(days: weekdayOffset));

    return List.generate(
      42,
      (index) => gridStart.add(Duration(days: index)),
    );
  }

  List<Map<String, dynamic>> _rowsForDay(DateTime day) {
    final key = _dayOnly(day);
    final all = List<Map<String, dynamic>>.from(
      widget.workDays[key] ?? const <Map<String, dynamic>>[],
    );

    if (widget.isPayments) {
      return all;
    }

    switch (_historyFilter) {
      case WorkerHistoryFilter.all:
        return all;
      case WorkerHistoryFilter.active:
        return all.where((r) => r['end_time'] == null).toList();
      case WorkerHistoryFilter.unpaid:
        return all.where(
          (r) => r['end_time'] != null && r['paid_at'] == null,
        ).toList();
      case WorkerHistoryFilter.paid:
        return all.where((r) => r['paid_at'] != null).toList();
    }
  }

  int _shiftCount(DateTime day) {
    final rows = _rowsForDay(day);

    if (widget.isPayments) {
      switch (_paymentsFilter) {
        case WorkerPaymentsFilter.all:
          return rows.length;
        case WorkerPaymentsFilter.thisMonth:
          final now = DateTime.now();
          final d = _dayOnly(day);
          return (d.year == now.year && d.month == now.month) ? rows.length : 0;
        case WorkerPaymentsFilter.thisYear:
          final now = DateTime.now();
          final d = _dayOnly(day);
          return d.year == now.year ? rows.length : 0;
      }
    }

    return rows.length;
  }

  WorkerCalendarDayState _stateOf(DateTime day) {
    final rows = _rowsForDay(day);

    if (widget.isPayments) {
      switch (_paymentsFilter) {
        case WorkerPaymentsFilter.thisMonth:
          final now = DateTime.now();
          final d = _dayOnly(day);
          if (!(d.year == now.year && d.month == now.month)) {
            return WorkerCalendarDayState.none;
          }
          break;

        case WorkerPaymentsFilter.thisYear:
          final now = DateTime.now();
          final d = _dayOnly(day);
          if (d.year != now.year) {
            return WorkerCalendarDayState.none;
          }
          break;

        case WorkerPaymentsFilter.all:
          break;
      }

      if (rows.isEmpty) return WorkerCalendarDayState.none;

      // payments mode: есть выплата в этот день
      return WorkerCalendarDayState.paid;
    }

    if (rows.isEmpty) return WorkerCalendarDayState.none;

    final hasActive = rows.any((r) => r['end_time'] == null);
    final hasPaid = rows.any((r) => r['paid_at'] != null);
    final hasUnpaid = rows.any(
          (r) => r['end_time'] != null && r['paid_at'] == null,
    );

    if (hasPaid && hasUnpaid) return WorkerCalendarDayState.mixed;
    if (hasActive) return WorkerCalendarDayState.active;
    if (hasPaid) return WorkerCalendarDayState.paid;
    if (hasUnpaid) return WorkerCalendarDayState.unpaid;

    return WorkerCalendarDayState.none;
  }

  String _rangeLabel() {
    if (_start == null && _end == null) {
      return 'All dates';
    }

    if (_start != null && _end == null) {
      return DateFormat('d MMM yyyy').format(_start!);
    }

    final s = _start!;
    final e = _end!;
    final sameYear = s.year == e.year;
    final sameDay = _sameDay(s, e);

    if (sameDay) {
      return DateFormat('d MMM yyyy').format(s);
    }

    if (sameYear) {
      return '${DateFormat('d MMM').format(s)} — ${DateFormat('d MMM yyyy').format(e)}';
    }

    return '${DateFormat('d MMM yyyy').format(s)} — ${DateFormat('d MMM yyyy').format(e)}';
  }

  @override
  Widget build(BuildContext context) {
    final monthText = DateFormat('MMMM yyyy').format(_visibleMonth);
    final days = _buildGridDays(_visibleMonth);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 18, 10, 10),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(30),
          child: Container(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.92,
            ),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0xFF0C131B),
                  Color(0xFF091018),
                  Color(0xFF060C12),
                ],
              ),
              borderRadius: BorderRadius.circular(30),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.08),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.48),
                  blurRadius: 36,
                  offset: const Offset(0, 18),
                ),
              ],
            ),
            child: Column(
              children: [
                const SizedBox(height: 10),
                Container(
                  width: 52,
                  height: 5,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                const SizedBox(height: 10),

                Flexible(
                  fit: FlexFit.loose,
                  child: SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(16, 6, 16, 8),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.fromLTRB(14, 14, 14, 16),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [
                                Color(0xFF16202A),
                                Color(0xFF111923),
                                Color(0xFF0D141C),
                              ],
                            ),
                            borderRadius: BorderRadius.circular(24),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.08),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Quick filter',
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.60),
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 12),
                              Row(
                                children: widget.isPayments
                                    ? [
                                  Expanded(
                                    child: _ModeChip(
                                      icon: Icons.grid_view_rounded,
                                      label: 'All',
                                      activeColor: Colors.lightBlueAccent,
                                      selected: _paymentsFilter == WorkerPaymentsFilter.all,
                                      onTap: () {
                                        setState(() {
                                          _paymentsFilter = WorkerPaymentsFilter.all;
                                        });
                                      },
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: _ModeChip(
                                      icon: Icons.calendar_view_month_rounded,
                                      label: 'This month',
                                      activeColor: Colors.orangeAccent,
                                      selected: _paymentsFilter == WorkerPaymentsFilter.thisMonth,
                                      onTap: () {
                                        setState(() {
                                          _paymentsFilter = WorkerPaymentsFilter.thisMonth;
                                        });
                                      },
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: _ModeChip(
                                      icon: Icons.event_note_rounded,
                                      label: 'This year',
                                      activeColor: Colors.greenAccent,
                                      selected: _paymentsFilter == WorkerPaymentsFilter.thisYear,
                                      onTap: () {
                                        setState(() {
                                          _paymentsFilter = WorkerPaymentsFilter.thisYear;
                                        });
                                      },
                                    ),
                                  ),
                                ]
                                    : [
                                  Expanded(
                                    child: _ModeChip(
                                      icon: Icons.grid_view_rounded,
                                      label: 'All',
                                      activeColor: Colors.lightBlueAccent,
                                      selected: _historyFilter == WorkerHistoryFilter.all,
                                      onTap: () {
                                        setState(() {
                                          _historyFilter = WorkerHistoryFilter.all;
                                        });
                                      },
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: _ModeChip(
                                      icon: Icons.hourglass_bottom_rounded,
                                      label: 'Unpaid',
                                      activeColor: Colors.orangeAccent,
                                      selected: _historyFilter == WorkerHistoryFilter.unpaid,
                                      onTap: () {
                                        setState(() {
                                          _historyFilter = WorkerHistoryFilter.unpaid;
                                        });
                                      },
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: _ModeChip(
                                      icon: Icons.check_circle_outline_rounded,
                                      label: 'Paid',
                                      activeColor: Colors.greenAccent,
                                      selected: _historyFilter == WorkerHistoryFilter.paid,
                                      onTap: () {
                                        setState(() {
                                          _historyFilter = WorkerHistoryFilter.paid;
                                        });
                                      },
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 14),

                        Container(
                          padding: const EdgeInsets.fromLTRB(14, 14, 14, 16),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [
                                Color(0xFF18212C),
                                Color(0xFF121A24),
                                Color(0xFF0E151D),
                              ],
                            ),
                            borderRadius: BorderRadius.circular(26),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.08),
                            ),
                          ),
                          child: AnimatedSwitcher(
                            duration: const Duration(milliseconds: 300),
                            switchInCurve: Curves.easeOutCubic,
                            switchOutCurve: Curves.easeInCubic,
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
                              final currentKey = ValueKey('${_visibleMonth.year}-${_visibleMonth.month}');
                              final isIncoming = child.key == currentKey;

                              final beginOffset = isIncoming
                                  ? (_slideToNext ? const Offset(0.18, 0) : const Offset(-0.18, 0))
                                  : (_slideToNext ? const Offset(-0.18, 0) : const Offset(0.18, 0));

                              return ClipRect(
                                child: FadeTransition(
                                  opacity: animation,
                                  child: SlideTransition(
                                    position: Tween<Offset>(
                                      begin: beginOffset,
                                      end: Offset.zero,
                                    ).animate(
                                      CurvedAnimation(
                                        parent: animation,
                                        curve: Curves.easeOutCubic,
                                      ),
                                    ),
                                    child: child,
                                  ),
                                ),
                              );
                            },
                            child: Column(
                              key: ValueKey('${_visibleMonth.year}-${_visibleMonth.month}'),
                              children: [
                                Row(
                                  children: [
                                    IconButton(
                                      onPressed: _goPrevMonth,
                                      splashRadius: 18,
                                      icon: const Icon(
                                        Icons.chevron_left_rounded,
                                        color: Colors.white70,
                                        size: 30,
                                      ),
                                    ),
                                    Expanded(
                                      child: Text(
                                        monthText,
                                        textAlign: TextAlign.center,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 16,
                                          fontWeight: FontWeight.w900,
                                        ),
                                      ),
                                    ),
                                    IconButton(
                                      onPressed: _goNextMonth,
                                      splashRadius: 18,
                                      icon: const Icon(
                                        Icons.chevron_right_rounded,
                                        color: Colors.white70,
                                        size: 30,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                const Row(
                                  children: [
                                    _WeekLabel('Sun'),
                                    _WeekLabel('Mon'),
                                    _WeekLabel('Tue'),
                                    _WeekLabel('Wed'),
                                    _WeekLabel('Thu'),
                                    _WeekLabel('Fri'),
                                    _WeekLabel('Sat'),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                GridView.builder(
                                  shrinkWrap: true,
                                  physics: const NeverScrollableScrollPhysics(),
                                  itemCount: days.length,
                                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                                    crossAxisCount: 7,
                                    mainAxisSpacing: 8,
                                    crossAxisSpacing: 8,
                                    childAspectRatio: 0.78,
                                  ),
                                  itemBuilder: (context, index) {
                                    final day = days[index];
                                    final inMonth = day.month == _visibleMonth.month;
                                    final isStart = _start != null && _sameDay(day, _start!);
                                    final isEnd = _end != null && _sameDay(day, _end!);
                                    final isRange = _isInRange(day);
                                    final count = _shiftCount(day);
                                    final state = _stateOf(day);

                                    return _CalendarDayCell(
                                      day: day,
                                      inMonth: inMonth,
                                      isStart: isStart,
                                      isEnd: isEnd,
                                      isInRange: isRange,
                                      count: count,
                                      state: state,
                                      onTap: () => _onDayTap(day),
                                    );
                                  },
                                ),
                              ],
                            ),
                          ),
                        ),

                        const SizedBox(height: 14),

                        if (widget.isPayments) ...[
                          Wrap(
                            alignment: WrapAlignment.center,
                            spacing: 16,
                            runSpacing: 8,
                            children: const [
                              _LegendItem(
                                color: Colors.greenAccent,
                                label: 'Paid day',
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Tap one day for a single date, or two days for a range',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.38),
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ] else ...[
                          if (widget.isPayments) ...[
                            Wrap(
                              alignment: WrapAlignment.center,
                              spacing: 16,
                              runSpacing: 8,
                              children: const [
                                _LegendItem(
                                  color: Colors.greenAccent,
                                  label: 'Paid day',
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            Text(
                              'Badge = payments on that date',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.48),
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ] else ...[
                            Wrap(
                              alignment: WrapAlignment.center,
                              spacing: 16,
                              runSpacing: 8,
                              children: const [
                                _LegendItem(
                                  color: Colors.greenAccent,
                                  label: 'Paid',
                                ),
                                _LegendItem(
                                  color: Colors.orangeAccent,
                                  label: 'Unpaid',
                                ),
                                _LegendItem(
                                  color: Colors.lightBlueAccent,
                                  label: 'Active',
                                ),
                                _LegendMixedItem(
                                  label: 'Mixed',
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            Text(
                              'Badge = shifts on that date',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.48),
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ]
                        ],
                      ],
                    ),
                  ),
                ),

                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 6, 16, 16),
                  child: Row(
                    children: [
                      Expanded(
                        child: InkWell(
                          onTap: _resetAll,
                          borderRadius: BorderRadius.circular(18),
                          child: Container(
                            height: 54,
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [
                                  Color(0xFF222A35),
                                  Color(0xFF18202A),
                                ],
                              ),
                              borderRadius: BorderRadius.circular(18),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.08),
                              ),
                            ),
                            child: const Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.restart_alt_rounded,
                                  color: Colors.white70,
                                  size: 20,
                                ),
                                SizedBox(width: 8),
                                Text(
                                  'Reset',
                                  style: TextStyle(
                                    color: Colors.white70,
                                    fontSize: 15,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: InkWell(
                          onTap: _save,
                          borderRadius: BorderRadius.circular(18),
                          child: Container(
                            height: 54,
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [
                                  Color(0xFF42D66B),
                                  Color(0xFF2FA955),
                                ],
                              ),
                              borderRadius: BorderRadius.circular(18),
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(0xFF42D66B)
                                      .withValues(alpha: 0.20),
                                  blurRadius: 18,
                                  offset: const Offset(0, 10),
                                ),
                              ],
                            ),
                            child: const Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.check_rounded,
                                  color: Colors.black,
                                  size: 20,
                                ),
                                SizedBox(width: 8),
                                Text(
                                  'Save',
                                  style: TextStyle(
                                    color: Colors.black,
                                    fontSize: 15,
                                    fontWeight: FontWeight.w900,
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
          ),
        ),
      ),
    );
  }
}

class _TopRangeField extends StatelessWidget {
  final String text;
  final VoidCallback onTap;

  const _TopRangeField({
    required this.text,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        height: 58,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFF323A47),
              Color(0xFF262E39),
              Color(0xFF202732),
            ],
          ),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.08),
          ),
        ),
        child: Row(
          children: [
            const Icon(
              Icons.calendar_today_rounded,
              size: 18,
              color: Colors.white70,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              size: 22,
              color: Colors.white.withValues(alpha: 0.50),
            ),
          ],
        ),
      ),
    );
  }
}

class _ModeChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Color activeColor;

  const _ModeChip({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
    required this.activeColor,
  });

  @override
  Widget build(BuildContext context) {
    final inactiveIcon = Colors.white.withValues(alpha: 0.62);
    final inactiveText = Colors.white.withValues(alpha: 0.76);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOutCubic,
          height: 76,
          decoration: BoxDecoration(
            gradient: selected
                ? const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color(0xFF2B3441),
                Color(0xFF222B36),
                Color(0xFF1A222C),
              ],
            )
                : const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color(0xFF242C37),
                Color(0xFF1C232D),
                Color(0xFF161D26),
              ],
            ),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: selected
                  ? activeColor.withValues(alpha: 0.72)
                  : Colors.white.withValues(alpha: 0.07),
              width: selected ? 1.2 : 1,
            ),
            boxShadow: selected
                ? [
              BoxShadow(
                color: activeColor.withValues(alpha: 0.16),
                blurRadius: 16,
                spreadRadius: 0.5,
                offset: const Offset(0, 8),
              ),
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.22),
                blurRadius: 14,
                offset: const Offset(0, 8),
              ),
            ]
                : null,
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              TweenAnimationBuilder<Color?>(
                tween: ColorTween(
                  end: selected ? activeColor : inactiveIcon,
                ),
                duration: const Duration(milliseconds: 260),
                curve: Curves.easeOutCubic,
                builder: (_, color, __) {
                  return Icon(
                    icon,
                    size: 20,
                    color: color,
                  );
                },
              ),
              const SizedBox(height: 10),
              TweenAnimationBuilder<Color?>(
                tween: ColorTween(
                  end: selected ? activeColor : inactiveText,
                ),
                duration: const Duration(milliseconds: 260),
                curve: Curves.easeOutCubic,
                builder: (_, color, __) {
                  return Text(
                    label,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: color,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w900,
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _WeekLabel extends StatelessWidget {
  final String text;

  const _WeekLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Center(
        child: Text(
          text,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.60),
            fontSize: 12,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}

class _CalendarDayCell extends StatelessWidget {
  final DateTime day;
  final bool inMonth;
  final bool isStart;
  final bool isEnd;
  final bool isInRange;
  final int count;
  final WorkerCalendarDayState state;
  final VoidCallback onTap;

  const _CalendarDayCell({
    required this.day,
    required this.inMonth,
    required this.isStart,
    required this.isEnd,
    required this.isInRange,
    required this.count,
    required this.state,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final bool isEdge = isStart || isEnd;
    final bool isSelected = isEdge || isInRange;

    final bg = isEdge
        ? const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFF4E5664),
              Color(0xFF3B424E),
            ],
          )
        : isInRange
            ? LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Colors.greenAccent.withValues(alpha: 0.16),
                  Colors.greenAccent.withValues(alpha: 0.08),
                ],
              )
            : null;

    final borderColor = isEdge
        ? Colors.white.withValues(alpha: 0.16)
        : isInRange
            ? Colors.greenAccent.withValues(alpha: 0.12)
            : Colors.white.withValues(alpha: 0.04);

    final textColor = !inMonth
        ? Colors.white.withValues(alpha: 0.24)
        : isSelected
            ? Colors.white
            : Colors.white.withValues(alpha: 0.88);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Ink(
          decoration: BoxDecoration(
            gradient: bg,
            color: bg == null ? Colors.white.withValues(alpha: 0.015) : null,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: borderColor),
          ),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              if (count > 0)
                Positioned(
                  top: -2,
                  right: -1,
                  child: Container(
                    constraints: const BoxConstraints(
                      minWidth: 17,
                      minHeight: 17,
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 3),
                    decoration: BoxDecoration(
                      color: const Color(0xFF5A6070).withValues(alpha: 0.88),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.13),
                      ),
                    ),
                    child: Center(
                      child: Text(
                        '$count',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 9,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ),
                ),
              Center(
                child: Text(
                  '${day.day}',
                  style: TextStyle(
                    color: textColor,
                    fontSize: 14,
                    fontWeight: isEdge ? FontWeight.w900 : FontWeight.w700,
                  ),
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 8,
                child: Center(
                  child: _DayStateDot(state: state),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DayStateDot extends StatelessWidget {
  final WorkerCalendarDayState state;

  const _DayStateDot({
    required this.state,
  });

  @override
  Widget build(BuildContext context) {
    switch (state) {
      case WorkerCalendarDayState.none:
        return const SizedBox(width: 8, height: 8);
      case WorkerCalendarDayState.active:
        return _dot(Colors.lightBlueAccent);
      case WorkerCalendarDayState.unpaid:
        return _dot(Colors.orangeAccent);
      case WorkerCalendarDayState.paid:
        return _dot(Colors.greenAccent);
      case WorkerCalendarDayState.mixed:
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _dot(Colors.greenAccent, 5),
            const SizedBox(width: 3),
            _dot(Colors.orangeAccent, 5),
          ],
        );
    }
  }

  Widget _dot(Color color, [double size = 6]) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
      ),
    );
  }
}

class _LegendItem extends StatelessWidget {
  final Color color;
  final String label;

  const _LegendItem({
    required this.color,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 13,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }
}

class _LegendMixedItem extends StatelessWidget {
  final String label;

  const _LegendMixedItem({
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              colors: [
                Colors.greenAccent,
                Colors.orangeAccent,
              ],
            ),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 13,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }
}
