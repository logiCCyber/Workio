import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'worker_range_calendar_sheet.dart';

enum WorkerHistoryFilter { all, active, unpaid, paid }
enum WorkerPaymentsFilter { all, thisMonth, thisYear }

class WorkerTimelineFilterResult {
  final DateTimeRange? historyRange;
  final DateTimeRange? paymentsRange;
  final WorkerHistoryFilter historyFilter;
  final WorkerPaymentsFilter paymentsFilter;

  const WorkerTimelineFilterResult({
    required this.historyRange,
    required this.paymentsRange,
    required this.historyFilter,
    required this.paymentsFilter,
  });

  WorkerTimelineFilterResult copyWith({
    DateTimeRange? historyRange,
    DateTimeRange? paymentsRange,
    WorkerHistoryFilter? historyFilter,
    WorkerPaymentsFilter? paymentsFilter,
  }) {
    return WorkerTimelineFilterResult(
      historyRange: historyRange ?? this.historyRange,
      paymentsRange: paymentsRange ?? this.paymentsRange,
      historyFilter: historyFilter ?? this.historyFilter,
      paymentsFilter: paymentsFilter ?? this.paymentsFilter,
    );
  }
}

String formatWorkerTimelineRange(DateTimeRange? range) {
  if (range == null) return 'All dates';

  final sameDay =
      range.start.year == range.end.year &&
          range.start.month == range.end.month &&
          range.start.day == range.end.day;

  if (sameDay) {
    return DateFormat('d MMM yyyy').format(range.start);
  }

  return '${DateFormat('d MMM').format(range.start)} — ${DateFormat('d MMM yyyy').format(range.end)}';
}

String historyFilterLabel(WorkerHistoryFilter filter) {
  switch (filter) {
    case WorkerHistoryFilter.active:
      return 'Active';
    case WorkerHistoryFilter.unpaid:
      return 'Unpaid';
    case WorkerHistoryFilter.paid:
      return 'Paid';
    case WorkerHistoryFilter.all:
      return 'All';
  }
}

String paymentsFilterLabel(WorkerPaymentsFilter filter) {
  switch (filter) {
    case WorkerPaymentsFilter.thisMonth:
      return 'This month';
    case WorkerPaymentsFilter.thisYear:
      return 'This year';
    case WorkerPaymentsFilter.all:
      return 'All';
  }
}

Future<WorkerTimelineFilterResult?> showWorkerTimelineFilterSheet({
  required BuildContext context,
  required bool isPayments,
  required DateTimeRange? historyRange,
  required DateTimeRange? paymentsRange,
  required WorkerHistoryFilter historyFilter,
  required WorkerPaymentsFilter paymentsFilter,
  required Map<DateTime, List<Map<String, dynamic>>> workDays,
}) {
  return showModalBottomSheet<WorkerTimelineFilterResult>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.64),
    builder: (_) => _WorkerTimelineFilterSheet(
      isPayments: isPayments,
      historyRange: historyRange,
      paymentsRange: paymentsRange,
      historyFilter: historyFilter,
      paymentsFilter: paymentsFilter,
      workDays: workDays,
    ),
  );
}

class WorkerTimelineFilterBar extends StatelessWidget {
  final bool isPayments;
  final DateTimeRange? range;
  final WorkerHistoryFilter historyFilter;
  final WorkerPaymentsFilter paymentsFilter;
  final VoidCallback onTap;

  const WorkerTimelineFilterBar({
    super.key,
    required this.isPayments,
    required this.range,
    required this.historyFilter,
    required this.paymentsFilter,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final accent = isPayments ? Colors.lightBlueAccent : Colors.orangeAccent;
    final title = isPayments ? 'Payments filter' : 'History filter';
    final filterText = isPayments
        ? paymentsFilterLabel(paymentsFilter)
        : historyFilterLabel(historyFilter);

    final subtitle = '${formatWorkerTimelineRange(range)} • $filterText';

    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(24),
            child: Container(
              height: 62,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(24),
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color(0xFF404451),
                    Color(0xFF303540),
                    Color(0xFF1A1F28),
                  ],
                ),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.10),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.30),
                    blurRadius: 22,
                    offset: const Offset(0, 14),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.08),
                      ),
                    ),
                    child: Icon(
                      isPayments
                          ? Icons.payments_rounded
                          : Icons.timeline_rounded,
                      size: 20,
                      color: accent,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13.5,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.58),
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Icon(
                    Icons.tune_rounded,
                    size: 20,
                    color: Colors.white.withValues(alpha: 0.48),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _WorkerTimelineFilterSheet extends StatefulWidget {
  final bool isPayments;
  final DateTimeRange? historyRange;
  final DateTimeRange? paymentsRange;
  final WorkerHistoryFilter historyFilter;
  final WorkerPaymentsFilter paymentsFilter;
  final Map<DateTime, List<Map<String, dynamic>>> workDays;

  const _WorkerTimelineFilterSheet({
    required this.isPayments,
    required this.historyRange,
    required this.paymentsRange,
    required this.historyFilter,
    required this.paymentsFilter,
    required this.workDays,
  });

  @override
  State<_WorkerTimelineFilterSheet> createState() =>
      _WorkerTimelineFilterSheetState();
}

class _WorkerTimelineFilterSheetState
    extends State<_WorkerTimelineFilterSheet> {
  late DateTimeRange? _historyRange;
  late DateTimeRange? _paymentsRange;
  late WorkerHistoryFilter _historyFilter;
  late WorkerPaymentsFilter _paymentsFilter;

  @override
  void initState() {
    super.initState();
    _historyRange = widget.historyRange;
    _paymentsRange = widget.paymentsRange;
    _historyFilter = widget.historyFilter;
    _paymentsFilter = widget.paymentsFilter;
  }

  Future<void> _pickRange() async {
    final picked = await showWorkerRangeCalendarSheet(
      context: context,
      initialRange: widget.isPayments ? _paymentsRange : _historyRange,
      workDays: widget.workDays,
      isPayments: widget.isPayments,
    );

    if (picked == null) return;

    setState(() {
      if (widget.isPayments) {
        _paymentsRange = picked;
      } else {
        _historyRange = picked;
      }
    });
  }

  void _resetCurrentMode() {
    setState(() {
      if (widget.isPayments) {
        _paymentsRange = null;
        _paymentsFilter = WorkerPaymentsFilter.all;
      } else {
        _historyRange = null;
        _historyFilter = WorkerHistoryFilter.all;
      }
    });
  }

  void _apply() {
    Navigator.pop(
      context,
      WorkerTimelineFilterResult(
        historyRange: _historyRange,
        paymentsRange: _paymentsRange,
        historyFilter: _historyFilter,
        paymentsFilter: _paymentsFilter,
      ),
    );
  }

  IconData _historyIcon(WorkerHistoryFilter filter) {
    switch (filter) {
      case WorkerHistoryFilter.all:
        return Icons.apps_rounded;
      case WorkerHistoryFilter.unpaid:
        return Icons.hourglass_bottom_rounded;
      case WorkerHistoryFilter.paid:
        return Icons.check_circle_outline_rounded;
      case WorkerHistoryFilter.active:
        return Icons.play_circle_outline_rounded;
    }
  }

  IconData _paymentsIcon(WorkerPaymentsFilter filter) {
    switch (filter) {
      case WorkerPaymentsFilter.all:
        return Icons.apps_rounded;
      case WorkerPaymentsFilter.thisMonth:
        return Icons.calendar_view_month_rounded;
      case WorkerPaymentsFilter.thisYear:
        return Icons.date_range_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    final accent =
    widget.isPayments ? Colors.lightBlueAccent : Colors.orangeAccent;

    final range = widget.isPayments ? _paymentsRange : _historyRange;
    final title = widget.isPayments ? 'Payments filter' : 'History filter';
    final subtitle = widget.isPayments
        ? 'Filter by payments and date range'
        : 'Filter by history, status and date range';

    final historyItems = [
      _SegmentItem(
        label: 'All',
        icon: _historyIcon(WorkerHistoryFilter.all),
        selected: _historyFilter == WorkerHistoryFilter.all,
        onTap: () {
          setState(() {
            _historyFilter = WorkerHistoryFilter.all;
          });
        },
      ),
      _SegmentItem(
        label: 'Unpaid',
        icon: _historyIcon(WorkerHistoryFilter.unpaid),
        selected: _historyFilter == WorkerHistoryFilter.unpaid,
        onTap: () {
          setState(() {
            _historyFilter = WorkerHistoryFilter.unpaid;
          });
        },
      ),
      _SegmentItem(
        label: 'Paid',
        icon: _historyIcon(WorkerHistoryFilter.paid),
        selected: _historyFilter == WorkerHistoryFilter.paid,
        onTap: () {
          setState(() {
            _historyFilter = WorkerHistoryFilter.paid;
          });
        },
      ),
    ];

    final paymentItems = [
      _SegmentItem(
        label: 'All',
        icon: _paymentsIcon(WorkerPaymentsFilter.all),
        selected: _paymentsFilter == WorkerPaymentsFilter.all,
        onTap: () {
          setState(() {
            _paymentsFilter = WorkerPaymentsFilter.all;
          });
        },
      ),
      _SegmentItem(
        label: 'Month',
        icon: _paymentsIcon(WorkerPaymentsFilter.thisMonth),
        selected: _paymentsFilter == WorkerPaymentsFilter.thisMonth,
        onTap: () {
          setState(() {
            _paymentsFilter = WorkerPaymentsFilter.thisMonth;
          });
        },
      ),
      _SegmentItem(
        label: 'Year',
        icon: _paymentsIcon(WorkerPaymentsFilter.thisYear),
        selected: _paymentsFilter == WorkerPaymentsFilter.thisYear,
        onTap: () {
          setState(() {
            _paymentsFilter = WorkerPaymentsFilter.thisYear;
          });
        },
      ),
    ];

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 18, 12, 12),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(30),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
            child: Container(
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    const Color(0xFF313744),
                    const Color(0xFF232933),
                    const Color(0xFF141920),
                  ],
                ),
                borderRadius: BorderRadius.circular(30),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.10),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.44),
                    blurRadius: 32,
                    offset: const Offset(0, 20),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(height: 10),
                  Container(
                    width: 46,
                    height: 5,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                  const SizedBox(height: 10),

                  // HEADER = ШАПКА НА ВСЮ ВЕРХНЮЮ ЧАСТЬ
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.fromLTRB(18, 16, 14, 16),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          Color(0xFF39404C),
                          Color(0xFF2B313C),
                          Color(0xFF1D232D),
                        ],
                      ),
                      border: Border(
                        bottom: BorderSide(
                          color: Colors.white.withValues(alpha: 0.08),
                        ),
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 46,
                          height: 46,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.05),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.08),
                            ),
                          ),
                          child: Icon(
                            widget.isPayments
                                ? Icons.payments_rounded
                                : Icons.timeline_rounded,
                            color: accent,
                            size: 22,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  title,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 16,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  subtitle,
                                  style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.58),
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    height: 1.35,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        IconButton(
                          onPressed: () => Navigator.pop(context),
                          splashRadius: 18,
                          icon: const Icon(
                            Icons.close_rounded,
                            color: Colors.white70,
                            size: 28,
                          ),
                        ),
                      ],
                    ),
                  ),

                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _SheetSection(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _RangeTile(
                                accent: accent,
                                text: formatWorkerTimelineRange(range),
                                hasValue: range != null,
                                onTap: _pickRange,
                                onClear: () {
                                  setState(() {
                                    if (widget.isPayments) {
                                      _paymentsRange = null;
                                    } else {
                                      _historyRange = null;
                                    }
                                  });
                                },
                              ),
                              const SizedBox(height: 14),
                              Text(
                                'Quick filter',
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.62),
                                  fontSize: 12,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 10),
                              _SegmentRow(
                                items: widget.isPayments
                                    ? paymentItems
                                    : historyItems,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(
                              child: InkWell(
                                onTap: _resetCurrentMode,
                                borderRadius: BorderRadius.circular(18),
                                child: Container(
                                  height: 52,
                                  decoration: BoxDecoration(
                                    gradient: const LinearGradient(
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                      colors: [
                                        Color(0xFF353A46),
                                        Color(0xFF282D38),
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
                                          fontWeight: FontWeight.w900,
                                          fontSize: 15,
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
                                onTap: _apply,
                                borderRadius: BorderRadius.circular(18),
                                child: Container(
                                  height: 52,
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                      colors: [
                                        accent.withValues(alpha: 0.96),
                                        accent.withValues(alpha: 0.74),
                                      ],
                                    ),
                                    borderRadius: BorderRadius.circular(18),
                                    boxShadow: [
                                      BoxShadow(
                                        color: accent.withValues(alpha: 0.18),
                                        blurRadius: 16,
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
                                        'Apply',
                                        style: TextStyle(
                                          color: Colors.black,
                                          fontWeight: FontWeight.w900,
                                          fontSize: 15,
                                        ),
                                      ),
                                    ],
                                  ),
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
        ),
      ),
    );
  }
}

class _SheetSection extends StatelessWidget {
  final Widget child;

  const _SheetSection({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF2C323E),
            Color(0xFF232933),
            Color(0xFF181E26),
          ],
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.08),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.18),
            blurRadius: 14,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _RangeTile extends StatelessWidget {
  final Color accent;
  final String text;
  final bool hasValue;
  final VoidCallback onTap;
  final VoidCallback onClear;

  const _RangeTile({
    required this.accent,
    required this.text,
    required this.hasValue,
    required this.onTap,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        height: 54,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFF3C4250),
              Color(0xFF2E3440),
            ],
          ),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.08),
          ),
        ),
        child: Row(
          children: [
            Icon(Icons.calendar_month_rounded, size: 18, color: accent),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            if (hasValue)
              GestureDetector(
                onTap: onClear,
                child: Icon(
                  Icons.close_rounded,
                  size: 18,
                  color: Colors.white.withValues(alpha: 0.44),
                ),
              )
            else
              Icon(
                Icons.chevron_right_rounded,
                size: 20,
                color: Colors.white.withValues(alpha: 0.44),
              ),
          ],
        ),
      ),
    );
  }
}

class _SegmentItem {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _SegmentItem({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });
}

class _SegmentRow extends StatelessWidget {
  final List<_SegmentItem> items;

  const _SegmentRow({
    required this.items,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: items.map((item) {
        return Expanded(
          child: Padding(
            padding: EdgeInsets.only(
              right: item == items.last ? 0 : 8,
            ),
            child: _SegmentButton(
              label: item.label,
              icon: item.icon,
              selected: item.selected,
              onTap: item.onTap,
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _SegmentButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _SegmentButton({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final iconColor = Colors.white.withValues(alpha: selected ? 0.72 : 0.46);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        height: 60,
        decoration: BoxDecoration(
          gradient: selected
              ? const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFF434958),
              Color(0xFF343A46),
              Color(0xFF272D37),
            ],
          )
              : const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFF2B303A),
              Color(0xFF20252E),
            ],
          ),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: selected
                ? Colors.white.withValues(alpha: 0.14)
                : Colors.white.withValues(alpha: 0.06),
          ),
          boxShadow: selected
              ? [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.20),
              blurRadius: 12,
              offset: const Offset(0, 8),
            ),
          ]
              : [],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 18,
              color: iconColor,
            ),
            const SizedBox(height: 6),
            Text(
              label,
              style: TextStyle(
                color: Colors.white.withValues(alpha: selected ? 0.92 : 0.72),
                fontSize: 13,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
      ),
    );
  }
}