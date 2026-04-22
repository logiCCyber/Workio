import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../animations/fade_slide_in.dart';

/// ===========================================================
/// HISTORY SECTION
///
/// Структура:
///   SECTION (ACTIVE / UNPAID / PAID)
///     YEAR (collapsible)
///       MONTH (collapsible)
///         shift cards
///
/// ВАЖНО:
/// - НЕТ show more months внутри года (чтобы не было бардака)
/// - Есть ТОЛЬКО одна кнопка снизу: Show more / Show less
///   Она раскрывает скрытые годы + месяцы сразу.
/// ===========================================================

class HistorySection extends StatefulWidget {
  final Widget Function(Map<String, dynamic> row) buildCard;
  final bool showAllYears;

  final List<Map<String, dynamic>> active;
  final List<Map<String, dynamic>> pending;
  final List<Map<String, dynamic>> paid;

  const HistorySection({
    super.key,
    required this.active,
    required this.pending,
    required this.paid,
    required this.buildCard,
    this.showAllYears = false,
  });

  @override
  State<HistorySection> createState() => _HistorySectionState();
}

class _HistorySectionState extends State<HistorySection> {
  // Открытые годы (ключ: prefix:year:YYYY)
  final Set<String> _openYears = {};

  // Открытый месяц (ключ: prefix:YYYY-MM)
  String? _openMonthKey;

  // Лимиты годов (1 = дефолт)
  int _activeYearsLimit = 1;
  int _pendingYearsLimit = 1;
  int _paidYearsLimit = 1;

  // Лимит месяцев на год (prefix:YYYY -> limit)
  // дефолт 1 месяц, при Show more -> 999 (все)
  final Map<String, int> _monthsLimitByYear = {};

  @override
  void initState() {
    super.initState();

    // Сразу открываем текущий год во всех секциях (если он будет видимым)
    final y = DateTime.now().year;
    _openYears.add('active:year:$y');
    _openYears.add('pending:year:$y');
    _openYears.add('paid:year:$y');
  }

  int _getMonthsLimit(String prefix, int year) =>
      _monthsLimitByYear['$prefix:$year'] ?? 1;

  void _setMonthsLimit(String prefix, int year, int limit) {
    _monthsLimitByYear['$prefix:$year'] = limit;
  }

  void _resetPrefixToDefault(String prefix) {
    // Возвращаем 1 месяц на год
    _monthsLimitByYear.removeWhere((k, _) => k.startsWith('$prefix:'));
    // Закрываем открытый месяц этой секции
    if (_openMonthKey != null && _openMonthKey!.startsWith('$prefix:')) {
      _openMonthKey = null;
    }
  }

  void _expandAllYearsAndMonths({
    required String prefix,
    required List<Map<String, dynamic>> rows,
    required List<String> dateKeysPriority,
  }) {
    final years = _groupByYearMonth(rows, dateKeysPriority: dateKeysPriority).keys;
    for (final y in years) {
      _setMonthsLimit(prefix, y, 999); // показать все месяцы для каждого года
      _openYears.add('$prefix:year:$y'); // можно оставить открытыми (удобно)
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildSection(
          prefix: 'active',
          title: 'ACTIVE',
          capsuleColor: Colors.blue.withOpacity(0.18),
          capsuleTextColor: Colors.lightBlueAccent,
          rows: widget.active,
          yearsLimit: _activeYearsLimit,
          onShowMore: () => setState(() {
            _activeYearsLimit = 999;
            _expandAllYearsAndMonths(
              prefix: 'active',
              rows: widget.active,
              dateKeysPriority: const ['end_time', 'start_time'],
            );
          }),
          onShowLess: () => setState(() {
            _activeYearsLimit = 1;
            _resetPrefixToDefault('active');
            // Оставим открытым только текущий год (если он видим)
            final y = DateTime.now().year;
            _openYears.removeWhere((k) => k.startsWith('active:year:'));
            _openYears.add('active:year:$y');
          }),
        ),
        _buildSection(
          prefix: 'pending',
          title: 'UNPAID',
          capsuleColor: Colors.white.withOpacity(0.10),
          capsuleTextColor: Colors.white60,
          rows: widget.pending,
          yearsLimit: _pendingYearsLimit,
          onShowMore: () => setState(() {
            _pendingYearsLimit = 999;
            _expandAllYearsAndMonths(
              prefix: 'pending',
              rows: widget.pending,
              dateKeysPriority: const ['end_time', 'start_time'],
            );
          }),
          onShowLess: () => setState(() {
            _pendingYearsLimit = 1;
            _resetPrefixToDefault('pending');
            final y = DateTime.now().year;
            _openYears.removeWhere((k) => k.startsWith('pending:year:'));
            _openYears.add('pending:year:$y');
          }),
        ),
        _buildSection(
          prefix: 'paid',
          title: 'PAID',
          capsuleColor: Colors.green.withOpacity(0.18),
          capsuleTextColor: Colors.greenAccent,
          rows: widget.paid,
          yearsLimit: _paidYearsLimit,
          onShowMore: () => setState(() {
            _paidYearsLimit = 999;
            _expandAllYearsAndMonths(
              prefix: 'paid',
              rows: widget.paid,
              dateKeysPriority: const ['paid_at', 'paid_time', 'end_time', 'start_time'],
            );
          }),
          onShowLess: () => setState(() {
            _paidYearsLimit = 1;
            _resetPrefixToDefault('paid');
            final y = DateTime.now().year;
            _openYears.removeWhere((k) => k.startsWith('paid:year:'));
            _openYears.add('paid:year:$y');
          }),
        ),
      ],
    );
  }

  /// ---------------- SECTION ----------------

  Widget _buildSection({
    required String prefix,
    required String title,
    required Color capsuleColor,
    required Color capsuleTextColor,
    required List<Map<String, dynamic>> rows,
    required int yearsLimit,
    required VoidCallback onShowMore,
    required VoidCallback onShowLess,
  }) {
    if (rows.isEmpty) return const SizedBox.shrink();

    final dateKeysPriority = prefix == 'paid'
        ? const ['paid_at', 'paid_time', 'end_time', 'start_time']
        : const ['end_time', 'start_time'];

    final grouped = _groupByYearMonth(rows, dateKeysPriority: dateKeysPriority);

    final allYears = grouped.keys.toList()..sort((a, b) => b.compareTo(a));
    if (allYears.isEmpty) return const SizedBox.shrink();

    final nowYear = DateTime.now().year;
    final defaultYear = allYears.contains(nowYear) ? nowYear : allYears.first;

    // showAllYears -> без футера, сразу всё
    final effectiveYearsLimit = widget.showAllYears ? 999 : yearsLimit;

    final visibleYears = <int>[];
    if (effectiveYearsLimit == 1) {
      visibleYears.add(defaultYear);
    } else {
      visibleYears.addAll(allYears.take(effectiveYearsLimit));
    }

    final hasMoreYears = allYears.length > visibleYears.length;
    final canShowLess = !widget.showAllYears && effectiveYearsLimit > 1;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // (не обязательно, но помогает визуально не путать секции)
        const SizedBox(height: 10),

        ...visibleYears.map((year) {
          final yearKey = '$prefix:year:$year';
          final isYearOpen = _openYears.contains(yearKey);

          final monthsMap = grouped[year]!;
          final monthKeys = monthsMap.keys.toList()..sort((a, b) => b.compareTo(a));

          final monthsLimit = _getMonthsLimit(prefix, year);

          final now = DateTime.now();
          final currentMonthKey =
              '${now.year}-${now.month.toString().padLeft(2, '0')}';

          List<String> visibleMonthKeys;
          if (monthsLimit == 1) {
            if (year == now.year && monthKeys.contains(currentMonthKey)) {
              visibleMonthKeys = [currentMonthKey];
            } else {
              visibleMonthKeys = monthKeys.isEmpty ? <String>[] : [monthKeys.first];
            }
          } else {
            visibleMonthKeys = monthKeys.take(monthsLimit).toList();
          }

          // мини-статистика на YEAR
          final monthsCount = monthKeys.length;
          final yearShiftsCount =
          monthKeys.fold<int>(0, (s, mk) => s + monthsMap[mk]!.length);
          final yearTotal = monthKeys.fold<double>(
            0,
                (s, mk) => s +
                monthsMap[mk]!.fold<double>(
                  0,
                      (ss, r) => ss + ((r['total_payment'] ?? 0) as num).toDouble(),
                ),
          );

          return Column(
            key: ValueKey('$prefix-year-$year'),
            children: [
              // ===== YEAR HEADER =====
              GestureDetector(
                onTap: () {
                  setState(() {
                    if (isYearOpen) {
                      _openYears.remove(yearKey);

                      // при закрытии года: сбросить месяцы на дефолт (1)
                      _monthsLimitByYear.remove('$prefix:$year');

                      // закрыть открытый месяц этого года
                      if (_openMonthKey != null &&
                          _openMonthKey!.startsWith('$prefix:$year-')) {
                        _openMonthKey = null;
                      }
                    } else {
                      _openYears.add(yearKey);
                    }
                  });
                },
                child: Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(bottom: 6),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: isYearOpen
                        ? Colors.white.withOpacity(0.10)
                        : Colors.white.withOpacity(0.06),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.white.withOpacity(0.12)),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          '$year',
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 15,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.3,
                          ),
                        ),
                      ),

                      _miniLine(
                        icon: Icons.grid_view_rounded,
                        iconColor: Colors.white60,
                        text: '$monthsCount mon.',
                      ),
                      const SizedBox(width: 12),
                      _miniLine(
                        icon: Icons.work_history_rounded,
                        iconColor: Colors.white60,
                        text: '$yearShiftsCount sh.',
                      ),
                      const SizedBox(width: 12),
                      _miniLine(
                        icon: Icons.attach_money,
                        iconColor: Colors.greenAccent,
                        text: yearTotal.toStringAsFixed(0),
                        bold: true,
                      ),
                      const SizedBox(width: 12),

                      // маленькая капсула секции (ACTIVE/UNPAID/PAID)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: capsuleColor,
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(color: Colors.white.withOpacity(0.12)),
                        ),
                        child: Text(
                          title,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w900,
                            color: capsuleTextColor,
                            letterSpacing: 0.4,
                          ),
                        ),
                      ),

                      const SizedBox(width: 10),
                      AnimatedRotation(
                        turns: isYearOpen ? 0.5 : 0,
                        duration: const Duration(milliseconds: 200),
                        child: const Icon(Icons.expand_more_rounded,
                            color: Colors.white60),
                      ),
                    ],
                  ),
                ),
              ),

              // ===== YEAR CONTENT (MONTHS) =====
              AnimatedSize(
                duration: const Duration(milliseconds: 260),
                curve: Curves.easeOutCubic,
                child: isYearOpen
                    ? Column(
                  children: [
                    ...visibleMonthKeys.map((monthKey) {
                      final shifts = monthsMap[monthKey]!;
                      final monthOpenKey = '$prefix:$monthKey';
                      final isMonthOpen = _openMonthKey == monthOpenKey;

                      final monthTotal = shifts.fold<double>(
                        0,
                            (s, r) =>
                        s + ((r['total_payment'] ?? 0) as num).toDouble(),
                      );

                      final label = DateFormat.MMMM()
                          .format(DateTime.parse('$monthKey-01'));
                      final monthLabel =
                          label[0].toUpperCase() + label.substring(1);

                      return Column(
                        key: ValueKey('$prefix-month-$monthKey'),
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // ===== MONTH HEADER =====
                          GestureDetector(
                            onTap: () {
                              setState(() {
                                _openMonthKey =
                                isMonthOpen ? null : monthOpenKey;
                              });
                            },
                            child: Container(
                              width: double.infinity,
                              margin: const EdgeInsets.only(bottom: 6),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 12),
                              decoration: BoxDecoration(
                                color: isMonthOpen
                                    ? Colors.white.withOpacity(0.10)
                                    : Colors.white.withOpacity(0.06),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                    color: Colors.white.withOpacity(0.12)),
                              ),
                              child: Row(
                                children: [
                                  const Icon(Icons.calendar_month,
                                      color: Colors.white60, size: 18),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      monthLabel,
                                      style: const TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w900,
                                        color: Colors.white70,
                                      ),
                                    ),
                                  ),
                                  _miniLine(
                                    icon: Icons.work_history_rounded,
                                    iconColor: Colors.white38,
                                    text: '${shifts.length} shifts',
                                  ),
                                  const SizedBox(width: 12),
                                  _miniLine(
                                    icon: Icons.attach_money,
                                    iconColor: Colors.white60,
                                    text: monthTotal.toStringAsFixed(0),
                                    bold: true,
                                  ),
                                  const SizedBox(width: 10),
                                  AnimatedRotation(
                                    turns: isMonthOpen ? 0.5 : 0,
                                    duration:
                                    const Duration(milliseconds: 200),
                                    child: const Icon(Icons.expand_more_rounded,
                                        color: Colors.white60),
                                  ),
                                ],
                              ),
                            ),
                          ),

                          // ===== MONTH CONTENT (SHIFT CARDS) =====
                          AnimatedSize(
                            duration: const Duration(milliseconds: 260),
                            curve: Curves.easeOutCubic,
                            child: isMonthOpen
                                ? Column(
                              children: shifts.map((r) {
                                final id = r['id'] ??
                                    r['shift_id'] ??
                                    r['start_time'] ??
                                    r.hashCode;
                                return FadeSlideIn(
                                  key: ValueKey('$prefix-$monthKey-$id'),
                                  child: widget.buildCard(r),
                                );
                              }).toList(),
                            )
                                : const SizedBox.shrink(),
                          ),
                        ],
                      );
                    }),
                  ],
                )
                    : const SizedBox.shrink(),
              ),
            ],
          );
        }),

        // ===== ONLY ONE FOOTER BUTTON (YEARS + MONTHS TOGETHER) =====
        if (!widget.showAllYears)
          _FooterWideButton(
            label: hasMoreYears ? 'Show more' : (canShowLess ? 'Show less' : ''),
            icon: hasMoreYears ? Icons.expand_more_rounded : Icons.expand_less_rounded,
            isHidden: !(hasMoreYears || canShowLess),
            onTap: hasMoreYears ? onShowMore : onShowLess,
          ),
      ],
    );
  }

  /// ---------------- SMALL LINE (icon + text) ----------------

  Widget _miniLine({
    required IconData icon,
    required Color iconColor,
    required String text,
    bool bold = false,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: iconColor),
        const SizedBox(width: 6),
        Text(
          text,
          style: TextStyle(
            color: iconColor,
            fontSize: 12,
            fontWeight: bold ? FontWeight.w900 : FontWeight.w800,
          ),
        ),
      ],
    );
  }
}

/// ===========================================================
/// HELPERS
/// ===========================================================

Map<int, Map<String, List<Map<String, dynamic>>>> _groupByYearMonth(
    List<Map<String, dynamic>> rows, {
      required List<String> dateKeysPriority,
    }) {
  final Map<int, Map<String, List<Map<String, dynamic>>>> out = {};

  DateTime? pickDate(Map<String, dynamic> r) {
    for (final k in dateKeysPriority) {
      final v = r[k];
      if (v == null) continue;
      try {
        return DateTime.parse(v.toString()).toLocal();
      } catch (_) {}
    }
    return null;
  }

  for (final r in rows) {
    final d = pickDate(r);
    if (d == null) continue;

    final year = d.year;
    final monthKey = '${d.year}-${d.month.toString().padLeft(2, '0')}';

    out.putIfAbsent(year, () => {});
    out[year]!.putIfAbsent(monthKey, () => []);
    out[year]![monthKey]!.add(r);
  }

  // сортировка внутри месяца (новые сверху)
  for (final y in out.keys) {
    for (final mk in out[y]!.keys) {
      out[y]![mk]!.sort((a, b) {
        final da = pickDate(a) ?? DateTime.fromMillisecondsSinceEpoch(0);
        final db = pickDate(b) ?? DateTime.fromMillisecondsSinceEpoch(0);
        return db.compareTo(da);
      });
    }
  }

  return out;
}

/// ===========================================================
/// FOOTER BUTTON (ONE CLEAN BUTTON)
/// ===========================================================

class _FooterWideButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final bool isHidden;

  const _FooterWideButton({
    required this.label,
    required this.icon,
    required this.onTap,
    this.isHidden = false,
  });

  @override
  Widget build(BuildContext context) {
    if (isHidden) return const SizedBox.shrink();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          height: 44,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.05),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: Colors.white.withOpacity(0.08),
              width: 1,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 18, color: Colors.white.withOpacity(0.85)),
              const SizedBox(width: 10),
              Text(
                label,
                style: TextStyle(
                  color: Colors.white.withOpacity(0.9),
                  fontWeight: FontWeight.w600,
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
