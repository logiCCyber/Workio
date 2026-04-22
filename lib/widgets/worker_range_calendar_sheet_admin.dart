import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

enum WorkerCalendarDayState { none, active, unpaid, paid, mixed }

Future<DateTimeRange?> showWorkerRangeCalendarSheet({
  required BuildContext context,
  required DateTimeRange? initialRange,
  required Map<DateTime, List<Map<String, dynamic>>> workDays,
  required bool isPayments,
}) {
  return showModalBottomSheet<DateTimeRange>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.68),
    builder: (_) => _WorkerRangeCalendarSheet(
      initialRange: initialRange,
      workDays: workDays,
      isPayments: isPayments,
    ),
  );
}

class _WorkerRangeCalendarSheet extends StatefulWidget {
  final DateTimeRange? initialRange;
  final Map<DateTime, List<Map<String, dynamic>>> workDays;
  final bool isPayments;

  const _WorkerRangeCalendarSheet({
    required this.initialRange,
    required this.workDays,
    required this.isPayments,
  });

  @override
  State<_WorkerRangeCalendarSheet> createState() =>
      _WorkerRangeCalendarSheetState();
}

class _WorkerRangeCalendarSheetState extends State<_WorkerRangeCalendarSheet> {
  late DateTime _visibleMonth;
  DateTime? _start;
  DateTime? _end;

  @override
  void initState() {
    super.initState();
    final base = widget.initialRange?.start ?? DateTime.now();
    _visibleMonth = DateTime(base.year, base.month, 1);
    _start = widget.initialRange?.start;
    _end = widget.initialRange?.end;
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
      _visibleMonth = DateTime(_visibleMonth.year, _visibleMonth.month - 1, 1);
    });
  }

  void _goNextMonth() {
    setState(() {
      _visibleMonth = DateTime(_visibleMonth.year, _visibleMonth.month + 1, 1);
    });
  }

  void _resetRange() {
    setState(() {
      _start = null;
      _end = null;
    });
  }

  void _saveRange() {
    if (_start == null) return;

    final start = _dayOnly(_start!);
    final end = _dayOnly(_end ?? _start!);

    Navigator.pop(
      context,
      DateTimeRange(start: start, end: end),
    );
  }

  List<DateTime> _buildGridDays(DateTime month) {
    final first = DateTime(month.year, month.month, 1);
    final weekdayOffset = first.weekday % 7; // sunday = 0
    final gridStart = first.subtract(Duration(days: weekdayOffset));

    return List.generate(
      42,
          (index) => gridStart.add(Duration(days: index)),
    );
  }

  int _shiftCount(DateTime day) {
    final key = _dayOnly(day);
    return (widget.workDays[key] ?? const []).length;
  }

  WorkerCalendarDayState _stateOf(DateTime day) {
    final key = _dayOnly(day);
    final rows = widget.workDays[key] ?? const <Map<String, dynamic>>[];

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
      return 'Start Date — End Date';
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
    final accent = widget.isPayments ? Colors.lightBlueAccent : Colors.orangeAccent;
    final title = widget.isPayments ? 'Select payment period' : 'Select history period';
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
                  Color(0xFF10161E),
                  Color(0xFF0D131A),
                  Color(0xFF0A1016),
                ],
              ),
              borderRadius: BorderRadius.circular(30),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.08),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.46),
                  blurRadius: 34,
                  offset: const Offset(0, 18),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
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
                const SizedBox(height: 14),

                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Row(
                    children: [
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(
                          Icons.close_rounded,
                          color: Colors.white70,
                          size: 28,
                        ),
                      ),
                      Expanded(
                        child: Column(
                          children: [
                            Text(
                              title,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              _rangeLabel(),
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.56),
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 48),
                    ],
                  ),
                ),

                Divider(
                  height: 1,
                  color: Colors.white.withValues(alpha: 0.08),
                ),

                Expanded(
                  child: SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
                    child: Column(
                      children: [
                        Container(
                          padding: const EdgeInsets.fromLTRB(14, 14, 14, 16),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [
                                Color(0xFF1B222C),
                                Color(0xFF161D26),
                                Color(0xFF111820),
                              ],
                            ),
                            borderRadius: BorderRadius.circular(26),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.08),
                            ),
                          ),
                          child: Column(
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
                                gridDelegate:
                                const SliverGridDelegateWithFixedCrossAxisCount(
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

                        const SizedBox(height: 14),

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
                          'Badge above a day = number of shifts on that date',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.48),
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: Row(
                    children: [
                      Expanded(
                        child: InkWell(
                          onTap: _resetRange,
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
                          onTap: _saveRange,
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
                                  color: const Color(0xFF42D66B).withValues(alpha: 0.20),
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
            children: [
              if (count > 0)
                Positioned(
                  top: 3,
                  right: 3,
                  child: Container(
                    constraints: const BoxConstraints(
                      minWidth: 16,
                      minHeight: 16,
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 3),
                    decoration: BoxDecoration(
                      color: const Color(0xFF5A6070).withValues(alpha: 0.82),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.12),
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