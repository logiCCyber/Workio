import 'package:flutter/material.dart';
import 'package:table_calendar/table_calendar.dart';
import 'dart:ui';

class PayCalendarSheet extends StatefulWidget {
  final Map<DateTime, List<Map<String, dynamic>>> workDays;

  const PayCalendarSheet({
    super.key,
    required this.workDays,
  });

  @override
  State<PayCalendarSheet> createState() => _PayCalendarSheetState();
}

class _PayCalendarSheetState extends State<PayCalendarSheet> {
  DateTime _focusedDay = DateTime.now();
  DateTime _k(DateTime d) => DateTime(d.year, d.month, d.day);
  DateTime? _rangeStart;
  DateTime? _rangeEnd;
  DateTime _dayKey(DateTime d) => DateTime(d.year, d.month, d.day);

  Color? _dayStatusColor(DateTime day) {
    final key = _k(day);
    final rows = widget.workDays[key];
    if (rows == null || rows.isEmpty) return null;

    final allPaid = rows.every((r) => r['paid_at'] != null);
    return allPaid ? Colors.green : Colors.orange;
  }

  DayPayStatus _dayPayStatus(DateTime day) {
    final key = _k(day);
    final rows = widget.workDays[key];
    if (rows == null || rows.isEmpty) return DayPayStatus.none;

    final hasPaid = rows.any((r) => r['paid_at'] != null);
    final hasUnpaid = rows.any((r) => r['paid_at'] == null);

    if (hasPaid && hasUnpaid) return DayPayStatus.mixed;
    if (hasPaid) return DayPayStatus.paidOnly;
    if (hasUnpaid) return DayPayStatus.unpaidOnly;

    return DayPayStatus.none;
  }


  // bool get _hasPaidInRange {
  //   if (_rangeStart == null || _rangeEnd == null) return false;
  //
  //   DateTime day = _rangeStart!;
  //   while (!day.isAfter(_rangeEnd!)) {
  //     final key = DateTime(day.year, day.month, day.day);
  //     final rows = widget.workDays[key];
  //     if (rows != null && rows.isNotEmpty) {
  //       final anyPaid = rows.any((r) => r['paid_at'] != null);
  //       if (anyPaid) return true;
  //     }
  //     day = day.add(const Duration(days: 1));
  //   }
  //   return false;
  // }

  // bool get _hasUnpaidInRange {
  //   if (_rangeStart == null || _rangeEnd == null) return false;
  //
  //   DateTime day = _rangeStart!;
  //   while (!day.isAfter(_rangeEnd!)) {
  //     final key = DateTime(day.year, day.month, day.day);
  //     final rows = widget.workDays[key];
  //
  //     if (rows != null && rows.isNotEmpty) {
  //       final anyUnpaid = rows.any((r) => r['paid_at'] == null);
  //       if (anyUnpaid) return true;
  //     }
  //
  //     day = day.add(const Duration(days: 1));
  //   }
  //   return false;
  // }


  // bool get _canPay {
  //   if (_rangeStart == null || _rangeEnd == null) return false;
  //
  //   return !_hasPaidInRange && _hasUnpaidInRange;
  // }
  /// 1️⃣ Есть ли вообще ХОТЬ ОДНА смена в диапазоне
  bool get _hasAnyShiftInRange {
    if (_rangeStart == null || _rangeEnd == null) return false;

    DateTime day = _rangeStart!;
    while (!day.isAfter(_rangeEnd!)) {
      final rows = widget.workDays[
      _k(day)
      ];
      if (rows != null && rows.isNotEmpty) return true;
      day = day.add(const Duration(days: 1));
    }
    return false;
  }

  /// 2️⃣ Есть ли PAID смены (пустые дни игнорируем)
  bool get _hasPaidOnlyDayInRange {
    if (_rangeStart == null || _rangeEnd == null) return false;

    DateTime day = _rangeStart!;
    while (!day.isAfter(_rangeEnd!)) {
      final status = _dayPayStatus(day);
      if (status == DayPayStatus.paidOnly) return true; // ✅ tolko polnostyu paid dni blokiruyut
      day = day.add(const Duration(days: 1));
    }
    return false;
  }

  bool get _canPay {
    return _hasUnpaidInRange && !_hasPaidOnlyDayInRange;
  }

  /// 3️⃣ Есть ли UNPAID смены
  bool get _hasUnpaidInRange {
    if (_rangeStart == null || _rangeEnd == null) return false;

    DateTime day = _rangeStart!;
    while (!day.isAfter(_rangeEnd!)) {
      final rows = widget.workDays[
      _k(day)
      ];
      if (rows != null && rows.any((r) => r['paid_at'] == null)) {
        return true;
      }
      day = day.add(const Duration(days: 1));
    }
    return false;
  }

  int _shiftCount(DateTime day) {
    final rows = widget.workDays[_k(day)];
    return rows?.length ?? 0;
  }

  Widget _buildCalendarDay(
      DateTime day, {
        bool outside = false,
        bool today = false,
        bool selected = false,
        bool rangeStart = false,
        bool rangeEnd = false,
        bool withinRange = false,
      }) {
    final count = _shiftCount(day);
    final status = _dayPayStatus(day);

    final bool isMainSelected = selected || rangeStart || rangeEnd;

    final textColor = outside
        ? Colors.white.withOpacity(0.24)
        : Colors.white.withOpacity(0.88);

    return Center(
      child: SizedBox(
        width: 38,
        height: 46,
        child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.center,
          children: [
            // Подложка для дней внутри диапазона
            if (withinRange)
              Positioned(
                left: 2,
                right: 2,
                top: 8,
                bottom: 8,
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.045),
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),

            // Круг для выбранного дня / начала / конца диапазона
            if (isMainSelected || (today && !withinRange))
              Container(
                width: 31,
                height: 31,
                decoration: BoxDecoration(
                  color: isMainSelected
                      ? const Color(0xFFB7BCFF)
                      : Colors.white.withOpacity(0.08),
                  shape: BoxShape.circle,
                ),
              ),

            // Число дня
            Text(
              '${day.day}',
              style: TextStyle(
                color: isMainSelected ? Colors.white : textColor,
                fontWeight: (isMainSelected || today)
                    ? FontWeight.w800
                    : FontWeight.w600,
                fontSize: 15,
              ),
            ),

            // Badge сверху справа, только если 2+ смен
            if (count >= 2)
              Positioned(
                top: -1,
                right: -2,
                child: _ShiftCountBadge(count: count),
              ),

            // Точка статуса внизу
            if (status != DayPayStatus.none)
              Positioned(
                bottom: 2,
                child: Opacity(
                  opacity: outside ? 0.55 : 1,
                  child: _DayMarkerDot(status: status),
                ),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Material(
          color: const Color(0xFF1B1C20),
          borderRadius: BorderRadius.circular(28),
          clipBehavior: Clip.antiAlias,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(22, 20, 22, 22),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                /// Header


                const SizedBox(height: 14),
                const Divider(color: Colors.white12),
                const SizedBox(height: 8),

                /// Calendar
                /// Calendar (glass block)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.045),
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(
                      color: Colors.white.withOpacity(0.08),
                    ),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      /// Centered title
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: const [
                          Icon(Icons.payments_rounded,
                              color: Colors.white70, size: 18),
                          SizedBox(width: 10),
                          Text(
                            'Select payment period',
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                              letterSpacing: 0.2,
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 14),
                      Divider(color: Colors.white.withOpacity(0.12)),
                      const SizedBox(height: 12),

                      TableCalendar(
                        firstDay: DateTime.utc(2023, 1, 1),
                        lastDay: DateTime.now(),
                        focusedDay: _focusedDay,
                        rangeSelectionMode: RangeSelectionMode.enforced,
                        rangeStartDay: _rangeStart,
                        rangeEndDay: _rangeEnd,
                        onRangeSelected: (start, end, focused) {
                          setState(() {
                            _rangeStart = start;
                            _rangeEnd = end;
                            _focusedDay = focused;
                          });

                          // ✅ DEBUG: проверяем совпадают ли ключи
                          if (start != null) {
                            final key = DateTime(start.year, start.month, start.day);
                            debugPrint('rangeStart raw=$start');
                            debugPrint('rangeStart key=$key');
                          }

                          debugPrint('workDays keys sample:');
                          widget.workDays.keys.take(10).forEach((k) {
                            debugPrint('  key=$k');
                          });
                        },
                        calendarFormat: CalendarFormat.month,
                        availableCalendarFormats: const {
                          CalendarFormat.month: 'Month',
                        },
                        headerStyle: const HeaderStyle(
                          titleCentered: true,
                          formatButtonVisible: false,
                          leftChevronIcon:
                          Icon(Icons.chevron_left, color: Colors.white70),
                          rightChevronIcon:
                          Icon(Icons.chevron_right, color: Colors.white70),
                          titleTextStyle: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                        daysOfWeekStyle: DaysOfWeekStyle(
                          weekdayStyle: TextStyle(color: Colors.white54),
                          weekendStyle: TextStyle(color: Colors.white54),
                        ),
                        calendarStyle: CalendarStyle(
                          defaultTextStyle:
                          const TextStyle(color: Colors.white70),
                          weekendTextStyle:
                          const TextStyle(color: Colors.white70),
                          outsideTextStyle:
                          const TextStyle(color: Colors.white24),

                          rangeHighlightColor:
                          Colors.white.withOpacity(0.04),

                          rangeStartDecoration: const BoxDecoration(
                            color: Colors.blueAccent,
                            shape: BoxShape.circle,
                          ),
                          rangeEndDecoration: const BoxDecoration(
                            color: Colors.blueAccent,
                            shape: BoxShape.circle,
                          ),

                          withinRangeTextStyle: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        calendarBuilders: CalendarBuilders(
                          defaultBuilder: (context, day, focusedDay) {
                            return _buildCalendarDay(day);
                          },
                          outsideBuilder: (context, day, focusedDay) {
                            return _buildCalendarDay(day, outside: true);
                          },
                          todayBuilder: (context, day, focusedDay) {
                            return _buildCalendarDay(day, today: true);
                          },
                          selectedBuilder: (context, day, focusedDay) {
                            return _buildCalendarDay(day, selected: true);
                          },
                          rangeStartBuilder: (context, day, focusedDay) {
                            return _buildCalendarDay(day, rangeStart: true);
                          },
                          rangeEndBuilder: (context, day, focusedDay) {
                            return _buildCalendarDay(day, rangeEnd: true);
                          },
                          withinRangeBuilder: (context, day, focusedDay) {
                            return _buildCalendarDay(day, withinRange: true);
                          },
                        ),

                      ),
                    ],
                  ),
                ),


                const SizedBox(height: 14),

                /// Legend
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: const [
                    _LegendDot(Colors.green, 'Paid'),
                    SizedBox(width: 16),
                    _LegendDot(Colors.orange, 'Unpaid'),
                    SizedBox(width: 16),
                    _MixedLegend(),
                  ],
                ),

                const SizedBox(height: 8),
                Text(
                  'Small badge above a day = number of shifts on that date',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 11.5,
                    color: Colors.white54,
                    fontWeight: FontWeight.w500,
                  ),
                ),

                const SizedBox(height: 12),

                if (_rangeStart != null && _rangeEnd != null && !_canPay) ...[
                  _PendingCapsule(
                    text: !_hasAnyShiftInRange
                        ? 'No unpaid shifts in selected period'
                        : 'This period includes already paid days',
                    icon: !_hasAnyShiftInRange
                        ? Icons.info_outline
                        : Icons.warning_amber_rounded,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    !_hasAnyShiftInRange
                        ? 'Select a period that includes unpaid days.'
                        : 'Select only unpaid days to continue.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12.5,
                      color: Colors.white.withOpacity(0.45),
                    ),
                  ),
                  const SizedBox(height: 14),
                ],

                /// Continue button

                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _canPay
                          ? const Color(0xFF4CAF50)
                          : Colors.white.withOpacity(0.08),
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18),
                      ),
                    ),
                    onPressed: _canPay
                        ? () {
                      final s = DateTime(_rangeStart!.year, _rangeStart!.month, _rangeStart!.day);
                      final e = DateTime(_rangeEnd!.year, _rangeEnd!.month, _rangeEnd!.day, 23, 59, 59, 999);

                      Navigator.pop(context, DateTimeRange(start: s, end: e));
                    }
                        : null,
                    child: Text(
                      'Continue',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: _canPay ? Colors.black : Colors.white70,
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

enum DayPayStatus { none, paidOnly, unpaidOnly, mixed }

class _PendingCapsule extends StatelessWidget {
  final String text;
  final IconData icon;

  const _PendingCapsule({
    required this.text,
    this.icon = Icons.schedule_rounded,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.08),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: Colors.white54),
          const SizedBox(width: 6),
          Text(
            text,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _LegendDot extends StatelessWidget {
  final Color color;
  final String text;

  const _LegendDot(this.color, this.text);

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Text(text, style: const TextStyle(fontSize: 12)),
      ],
    );
  }
}

class _DayMarkerDot extends StatelessWidget {
  final DayPayStatus status;

  const _DayMarkerDot({required this.status});

  @override
  Widget build(BuildContext context) {
    const double size = 7;

    switch (status) {
      case DayPayStatus.none:
        return const SizedBox.shrink();

      case DayPayStatus.paidOnly:
        return Container(
          width: size,
          height: size,
          decoration: const BoxDecoration(
            color: Colors.green,
            shape: BoxShape.circle,
          ),
        );

      case DayPayStatus.unpaidOnly:
        return Container(
          width: size,
          height: size,
          decoration: const BoxDecoration(
            color: Colors.orange,
            shape: BoxShape.circle,
          ),
        );

      case DayPayStatus.mixed:
        return CustomPaint(
          size: const Size(size, size),
          painter: _MixedDotPainter(),
        );
    }
  }
}

class _ShiftCountBadge extends StatelessWidget {
  final int count;

  const _ShiftCountBadge({required this.count});

  @override
  Widget build(BuildContext context) {
    final text = count > 9 ? '9+' : '$count';

    return Container(
      constraints: const BoxConstraints(
        minWidth: 16,
        minHeight: 16,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      decoration: BoxDecoration(
        color: const Color(0xFF3A3D46),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: Colors.white.withOpacity(0.14),
        ),
      ),
      child: Center(
        child: Text(
          text,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 9.5,
            fontWeight: FontWeight.w800,
            height: 1,
          ),
        ),
      ),
    );
  }
}

class _MixedDotPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final r = size.width / 2;
    final center = Offset(r, r);

    // Левая половина — зелёная
    final greenPaint = Paint()..color = Colors.green;

    // Правая половина — оранжевая
    final orangePaint = Paint()..color = Colors.orange;

    // Полукруг слева
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: r),
      3.1415926535 / 2, // 90°
      3.1415926535,     // 180°
      true,
      greenPaint,
    );

    // Полукруг справа
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: r),
      -3.1415926535 / 2, // -90°
      3.1415926535,      // 180°
      true,
      orangePaint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
class _MixedLegend extends StatelessWidget {
  const _MixedLegend();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        CustomPaint(
          size: const Size(8, 8),
          painter: _MixedLegendPainter(),
        ),
        const SizedBox(width: 4),
        const Text('Mixed', style: TextStyle(fontSize: 12)),
      ],
    );
  }
}

class _MixedLegendPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final r = size.width / 2;
    final center = Offset(r, r);

    final greenPaint = Paint()..color = Colors.green;
    final orangePaint = Paint()..color = Colors.orange;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: r),
      3.1415926535 / 2,
      3.1415926535,
      true,
      greenPaint,
    );

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: r),
      -3.1415926535 / 2,
      3.1415926535,
      true,
      orangePaint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
Future<void> showPaymentSuccessDialog({
  required BuildContext context,
  required int paidShifts,
  required double totalAmount,
}) async {
  await showDialog(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 22),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(26),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: Container(
            padding: const EdgeInsets.fromLTRB(22, 24, 22, 22),
            decoration: BoxDecoration(
              color: const Color(0xFF1E1C22),
              borderRadius: BorderRadius.circular(26),
              border: Border.all(color: Colors.white.withOpacity(0.08)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.greenAccent.withOpacity(0.15),
                  ),
                  child: const Icon(
                    Icons.check_circle,
                    color: Colors.greenAccent,
                    size: 34,
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Payment successful',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Paid shifts: $paidShifts',
                  style: const TextStyle(color: Colors.white70),
                ),
                const SizedBox(height: 6),
                Text(
                  '\$${totalAmount.toStringAsFixed(2)}',
                  style: const TextStyle(
                    color: Colors.greenAccent,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 20),
                GestureDetector(
                  onTap: () => Navigator.pop(ctx),
                  child: Container(
                    height: 46,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(999),
                      gradient: const LinearGradient(
                        colors: [
                          Color(0xFF6CFF8D),
                          Color(0xFF2E7D32),
                        ],
                      ),
                    ),
                    child: const Center(
                      child: Text(
                        'OK',
                        style: TextStyle(
                          color: Colors.black,
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
  );
}

