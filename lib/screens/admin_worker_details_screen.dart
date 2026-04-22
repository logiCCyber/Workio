import 'dart:async';
import 'dart:ui';
import 'dart:typed_data';
import '../ui/toast.dart';

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:printing/printing.dart' as pr;
import 'package:pdf/widgets.dart' as pw;
import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import '../widgets/animations/fade_slide_in.dart';
import '../dialogs/edit_worker_dialog.dart';
import '../widgets/worker_range_calendar_sheet_updated.dart';
import '../widgets/quick_calculator_sheet.dart';
import 'pay_calendar_sheet.dart';
import '../utils/company_logo_helper.dart';

class AdminWorkerDetailsScreen extends StatefulWidget {
  final Map<String, dynamic> worker;

  const AdminWorkerDetailsScreen({
    super.key,
    required this.worker,
  });

  @override
  State<AdminWorkerDetailsScreen> createState() =>
      _AdminWorkerDetailsScreenState();
}

class _AdminWorkerDetailsScreenState
    extends State<AdminWorkerDetailsScreen> {

  void _clearSectionFilter({
    required bool isPayments,
  }) {
    setState(() {
      if (isPayments) {
        _paymentsRange = null;
        _paymentsFilter = WorkerPaymentsFilter.all;
      } else {
        _historyRange = null;
        _historyFilter = WorkerHistoryFilter.all;
        _historyAutoOpenVersion++;
      }
    });
  }

  bool _showPaymentsPanel = false;
  late Future<Map<String, dynamic>?> _lastPaymentFuture;
  String? _expandedPaymentId;
  bool _showAllPayments = false;
  Timer? _paymentsTicker;
  final ValueNotifier<int> _paymentsTipIndex = ValueNotifier<int>(0);
  late Future<List<Map<String, dynamic>>> _paymentsFuture;

  List<Map<String, dynamic>> _paymentsCache = [];
  bool _paymentsLoaded = false;

  bool get _workerOnShiftNow =>
      (workerFull?['on_shift'] ?? widget.worker['on_shift']) == true;

  bool get _canDeleteWorker {
    return !loading &&
        _paymentsLoaded &&
        !_workerOnShiftNow &&
        history.isEmpty &&
        _paymentsCache.isEmpty;
  }

  // ===== HISTORY YEARS CONTROL =====
  final GlobalKey<_YearGroupedHistorySectionState> _historyKey =
  GlobalKey<_YearGroupedHistorySectionState>();
  int _historyAutoOpenVersion = 0;
  int _paymentsAutoOpenVersion = 0;
  int _lastPaymentsAutoOpenHandled = 0;
  DateTimeRange? _historyRange;
  DateTimeRange? _paymentsRange;

  WorkerHistoryFilter _historyFilter = WorkerHistoryFilter.all;
  WorkerPaymentsFilter _paymentsFilter = WorkerPaymentsFilter.all;

  bool _historyShowAllYears = false;
  int _historyHiddenYearsCount = 0;

  String _workerMode() {
    final raw = (workerFull?['access_mode'] ?? widget.worker['access_mode'] ?? 'active')
        .toString()
        .toLowerCase()
        .trim();

    if (raw == 'readonly' || raw == 'viewonly' || raw == 'view_only') {
      return 'view_only';
    }

    return raw;
  }

  Future<void> _deleteWorker() async {
    final session = supabase.auth.currentSession;
    if (session == null) {
      _showError('Session not found');
      return;
    }

    try {
      final res = await supabase.functions.invoke(
        'delete-worker-safe',
        body: {
          'worker_id': widget.worker['id'],
        },
        headers: {
          'Authorization': 'Bearer ${session.accessToken}',
        },
      );

      if (res.status != 200) {
        if (res.data is Map && res.data['error'] != null) {
          _showError(res.data['error'].toString());
        } else {
          _showError('Delete failed: ${res.status}');
        }
        return;
      }

      if (!mounted) return;

      AppToast.success(context, 'Worker deleted successfully');
      Navigator.pop(context, true);
    } on FunctionException catch (e) {
      _showError(e.details?.toString() ?? e.reasonPhrase ?? e.toString());
    } catch (e) {
      _showError(e.toString());
    }
  }

  Future<pw.ImageProvider?> _loadCompanyLogoForPdf() async {
    try {
      final adminId = supabase.auth.currentUser?.id;
      if (adminId == null) {
        return await pr.networkImage(CompanyLogoHelper.defaultLogoUrl);
      }

      final row = await supabase
          .from('company_settings')
          .select('logo_url')
          .eq('admin_auth_id', adminId)
          .maybeSingle();

      final customLogo = (row?['logo_url'] ?? '').toString().trim();

      final resolvedLogo = customLogo.isNotEmpty
          ? customLogo
          : CompanyLogoHelper.defaultLogoUrl;

      return await pr.networkImage(resolvedLogo);
    } catch (_) {
      try {
        return await pr.networkImage(CompanyLogoHelper.defaultLogoUrl);
      } catch (_) {
        return null;
      }
    }
  }

  Future<void> _openRangeCalendar({
    required bool isPayments,
  }) async {
    final result = await showWorkerRangeCalendarSheet(
      context: context,
      initialRange: isPayments ? _paymentsRange : _historyRange,
      workDays: isPayments ? _paymentDays : _historyWorkDays,
      isPayments: isPayments,
      historyFilter: _historyFilter,
      paymentsFilter: _paymentsFilter,
    );

    if (result == null || !mounted) return;

    setState(() {
      if (isPayments) {
        _paymentsRange = result.range;
        _paymentsFilter = result.paymentsFilter;
        _showPaymentsPanel = true;
        _paymentsAutoOpenVersion++;
      } else {
        _historyRange = result.range;
        _historyFilter = result.historyFilter;
        _historyAutoOpenVersion++;
      }
    });
  }

  String _historyFilterFieldLabel() {
    switch (_historyFilter) {
      case WorkerHistoryFilter.unpaid:
        return 'Unpaid';
      case WorkerHistoryFilter.paid:
        return 'Paid';
      case WorkerHistoryFilter.active:
        return 'Active';
      case WorkerHistoryFilter.all:
        return 'All';
    }
  }

  String _paymentsFilterFieldLabel() {
    switch (_paymentsFilter) {
      case WorkerPaymentsFilter.thisMonth:
        return 'This month';
      case WorkerPaymentsFilter.thisYear:
        return 'This year';
      case WorkerPaymentsFilter.all:
        return 'All';
    }
  }

  String _formatSectionRange(DateTimeRange? range) {
    if (range == null) return 'All dates';

    final sameDay =
        range.start.year == range.end.year &&
        range.start.month == range.end.month &&
        range.start.day == range.end.day;

    if (sameDay) {
      return DateFormat('d MMM yyyy').format(range.start);
    }

    final sameYear = range.start.year == range.end.year;
    if (sameYear) {
      return '${DateFormat('d MMM').format(range.start)} — ${DateFormat('d MMM yyyy').format(range.end)}';
    }

    return '${DateFormat('d MMM yyyy').format(range.start)} — ${DateFormat('d MMM yyyy').format(range.end)}';
  }

   Future<void> _confirmDeleteWorker() async {
    if (!_canDeleteWorker) {
      _showError('Delete is allowed only when there is no history, no payments and no active shift');
      return;
    }

    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withOpacity(0.55),
      builder: (ctx) {
        return Dialog(
          backgroundColor: const Color(0xFF1E1C22),
          insetPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 24),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(26),
          ),
          child: Container(
            decoration: BoxDecoration(
              color: const Color(0xFF24252B), // ✅ сплошной фон
              borderRadius: BorderRadius.circular(26),
              border: Border.all(color: Colors.white.withOpacity(0.08)),
              boxShadow: const [
                BoxShadow(
                  color: Colors.black54,
                  blurRadius: 28,
                  offset: Offset(0, 18),
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 62,
                    height: 62,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: kSuspendedAccent.withOpacity(0.16),
                      border: Border.all(color: kSuspendedAccent.withOpacity(0.28)),
                    ),
                    child: const Icon(
                      Icons.delete_outline_rounded,
                      color: kSuspendedAccent,
                      size: 34,
                    ),
                  ),

                  const SizedBox(height: 14),

                  const Text(
                    'Delete worker',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                    ),
                  ),

                  const SizedBox(height: 10),

                  const Text(
                    'This worker has no history and no payments.\nThe account will be deleted permanently and cannot be restored.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white60,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      height: 1.4,
                    ),
                  ),

                  const SizedBox(height: 16),

                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFF2E2D34),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: Colors.white.withOpacity(0.07)),
                    ),
                    child: Column(
                      children: [
                        _dangerInfoRow(Icons.person_outline, 'Worker row will be deleted'),
                        const SizedBox(height: 8),
                        _dangerInfoRow(Icons.lock_outline, 'Auth account will be deleted'),
                        const SizedBox(height: 8),
                        _dangerInfoRow(Icons.refresh_rounded, 'Email can be used again after deletion'),
                      ],
                    ),
                  ),

                  const SizedBox(height: 18),

                  Row(
                    children: [
                      Expanded(
                        child: _pillButton(
                          label: 'Cancel',
                          icon: Icons.close,
                          bg: Colors.white.withOpacity(0.08),
                          fg: Colors.white70,
                          onTap: () => Navigator.pop(ctx, false),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _pillButton(
                          label: 'DELETE',
                          icon: Icons.delete_outline_rounded,
                          bg: kSuspendedAccent,
                          fg: Colors.black, // ✅ текст и иконка чёрные
                          onTap: () => Navigator.pop(ctx, true),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );

    if (ok == true) {
      await _deleteWorker();
    }
  }

  Widget _dangerInfoRow(IconData icon, String text) {
    return Row(
      children: [
        const SizedBox(width: 2),
        Icon(icon, size: 16, color: kSuspendedAccent),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }


  bool get _isSuspended => _workerMode() == 'suspended';

  bool _inRange(DateTime value, DateTimeRange? range) {
    if (range == null) return true;

    final start = DateTime(
      range.start.year,
      range.start.month,
      range.start.day,
    );

    final end = DateTime(
      range.end.year,
      range.end.month,
      range.end.day,
      23, 59, 59, 999,
    );

    return !value.isBefore(start) && !value.isAfter(end);
  }

  List<Map<String, dynamic>> _applyHistoryFilters(List<Map<String, dynamic>> rows) {
    return rows.where((r) {
      final raw = r['start_time'];
      if (raw == null) return false;

      final dt = DateTime.parse(raw.toString()).toLocal();
      if (!_inRange(dt, _historyRange)) return false;

      switch (_historyFilter) {
        case WorkerHistoryFilter.all:
          return true;
        case WorkerHistoryFilter.active:
          return r['end_time'] == null;
        case WorkerHistoryFilter.unpaid:
          return r['end_time'] == null ||
              (r['end_time'] != null && r['paid_at'] == null);
        case WorkerHistoryFilter.paid:
          return r['end_time'] == null || r['paid_at'] != null;
      }
    }).toList();
  }

  List<Map<String, dynamic>> _applyPaymentsFilters(List<Map<String, dynamic>> rows) {
    final now = DateTime.now();

    return rows.where((p) {
      final raw = p['created_at'];
      if (raw == null) return false;

      final dt = DateTime.parse(raw.toString()).toLocal();

      if (!_inRange(dt, _paymentsRange)) return false;

      switch (_paymentsFilter) {
        case WorkerPaymentsFilter.all:
          return true;
        case WorkerPaymentsFilter.thisMonth:
          return dt.year == now.year && dt.month == now.month;
        case WorkerPaymentsFilter.thisYear:
          return dt.year == now.year;
      }
    }).toList();
  }

  Map<String, dynamic> splitHistoryByMonth(List<Map<String, dynamic>> history) {
    final now = DateTime.now();
    final currentYear = now.year;
    final currentMonth = now.month;

    final List<Map<String, dynamic>> currentMonthShifts = [];
    final Map<String, List<Map<String, dynamic>>> pastMonths = {};

    for (final r in history) {
      final start = DateTime.parse(r['start_time']).toLocal();

      final isCurrentMonth =
          start.year == currentYear && start.month == currentMonth;

      if (isCurrentMonth) {
        currentMonthShifts.add(r);
      } else {
        final key =
            '${start.year}-${start.month.toString().padLeft(2, '0')}';

        pastMonths.putIfAbsent(key, () => []);
        pastMonths[key]!.add(r);
      }
    }

    return {
      'current': currentMonthShifts,
      'past': pastMonths,
    };
  }

  Widget _sectionCentered(Widget child) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Align(
        alignment: Alignment.center,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: child,
        ),
      ),
    );
  }

  Widget _animatedHistory(List<Map<String, dynamic>> rows) {
    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: rows.length,
      itemBuilder: (context, index) {
        return FadeSlideIn(
          child: _shiftCard(rows[index]),
        );
      },
    );
  }

  @override
  void dispose() {
    _paymentsTicker?.cancel();
    _ticker?.cancel();
    _now.dispose();
    _paymentsTipIndex.dispose(); // ✅ ДОБАВЬ ЭТУ СТРОКУ
    super.dispose();
  }

  late final ValueNotifier<DateTime> _now = ValueNotifier(DateTime.now());
  Timer? _ticker;

  final supabase = Supabase.instance.client;

  List<Map<String, dynamic>> history = [];
  bool loading = true;
  bool showOlderPaid = true; // ✅ always show full history
  // ===== Calendar =====
  final Map<DateTime, List<Map<String, dynamic>>> _historyWorkDays = {};
  final Map<DateTime, List<Map<String, dynamic>>> _paymentDays = {};
  // DateTime _focusedDay = DateTime.now();
  // DateTime? _selectedDay;
  Map<String, dynamic>? workerFull;

  // Future<void> _exportPdf() async {
  //   final pdf = pw.Document();
  //
  //   final worker = workerFull ?? widget.worker;
  //
  //   final totalHours = history.fold<double>(
  //     0,
  //         (s, r) => s + ((r['total_hours'] ?? 0) as num).toDouble(),
  //   );
  //
  //   final totalAmount = history.fold<double>(
  //     0,
  //         (s, r) => s + ((r['total_payment'] ?? 0) as num).toDouble(),
  //   );
  //
  //   // ✅ важно: header async — грузим ДО addPage
  //   final header = await _pdfHeader(
  //   worker,
  //   logoImage: logoImage,
  // );
  //
  //   pdf.addPage(
  //     pw.MultiPage(
  //       pageTheme: const pw.PageTheme(
  //         margin: pw.EdgeInsets.all(32),
  //       ),
  //       build: (context) => [
  //         header,
  //         pw.SizedBox(height: 18),
  //         _pdfSummary(totalHours, totalAmount),
  //         pw.SizedBox(height: 20),
  //         _pdfTable(),
  //         pw.SizedBox(height: 18),
  //         _pdfFooter(),
  //       ],
  //     ),
  //   );
  //
  //   await Printing.layoutPdf(
  //     onLayout: (format) async => pdf.save(),
  //   );
  // }

  Future<pw.Widget> _pdfHeader(
      Map<String, dynamic> worker, {
        pw.ImageProvider? logoImage,
      }) async {
    return pw.Container(
      padding: const pw.EdgeInsets.only(bottom: 18),
      decoration: const pw.BoxDecoration(
        border: pw.Border(
          bottom: pw.BorderSide(width: 0.5, color: PdfColors.grey400),
        ),
      ),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              if (logoImage != null)
                pw.Container(
                  width: 64,
                  height: 48,
                  margin: const pw.EdgeInsets.only(right: 12),
                  child: pw.Image(
                    logoImage,
                    fit: pw.BoxFit.contain,
                  ),
                ),
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    widget.worker['name'] ?? '—',
                    style: pw.TextStyle(
                      fontSize: 14,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                  pw.SizedBox(height: 6),
                  pw.Text(
                    widget.worker['email'] ?? '—',
                    style: pw.TextStyle(
                      fontSize: 10,
                      color: PdfColors.grey700,
                    ),
                  ),
                ],
              ),
            ],
          ),
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              pw.Text(
                'PAYMENT STATEMENT',
                style: pw.TextStyle(
                  fontSize: 14,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.SizedBox(height: 4),
              pw.Text(
                DateFormat.yMMMd().format(DateTime.now()),
                style: pw.TextStyle(
                  fontSize: 10,
                  color: PdfColors.grey600,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  pw.Widget _pdfSummaryCell({
    required String label,
    required String value,
    required PdfColor color,
  }) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.center,
      children: [
        pw.Text(
          label,
          style: const pw.TextStyle(
            fontSize: 9,
            color: PdfColors.grey600,
          ),
        ),
        pw.SizedBox(height: 4),
        pw.Text(
          value,
          style: pw.TextStyle(
            fontSize: 12,
            fontWeight: pw.FontWeight.bold,
            color: color,
          ),
        ),
      ],
    );
  }


  pw.Widget _pdfTable() {
    return pw.Table(
      border: const pw.TableBorder(
        horizontalInside: pw.BorderSide(width: 0.3, color: PdfColors.grey300),
        bottom: pw.BorderSide(width: 0.5, color: PdfColors.grey400),
      ),
      children: [
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: PdfColors.grey200),
          children: [
            _th('DATE', align: pw.TextAlign.left),
            _th('TIME', align: pw.TextAlign.center),   // start-end
            _th('WORKED', align: pw.TextAlign.center), // hours
            _th('AMOUNT', align: pw.TextAlign.right),
          ],
        ),

        ...history.map((r) {
          final start = DateTime.parse(r['start_time']).toLocal();
          final end = r['end_time'] != null
              ? DateTime.parse(r['end_time']).toLocal()
              : null;

          final hours = ((r['total_hours'] ?? 0) as num).toDouble();
          final payment = ((r['total_payment'] ?? 0) as num).toDouble();

          final timeRange = end != null
              ? '${DateFormat.Hm().format(start)} - ${DateFormat.Hm().format(end)}'
              : '${DateFormat.Hm().format(start)} - —';

          final cells = [
            DateFormat.yMMMd().format(start),
            timeRange,
            '${hours.toStringAsFixed(2)} h',
            '\$${payment.toStringAsFixed(2)}',
          ];

          return pw.TableRow(
            children: cells.map((e) {
              return pw.Padding(
                padding: const pw.EdgeInsets.all(8),
                child: pw.Text(e),
              );
            }).toList(),
          );
        }),
      ],
    );
  }


  pw.Widget _pdfFooter() {
    return pw.Container(
      padding: const pw.EdgeInsets.only(top: 14),
      decoration: const pw.BoxDecoration(
        border: pw.Border(
          top: pw.BorderSide(width: 0.5, color: PdfColors.grey300),
        ),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(
            'Generated by your app',
            style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey600),
          ),
          pw.Text(
            '© ${DateTime.now().year}',
            style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey600),
          ),
        ],
      ),
    );
  }


  Future<void> _forceEndShift() async {
    // 1️⃣ найти активную смену
    final activeShift = await supabase
        .from('work_logs')
        .select()
        .eq('user_id', widget.worker['auth_user_id'])
        .isFilter('end_time', null)
        .order('start_time', ascending: false)
        .limit(1)
        .maybeSingle();

    if (activeShift == null) {
      _showError('No active shift found');
      return;
    }

    // 2️⃣ расчёт времени
    final start = DateTime.parse(activeShift['start_time']).toLocal();
    final end = DateTime.now();

    final hours = safeWorkedDuration(start, end).inSeconds / 3600;

    // 3️⃣ ставка
    final rate = (activeShift['pay_rate'] ??
        widget.worker['hourly_rate'] ??
        0)
        .toDouble();

    final total = hours * rate;

    await supabase.from('work_logs').update({
      'end_time': end.toUtc().toIso8601String(),
      'total_hours': hours,
      'total_payment': total,
      'payment_status': 'pending', // ✅ важно (если LIVE считается по статусу)
    }).eq('id', activeShift['id']);

// ✅ ДОБАВЬ: снять флаг on_shift у worker (если LIVE считается по workers)
    await supabase.from('workers').update({
      'on_shift': false,
      'last_work_at': end.toUtc().toIso8601String(),
    }).eq('id', widget.worker['id']);

    // 5️⃣ обновляем данные
    await _loadHistory();
    await _loadWorker();

    setState(() {
      _lastPaymentFuture = _loadLastPayment();
    });

    if (!mounted) return;

    AppToast.success(context, 'Shift force-ended successfully');
  }


  Future<void> _confirmForceEndShift() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: const [
            Icon(Icons.warning, color: Colors.red),
            SizedBox(width: 8),
            Text('Force end shift'),
          ],
        ),
        content: const Text(
          'This will immediately end the current shift and calculate payment.\n\nAre you sure?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Force End'),
          ),
        ],
      ),
    );

    if (ok == true) {
      await _forceEndShift();
      if (mounted) {
        Navigator.pop(context, true); // 🔥 СИГНАЛ НАЗАД
      }
    }

  }


  @override
  void initState() {
    super.initState();
    _loadWorker();
    _loadHistory();
    _paymentsFuture = _loadPayments();
    _lastPaymentFuture = _loadLastPayment();

    // ⏱ тик каждую секунду
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      _now.value = DateTime.now();
    });
    // ✅ PAYMENTS ротатор (каждые 3 секунды)
    _paymentsTicker = Timer.periodic(const Duration(seconds: 3), (_) {
      if (!mounted) return;
      _paymentsTipIndex.value = (_paymentsTipIndex.value + 1) % 3;
    });
  }



  // ================= DATA =================

  Future<void> _loadHistory() async {
    final data = await supabase
        .from('work_logs')
        .select()
        .eq('user_id', widget.worker['auth_user_id'])
        .order('start_time', ascending: false);

    history = List<Map<String, dynamic>>.from(data);
    print('HISTORY LEN: ${history.length}');
    if (history.isNotEmpty) {
      print('FIRST ROW KEYS: ${history.first.keys.toList()}');
      print('FIRST ROW total_hours: ${history.first['total_hours']}');
      print('FIRST ROW total_payment: ${history.first['total_payment']}');
      print('FIRST ROW paid_at: ${history.first['paid_at']}');
    }

    _buildHistoryWorkDays();

    setState(() {
      loading = false;
    });


  }


  Future<void> _loadWorker() async {
    final data = await supabase
        .from('workers')
        .select()
        .eq('id', widget.worker['id'])
        .maybeSingle();

    if (!mounted) return;

    if (data != null) {
      setState(() {
        workerFull = Map<String, dynamic>.from(data);
      });
    }
  }


  void _buildHistoryWorkDays() {
    _historyWorkDays.clear();

    for (final row in history) {
      if (row['start_time'] == null) continue;

      final start = DateTime.parse(row['start_time']).toLocal();
      final day = DateTime(start.year, start.month, start.day);

      _historyWorkDays.putIfAbsent(day, () => []);
      _historyWorkDays[day]!.add(row);
    }
  }

  void _buildPaymentDays(List<Map<String, dynamic>> payments) {
    _paymentDays.clear();

    for (final payment in payments) {
      final raw = payment['created_at'];
      if (raw == null) continue;

      final dt = DateTime.parse(raw.toString()).toLocal();
      final day = DateTime(dt.year, dt.month, dt.day);

      _paymentDays.putIfAbsent(day, () => []);
      _paymentDays[day]!.add(payment);
    }
  }

  Color? _dayStatusColor(DateTime day) {
    final key = DateTime(day.year, day.month, day.day);
    final rows = _historyWorkDays[key];

    if (rows == null || rows.isEmpty) return null;

    final allPaid = rows.every((r) => r['paid_at'] != null);

    if (allPaid) return Colors.green;
    return Colors.orange;
  }

  Future<List<Map<String, dynamic>>> _loadPayments() async {
    final data = await supabase
        .from('payments')
        .select('''
        id,
        created_at,
        total_amount,
        total_hours,
        payment_items (
          id,
          amount,
          work_logs:work_log_id (
            id,
            start_time,
            end_time,
            total_payment,
            total_hours
          )
        )
      ''')
        .eq('worker_auth_id', widget.worker['auth_user_id'])
        .order('created_at', ascending: false);

    final list = List<Map<String, dynamic>>.from(data);
    _buildPaymentDays(list);

    if (mounted) {
      setState(() {
        _paymentsCache = list;
        _paymentsLoaded = true;
      });
    } else {
      _paymentsCache = list;
      _paymentsLoaded = true;
    }

    return list;
  }

  Future<Map<String, dynamic>?> _loadLastPayment() async {
    final data = await supabase
        .from('payments')
        .select()
        .eq('worker_auth_id', widget.worker['auth_user_id'])
        .order('created_at', ascending: false)
        .limit(1)
        .maybeSingle();

    return data != null ? Map<String, dynamic>.from(data) : null;
  }


  Map<String, List<Map<String, dynamic>>> _groupByDay() {
    final Map<String, List<Map<String, dynamic>>> map = {};

    for (final row in history) {
      final day = DateFormat.yMMMMd()
          .format(DateTime.parse(row['start_time']).toLocal());

      map.putIfAbsent(day, () => []);
      map[day]!.add(row);
    }

    return map;
  }

  Widget _legendDot(Color color, String text) {
    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Text(
          text,
          style: TextStyle(
            fontWeight: FontWeight.w900,
            color: text.contains('\$') ? Colors.green : null,
          ),
        ),

      ],
    );
  }

  Widget _pendingRow(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Icon(icon, size: 18, color: kTextSecondary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: kTextSecondary,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _timeRangeRow({
    required Color accent,
    required String startTime,
    required String endTime,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Icon(Icons.schedule_rounded, size: 18, color: accent),
          const SizedBox(width: 8),
          const Text(
            'Time:',
            style: TextStyle(
              color: kTextSecondary,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            '$startTime → $endTime',
            style: TextStyle(
              color: accent,
              fontSize: 13,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  Widget _paidRow(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Icon(icon, size: 18, color: kTextSecondary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: kTextSecondary,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _detailsHintRow({
    required Color accent,
    required String text,
  }) {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        children: [
          Icon(Icons.touch_app_rounded, size: 16, color: accent.withOpacity(0.92)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: accent.withOpacity(0.95),
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _historyDetailCapsule({
    required IconData icon,
    required String label,
    required String value,
    Color? valueColor,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      decoration: BoxDecoration(
        color: const Color(0xFF2F333B),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withOpacity(0.07)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.18),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
          BoxShadow(
            color: Colors.white.withOpacity(0.02),
            blurRadius: 3,
            offset: const Offset(0, -1),
          ),
        ],
      ),
      child: Row(
        children: [
          Icon(
            icon,
            size: 16,
            color: Colors.white.withOpacity(0.48),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 76,
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Colors.white.withOpacity(0.58),
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                height: 1.0,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: valueColor ?? Colors.white.withOpacity(0.94),
                fontSize: 12.5,
                fontWeight: FontWeight.w800,
                height: 1.1,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _historySessionCapsule({
    required int index,
    required String timeText,
    required String workedText,
    required String amountText,
    required Color accent,
    String? startAddress,
    String? endAddress,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(12, 11, 12, 11),
      decoration: BoxDecoration(
        color: const Color(0xFF2A2E35),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: Colors.white.withOpacity(0.07)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.20),
            blurRadius: 12,
            offset: const Offset(0, 5),
          ),
          BoxShadow(
            color: Colors.white.withOpacity(0.02),
            blurRadius: 3,
            offset: const Offset(0, -1),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Session $index',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.90),
                    fontWeight: FontWeight.w800,
                    fontSize: 12.5,
                  ),
                ),
              ),
              Text(
                amountText,
                style: TextStyle(
                  color: accent,
                  fontWeight: FontWeight.w900,
                  fontSize: 12.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _historyDetailCapsule(
            icon: Icons.schedule_rounded,
            label: 'Time',
            value: timeText,
          ),
          _historyDetailCapsule(
            icon: Icons.timer_rounded,
            label: 'Worked',
            value: workedText,
          ),
          if (startAddress != null && startAddress.trim().isNotEmpty)
            _historyDetailCapsule(
              icon: Icons.login_rounded,
              label: 'Start address',
              value: startAddress,
            ),
          if (endAddress != null && endAddress.trim().isNotEmpty)
            _historyDetailCapsule(
              icon: Icons.logout_rounded,
              label: 'End address',
              value: endAddress,
            ),
        ],
      ),
    );
  }

  Future<void> _openShiftDetailsSheet({
    required List<Map<String, dynamic>> rows,
    required ShiftStatus status,
  }) async {
    final sorted = [...rows]
      ..sort((a, b) {
        final ad = DateTime.parse(a['start_time']).toLocal();
        final bd = DateTime.parse(b['start_time']).toLocal();
        return ad.compareTo(bd);
      });

    if (sorted.isEmpty) return;

    final firstStart = DateTime.parse(sorted.first['start_time']).toLocal();

    DateTime rangeStart = firstStart;
    DateTime rangeEnd = sorted.first['end_time'] != null
        ? DateTime.parse(sorted.first['end_time']).toLocal()
        : DateTime.now();

    Duration totalWorked = Duration.zero;
    double totalAmount = 0;

    for (final row in sorted) {
      final start = DateTime.parse(row['start_time']).toLocal();
      final end = row['end_time'] != null
          ? DateTime.parse(row['end_time']).toLocal()
          : DateTime.now();

      if (start.isBefore(rangeStart)) {
        rangeStart = start;
      }
      if (end.isAfter(rangeEnd)) {
        rangeEnd = end;
      }

      totalWorked += safeWorkedDuration(start, end);

      if (status == ShiftStatus.active) {
        final rate =
        ((row['pay_rate'] ?? workerFull?['hourly_rate'] ?? 0) as num).toDouble();
        totalAmount += end.difference(start).inSeconds / 3600 * rate;
      } else {
        totalAmount += ((row['total_payment'] ?? 0) as num).toDouble();
      }
    }

    final overallStartAddress = (sorted.first['address_start'] ??
        sorted.first['location'] ??
        sorted.first['address'] ??
        sorted.first['work_place'] ??
        '')
        .toString()
        .trim();

    final overallEndAddress = (sorted.last['address_end'] ??
        sorted.last['location'] ??
        sorted.last['address'] ??
        sorted.last['work_place'] ??
        '')
        .toString()
        .trim();

    final hasMultipleSessions = sorted.length > 1;

    final dateText = DateFormat.yMMMd().format(rangeStart);

    final timeSpan =
        '${DateFormat.Hm().format(rangeStart)} → ${status == ShiftStatus.active ? 'now' : DateFormat.Hm().format(rangeEnd)}';

    final workedText =
        '${totalWorked.inHours}:${(totalWorked.inMinutes % 60).toString().padLeft(2, '0')}';

    final accent = status == ShiftStatus.active
        ? Colors.orangeAccent
        : status == ShiftStatus.pending
        ? Colors.white
        : Colors.greenAccent;

    final badgeText = status == ShiftStatus.active
        ? 'ACTIVE'
        : status == ShiftStatus.pending
        ? 'UNPAID'
        : 'PAID';

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withOpacity(0.56),
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 18, 12, 12),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(28),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
                child: Container(
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.of(context).size.height * 0.88,
                  ),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        const Color(0xFF2A2D34).withOpacity(0.985),
                        const Color(0xFF1E2229).withOpacity(0.985),
                        const Color(0xFF11151B).withOpacity(0.99),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(28),
                    border: Border.all(color: Colors.white.withOpacity(0.08)),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.38),
                        blurRadius: 24,
                        offset: const Offset(0, 12),
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
                          color: Colors.white.withOpacity(0.18),
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                      const SizedBox(height: 14),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                'Shift details',
                                style: TextStyle(
                                  color: Colors.white.withOpacity(0.94),
                                  fontWeight: FontWeight.w900,
                                  fontSize: 15,
                                  letterSpacing: 0.2,
                                ),
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(
                                color: accent.withOpacity(status == ShiftStatus.pending ? 0.10 : 0.16),
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(
                                badgeText,
                                style: TextStyle(
                                  color: status == ShiftStatus.pending ? Colors.white : accent,
                                  fontWeight: FontWeight.w900,
                                  fontSize: 11.5,
                                  letterSpacing: 0.6,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                      Flexible(
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.fromLTRB(14, 0, 14, 16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _historyDetailCapsule(
                                icon: Icons.calendar_month_rounded,
                                label: 'Date',
                                value: dateText,
                              ),
                              if (hasMultipleSessions)
                                _historyDetailCapsule(
                                  icon: Icons.layers_rounded,
                                  label: 'Sessions',
                                  value: '${sorted.length}',
                                ),
                              _historyDetailCapsule(
                                icon: Icons.timer_rounded,
                                label: 'Worked',
                                value: workedText,
                              ),
                              _historyDetailCapsule(
                                icon: Icons.attach_money_rounded,
                                label: 'Amount',
                                value: '\$${totalAmount.toStringAsFixed(2)}',
                                valueColor: accent,
                              ),
                              _historyDetailCapsule(
                                icon: Icons.schedule_rounded,
                                label: 'Time span',
                                value: timeSpan,
                              ),
                              if (!hasMultipleSessions && overallStartAddress.isNotEmpty)
                                _historyDetailCapsule(
                                  icon: Icons.login_rounded,
                                  label: 'Start address',
                                  value: overallStartAddress,
                                ),
                              if (!hasMultipleSessions && overallEndAddress.isNotEmpty)
                                _historyDetailCapsule(
                                  icon: Icons.logout_rounded,
                                  label: 'End address',
                                  value: overallEndAddress,
                                ),
                              if (hasMultipleSessions) ...[
                                const SizedBox(height: 6),
                                Padding(
                                  padding: const EdgeInsets.only(left: 2, bottom: 8),
                                  child: Text(
                                    'Sessions',
                                    style: TextStyle(
                                      color: Colors.white.withOpacity(0.62),
                                      fontWeight: FontWeight.w800,
                                      fontSize: 12,
                                      letterSpacing: 0.4,
                                    ),
                                  ),
                                ),
                                ...sorted.asMap().entries.map((entry) {
                                  final index = entry.key + 1;
                                  final row = entry.value;

                                  final start = DateTime.parse(row['start_time']).toLocal();
                                  final end = row['end_time'] != null
                                      ? DateTime.parse(row['end_time']).toLocal()
                                      : DateTime.now();

                                  final worked = safeWorkedDuration(start, end);
                                  final workedText =
                                      '${worked.inHours}:${(worked.inMinutes % 60).toString().padLeft(2, '0')}';

                                  double amount;
                                  if (status == ShiftStatus.active) {
                                    final rate = ((row['pay_rate'] ??
                                        workerFull?['hourly_rate'] ??
                                        0) as num)
                                        .toDouble();
                                    amount = end.difference(start).inSeconds / 3600 * rate;
                                  } else {
                                    amount = ((row['total_payment'] ?? 0) as num).toDouble();
                                  }

                                  final startAddress = (row['address_start'] ??
                                      row['location'] ??
                                      row['address'] ??
                                      row['work_place'] ??
                                      '')
                                      .toString()
                                      .trim();

                                  final endAddress = (row['address_end'] ??
                                      row['location'] ??
                                      row['address'] ??
                                      row['work_place'] ??
                                      '')
                                      .toString()
                                      .trim();

                                  return _historySessionCapsule(
                                    index: index,
                                    timeText:
                                    '${DateFormat.Hm().format(start)} → ${row['end_time'] == null ? 'now' : DateFormat.Hm().format(end)}',
                                    workedText: workedText,
                                    amountText: '\$${amount.toStringAsFixed(2)}',
                                    accent: accent,
                                    startAddress: startAddress.isEmpty ? null : startAddress,
                                    endAddress: endAddress.isEmpty ? null : endAddress,
                                  );
                                }),
                              ],
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
        );
      },
    );
  }

  Widget _shiftCard(Map<String, dynamic> r) {
    final status = _shiftStatus(r);

    return KeyedSubtree(
      key: ValueKey('${r['id']}_$status'),
      child: _shiftCardInner(r, status),
    );
  }

  Widget _shiftCardInner(Map<String, dynamic> r, ShiftStatus status) {
    final isActive = status == ShiftStatus.active;
    final isPending = status == ShiftStatus.pending;
    final isPaid = status == ShiftStatus.paid;

    final rawGroup = r['__group_rows'];

    final List<Map<String, dynamic>> sortedRows = rawGroup is List
        ? rawGroup
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList()
        : <Map<String, dynamic>>[Map<String, dynamic>.from(r)];

    sortedRows.sort((a, b) {
      final ad = DateTime.parse(a['start_time']).toLocal();
      final bd = DateTime.parse(b['start_time']).toLocal();
      return ad.compareTo(bd);
    });

    final bool isGrouped = sortedRows.length > 1;

    final start = DateTime.parse(sortedRows.first['start_time']).toLocal();

    DateTime rangeEnd = sortedRows.first['end_time'] != null
        ? DateTime.parse(sortedRows.first['end_time']).toLocal()
        : DateTime.now();

    Duration totalWorked = Duration.zero;
    double staticAmount = 0;

    for (final row in sortedRows) {
      final rowStart = DateTime.parse(row['start_time']).toLocal();
      final rowEnd = row['end_time'] != null
          ? DateTime.parse(row['end_time']).toLocal()
          : DateTime.now();

      if (rowEnd.isAfter(rangeEnd)) {
        rangeEnd = rowEnd;
      }

      totalWorked += safeWorkedDuration(rowStart, rowEnd);

      if (status != ShiftStatus.active) {
        staticAmount += ((row['total_payment'] ?? 0) as num).toDouble();
      }
    }

    final startTime = DateFormat.Hm().format(start);
    final endTime = status == ShiftStatus.active ? 'now' : DateFormat.Hm().format(rangeEnd);
    final dateText = DateFormat.yMMMd().format(start);

    final workedText =
        '${totalWorked.inHours}:${(totalWorked.inMinutes % 60).toString().padLeft(2, '0')}';

    final detailsHint = isGrouped
        ? '${sortedRows.length} sessions • Tap for more details'
        : 'Tap for more details';

    late final Widget card;

    if (isActive) {
      card = ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
          child: Container(
            margin: const EdgeInsets.fromLTRB(6, 0, 6, 14),
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(22),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Colors.orangeAccent.withOpacity(0.10),
                  Colors.orangeAccent.withOpacity(0.05),
                  Colors.orange.withOpacity(0.30),
                ],
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.calendar_month, size: 16, color: Colors.orangeAccent),
                        const SizedBox(width: 6),
                        Text(
                          dateText,
                          style: const TextStyle(
                            color: kTextPrimary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                    _ActiveLiveCapsule(),
                  ],
                ),
                const SizedBox(height: 14),
                Center(
                  child: ValueListenableBuilder<DateTime>(
                    valueListenable: _now,
                    builder: (_, now, __) {
                      double liveAmount = 0;

                      for (final row in sortedRows) {
                        final rowStart = DateTime.parse(row['start_time']).toLocal();
                        final rate = ((row['pay_rate'] ??
                            workerFull?['hourly_rate'] ??
                            0) as num)
                            .toDouble();

                        final seconds = now.difference(rowStart).inSeconds;
                        final hours = seconds / 3600;
                        liveAmount += hours * rate;
                      }

                      return AnimatedAmount(
                        value: liveAmount,
                        style: const TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.w900,
                          color: Colors.orangeAccent,
                          letterSpacing: 0.4,
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 6),
                Center(
                  child: ValueListenableBuilder<DateTime>(
                    valueListenable: _now,
                    builder: (_, now, __) {
                      Duration total = Duration.zero;

                      for (final row in sortedRows) {
                        final rowStart = DateTime.parse(row['start_time']).toLocal();
                        total += now.difference(rowStart);
                      }

                      final h = total.inHours;
                      final m = (total.inMinutes % 60).toString().padLeft(2, '0');

                      return Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.timer,
                            size: 16,
                            color: Colors.orangeAccent,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            '$h:$m',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: Colors.orangeAccent,
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    const Icon(
                      Icons.login,
                      size: 18,
                      color: Colors.orangeAccent,
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      'Started:',
                      style: TextStyle(
                        color: kTextSecondary,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      startTime,
                      style: const TextStyle(
                        color: Colors.orangeAccent,
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
                if (isGrouped) ...[
                  const SizedBox(height: 6),
                  _pendingRow(Icons.layers_rounded, '${sortedRows.length} sessions'),
                ],
                _detailsHintRow(
                  accent: Colors.orangeAccent,
                  text: detailsHint,
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        ),
      );
    } else if (isPending) {
      card = ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
          child: Container(
            margin: const EdgeInsets.fromLTRB(6, 0, 6, 14),
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(22),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Colors.white.withOpacity(0.10),
                  Colors.white.withOpacity(0.05),
                  Colors.black.withOpacity(0.30),
                ],
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.calendar_month, size: 16, color: Colors.white60),
                        const SizedBox(width: 6),
                        Text(
                          dateText,
                          style: const TextStyle(
                            color: kTextPrimary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(999),
                        color: Colors.white.withOpacity(0.10),
                      ),
                      child: const Text(
                        'PENDING',
                        style: TextStyle(
                          color: kTextPrimary,
                          fontWeight: FontWeight.w800,
                          fontSize: 12,
                          letterSpacing: 0.6,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Center(
                  child: Text(
                    '\$${staticAmount.toStringAsFixed(2)}',
                    style: const TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.w900,
                      color: kTextPrimary,
                      letterSpacing: 0.4,
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                _pendingRow(Icons.timer, 'Worked: $workedText'),
                if (isGrouped) _pendingRow(Icons.layers_rounded, '${sortedRows.length} sessions'),
                _detailsHintRow(
                  accent: Colors.white70,
                  text: detailsHint,
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        ),
      );
    } else if (isPaid) {
      card = ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
          child: Container(
            margin: const EdgeInsets.fromLTRB(6, 0, 6, 14),
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(22),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Colors.green.withOpacity(0.14),
                  Colors.greenAccent.withOpacity(0.06),
                  Colors.lightGreen.withOpacity(0.34),
                ],
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.calendar_month, size: 16, color: Colors.greenAccent),
                        const SizedBox(width: 6),
                        Text(
                          dateText,
                          style: const TextStyle(
                            color: kTextPrimary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(999),
                        color: Colors.green.withOpacity(0.18),
                      ),
                      child: const Text(
                        'PAID',
                        style: TextStyle(
                          color: Colors.greenAccent,
                          fontWeight: FontWeight.w900,
                          fontSize: 12,
                          letterSpacing: 0.6,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Center(
                  child: Text(
                    '\$${staticAmount.toStringAsFixed(2)}',
                    style: const TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.w900,
                      color: Colors.greenAccent,
                      letterSpacing: 0.4,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    const Icon(
                      Icons.timer,
                      size: 18,
                      color: Colors.greenAccent,
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      'Worked:',
                      style: TextStyle(
                        color: kTextSecondary,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      workedText,
                      style: const TextStyle(
                        color: Colors.greenAccent,
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
                if (isGrouped) ...[
                  const SizedBox(height: 6),
                  _paidRow(Icons.layers_rounded, '${sortedRows.length} sessions'),
                ],
                _detailsHintRow(
                  accent: Colors.greenAccent,
                  text: detailsHint,
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        ),
      );
    } else {
      return const SizedBox.shrink();
    }

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: () => _openShiftDetailsSheet(
          rows: sortedRows,
          status: status,
        ),
        child: card,
      ),
    );
  }

  // ================= ACTIONS =================

  Future<void> _editWorker() async {
    await showDialog(
      context: context,
      builder: (_) => EditWorkerDialog(
        worker: workerFull!,
      ),
    );

// 🔥 ВСЕГДА перечитываем worker после закрытия
    await _loadWorker();
  }

  Future<void> _payWorker() async {

    if (_isSuspended) {
      _showError('Payments disabled for suspended worker');
      return;
    }

    // 1) подготовь workDays как раньше (как ты уже делаешь)
    final workDays = Map<DateTime, List<Map<String, dynamic>>>.from(_historyWorkDays);

    // 2) открой sheet и жди выбранный диапазон
    final range = await showModalBottomSheet<DateTimeRange>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => PayCalendarSheet(workDays: workDays),
    );

    if (range == null) return;

    // 3) собери UTC границы

    final fromUtc = range.start.toUtc();
    final toUtc   = range.end.toUtc();

    // 4) открой preview (ТУТ ЖЕ, В РОДИТЕЛЬСКОМ КОНТЕКСТЕ)
    await _openPaymentPreview(
      worker: widget.worker,
      fromUtc: fromUtc,
      toUtc: toUtc,
      onShift: (widget.worker['on_shift'] == true),
    );
  }

  DateTime _shiftDayKey(Map<String, dynamic> r) {
    final start = DateTime.parse(r['start_time']).toLocal();
    return DateTime(start.year, start.month, start.day);
  }

  bool _dayHasPaidShift(DateTime dayKey) {
    final rows = _historyWorkDays[dayKey] ?? const <Map<String, dynamic>>[];
    return rows.any((x) => x['paid_at'] != null);
  }

  bool _dayHasActiveShift(DateTime dayKey) {
    final rows = _historyWorkDays[dayKey] ?? const <Map<String, dynamic>>[];
    return rows.any((x) => x['end_time'] == null);
  }

  bool _dayHasUnpaidShift(DateTime dayKey) {
    final rows = _historyWorkDays[dayKey] ?? const <Map<String, dynamic>>[];
    return rows.any((x) =>
    x['end_time'] != null && x['paid_at'] == null);
  }

  Future<void> _payNowForShiftDay(Map<String, dynamic> shiftRow) async {
    if (_isSuspended) {
      _showError('Payments disabled for suspended worker');
      return;
    }

    final dayKey = _shiftDayKey(shiftRow);

    // Делаем границы дня в LOCAL, а потом переводим в UTC так же, как ты делал в PayCalendarSheet
    final fromUtc = DateTime(dayKey.year, dayKey.month, dayKey.day, 0, 0, 0).toUtc();
    final toUtc   = DateTime(dayKey.year, dayKey.month, dayKey.day, 23, 59, 59, 999).toUtc();

    await _openPaymentPreview(
      worker: workerFull ?? widget.worker,
      fromUtc: fromUtc,
      toUtc: toUtc,
      onShift: (widget.worker['on_shift'] == true),
    );
  }

  // ================= PREVIEW =================

  Future<void> _openPaymentPreview({
    required Map<String, dynamic> worker,
    required DateTime fromUtc,
    required DateTime toUtc,
    required bool onShift, // ✅
  }) async {
    debugPrint('OPEN PREVIEW -> start');

    if (_isSuspended) {
      _showError('Payments disabled for suspended worker');
      return;
    }

    final session = supabase.auth.currentSession;
    if (session == null) return;

    try {
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

      // если invoke НЕ бросил — можно проверить статус
      if (res.status != 200) {
        _showError(res.data?.toString() ?? 'Error ${res.status}');
        return;
      }

      if (!mounted) return;

      _showPaymentPreviewDialog(
        worker: worker,
        preview: Map<String, dynamic>.from(res.data),
        fromUtc: fromUtc,
        toUtc: toUtc,
        isOnShift: onShift,
      );

    } on FunctionException catch (e) {
      // самое важное
      _showError(e.details ?? e.reasonPhrase ?? e.toString());
    } catch (e) {
      _showError(e.toString());
    }
  }

  void _showPaymentPreviewDialog({
    required Map<String, dynamic> worker,
    required Map<String, dynamic> preview,
    required DateTime fromUtc,
    required DateTime toUtc,
    required bool isOnShift,
  }) {
    final rows = List<Map<String, dynamic>>.from(preview['rows'] ?? const []);
    final totalHours = ((preview['total_hours'] ?? 0) as num).toDouble();
    final totalAmount = ((preview['total_amount'] ?? 0) as num).toDouble();
    final unpaidCount = rows.length;

    showDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withOpacity(0.55),
      builder: (ctx) {
        return Dialog(
          backgroundColor: const Color(0xFF1E1C22), // ✅ НЕ прозрачный
          insetPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 24),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(26),
          ),
          child: Container(
            decoration: BoxDecoration(
              // ✅ полностью НЕ прозрачный градиент (как твой стиль в приложении)
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0xFF2F3036),
                  Color(0xFF24252B),
                  Color(0xFF1E1C22),
                ],
              ),
              borderRadius: BorderRadius.circular(26),
              border: Border.all(color: Colors.white10),
              boxShadow: [
                BoxShadow(
                  color: Colors.black54,
                  blurRadius: 28,
                  offset: Offset(0, 18),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // ===== TITLE =====
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 16, 18, 12),
                  child: Row(
                    children: const [
                      Icon(Icons.payments_rounded, color: Colors.greenAccent, size: 18),
                      SizedBox(width: 8),
                      Text(
                        'Payment preview',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                          fontSize: 16,
                        ),
                      ),
                    ],
                  ),
                ),

                // ===== HEADER CARD (name/email/date) =====
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 14),
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1C1B20),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: Colors.white.withOpacity(0.08)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.person, size: 14, color: Colors.deepPurpleAccent),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              (worker['name'] ?? '—').toString(),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                                fontSize: 14,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          const Icon(Icons.email_outlined, size: 13, color: Colors.white70),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              (worker['email'] ?? '—').toString(),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: Colors.white60, fontSize: 12),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          const Icon(Icons.calendar_month, size: 13, color: Colors.lightBlueAccent),
                          const SizedBox(width: 6),
                          Text(
                            '${DateFormat.yMMMd().format(fromUtc.toLocal())} - ${DateFormat.yMMMd().format(toUtc.toLocal())}',
                            style: const TextStyle(color: Colors.white38, fontSize: 12),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 12),

                // ===== BODY CARD =====
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 14),
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.04),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: Colors.white.withOpacity(0.10)),
                  ),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          _previewStat(Icons.timer, _fmtHmFromHours(totalHours),
                              iconColor: Colors.lightBlueAccent),
                          _previewStat(Icons.attach_money, totalAmount.toStringAsFixed(2),
                              iconColor: Colors.greenAccent),
                          _previewStat(Icons.warning_rounded, '$unpaidCount shifts',
                              iconColor: Colors.amber),
                        ],
                      ),

                      const SizedBox(height: 12),
                      Divider(height: 1, color: Colors.white.withOpacity(0.10)),
                      const SizedBox(height: 10),

                      Container(
                        padding: const EdgeInsets.fromLTRB(10, 10, 10, 6),
                        decoration: BoxDecoration(
                          color: const Color(0xFF2A2C33),
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(color: Colors.white.withOpacity(0.08)),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.18),
                              blurRadius: 12,
                              offset: const Offset(0, 5),
                            ),
                          ],
                        ),
                        child: SizedBox(
                          height: (rows.length.clamp(1, 3)) * 70.0,
                          child: ScrollConfiguration(
                            behavior: const _NoScrollbarNoGlow(),
                            child: ListView.separated(
                              padding: EdgeInsets.zero,
                              itemCount: rows.length,
                              physics: const BouncingScrollPhysics(),
                              separatorBuilder: (_, __) => Divider(
                                height: 1,
                                color: Colors.white.withOpacity(0.08),
                              ),
                              itemBuilder: (context, index) {
                                final r = rows[index];
                                final start = DateTime.parse(r['start_time']).toLocal();
                                final end = DateTime.parse(r['end_time']).toLocal();
                                final amount = ((r['total_payment'] ?? 0) as num).toDouble();

                                return Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
                                  child: Row(
                                    children: [
                                      Container(
                                        width: 30,
                                        height: 30,
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          color: Colors.orange.withOpacity(0.16),
                                        ),
                                        child: Center(
                                          child: Text(
                                            '${index + 1}',
                                            style: const TextStyle(
                                              color: Colors.orangeAccent,
                                              fontWeight: FontWeight.w900,
                                              fontSize: 12,
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
                                              DateFormat.yMMMd().format(start),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                color: Colors.white70,
                                                fontWeight: FontWeight.w800,
                                                fontSize: 13.5,
                                              ),
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              '${DateFormat.Hm().format(start)} - ${DateFormat.Hm().format(end)}',
                                              style: const TextStyle(
                                                color: Colors.white54,
                                                fontSize: 12.5,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      Text(
                                        '\$${amount.toStringAsFixed(2)}',
                                        style: const TextStyle(
                                          color: Colors.greenAccent,
                                          fontWeight: FontWeight.w900,
                                          fontSize: 14,
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                          ),
                        ),
                      ),

                      const SizedBox(height: 10),

                      Text(
                        '\$${totalAmount.toStringAsFixed(2)}',
                        style: const TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.w900,
                          color: Colors.greenAccent,
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 14),

                // ===== ACTIONS =====
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                  child: Row(
                    children: [
                      Expanded(
                        child: _pillButton(
                          label: 'Cancel',
                          icon: Icons.close,
                          bg: Colors.white.withOpacity(0.08),
                          fg: Colors.white70,
                          onTap: () => Navigator.pop(ctx),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _pillButton(
                          label: 'PAY',
                          icon: Icons.attach_money,
                          bg: (isOnShift || unpaidCount == 0)
                              ? Colors.white.withOpacity(0.08)
                              : const Color(0xFF4CAF50),
                          fg: (isOnShift || unpaidCount == 0)
                              ? Colors.white38
                              : Colors.black,
                          onTap: (isOnShift || unpaidCount == 0)
                              ? null
                              : () async {
                            Navigator.pop(ctx);
                            await _payWorkerPeriod(
                              workerAuthId: worker['auth_user_id'],
                              fromUtc: fromUtc,
                              toUtc: toUtc,
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _previewStat(IconData icon, String text, {required Color iconColor}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 18, color: iconColor),
        const SizedBox(width: 6),
        Text(
          text,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w900,
            fontSize: 14,
          ),
        ),
      ],
    );
  }

  Widget _pillButton({
    required String label,
    required IconData icon,
    required Color bg,
    required Color fg,
    required VoidCallback? onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withOpacity(0.10)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 18, color: fg),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                color: fg,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.6,
              ),
            ),
          ],
        ),
      ),
    );
  }



  Widget _stat(
      IconData icon,
      String text, {
        required Color iconColor,
      }) {
    return Row(
      children: [
        Icon(icon, size: 18, color: iconColor),
        const SizedBox(width: 6),
        Text(
          text,
          style: const TextStyle(
            fontWeight: FontWeight.w900,
            fontSize: 14,
          ),
        ),
      ],
    );
  }



  // ================= PAY =================

  Future<void> _payWorkerPeriod({
    required String workerAuthId,
    required DateTime fromUtc,
    required DateTime toUtc,
  }) async {
    final session = supabase.auth.currentSession;
    if (session == null) return;

    if (_isSuspended) {
      _showError('Payments disabled for suspended worker');
      return;
    }

    debugPrint(
      'PAY invoke -> start user=$workerAuthId from=${fromUtc.toIso8601String()} to=${toUtc.toIso8601String()}',
    );

    try {
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

      debugPrint('PAY invoke -> status=${res.status} data=${res.data}');

      if (res.status != 200) {
        _showError(res.data?.toString() ?? 'Error ${res.status}');
        return;
      }

      final data = Map<String, dynamic>.from(res.data);

      _showPaymentSuccessDialog(
        paidShifts: (data['paid_shifts'] ?? 0) as int,
        totalAmount: (data['total_amount'] ?? 0) as num,
      );

      await _loadHistory();
      if (mounted) setState(() {});
    } on FunctionException catch (e) {
      debugPrint('PAY FunctionException: ${e.details ?? e.reasonPhrase ?? e.toString()}');
      _showError(e.details ?? e.reasonPhrase ?? e.toString());
    } catch (e) {
      _showError(e.toString());
    }
  }


  void _showPaymentSuccessDialog({
    required int paidShifts,
    required num totalAmount,
  }) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(4),
          ),
          backgroundColor: Colors.transparent,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
              child: Container(
                padding: const EdgeInsets.fromLTRB(22, 24, 22, 20),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Colors.green.withOpacity(0.25),
                      Colors.greenAccent.withOpacity(0.12),
                      Colors.black.withOpacity(0.35),
                    ],
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // ✅ ICON
                    Container(
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.greenAccent.withOpacity(0.2),
                      ),
                      child: const Icon(
                        Icons.check_circle_rounded,
                        size: 42,
                        color: Colors.greenAccent,
                      ),
                    ),

                    const SizedBox(height: 16),

                    // ✅ TITLE
                    const Text(
                      'Payment successful',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                        letterSpacing: 0.4,
                      ),
                    ),

                    const SizedBox(height: 12),

                    // ✅ STATS
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.event_available,
                              size: 22,
                              color: Colors.lightBlueAccent,
                            ),
                            SizedBox(width: 6),
                            Text(
                              '$paidShifts shift${paidShifts == 1 ? '' : 's'}',
                              style: const TextStyle(
                                color: Colors.white70,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(width: 24),

                        Row(
                          children: [
                            const Icon(
                              Icons.paid,
                              size: 22,
                              color: Colors.greenAccent,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              '\$${totalAmount.toStringAsFixed(2)}',
                              style: const TextStyle(
                                color: Colors.greenAccent,
                                fontWeight: FontWeight.w900,
                                fontSize: 16,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),


                    const SizedBox(height: 22),

                    // ✅ BUTTON
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.greenAccent,
                          foregroundColor: Colors.black,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        onPressed: () => Navigator.pop(ctx),
                        child: const Text(
                          'DONE',
                          style: TextStyle(
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.6,
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
      },
    );
  }

  Widget _successStat({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Column(
      children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(height: 6),
        Text(
          value,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w900,
            color: color,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            color: Colors.white60,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }


  Future<Uint8List> _buildPaymentPdfBytes(Map<String, dynamic> payment) async {
    final pdf = pw.Document();

    // LOGO
    final logoImage = await _loadCompanyLogoForPdf();

    // AVATAR (optional)
    pw.ImageProvider? avatarImage;
    final avatarUrl = widget.worker['avatar_url'];

    if (avatarUrl != null && avatarUrl.toString().isNotEmpty) {
      try {
        final response = await http.get(Uri.parse(avatarUrl));
        if (response.statusCode == 200) {
          avatarImage = pw.MemoryImage(response.bodyBytes);
        }
      } catch (_) {
        avatarImage = null;
      }
    }

    // PAYMENT DATA
    final totalAmount = (payment['total_amount'] ?? 0).toDouble();
    final paidAt = DateTime.parse(payment['created_at']).toLocal();

    final items = List<Map<String, dynamic>>.from(
      payment['payment_items'] ?? [],
    );

    // PERIOD from shifts
    DateTime? from;
    DateTime? to;

    for (final it in items) {
      final wl = it['work_logs'];
      if (wl == null) continue;

      final start = DateTime.parse(wl['start_time']).toLocal();
      from = from == null || start.isBefore(from!) ? start : from;
      to   = to   == null || start.isAfter(to!)   ? start : to;
    }

    final periodText = (from != null && to != null)
        ? '${DateFormat.yMMMd().format(from)} - ${DateFormat.yMMMd().format(to)}'
        : '—';

    double totalWorked = 0;
    double totalAmountCheck = 0;

    for (final it in items) {
      final wl = it['work_logs'];
      if (wl == null) continue;

      totalWorked += ((wl['total_hours'] ?? 0) as num).toDouble();
      totalAmountCheck += ((it['amount'] ?? 0) as num).toDouble();
    }

    pdf.addPage(
      pw.MultiPage(
        pageTheme: pw.PageTheme(
          margin: const pw.EdgeInsets.all(32),
          theme: pw.ThemeData.withFont(
            base: pw.Font.helvetica(),
            bold: pw.Font.helveticaBold(),
          ),
        ),
        build: (_) => [
          // HEADER
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            crossAxisAlignment: pw.CrossAxisAlignment.center,
            children: [
              if (logoImage != null)
                pw.Container(
                  width: 90,
                  height: 52,
                  child: pw.Image(
                    logoImage,
                    fit: pw.BoxFit.contain,
                  ),
                )
              else
                pw.SizedBox(width: 90, height: 52),

              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  pw.Text(
                    'PAYMENT STATEMENT',
                    style: pw.TextStyle(
                      fontSize: 16,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                  pw.SizedBox(height: 4),
                  pw.Text(
                    DateFormat.yMMMd().format(DateTime.now()),
                    style: const pw.TextStyle(
                      fontSize: 10,
                      color: PdfColors.grey600,
                    ),
                  ),
                ],
              ),
            ],
          ),

          pw.SizedBox(height: 24),

          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              if (avatarImage != null)
                pw.Container(
                  width: 56,
                  height: 56,
                  decoration: pw.BoxDecoration(
                    borderRadius: pw.BorderRadius.circular(6),
                  ),
                  child: pw.Image(avatarImage!, fit: pw.BoxFit.cover),
                ),

              pw.SizedBox(width: 14),

              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    (workerFull?['name'] ?? '—').toString(),
                    style: pw.TextStyle(
                      fontSize: 12,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                  pw.SizedBox(height: 4),
                  pw.Text(
                    widget.worker['email'] ?? '—',
                    style: pw.TextStyle(
                      fontSize: 10,
                      color: PdfColors.grey600,
                    ),
                  ),
                  pw.SizedBox(height: 6),
                  pw.Text(
                    '\$${(workerFull?['hourly_rate'] ?? 0).toString()}/h',
                    style: pw.TextStyle(
                      fontSize: 10,
                      color: PdfColors.grey700,
                    ),
                  ),
                ],
              ),
            ],
          ),

          pw.SizedBox(height: 20),

          pw.Container(
            padding: const pw.EdgeInsets.symmetric(vertical: 16),
            decoration: pw.BoxDecoration(
              color: PdfColors.grey100,
              borderRadius: pw.BorderRadius.circular(10),
              border: pw.Border.all(color: PdfColors.grey300),
            ),
            child: pw.Row(
              children: [
                _summaryCell(
                  label: 'TOTAL PAID',
                  value: '\$${totalAmount.toStringAsFixed(2)}',
                  valueColor: PdfColors.green700,
                ),
                _summaryDivider(),
                _summaryCell(
                  label: 'TOTAL HOURS',
                  value: '${totalWorked.toStringAsFixed(2)} h',
                ),
                _summaryDivider(),
                _summaryCell(
                  label: 'PERIOD',
                  value: periodText,
                  flex: 2,
                ),
                _summaryDivider(),
                _summaryCell(
                  label: 'SHIFTS',
                  value: items.length.toString(),
                ),
              ],
            ),
          ),

          pw.SizedBox(height: 18),

          pw.Text(
            'Shifts details',
            style: pw.TextStyle(
              fontSize: 13,
              fontWeight: pw.FontWeight.bold,
            ),
          ),

          pw.SizedBox(height: 10),

          pw.Table(
            columnWidths: const {
              0: pw.FlexColumnWidth(2),
              1: pw.FlexColumnWidth(3),
              2: pw.FlexColumnWidth(2),
              3: pw.FlexColumnWidth(2),
            },
            border: pw.TableBorder(
              top: pw.BorderSide(color: PdfColors.grey400),
              bottom: pw.BorderSide(color: PdfColors.grey400),
              horizontalInside: pw.BorderSide(color: PdfColors.grey300, width: 0.5),
            ),
            children: [
              pw.TableRow(
                decoration: const pw.BoxDecoration(color: PdfColors.grey200),
                children: [
                  _th('DATE', align: pw.TextAlign.left),
                  _th('TIME', align: pw.TextAlign.center),
                  _th('WORKED', align: pw.TextAlign.center),
                  _th('AMOUNT', align: pw.TextAlign.right),
                ],
              ),
              ...items.asMap().entries.map((entry) {
                final index = entry.key;
                final it = entry.value;

                final wl = it['work_logs'];
                if (wl == null) {
                  return pw.TableRow(
                    children: [_td('—'), _td('—'), _td('—'), _td('—')],
                  );
                }

                final start = DateTime.parse(wl['start_time']).toLocal();
                final end = DateTime.parse(wl['end_time']).toLocal();
                final worked = safeWorkedDuration(start, end);
                final hours = worked.inSeconds / 3600;

                final amount = ((it['amount'] ?? 0) as num).toDouble();

                return pw.TableRow(
                  decoration: pw.BoxDecoration(
                    color: index.isEven ? PdfColors.white : PdfColors.grey100,
                  ),
                  children: [
                    _td(DateFormat.yMMMd().format(start), align: pw.TextAlign.left),
                    _td(
                      '${DateFormat.Hm().format(start)} - ${DateFormat.Hm().format(end)}',
                      align: pw.TextAlign.center,
                    ),
                    _td('${hours.toStringAsFixed(2)} h', align: pw.TextAlign.center),
                    _td('\$${amount.toStringAsFixed(2)}', align: pw.TextAlign.right),
                  ],
                );
              }),

              pw.TableRow(
                decoration: const pw.BoxDecoration(color: PdfColors.grey300),
                children: [
                  _tdBold('TOTAL', align: pw.TextAlign.left),
                  _td('', align: pw.TextAlign.center),
                  _tdBold('${totalWorked.toStringAsFixed(2)} h', align: pw.TextAlign.center),
                  _tdBold(
                    '\$${totalAmountCheck.toStringAsFixed(2)}',
                    color: PdfColors.green700,
                    align: pw.TextAlign.right,
                  ),
                ],
              ),
            ],
          ),

          pw.SizedBox(height: 24),
          pw.Align(
            alignment: pw.Alignment.center,
            child: pw.Text(
              'Generated Workio Company',
              style: pw.TextStyle(fontSize: 8, color: PdfColors.grey500),
            ),
          ),
        ],
      ),
    );

    return pdf.save(); // ✅ Uint8List
  }

  pw.Widget _pdfStat({
    required String label,
    required String value,
    required PdfColor color,
  }) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          label.toUpperCase(),
          style: const pw.TextStyle(
            fontSize: 9,
            color: PdfColors.grey600,
          ),
        ),
        pw.SizedBox(height: 4),
        pw.Text(
          value,
          style: pw.TextStyle(
            fontSize: 12,
            fontWeight: pw.FontWeight.bold,
            color: color,
          ),
        ),
      ],
    );
  }

  Future<void> _pdfPreview(Map<String, dynamic> payment) async {
    final bytes = await _buildPaymentPdfBytes(payment);
    await pr.Printing.layoutPdf(onLayout: (_) async => bytes);
  }

  Future<void> _pdfShare(Map<String, dynamic> payment) async {
    final bytes = await _buildPaymentPdfBytes(payment);

    final paidAt = DateTime.parse(payment['created_at']).toLocal();
    final filename = 'payment_${DateFormat('yyyy-MM-dd').format(paidAt)}.pdf';

    await pr.Printing.sharePdf(bytes: bytes, filename: filename);
  }

  Future<void> _pdfSave(Map<String, dynamic> payment) async {
    final bytes = await _buildPaymentPdfBytes(payment);

    final paidAt = DateTime.parse(payment['created_at']).toLocal();
    final filename = 'payment_${DateFormat('yyyy-MM-dd').format(paidAt)}.pdf';

    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/$filename');
    await file.writeAsBytes(bytes, flush: true);

    if (!mounted) return;

    _showGlassSnack(
      'Saved: $filename',
      icon: Icons.download_done_rounded,
      accent: const Color(0xFF63F5C2),
    );
  }

  void _showPdfActions(Map<String, dynamic> payment) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: false,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(22),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                child: Container(
                  // ✅ БЕЗ ГРАДИЕНТА
                  decoration: BoxDecoration(
                    color: const Color(0xFF24252B).withOpacity(0.94),
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
                    children: [
                      const SizedBox(height: 10),
                      Container(
                        width: 44,
                        height: 5,
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.18),
                          borderRadius: BorderRadius.circular(99),
                        ),
                      ),
                      const SizedBox(height: 14),

                      const Text(
                        'PDF actions',
                        style: TextStyle(
                          color: Colors.white70,
                          fontWeight: FontWeight.w900,
                          fontSize: 14,
                          letterSpacing: 0.6,
                        ),
                      ),
                      const SizedBox(height: 14),

                      _pdfActionTile(
                        icon: Icons.visibility_rounded,
                        title: 'Preview',
                        subtitle: 'Open print preview',
                        color: Colors.lightBlueAccent,
                        onTap: () async {
                          Navigator.pop(context);
                          await _pdfPreview(payment);
                        },
                      ),
                      _pdfActionTile(
                        icon: Icons.share_rounded,
                        title: 'Share',
                        subtitle: 'Send file to apps',
                        color: Colors.greenAccent,
                        onTap: () async {
                          Navigator.pop(context);
                          await _pdfShare(payment);
                        },
                      ),
                      _pdfActionTile(
                        icon: Icons.download_rounded,
                        title: 'Save',
                        subtitle: 'Save into app storage',
                        color: Colors.orangeAccent,
                        onTap: () async {
                          Navigator.pop(context);
                          await _pdfSave(payment);
                        },
                      ),

                      const SizedBox(height: 12),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _pdfActionTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required Future<void> Function() onTap,
  }) {
    return InkWell(
      onTap: () => onTap(),
      child: Container(
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 10),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.06),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withOpacity(0.08)),
        ),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: color.withOpacity(0.14),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: color.withOpacity(0.20)),
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
                    style: const TextStyle(
                      color: Colors.white70,
                      fontWeight: FontWeight.w900,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      color: Colors.white54,
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: Colors.white38),
          ],
        ),
      ),
    );
  }




  pw.Widget _th(String text, {pw.TextAlign align = pw.TextAlign.left}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.all(8),
      child: pw.Text(
        text,
        textAlign: align,
        style: pw.TextStyle(
          fontSize: 10,
          fontWeight: pw.FontWeight.bold,
        ),
      ),
    );
  }

  pw.Widget _td(String text, {pw.TextAlign align = pw.TextAlign.left}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.all(8),
      child: pw.Text(
        text,
        textAlign: align,
        style: const pw.TextStyle(
          fontSize: 10,
          color: PdfColors.grey800,
        ),
      ),
    );
  }

  pw.Widget _tdBold(String text,
      {PdfColor? color, pw.TextAlign align = pw.TextAlign.left}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.all(8),
      child: pw.Text(
        text,
        textAlign: align,
        style: pw.TextStyle(
          fontSize: 10,
          fontWeight: pw.FontWeight.bold,
          color: color ?? PdfColors.grey900,
        ),
      ),
    );
  }

  void _showGlassSnack(
      String text, {
        IconData icon = Icons.info_outline_rounded,
        Color accent = const Color(0xFF7AB8FF),
      }) {
    if (!mounted) return;

    final messenger = ScaffoldMessenger.of(context);

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

  void _showError(String message) {
    _showGlassSnack(
      message,
      icon: Icons.error_outline_rounded,
      accent: const Color(0xFFFF8A7A),
    );
  }

  Widget workerHeaderExact({
    required String email,
    required String avatarUrl,
    required bool onShift,
    required double total,
    required double worked,
    required double salary,
    required double lastPaid,
    required DateTime? lastPaidDate,
    required bool isSuspended,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 16, 14, 12),
      child: Align(
        alignment: Alignment.center,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 430),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
              child: Stack(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(24),
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          const Color(0xFF3A3C45).withOpacity(0.96),
                          const Color(0xFF2B2D35).withOpacity(0.93),
                          const Color(0xFF171A22).withOpacity(0.90),
                        ],
                      ),
                      border: Border.all(
                        color: Colors.white.withOpacity(0.10),
                        width: 1,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.42),
                          blurRadius: 28,
                          offset: const Offset(0, 18),
                        ),
                        BoxShadow(
                          color: Colors.white.withOpacity(0.04),
                          blurRadius: 14,
                          spreadRadius: -6,
                          offset: const Offset(0, -4),
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  email,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: isSuspended ? kSuspendedAccent : Colors.white70,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        Divider(height: 1, color: Colors.white.withOpacity(0.08)),
                        const SizedBox(height: 14),

                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Column(
                              children: [
                                Container(
                                  width: 96,
                                  height: 96,
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(20),
                                    border: Border.all(
                                      color: Colors.white.withOpacity(0.08),
                                      width: 1,
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withOpacity(0.22),
                                        blurRadius: 14,
                                        offset: const Offset(0, 8),
                                      ),
                                    ],
                                  ),
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(20),
                                    child: Stack(
                                      fit: StackFit.expand,
                                      children: [
                                        Image.network(
                                          avatarUrl,
                                          fit: BoxFit.cover,
                                        ),
                                        Container(
                                          color: Colors.black.withOpacity(0.18),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 10),
                                _HeaderShiftStatus(
                                  onShift: onShift,
                                  isSuspended: isSuspended,
                                ),
                              ],
                            ),

                            const SizedBox(width: 24),

                            Expanded(
                              child: Align(
                                alignment: Alignment.centerRight,
                                child: SizedBox(
                                  width: 270,
                                  child: Column(
                                    children: [
                                      _InfoCapsuleRow(
                                        icon: Icons.attach_money,
                                        label: 'Total',
                                        value: '\$${total.toStringAsFixed(2)}',
                                        color: Colors.greenAccent,
                                        dimmed: isSuspended,
                                      ),
                                      const SizedBox(height: 10),
                                      _InfoCapsuleRow(
                                        icon: Icons.timer,
                                        label: 'Worked',
                                        value: _fmtHmFromHours(worked),
                                        color: Colors.orange,
                                        dimmed: isSuspended,
                                      ),
                                      const SizedBox(height: 10),
                                      _InfoCapsuleRow(
                                        icon: Icons.wallet,
                                        label: 'Salary',
                                        value:
                                        '\$${salary % 1 == 0 ? salary.toStringAsFixed(0) : salary.toStringAsFixed(1)}/h',
                                        color: Colors.lightBlueAccent,
                                        dimmed: isSuspended,
                                      ),
                                      const SizedBox(height: 10),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 12),
                        Divider(height: 1, color: Colors.white.withOpacity(0.08)),
                        const SizedBox(height: 8),

                        FutureBuilder<Map<String, dynamic>?>(
                          future: _lastPaymentFuture,
                          builder: (context, snapshot) {
                            if (snapshot.connectionState == ConnectionState.waiting) {
                              return const Padding(
                                padding: EdgeInsets.only(top: 2),
                                child: Text(
                                  'Loading last payment...',
                                  style: TextStyle(color: Colors.white38, fontSize: 12),
                                ),
                              );
                            }

                            if (!snapshot.hasData || snapshot.data == null) {
                              return const SizedBox.shrink();
                            }

                            final p = snapshot.data!;
                            final amount = (p['total_amount'] ?? 0).toDouble();
                            final paidAt = DateTime.parse(p['created_at']).toLocal();

                            return Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.payments_rounded,
                                    size: 14,
                                    color: Colors.white.withOpacity(0.42),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    'Last payment',
                                    style: TextStyle(
                                      fontSize: 12.5,
                                      color: Colors.white.withOpacity(0.46),
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    '•',
                                    style: TextStyle(
                                      color: Colors.white.withOpacity(0.26),
                                      fontSize: 14,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    '\$${amount.toStringAsFixed(2)}',
                                    style: const TextStyle(
                                      fontSize: 12.5,
                                      color: Colors.white70,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    '•',
                                    style: TextStyle(
                                      color: Colors.white.withOpacity(0.26),
                                      fontSize: 14,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    DateFormat.yMMMd().format(paidAt),
                                    style: TextStyle(
                                      fontSize: 12.5,
                                      color: Colors.white.withOpacity(0.54),
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ],
                              ),
                            );
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
                            Colors.white.withOpacity(0.28),
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
        ),
      ),
    );
  }



  Widget _infoRow(
      IconData icon,
      String text,
      Color color, {
        bool alignEnd = false,
      }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 8),
        Text(
          text,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: color,
          ),
          textAlign: alignEnd ? TextAlign.right : TextAlign.left,
        ),
      ],
    );
  }

  Widget _liveDot() {
    return Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(
        color: Colors.green,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: Colors.green.withValues(alpha: 0.6),
            blurRadius: 6,
            spreadRadius: 2,
          ),
        ],
      ),
    );
  }

  void _showWorkerSummarySheet() {
    final worker = workerFull ?? widget.worker;

    final allHistory = history;
    final active = allHistory.where((r) => r['end_time'] == null).toList();
    final unpaid =
    allHistory.where((r) => r['end_time'] != null && r['paid_at'] == null).toList();
    final paid = allHistory.where((r) => r['paid_at'] != null).toList();

    final totalWorkedAll = allHistory.fold<double>(
      0,
          (s, r) => s + ((r['total_hours'] ?? 0) as num).toDouble(),
    );

    final totalEarnedAll = allHistory.fold<double>(
      0,
          (s, r) => s + ((r['total_payment'] ?? 0) as num).toDouble(),
    );

    final unpaidWorked = unpaid.fold<double>(
      0,
          (s, r) => s + ((r['total_hours'] ?? 0) as num).toDouble(),
    );

    final unpaidAmount = unpaid.fold<double>(
      0,
          (s, r) => s + ((r['total_payment'] ?? 0) as num).toDouble(),
    );

    final paidWorked = paid.fold<double>(
      0,
          (s, r) => s + ((r['total_hours'] ?? 0) as num).toDouble(),
    );

    final paidAmount = paid.fold<double>(
      0,
          (s, r) => s + ((r['total_payment'] ?? 0) as num).toDouble(),
    );

    final shiftCount = allHistory.length;
    final activeCount = active.length;
    final unpaidCount = unpaid.length;
    final paidCount = paid.length;

    final salary = ((worker['hourly_rate'] ?? 0) as num).toDouble();
    final name = (worker['name'] ?? '—').toString();
    final email = (worker['email'] ?? widget.worker['email'] ?? '—').toString();
    final avatarUrl = (worker['avatar_url'] ??
        'https://ui-avatars.com/api/?name=${Uri.encodeComponent(name)}')
        .toString();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withOpacity(0.55),
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 18, 12, 12),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(28),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
                child: Container(
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.of(context).size.height * 0.88,
                  ),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        const Color(0xFF343741).withOpacity(0.97),
                        const Color(0xFF2A2D35).withOpacity(0.96),
                        const Color(0xFF171A22).withOpacity(0.97),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(28),
                    border: Border.all(color: Colors.white.withOpacity(0.10)),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.45),
                        blurRadius: 32,
                        offset: const Offset(0, 18),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [

                      // ===== HEADER =====
                      const SizedBox(height: 10),

                      Container(
                        width: 46,
                        height: 5,
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.18),
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),

                      const SizedBox(height: 14),

                      Flexible(
                        child: ScrollConfiguration(
                          behavior: const _NoScrollbarNoGlow(),
                          child: SingleChildScrollView(
                            physics: const BouncingScrollPhysics(),
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 18),
                            child: Column(
                              children: [
                                // ===== PROFILE CARD =====
                            Container(
                              padding: const EdgeInsets.fromLTRB(14, 10, 14, 18),
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
                              borderRadius: BorderRadius.circular(24),
                              border: Border.all(color: Colors.white.withOpacity(0.08)),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.34),
                                  blurRadius: 26,
                                  offset: const Offset(0, 16),
                                ),
                                BoxShadow(
                                  color: Colors.white.withOpacity(0.025),
                                  blurRadius: 12,
                                  spreadRadius: -4,
                                  offset: const Offset(0, -3),
                                ),
                              ],
                            ),
                              child: Column(
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Row(
                                          children: [
                                            Icon(
                                              Icons.insights_rounded,
                                              size: 18,
                                              color: Colors.white.withOpacity(0.72),
                                            ),
                                            const SizedBox(width: 8),
                                            Text(
                                              'Worker statistics',
                                              style: TextStyle(
                                                color: Colors.white.withOpacity(0.84),
                                                fontSize: 15,
                                                fontWeight: FontWeight.w800,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      IconButton(
                                        onPressed: () => Navigator.pop(sheetContext),
                                        splashRadius: 18,
                                        padding: EdgeInsets.zero,
                                        constraints: const BoxConstraints(
                                          minWidth: 28,
                                          minHeight: 28,
                                        ),
                                        icon: Icon(
                                          Icons.close_rounded,
                                          color: Colors.white.withOpacity(0.62),
                                          size: 21,
                                        ),
                                      ),
                                    ],
                                  ),

                                  const SizedBox(height: 8),

                                  Divider(
                                    height: 1,
                                    color: Colors.white.withOpacity(0.10),
                                  ),

                                  const SizedBox(height: 10),

                                  Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Column(
                                        children: [
                                          Stack(
                                            clipBehavior: Clip.none,
                                            children: [
                                              Container(
                                                width: 80,
                                                height: 100,
                                                decoration: BoxDecoration(
                                                  borderRadius: BorderRadius.circular(22),
                                                  border: Border.all(
                                                    color: Colors.white.withOpacity(0.10),
                                                  ),
                                                  boxShadow: [
                                                    BoxShadow(
                                                      color: Colors.black.withOpacity(0.28),
                                                      blurRadius: 18,
                                                      offset: const Offset(0, 10),
                                                    ),
                                                  ],
                                                ),
                                                child: ClipRRect(
                                                  borderRadius: BorderRadius.circular(22),
                                                  child: Stack(
                                                    fit: StackFit.expand,
                                                    children: [
                                                      Image.network(
                                                        avatarUrl,
                                                        fit: BoxFit.cover,
                                                      ),
                                                      Container(
                                                        color: Colors.black.withOpacity(0.10),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              ),
                                              Positioned(
                                                right: -2,
                                                bottom: -2,
                                                child: _WorkerLiveDot(
                                                  isOnShift: activeCount > 0,
                                                  isSuspended: _isSuspended,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),

                                      const SizedBox(width: 14),

                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            _summaryPlainRow(
                                              icon: Icons.person_rounded,
                                              value: name,
                                              iconColor: Colors.white,
                                              textColor: Colors.white,
                                            ),

                                            const SizedBox(height: 10),

                                            Divider(
                                              height: 1,
                                              color: Colors.white.withOpacity(0.08),
                                            ),

                                            const SizedBox(height: 10),

                                            _summaryPlainRow(
                                              icon: Icons.email_rounded,
                                              value: email,
                                              iconColor: Colors.amber,
                                              textColor: Colors.white70,
                                            ),

                                            const SizedBox(height: 10),

                                            Divider(
                                              height: 1,
                                              color: Colors.white.withOpacity(0.08),
                                            ),

                                            const SizedBox(height: 10),

                                            _summaryLabeledPlainRow(
                                              icon: Icons.wallet_rounded,
                                              label: 'Salary',
                                              value:
                                              '\$${salary % 1 == 0 ? salary.toStringAsFixed(0) : salary.toStringAsFixed(1)}/h',
                                              accent: Colors.lightBlueAccent,
                                            ),

                                            const SizedBox(height: 10),

                                            Divider(
                                              height: 1,
                                              color: Colors.white.withOpacity(0.08),
                                            ),

                                            const SizedBox(height: 25),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                          ),

                                const SizedBox(height: 14),

                                Row(
                                  children: [
                                    Expanded(
                                      child: _summaryStatCard(
                                        title: 'Unpaid total',
                                        value: '\$${unpaidAmount.toStringAsFixed(2)}',
                                        icon: Icons.attach_money_rounded,
                                        color: Colors.greenAccent,
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: _summaryStatCard(
                                        title: 'Unpaid worked',
                                        value: _fmtHmFromHours(unpaidWorked),
                                        icon: Icons.timer_rounded,
                                        color: Colors.orangeAccent,
                                      ),
                                    ),
                                  ],
                                ),

                                const SizedBox(height: 10),

                                Row(
                                  children: [
                                    Expanded(
                                      child: _summaryStatCard(
                                        title: 'All earned',
                                        value: '\$${totalEarnedAll.toStringAsFixed(2)}',
                                        icon: Icons.bolt_rounded,
                                        color: Colors.greenAccent,
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: _summaryStatCard(
                                        title: 'All worked',
                                        value: _fmtHmFromHours(totalWorkedAll),
                                        icon: Icons.av_timer_rounded,
                                        color: Colors.amber,
                                      ),
                                    ),
                                  ],
                                ),

                                const SizedBox(height: 12),

                                _summaryBlock(
                                  title: 'COUNTS',
                                  child: Column(
                                    children: [
                                      _summaryLine(
                                        icon: Icons.format_list_numbered_rounded,
                                        label: 'All shifts',
                                        value: '$shiftCount',
                                      ),
                                      _summaryLine(
                                        icon: Icons.play_circle_outline_rounded,
                                        label: 'Active shifts',
                                        value: '$activeCount',
                                      ),
                                      _summaryLine(
                                        icon: Icons.schedule_rounded,
                                        label: 'Unpaid shifts',
                                        value: '$unpaidCount',
                                      ),
                                      _summaryLine(
                                        icon: Icons.check_circle_outline_rounded,
                                        label: 'Paid shifts',
                                        value: '$paidCount',
                                      ),
                                    ],
                                  ),
                                ),

                                const SizedBox(height: 12),

                                _summaryBlock(
                                  title: 'AMOUNTS & HOURS',
                                  child: Column(
                                    children: [
                                      _summaryLine(
                                        icon: Icons.payments_outlined,
                                        label: 'Unpaid amount',
                                        value: '\$${unpaidAmount.toStringAsFixed(2)}',
                                      ),
                                      _summaryLine(
                                        icon: Icons.account_balance_wallet_outlined,
                                        label: 'Paid amount',
                                        value: '\$${paidAmount.toStringAsFixed(2)}',
                                      ),
                                      _summaryLine(
                                        icon: Icons.bolt_rounded,
                                        label: 'Total earned',
                                        value: '\$${totalEarnedAll.toStringAsFixed(2)}',
                                      ),
                                      _summaryLine(
                                        icon: Icons.timer_outlined,
                                        label: 'Unpaid worked',
                                        value: _fmtHmFromHours(unpaidWorked),
                                      ),
                                      _summaryLine(
                                        icon: Icons.av_timer_rounded,
                                        label: 'Paid worked',
                                        value: _fmtHmFromHours(paidWorked),
                                      ),
                                      _summaryLine(
                                        icon: Icons.hourglass_bottom_rounded,
                                        label: 'All worked',
                                        value: _fmtHmFromHours(totalWorkedAll),
                                      ),
                                    ],
                                  ),
                                ),

                                const SizedBox(height: 12),

                                FutureBuilder<Map<String, dynamic>?>(
                                  future: _lastPaymentFuture,
                                  builder: (context, snapshot) {
                                    final p = snapshot.data;

                                    return _summaryBlock(
                                      title: 'LAST PAYMENT',
                                      child: p == null
                                          ? _SectionEmptyState(
                                        icon: Icons.payments_outlined,
                                        title: 'No payments yet',
                                        subtitle: 'Statements and exports will appear here.',
                                        gradientColors: [
                                          kHistoryCardHeadBg.withOpacity(0.97),
                                          kHistoryPanelBg.withOpacity(0.96),
                                        ],
                                      )
                                          : Column(
                                        children: [
                                          _summaryLine(
                                            icon: Icons.attach_money_rounded,
                                            label: 'Amount',
                                            value: '\$${((p['total_amount'] ?? 0) as num).toDouble().toStringAsFixed(2)}',
                                          ),
                                          _summaryLine(
                                            icon: Icons.event_rounded,
                                            label: 'Date',
                                            value: DateFormat.yMMMd().format(
                                              DateTime.parse(p['created_at']).toLocal(),
                                            ),
                                          ),
                                        ],
                                      ),
                                    );
                                  },
                                ),

                                const SizedBox(height: 16),

                                SizedBox(
                                  width: double.infinity,
                                  child: ElevatedButton(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.white.withOpacity(0.08),
                                      foregroundColor: Colors.white70,
                                      elevation: 0,
                                      padding: const EdgeInsets.symmetric(vertical: 15),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(16),
                                      ),
                                    ),
                                    onPressed: () => Navigator.pop(sheetContext),
                                    child: const Text(
                                      'CLOSE',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w900,
                                        letterSpacing: 0.6,
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
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _summaryMiniChip({
    required IconData icon,
    required String text,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withOpacity(0.18)),
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
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  Widget _summarySlimLabeledRow({
    required IconData icon,
    required String label,
    required String value,
    required Color accent,
  }) {
    return Container(
      height: 46,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.white.withOpacity(0.06),
            Colors.white.withOpacity(0.035),
            Colors.black.withOpacity(0.10),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.22),
            blurRadius: 12,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          Icon(
            icon,
            size: 20,
            color: accent,
          ),
          const SizedBox(width: 12),
          Text(
            label,
            style: TextStyle(
              color: Colors.white.withOpacity(0.72),
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
          const Spacer(),
          Text(
            value,
            style: TextStyle(
              color: accent,
              fontSize: 13.5,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }

  Widget _summarySlimValueRow({
    required IconData icon,
    required String value,
    required Color accent,
  }) {
    return Container(
      height: 46,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.white.withOpacity(0.06),
            Colors.white.withOpacity(0.035),
            Colors.black.withOpacity(0.10),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.22),
            blurRadius: 12,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          Icon(
            icon,
            size: 20,
            color: accent,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: accent,
                fontSize: 13.5,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _summaryStatCard({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: Stack(
        children: [
          Container(
            width: double.infinity, // ← ВОТ СЮДА
            constraints: const BoxConstraints(minHeight: 118), // ← И ВОТ СЮДА
            padding: const EdgeInsets.all(14),
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
              border: Border.all(
                color: Colors.white.withOpacity(0.08),
                width: 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.34),
                  blurRadius: 24,
                  offset: const Offset(0, 14),
                ),
                BoxShadow(
                  color: Colors.white.withOpacity(0.025),
                  blurRadius: 12,
                  spreadRadius: -4,
                  offset: const Offset(0, -3),
                ),
              ],
            ),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Container(
                    width: 38,
                    height: 38,
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
                      borderRadius: BorderRadius.circular(13),
                      border: Border.all(
                        color: Colors.white.withOpacity(0.08),
                        width: 1,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.22),
                          blurRadius: 10,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: Icon(
                      icon,
                      size: 18,
                      color: color,
                    ),
                  ),

                  const SizedBox(height: 12),

                  Text(
                    title,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.58),
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),

                  const SizedBox(height: 6),

                  Text(
                    value,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: color,
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.2,
                    ),
                  ),
                ],
              ),
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
                    Colors.white.withOpacity(0.22),
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

  Widget _summaryBlock({
    required String title,
    required Widget child,
  }) {
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
          BoxShadow(
            color: Colors.white.withOpacity(0.025),
            blurRadius: 12,
            spreadRadius: -4,
            offset: const Offset(0, -3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: Colors.white70,
              fontWeight: FontWeight.w900,
              fontSize: 14,
              letterSpacing: 0.2,
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

  Widget _summaryLine({
    required IconData icon,
    required String label,
    required String value,
  }) {
    final rowColor = Colors.white.withOpacity(0.56);

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
            const SizedBox(width: 10),
            Text(
              value,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ================= UI =================

  // ================= PAYMENTS HEADER (same style as HISTORY) =================

  Widget _paymentsRotatingTip({
    required List<Map<String, dynamic>> payments,
    required double paymentsTotal,
  }) {
    DateTime? lastPaid;
    if (payments.isNotEmpty) {
      lastPaid = DateTime.parse(payments.first['created_at']).toLocal();
    }

    final avg = payments.isEmpty ? 0.0 : (paymentsTotal / payments.length);

    final totalShifts = payments.fold<int>(0, (s, p) {
      final items = List<Map<String, dynamic>>.from(p['payment_items'] ?? []);
      return s + items.length;
    });

    final tips = <({String text, Color color, IconData icon})>[
      (
      text: lastPaid != null ? _fmtMonthDay(lastPaid) : '—',
      color: Colors.lightBlueAccent,
      icon: Icons.event,
      ),
      (
      text: '\$${avg.toStringAsFixed(0)} avg',
      color: Colors.amber,
      icon: Icons.insights_rounded,
      ),
      (
      text: '$totalShifts shifts',
      color: Colors.orangeAccent,
      icon: Icons.work_history_rounded,
      ),
    ];


    return ValueListenableBuilder<int>(
      valueListenable: _paymentsTipIndex,
      builder: (_, idx, __) {
        final tip = tips[idx % tips.length];

        return SizedBox(
          width: 92,
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            transitionBuilder: (child, anim) {
              final fade = CurvedAnimation(parent: anim, curve: Curves.easeOut);
              return FadeTransition(opacity: fade, child: child);
            },
            child: Align(
              key: ValueKey(tip.text),
              alignment: Alignment.centerLeft,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(tip.icon, size: 14, color: tip.color),
                  const SizedBox(width: 6),
                  Text(
                    tip.text,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w900,
                      color: tip.color,
                      letterSpacing: 0.6,
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

  Widget _historyPaymentsSwitcherHeader() {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 320),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, animation) {
        final offsetAnimation = Tween<Offset>(
          begin: _showPaymentsPanel
              ? const Offset(0.18, 0)
              : const Offset(-0.18, 0),
          end: Offset.zero,
        ).animate(animation);

        return FadeTransition(
          opacity: animation,
          child: SlideTransition(
            position: offsetAnimation,
            child: child,
          ),
        );
      },
      child: _showPaymentsPanel
          ? Container(
        key: const ValueKey('payments_header'),
        width: double.infinity,
        decoration: BoxDecoration(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              const Color(0xFF3A3B42),
              const Color(0xFF2F3138),
              const Color(0xFF26282F),
            ],
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: double.infinity,
              padding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                children: [
                  const SizedBox(width: 58),
                  const Spacer(),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: const [
                      Text(
                        'PAYMENTS',
                        style: TextStyle(
                          color: kTextPrimary,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.2,
                          fontSize: 14,
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'Statements & exports',
                        style: TextStyle(
                          color: kTextSecondary,
                          fontWeight: FontWeight.w700,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                  const Spacer(),
                  const SizedBox(width: 58),
                ],
              ),
            ),

            Container(height: 1, color: kDividerSoft),

            _buildAttachedSectionFilterField(
              isPayments: true,
            ),
          ],
        ),
      )
          : Container(
        key: const ValueKey('history_header'),
        width: double.infinity,
        decoration: BoxDecoration(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              const Color(0xFF3A3B42),
              const Color(0xFF2F3138),
              const Color(0xFF26282F),
            ],
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: double.infinity,
              padding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                children: [
                  const SizedBox(width: 58),
                  const Spacer(),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: const [
                      Text(
                        'HISTORY',
                        style: TextStyle(
                          color: kTextPrimary,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.2,
                          fontSize: 14,
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'Activity & shifts',
                        style: TextStyle(
                          color: kTextSecondary,
                          fontWeight: FontWeight.w700,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                  const Spacer(),
                  const SizedBox(width: 58),
                ],
              ),
            ),

            Container(height: 1, color: kDividerSoft),

            _buildAttachedSectionFilterField(
              isPayments: false,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAttachedSectionFilterField({
    required bool isPayments,
  }) {
    final range = isPayments ? _paymentsRange : _historyRange;
    final modeText = isPayments
        ? _paymentsFilterFieldLabel()
        : _historyFilterFieldLabel();

    final hasActiveFilter = range != null || modeText != 'All';

    return Container(
      width: double.infinity,
      color: const Color(0xFF2E3139),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
              Tooltip(
                message: isPayments ? 'Back to history' : 'Open payments',
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: () {
                      setState(() {
                        _showPaymentsPanel = !isPayments;
                      });
                    },
                    child: Container(
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        color: const Color(0xFF2B2F36),
                        border: Border.all(
                          color: Colors.white.withOpacity(0.16),
                          width: 1.1,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.16),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Center(
                        child: Icon(
                          isPayments
                              ? Icons.history_rounded
                              : Icons.payments_rounded,
                          size: 21,
                          color: Colors.white.withOpacity(0.78),
                        ),
                      ),
                    ),
                  ),
                ),
              ),

              if (!isPayments) const SizedBox(width: 8),

              if (!isPayments)
                Tooltip(
                  message: 'Calculator',
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onTap: () => showQuickCalculatorSheet(context: context),
                      child: Container(
                        width: 46,
                        height: 46,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          color: const Color(0xFF2B2F36),
                          border: Border.all(
                            color: Colors.white.withOpacity(0.16),
                            width: 1.1,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.16),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Center(
                          child: Icon(
                            Icons.calculate_rounded,
                            size: 21,
                            color: Colors.white.withOpacity(0.78),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),

              const SizedBox(width: 8),

              Tooltip(
                message: hasActiveFilter
                    ? 'Search / filter active\nLong press to clear'
                    : 'Search period',
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: () => _openRangeCalendar(isPayments: isPayments),
                    onLongPress: hasActiveFilter
                        ? () => _clearSectionFilter(isPayments: isPayments)
                        : null,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        color: hasActiveFilter
                            ? const Color(0xFF2F333A)
                            : const Color(0xFF2B2F36),
                        border: Border.all(
                          color: hasActiveFilter
                              ? Colors.white.withOpacity(0.22)
                              : Colors.white.withOpacity(0.16),
                          width: 1.1,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.16),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          Center(
                            child: Icon(
                              Icons.search_rounded,
                              size: 21,
                              color: hasActiveFilter
                                  ? Colors.white.withOpacity(0.92)
                                  : Colors.white.withOpacity(0.78),
                            ),
                          ),
                          if (hasActiveFilter)
                            Positioned(
                              top: 7,
                              right: 7,
                              child: Container(
                                width: 8,
                                height: 8,
                                decoration: const BoxDecoration(
                                  color: Color(0xFF59F0A7),
                                  shape: BoxShape.circle,
                                ),
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
    );
  }

  Widget _historyPaymentsAnimatedBody({
    required Widget historyBody,
    required Widget paymentsBody,
  }) {
    return GestureDetector(
      onHorizontalDragEnd: (details) {
        final v = details.primaryVelocity ?? 0;

        if (v < -180 && !_showPaymentsPanel) {
          setState(() {
            _showPaymentsPanel = true;
          });
        } else if (v > 180 && _showPaymentsPanel) {
          setState(() {
            _showPaymentsPanel = false;
          });
        }
      },
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 360),
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
          final isPayments =
              child.key == const ValueKey('payments_body');

          final beginOffset = isPayments
              ? const Offset(1.0, 0)
              : const Offset(-1.0, 0);

          return ClipRect(
            child: FadeTransition(
              opacity: animation,
              child: SlideTransition(
                position: Tween<Offset>(
                  begin: beginOffset,
                  end: Offset.zero,
                ).animate(animation),
                child: child,
              ),
            ),
          );
        },
        child: _showPaymentsPanel
            ? KeyedSubtree(
          key: const ValueKey('payments_body'),
          child: paymentsBody,
        )
            : KeyedSubtree(
          key: const ValueKey('history_body'),
          child: historyBody,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // ================= UNPAID LOGIC (ЕДИНСТВЕННЫЙ ИСТОЧНИК ПРАВДЫ) =================

    final unpaid = history.where((r) {
      return r['end_time'] != null && r['paid_at'] == null;
    }).toList();

    final unpaidAmount = unpaid.fold<double>(
      0,
          (s, r) => s + ((r['total_payment'] ?? 0) as num).toDouble(),
    );

    final unpaidHours = unpaid.fold<double>(
      0,
          (s, r) => s + ((r['total_hours'] ?? 0) as num).toDouble(),
    );

    final filteredHistory = _applyHistoryFilters(history);
    final bool autoExpandFromSearch =
        _historyRange != null || _historyFilter != WorkerHistoryFilter.all;

    final active = filteredHistory.where((r) => r['end_time'] == null).toList();

    final pending = filteredHistory.where((r) {
      return r['end_time'] != null && r['paid_at'] == null;
    }).toList();

    final paidAll = filteredHistory.where((r) => r['paid_at'] != null).toList();

    final filteredUnpaidAmount = pending.fold<double>(
      0,
          (s, r) => s + ((r['total_payment'] ?? 0) as num).toDouble(),
    );

    final filteredUnpaidHours = pending.fold<double>(
      0,
          (s, r) => s + ((r['total_hours'] ?? 0) as num).toDouble(),
    );

    final visiblePaid = showOlderPaid
        ? paidAll
        : paidAll.take(2).toList();

    final hiddenPaidCount = paidAll.length > 2 ? (paidAll.length - 2) : 0;

    final historyCount = active.length + pending.length;
    final historyTotal = filteredUnpaidAmount;
    final historyWorked = filteredUnpaidHours;
    final bool onShift = active.isNotEmpty;

    final bool isSuspended = _isSuspended;
    final String appBarTitle = isSuspended ? 'Suspended details' : 'Worker details';
    final Color appBarTitleColor = isSuspended ? kSuspendedAccent : Colors.white70;

    final bool paymentsAutoExpandFromSearch =
        _paymentsRange != null || _paymentsFilter != WorkerPaymentsFilter.all;

    final historyPanel = _sectionCentered(
      _SectionPanel(
        header: _historyPaymentsSwitcherHeader(),
        child: _historyPaymentsAnimatedBody(
          historyBody: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(0, 10, 0, 12),
                child: YearGroupedHistorySection(
                  key: _historyKey,
                  active: _groupHistoryCardsByDay(active),
                  pending: _groupHistoryCardsByDay(pending),
                  autoOpenVersion: _historyAutoOpenVersion,
                  paid: _groupHistoryCardsByDay(paidAll),
                  selectedFilter: _historyFilter,
                  autoExpandFromSearch: autoExpandFromSearch,
                  showAllPaid: showOlderPaid,
                  accentColor: _isSuspended ? kSuspendedAccent : Colors.orangeAccent,
                  buildCard: (row) => _shiftCard(row),
                  onYearsToggleData: (showAll, hiddenCount) {
                    setState(() {
                      _historyShowAllYears = showAll;
                      _historyHiddenYearsCount = hiddenCount;
                    });
                  },
                ),
              ),
            ],
          ),
          paymentsBody: Column(
            children: [
              FutureBuilder<List<Map<String, dynamic>>>(
                future: _paymentsFuture,
                builder: (context, snapshot) {
                  if (!snapshot.hasData) {
                    return const Padding(
                      padding: EdgeInsets.all(16),
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }

                  final payments = _applyPaymentsFilters(snapshot.data!);
                  if (paymentsAutoExpandFromSearch &&
                      payments.isNotEmpty &&
                      _lastPaymentsAutoOpenHandled != _paymentsAutoOpenVersion) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (!mounted) return;
                      setState(() {
                        _expandedPaymentId = payments.first['id'];
                        _lastPaymentsAutoOpenHandled = _paymentsAutoOpenVersion;
                      });
                    });
                  }
                  final paymentsCount = payments.length;

                  final paymentsTotal = payments.fold<double>(
                    0,
                        (s, p) => s + ((p['total_amount'] ?? 0) as num).toDouble(),
                  );

                  if (payments.isEmpty) {
                    return _SectionEmptyState(
                      icon: Icons.payments_outlined,
                      title: 'No payments yet',
                      subtitle: 'Statements and exports will appear here.',
                      gradientColors: [
                        kHistoryCardHeadBg.withOpacity(0.97),
                        kHistoryPanelBg.withOpacity(0.96),
                      ],
                    );
                  }

                  return Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(0, 2, 0, 12),
                        child: YearGroupedPaymentsSection(
                          payments: payments,
                          accentColor:
                          _isSuspended ? kPaymentsBurgundy : Colors.lightBlueAccent,
                          buildTile: (p) => _PaymentTile(
                            payment: p,
                            accentColor:
                            _isSuspended ? kPaymentsBurgundy : Colors.lightBlueAccent,
                            expanded: _expandedPaymentId == p['id'],
                            onToggle: () {
                              setState(() {
                                _expandedPaymentId =
                                (_expandedPaymentId == p['id']) ? null : p['id'];
                              });
                            },
                            onPdf: () => _showPdfActions(p),
                          ),
                        ),
                      ),
                      Container(
                        height: 1,
                        color: kDividerSoft,
                      ),
                      _PaymentsFooterBar(
                        paymentsCount: paymentsCount,
                        totalText: '\$${paymentsTotal.toStringAsFixed(0)}',
                        tip: _paymentsRotatingTip(
                          payments: payments,
                          paymentsTotal: paymentsTotal,
                        ),
                        canToggle: false,
                        showAll: false,
                        hiddenCount: 0,
                        onToggle: () {},
                      ),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
        footer: !_showPaymentsPanel
            ? _HistoryFooterBar(
          shifts: historyCount,
          workedText: _fmtHmFromHours(historyWorked),
          amountText: '\$${historyTotal.toStringAsFixed(0)}',
          canToggle: _historyHiddenYearsCount > 0 || _historyShowAllYears,
          showAll: _historyShowAllYears,
          hiddenCount: _historyHiddenYearsCount,
          onToggle: () {
            _historyKey.currentState?.toggleShowAllYears();
          },
        )
            : null,
      ),
    );

    // ================= UI =================

    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF0B0D12),
        elevation: 0,

        // ✅ как в Admin panel
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

              // ===== PANEL =====
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
                      // ⬅️ BACK
                      IconButton(
                        icon: const Icon(Icons.arrow_back_ios_new_rounded),
                        onPressed: () => Navigator.pop(context, true),
                      ),

                      const SizedBox(width: 6),

                      // TITLE
                      Expanded(
                        child: Text(
                          appBarTitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 18,
                            color: appBarTitleColor,
                          ),
                        ),
                      ),
// ⋮ МЕНЮ (Payments / Force stop / About)
                      PopupMenuButton<String>(
                        tooltip: 'Menu',
                        icon: const Icon(Icons.more_vert_rounded),
                        color: const Color(0xFF1F2025),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        onSelected: (v) async {
                          if (v == 'statistics') {
                            _showWorkerSummarySheet();
                          } else if (v == 'edit') {
                            await _editWorker();
                          } else if (v == 'delete_worker') {
                            await _confirmDeleteWorker();
                          } else if (v == 'payments') {
                            if (!onShift && !_isSuspended) {
                              await _payWorker();
                            }
                          } else if (v == 'force_stop') {
                            if (onShift) await _confirmForceEndShift();
                          }
                        },
                        itemBuilder: (_) {
                          final disabledColor = Colors.white.withOpacity(0.28);
                          final enabledColor = Colors.white.withOpacity(0.85);

                          return [
                            PopupMenuItem<String>(
                              value: 'statistics',
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.insights_rounded,
                                    size: 18,
                                    color: enabledColor,
                                  ),
                                  const SizedBox(width: 10),
                                  Text(
                                    'Statistics',
                                    style: TextStyle(
                                      color: enabledColor,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const PopupMenuDivider(),
                            PopupMenuItem<String>(
                              value: 'edit',
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.edit_rounded,
                                    size: 18,
                                    color: enabledColor,
                                  ),
                                  const SizedBox(width: 10),
                                  Text(
                                    'Edit worker',
                                    style: TextStyle(
                                      color: enabledColor,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              ),
                            ),

                            PopupMenuItem<String>(
                              value: 'delete_worker',
                              enabled: _canDeleteWorker,
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.delete_outline_rounded,
                                    size: 18,
                                    color: _canDeleteWorker ? kSuspendedAccent : disabledColor,
                                  ),
                                  const SizedBox(width: 10),
                                  Text(
                                    'Delete worker',
                                    style: TextStyle(
                                      color: _canDeleteWorker ? kSuspendedAccent : disabledColor,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              ),
                            ),

                            const PopupMenuDivider(),

                            PopupMenuItem<String>(
                              value: 'payments',
                              enabled: !onShift && !_isSuspended,
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.payments_rounded,
                                    size: 18,
                                    color: (!onShift && !_isSuspended) ? enabledColor : disabledColor,
                                  ),
                                  const SizedBox(width: 10),
                                  Text(
                                    'Payments',
                                    style: TextStyle(
                                      color: (!onShift && !_isSuspended) ? enabledColor : disabledColor,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              ),
                            ),

                            PopupMenuItem<String>(
                              value: 'force_stop',
                              enabled: onShift,
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.warning_rounded,
                                    size: 18,
                                    color: onShift ? Colors.redAccent : disabledColor,
                                  ),
                                  const SizedBox(width: 10),
                                  Text(
                                    'Force stop',
                                    style: TextStyle(
                                      color: onShift ? Colors.redAccent : disabledColor,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ];

                        },
                      ),
                    ],
                  ),
                ),
              ),

              // ===== TOP HIGHLIGHT =====
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
        children: [
          const _WorkerDetailsBackgroundBase(),

          loading
              ? const Center(child: CircularProgressIndicator())
              : ListView(
            padding: const EdgeInsets.only(bottom: 24),
            children: [

              // ================= HEADER =================
              workerHeaderExact(
                email: (workerFull?['email'] ?? widget.worker['email'] ?? '').toString(),
                avatarUrl: workerFull?['avatar_url']
                    ?? 'https://ui-avatars.com/api/?name=User',
                onShift: onShift,
                isSuspended: _isSuspended,
                total: unpaidAmount,
                worked: unpaidHours,
                salary: (workerFull?['hourly_rate'] ?? 0).toDouble(),
                lastPaid: 0,
                lastPaidDate: null,
              ),

              historyPanel,

              const SizedBox(height: 12),

            ],
          ),
        ],
      ),
    );
  }
}

// class _PaymentTile extends StatelessWidget {
//   final Map<String, dynamic> payment;
//   final bool expanded;
//   final VoidCallback onToggle;
//
//   const _PaymentTile({
//     required this.payment,
//     required this.expanded,
//     required this.onToggle,
//   });
//
//   @override
//   Widget build(BuildContext context) {
//     final items = List<Map<String, dynamic>>.from(
//       payment['payment_items'] ?? [],
//     );
//
//     DateTime? from;
//     DateTime? to;
//
//     for (final it in items) {
//       final wl = it['work_logs'];
//       if (wl == null) continue;
//
//       final start = DateTime.parse(wl['start_time']).toLocal();
//       from = from == null || start.isBefore(from!) ? start : from;
//       to   = to   == null || start.isAfter(to!)   ? start : to;
//     }
//
//     final rangeText = (from != null && to != null)
//         ? '${DateFormat.yMMMd().format(from)} → ${DateFormat.yMMMd().format(to)}'
//         : '—';
//
//     return Column(
//       children: [
//         InkWell(
//           onTap: onToggle,
//           child: Container(
//             padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
//             decoration: BoxDecoration(
//               border: Border(
//                 bottom: BorderSide(color: Colors.white.withOpacity(0.06)),
//               ),
//             ),
//             child: Row(
//               children: [
//                 Container(
//                   width: 40,
//                   height: 40,
//                   decoration: BoxDecoration(
//                     color: Colors.green.withOpacity(0.18),
//                     borderRadius: BorderRadius.circular(10),
//                   ),
//                   child: const Icon(
//                     Icons.payments_rounded,
//                     color: Colors.greenAccent,
//                     size: 20,
//                   ),
//                 ),
//                 const SizedBox(width: 14),
//                 Expanded(
//                   child: Column(
//                     crossAxisAlignment: CrossAxisAlignment.start,
//                     children: [
//                       Text(
//                         '\$${(payment['total_amount'] as num).toStringAsFixed(2)}',
//                         style: const TextStyle(
//                           fontSize: 18,
//                           fontWeight: FontWeight.w900,
//                           color: Colors.greenAccent,
//                         ),
//                       ),
//                       const SizedBox(height: 4),
//                       Text(
//                         '$rangeText · ${items.length} shifts',
//                         style: const TextStyle(
//                           fontSize: 12,
//                           color: Colors.white60,
//                         ),
//                       ),
//                     ],
//                   ),
//                 ),
//                 Icon(
//                   expanded ? Icons.expand_less : Icons.expand_more,
//                   color: Colors.white54,
//                 ),
//               ],
//             ),
//           ),
//         ),
//
//         AnimatedCrossFade(
//           duration: const Duration(milliseconds: 250),
//           crossFadeState: expanded
//               ? CrossFadeState.showFirst
//               : CrossFadeState.showSecond,
//           firstChild: _PaymentDetails(items),
//           secondChild: const SizedBox.shrink(),
//         ),
//       ],
//     );
//   }
// }
//
// class _PaymentDetails extends StatelessWidget {
//   final List<Map<String, dynamic>> items;
//
//   const _PaymentDetails(this.items);
//
//   @override
//   Widget build(BuildContext context) {
//     return Padding(
//       padding: const EdgeInsets.fromLTRB(64, 6, 16, 12),
//       child: Column(
//         children: items.map((it) {
//           final wl = it['work_logs'];
//           if (wl == null) return const SizedBox();
//
//           final start = DateTime.parse(wl['start_time']).toLocal();
//           final end = DateTime.parse(wl['end_time']).toLocal();
//           final amount = (wl['total_payment'] ?? 0).toDouble();
//
//           return Padding(
//             padding: const EdgeInsets.symmetric(vertical: 6),
//             child: Row(
//               children: [
//                 Expanded(
//                   child: Text(
//                     '${DateFormat.yMMMd().format(start)} '
//                         '${DateFormat.Hm().format(start)} → ${DateFormat.Hm().format(end)}',
//                     style: const TextStyle(
//                       fontSize: 12,
//                       color: Colors.white54,
//                     ),
//                   ),
//                 ),
//                 Text(
//                   '\$${amount.toStringAsFixed(2)}',
//                   style: const TextStyle(
//                     fontSize: 12,
//                     fontWeight: FontWeight.w700,
//                     color: Colors.white70,
//                   ),
//                 ),
//               ],
//             ),
//           );
//         }).toList(),
//       ),
//     );
//   }
// }

String _fmtDateShort(DateTime d) => DateFormat.yMMMd().format(d);
String _fmtMonthDay(DateTime d) => DateFormat.MMMd().format(d); // "Jan 25"
String _fmtTime(DateTime d) => DateFormat.Hm().format(d);

String _fmtMonthDayNoYear(DateTime d) => DateFormat.MMMd().format(d); // Jan 25

String _fmtRangeNoYear(DateTime from, DateTime to) {
  // если разные годы — покажем год, иначе нет_PaymentTile
  if (from.year != to.year) {
    return '${DateFormat.yMMMd().format(from)} - ${DateFormat.yMMMd().format(to)}';
  }

  // если один и тот же день
  final sameDay = from.year == to.year && from.month == to.month && from.day == to.day;
  if (sameDay) return DateFormat.MMMd().format(from); // Jan 22

  // обычный диапазон без года
  return '${DateFormat.MMMd().format(from)} - ${DateFormat.MMMd().format(to)}'; // Jan 22 - Jan 25
}


class _PaymentTile extends StatelessWidget {
  final Map<String, dynamic> payment;
  final bool expanded;
  final VoidCallback onToggle;
  final VoidCallback onPdf;
  final Color accentColor;

  const _PaymentTile({
    required this.payment,
    required this.expanded,
    required this.onToggle,
    required this.onPdf,
    required this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    const accent = Colors.lightBlueAccent;

    final items = List<Map<String, dynamic>>.from(payment['payment_items'] ?? []);
    final paidAt = DateTime.parse(payment['created_at']).toLocal();

    DateTime? from;
    DateTime? to;
    for (final it in items) {
      final wl = it['work_logs'];
      if (wl == null) continue;
      final start = DateTime.parse(wl['start_time']).toLocal();
      from = (from == null || start.isBefore(from!)) ? start : from;
      to   = (to == null || start.isAfter(to!)) ? start : to;
    }

    final periodText = (from != null && to != null)
        ? _fmtRangeNoYear(from!, to!)
        : '—';

    final totalAmount = ((payment['total_amount'] ?? 0) as num).toDouble();
    final shiftCount = items.length;
    final paidText = 'Paid ${_fmtMonthDayNoYear(paidAt)}'; // -> "Paid Feb 26"

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Align(
        alignment: Alignment.center,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 340), // ✅ ширина payment-card
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              color: Colors.white.withOpacity(0.055), // 👈 чуть светлее чем у 2026
              border: Border.all(color: Colors.white.withOpacity(0.08)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.25),
                  blurRadius: 18,
                  offset: const Offset(0, 10),
                ),
              ],
            ),

            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Column(
                children: [
                  // ⬇️ ДАЛЬШЕ ОСТАВЬ СВОЙ СТАРЫЙ КОД ТУТ БЕЗ ИЗМЕНЕНИЙ
                  // ================= HEADER =================
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                    decoration: BoxDecoration(
                      color: kHistoryCardHeadBg,
                      border: Border(
                        bottom: BorderSide(color: kDividerSoft),
                      ),
                    ),
                    child: Row(
                      children: [
                        const Spacer(),
                        IconButton(
                          onPressed: onPdf,
                          tooltip: 'Export PDF',
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
                          icon: const Icon(
                            Icons.picture_as_pdf_rounded,
                            color: Colors.white70,
                            size: 22,
                          ),
                        ),
                      ],
                    ),
                  ),

                  // ================= BODY =================
                  InkWell(
                    onTap: onToggle,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Icon(
                                      Icons.date_range,
                                      size: 14,
                                      color: Colors.white,
                                    ),
                                    SizedBox(width: 6),
                                    Expanded(
                                      child: Text(
                                        periodText,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.white,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                Row(
                                  children: [
                                    Text(
                                      paidText,
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: Colors.white60,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Text(
                                      '·',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.white.withOpacity(0.35),
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Text(
                                      '$shiftCount shifts',
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: Colors.white60,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Text(
                                      '·',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.white.withOpacity(0.35),
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Text(
                                      '\$${totalAmount.toStringAsFixed(2)}',
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: Colors.white60,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          Icon(
                            expanded ? Icons.expand_less : Icons.expand_more,
                            color: Colors.white54,
                          ),
                        ],
                      ),
                    ),
                  ),

                  // ================= EXPANDED =================
                  AnimatedCrossFade(
                    duration: const Duration(milliseconds: 220),
                    crossFadeState:
                    expanded ? CrossFadeState.showFirst : CrossFadeState.showSecond,
                    firstChild: _PaymentDetails(
                      items,
                      accentColor: accentColor,
                    ),
                    secondChild: const SizedBox.shrink(),
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

class _MiniLabelRow extends StatelessWidget {
  final String title;
  const _MiniLabelRow({required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Row(
        children: [
          Expanded(child: Container(height: 1, color: Colors.white10)),
          const SizedBox(width: 10),
          Text(
            title,
            style: TextStyle(
              color: Colors.white.withOpacity(0.35),
              fontWeight: FontWeight.w900,
              fontSize: 10,
              letterSpacing: 1.0,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(child: Container(height: 1, color: Colors.white10)),
        ],
      ),
    );
  }
}


class _PaymentDetails extends StatelessWidget {
  final List<Map<String, dynamic>> items;
  final Color accentColor;

  const _PaymentDetails(
      this.items, {
        required this.accentColor,
      });

  @override
  Widget build(BuildContext context) {
    // ✅ мягкий фон под деталями (чтобы видно было “раскрытие”)
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(28, 8, 12, 12),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.12),
        border: Border(
          bottom: BorderSide(color: Colors.white.withOpacity(0.06)),
        ),
      ),
      child: Column(
        children: items.map((it) {
          final wl = it['work_logs'];
          if (wl == null) return const SizedBox.shrink();

          final start = DateTime.parse(wl['start_time']).toLocal();
          final end = wl['end_time'] != null
              ? DateTime.parse(wl['end_time']).toLocal()
              : null;

// ✅ считаем workedHours
          final worked = (end ?? DateTime.now()).difference(start);
          final workedHours = worked.inSeconds / 3600;


          // ✅ amount берем из payment_items.amount (самый правильный источник для платежа)
          final amount = ((it['amount'] ?? 0) as num).toDouble();

          return Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              color: Colors.white.withOpacity(0.05),
              border: Border.all(color: Colors.white.withOpacity(0.06)),
            ),
            child: Row(
              children: [
                // маленькая иконка
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: accentColor.withOpacity(0.18),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    Icons.schedule,
                    size: 16,
                    color: accentColor,
                  ),
                ),
                const SizedBox(width: 10),

                // текст
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _fmtDateShort(start),
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.white70,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${_fmtTime(start)}  ${end != null ? _fmtTime(end) : '—'}'
                            ' (${_fmtHmFromHours(workedHours)})',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.white54,
                          fontWeight: FontWeight.w700,
                        ),
                      ),

                    ],
                  ),
                ),

                // amount
                Text(
                  '\$${amount.toStringAsFixed(2)}',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                    color: Colors.greenAccent,
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }
}

enum ShiftStatus { active, pending, paid }

ShiftStatus _shiftStatus(Map<String, dynamic> r) {
  if (r['end_time'] == null) return ShiftStatus.active;
  if (r['paid_at'] == null) return ShiftStatus.pending;
  return ShiftStatus.paid;
}

class _InfoCell extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _InfoCell({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(width: 14),
        Expanded( // 🔥 ВАЖНО: ВОТ ЭТОГО НЕ БЫЛО
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 12,
                  color: Colors.white60,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ],
    );

  }
}

class _InfoCapsuleRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;
  final bool dimmed;

  const _InfoCapsuleRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
    this.dimmed = false,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveColor = dimmed ? color.withOpacity(0.55) : color;
    final labelColor =
    dimmed ? Colors.white.withOpacity(0.42) : Colors.white.withOpacity(0.72);

    final base = Colors.white.withOpacity(0.035);

    final bg = dimmed
        ? Colors.white.withOpacity(0.045)
        : Color.lerp(base, effectiveColor.withOpacity(0.10), 0.45)!;

    final borderColor = dimmed
        ? Colors.white.withOpacity(0.08)
        : Color.lerp(
      Colors.white.withOpacity(0.10),
      effectiveColor.withOpacity(0.22),
      0.60,
    )!;

    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: borderColor),
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
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: effectiveColor.withOpacity(0.18),
              borderRadius: BorderRadius.circular(9),
              border: Border.all(color: effectiveColor.withOpacity(0.10)),
            ),
            child: Icon(
              icon,
              size: 14,
              color: effectiveColor,
            ),
          ),
          const SizedBox(width: 10),
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              color: labelColor,
              fontWeight: FontWeight.w700,
            ),
          ),
          const Spacer(),
          Text(
            value,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w900,
              color: effectiveColor,
            ),
          ),
        ],
      ),
    );
  }
}

class _OnShiftBadge extends StatelessWidget {
  final bool onShift;

  const _OnShiftBadge({required this.onShift});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: onShift
            ? Colors.green.withOpacity(0.18)
            : Colors.grey.withOpacity(0.18),
        border: Border.all(
          color: onShift ? Colors.green : Colors.grey,
        ),
      ),
      child: Text(
        onShift ? 'ON SHIFT' : 'OFF SHIFT',
        style: TextStyle(
          color: onShift ? Colors.green : Colors.grey,
          fontWeight: FontWeight.w900,
          letterSpacing: 0.6,
        ),
      ),
    );
  }
}
class _HeaderShiftStatus extends StatefulWidget {
  final bool onShift;
  final bool isSuspended;
  const _HeaderShiftStatus({
    required this.onShift,
    required this.isSuspended,
  });


  @override
  State<_HeaderShiftStatus> createState() => _HeaderShiftStatusState();
}

class _HeaderShiftStatusState extends State<_HeaderShiftStatus> {
  bool _visible = true;

  @override
  void initState() {
    super.initState();
    _blink();
  }

  Future<void> _blink() async {
    while (mounted && widget.onShift && !widget.isSuspended) {
      await Future.delayed(const Duration(milliseconds: 700));
      setState(() => _visible = !_visible);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.isSuspended) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(999),
          color: kSuspendedAccent.withOpacity(0.14),
          border: Border.all(color: kSuspendedAccent.withOpacity(0.35)),
        ),
        child: const Text(
          'SUSPENDED',
          style: TextStyle(
            color: kSuspendedAccent,
            fontWeight: FontWeight.w900,
            letterSpacing: 0.6,
            fontSize: 12,
          ),
        ),
      );
    }

    final isOn = widget.onShift;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: isOn
            ? Colors.green.withOpacity(0.18)
            : Colors.grey.withOpacity(0.18),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 🔴 МИГАЮЩИЙ LIVE DOT
          if (isOn)
            AnimatedOpacity(
              opacity: _visible ? 1 : 0.25,
              duration: const Duration(milliseconds: 300),
              child: Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.green,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.green.withOpacity(0.6),
                      blurRadius: 8,
                      spreadRadius: 1,
                    ),
                  ],
                ),
              ),
            ),

          if (isOn) const SizedBox(width: 6),

          Text(
            isOn ? 'ON SHIFT' : 'OFF SHIFT',
            style: TextStyle(
              color: isOn ? Colors.green : Colors.grey,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.6,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}



// ================= EDIT WORKER DIALOG =================

class _OffShiftCapsule extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: Colors.grey.withOpacity(0.15),
        border: Border.all(color: Colors.grey.withOpacity(0.4)),
      ),
      child: const Text(
        'OFF SHIFT',
        style: TextStyle(
          color: Colors.grey,
          fontWeight: FontWeight.w900,
          letterSpacing: 0.6,
        ),
      ),
    );
  }
}

class _LiveOnShiftCapsule extends StatefulWidget {
  @override
  State<_LiveOnShiftCapsule> createState() => _LiveOnShiftCapsuleState();
}

class _LiveOnShiftCapsuleState extends State<_LiveOnShiftCapsule> {
  bool _visible = true;

  @override
  void initState() {
    super.initState();
    _blink();
  }

  Future<void> _blink() async {
    while (mounted) {
      await Future.delayed(const Duration(milliseconds: 700));
      setState(() => _visible = !_visible);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: Colors.green.withOpacity(0.15),
        border: Border.all(color: Colors.green.withOpacity(0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedOpacity(
            opacity: _visible ? 1 : 0.25,
            duration: const Duration(milliseconds: 300),
            child: Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.green,
                boxShadow: [
                  BoxShadow(
                    color: Colors.green.withOpacity(0.55),
                    blurRadius: 8,
                    spreadRadius: 1,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          const Text(
            'ON SHIFT',
            style: TextStyle(
              color: Colors.green,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.6,
            ),
          ),
        ],
      ),
    );
  }
}
class _ActiveLiveCapsule extends StatefulWidget {
  @override
  State<_ActiveLiveCapsule> createState() => _ActiveLiveCapsuleState();
}

class _ActiveLiveCapsuleState extends State<_ActiveLiveCapsule> {
  bool _visible = true;

  @override
  void initState() {
    super.initState();
    _blink();
  }

  Future<void> _blink() async {
    while (mounted) {
      await Future.delayed(const Duration(milliseconds: 650));
      setState(() => _visible = !_visible);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: Colors.orange.withOpacity(0.18),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedOpacity(
            opacity: _visible ? 1 : 0.25,
            duration: const Duration(milliseconds: 250),
            child: const Icon(
              Icons.play_arrow_rounded,
              size: 16,
              color: Colors.orangeAccent,
            ),
          ),
          const SizedBox(width: 4),
          const Text(
            'ACTIVE',
            style: TextStyle(
              color: Colors.orangeAccent,
              fontWeight: FontWeight.w900,
              fontSize: 12,
              letterSpacing: 0.6,
            ),
          ),
        ],
      ),
    );
  }
}
class AnimatedAmount extends StatelessWidget {
  final double value;
  final TextStyle style;

  const AnimatedAmount({
    super.key,
    required this.value,
    required this.style,
  });

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(end: value),
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeOut,
      builder: (_, v, __) {
        return Text(
          '\$${v.toStringAsFixed(2)}',
          style: style,
        );
      },
    );
  }
}
pw.Widget _summaryCell({
  required String label,
  required String value,
  PdfColor valueColor = PdfColors.grey900,
  int flex = 1,
}) {
  return pw.Expanded(
    flex: flex,
    child: pw.Column(
      mainAxisAlignment: pw.MainAxisAlignment.center,
      children: [
        pw.Text(
          label,
          textAlign: pw.TextAlign.center,
          style: pw.TextStyle(
            fontSize: 9,
            color: PdfColors.grey600,
            letterSpacing: 0.8,
          ),
        ),

        pw.SizedBox(height: 6),

        // 🔹 тонкая линия-разделитель
        pw.Container(
          width: 28,
          height: 1,
          color: PdfColors.grey400,
        ),

        pw.SizedBox(height: 6),

        pw.Text(
          value,
          textAlign: pw.TextAlign.center,
          style: pw.TextStyle(
            fontSize: 12,
            fontWeight: pw.FontWeight.bold,
            color: valueColor,
          ),
        ),
      ],
    ),
  );
}


pw.Widget _summaryDivider() {
  return pw.Container(
    width: 1,
    height: 36,
    color: PdfColors.grey300,
  );
}
Duration safeWorkedDuration(DateTime start, DateTime? end) {
  if (end == null) return Duration.zero;

  if (end.isBefore(start)) {
    // ❌ защита от отрицательного времени
    return Duration.zero;
  }

  return end.difference(start);
}
// ================= HELPERS =================

String _fmtHmFromHours(double hours) {
  final totalMinutes = (hours * 60).round();
  final h = totalMinutes ~/ 60;
  final m = totalMinutes % 60;
  return '$h:${m.toString().padLeft(2, '0')}';
}

String fmtCompactInt(num value) {
  final v = value.toDouble().abs();

  String core;
  if (v < 1000) {
    core = v.toStringAsFixed(0);
  } else if (v < 10000) {
    core = (v / 1000).toStringAsFixed(1);
    core = core.replaceAll(RegExp(r'\.?0+$'), '');
    core = '${core}K';
  } else if (v < 1000000) {
    core = (v / 1000).toStringAsFixed(0);
    core = '${core}K';
  } else {
    core = (v / 1000000).toStringAsFixed(v < 10000000 ? 1 : 0);
    core = core.replaceAll(RegExp(r'\.?0+$'), '');
    core = '${core}M';
  }

  final sign = value.isNegative ? '-' : '';
  return '$sign$core';
}

String fmtCompactHours(double hours) {
  final v = hours.abs();

  String core;
  if (v < 1000) {
    core = v.toStringAsFixed(1);
    core = core.replaceAll(RegExp(r'\.?0+$'), '');
  } else if (v < 10000) {
    core = (v / 1000).toStringAsFixed(1);
    core = core.replaceAll(RegExp(r'\.?0+$'), '');
    core = '${core}K';
  } else {
    core = (v / 1000).toStringAsFixed(0);
    core = '${core}K';
  }

  final sign = hours.isNegative ? '-' : '';
  return '${sign}${core}h';
}

// ================= UI WIDGETS =================

const Color kSuspendedAccent = Color(0xFFD46A73);      // приятный красный

const Color kPaymentsBurgundy = Color(0xFFC86A8A);     // яркий бордовый

const Color kSuspendedAccentSoft = Color(0xFFB85A64);  // темнее

const Color kSectionHeaderBg   = Color(0xFF2E323A);

const Color kHistoryPanelBg    = Color(0xFF1F232A);
const Color kHistoryCardBg     = Color(0xFF262B33);
const Color kHistoryCardHeadBg = Color(0xFF2C3139);

const Color kTextPrimary       = Color(0xFFF2F4F7);
const Color kTextSecondary     = Color(0xFFC9CED6);
const Color kTextMuted         = Color(0xFF98A0AA);

const Color kBorderSoft        = Color(0x22FFFFFF);
const Color kDividerSoft       = Color(0x12FFFFFF);

const Color kMoneyAccent       = Color(0xFF72F2B2); // чуть темнее (для HISTORY/PAYMENTS)

class _SectionPanel extends StatelessWidget {
  final Widget header;
  final Widget child;

  // ✅ добавили footer (может быть null)
  final Widget? footer;

  const _SectionPanel({
    required this.header,
    required this.child,
    this.footer,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF232831),
            Color(0xFF1D2128),
            Color(0xFF171B21),
          ],
        ),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: kBorderSoft),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.22),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        children: [
          header,
          Container(height: 1, color: kDividerSoft),
          child,

          // ✅ FOOTER снизу (если передали)
          if (footer != null) ...[
            Container(height: 1, color: kDividerSoft),
            footer!,
          ],
        ],
      ),
    );
  }
}

class _HistoryHeaderBar extends StatelessWidget {
  const _HistoryHeaderBar();

  @override
  Widget build(BuildContext context) {
    const accent = Colors.amber;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: const BoxDecoration(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
        color: kSectionHeaderBg,
      ),
      child: Stack(
        children: [

          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const SizedBox(width: 12),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: const [
                  Text(
                    'HISTORY',
                    style: TextStyle(
                      color: kTextPrimary,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.2,
                      fontSize: 14,
                    ),
                  ),
                  SizedBox(height: 2),
                  Text(
                    'Activity & shifts',
                    style: TextStyle(
                      color: kTextSecondary,
                      fontWeight: FontWeight.w700,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _HistoryFooterBar extends StatelessWidget {
  final int shifts;
  final String workedText;
  final String amountText;

  // ✅ toggle как в payments
  final bool canToggle;
  final bool showAll;
  final int hiddenCount;
  final VoidCallback onToggle;

  const _HistoryFooterBar({
    required this.shifts,
    required this.workedText,
    required this.amountText,
    required this.canToggle,
    required this.showAll,
    required this.hiddenCount,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      // ✅ единый контейнер: кнопка + строка итогов
      width: double.infinity,
      decoration: BoxDecoration(
        color: kHistoryPanelBg,
        borderRadius: const BorderRadius.vertical(
          bottom: Radius.circular(22),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [

          // ✅ верхняя кнопка (стрелка) — занимает всю ширину
          if (canToggle)
            InkWell(
              onTap: onToggle,
              child: Container(
                width: double.infinity,
                height: 44, // можешь 40/42/44
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: kHistoryCardBg,
                  borderRadius: BorderRadius.vertical(
                    bottom: Radius.circular(0), // ничего, просто ясно
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      showAll
                          ? Icons.keyboard_arrow_up_rounded
                          : Icons.keyboard_arrow_down_rounded,
                      size: 22,
                      color: kTextSecondary,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      showAll ? 'Show less' : 'Show more ($hiddenCount)',
                      style: TextStyle(
                        color: kTextSecondary,
                        fontWeight: FontWeight.w900,
                        fontSize: 13,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ],
                ),

              ),
            ),

// ✅ линия-разделитель между кнопкой и итогами
          if (canToggle)
            Container(
              height: 1,
              color: kDividerSoft,
            ),


          // ✅ нижняя строка итогов (как было)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '$shifts shifts',
                    style: const TextStyle(
                      color: Colors.white70,
                      fontWeight: FontWeight.w900,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(width: 10),
                  const Text('·', style: TextStyle(color: kTextMuted, fontSize: 16)),
                  const SizedBox(width: 10),
                  Text(
                    workedText,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontWeight: FontWeight.w900,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(width: 10),
                  const Text('·', style: TextStyle(color: kTextMuted, fontSize: 16)),
                  const SizedBox(width: 10),
                  Text(
                    amountText,
                    style: const TextStyle(
                      color: Colors.greenAccent,
                      fontWeight: FontWeight.w900,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PaymentsFooterBar extends StatelessWidget {
  final int paymentsCount;
  final String totalText;
  final Widget tip;

  final bool canToggle;
  final bool showAll;
  final int hiddenCount;
  final VoidCallback onToggle;

  const _PaymentsFooterBar({
    required this.paymentsCount,
    required this.totalText,
    required this.tip,
    required this.canToggle,
    required this.showAll,
    required this.hiddenCount,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      // ✅ ОДИН КОНТЕЙНЕР на всё: кнопка + footer
      width: double.infinity,
      decoration: BoxDecoration(
        color: kHistoryPanelBg,
        borderRadius: const BorderRadius.vertical(
          bottom: Radius.circular(22),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ✅ "HEADER" для футера — кнопка (вровень, без padding по бокам)
          if (canToggle)
            InkWell(
              onTap: onToggle,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  // ✅ верхняя часть остаётся прямой (потому что это внутри футера),
                  // низ разделим линией
                  color: kHistoryCardBg,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      showAll
                          ? Icons.keyboard_arrow_up_rounded
                          : Icons.keyboard_arrow_down_rounded,
                      size: 20,
                      color: kHistoryCardBg,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      showAll ? 'Show less' : 'Show more',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                        color: kHistoryCardBg,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ],
                ),
              ),
            ),

          // ✅ разделитель между "кнопкой-хедером" и нижней строкой футера
          if (canToggle)
            Container(
              height: 1,
              color: Colors.white.withOpacity(0.06),
            ),

          // ✅ нижняя часть футера
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '$paymentsCount payments',
                    style: const TextStyle(
                      color: Colors.white70,
                      fontWeight: FontWeight.w900,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(width: 10),
                  const Text('·', style: TextStyle(color: kTextMuted, fontSize: 16)),
                  const SizedBox(width: 10),
                  Text(
                    totalText,
                    style: const TextStyle(
                      color: Colors.greenAccent,
                      fontWeight: FontWeight.w900,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(width: 10),
                  const Text('·',
                      style: TextStyle(color: Colors.white38, fontSize: 16)),
                  const SizedBox(width: 10),
                  tip,
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PaymentsHeaderBar extends StatelessWidget {
  const _PaymentsHeaderBar();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: const BoxDecoration(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
        color: kSectionHeaderBg,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(width: 12),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: const [
              Text(
                'PAYMENTS',
                style: TextStyle(
                  color: kTextPrimary,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.2,
                  fontSize: 14,
                ),
              ),
              SizedBox(height: 2),
              Text(
                'Statements & exports',
                style: TextStyle(
                  color: kTextSecondary,
                  fontWeight: FontWeight.w700,
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

List<Map<String, dynamic>> _groupHistoryCardsByDay(
    List<Map<String, dynamic>> rows,
    ) {
  if (rows.isEmpty) return const <Map<String, dynamic>>[];

  final sorted = [...rows]
    ..sort((a, b) {
      final ad = DateTime.parse(a['start_time']).toLocal();
      final bd = DateTime.parse(b['start_time']).toLocal();
      return bd.compareTo(ad);
    });

  final Map<String, List<Map<String, dynamic>>> byDay = {};

  for (final row in sorted) {
    final start = DateTime.parse(row['start_time']).toLocal();
    final key =
        '${start.year}-${start.month.toString().padLeft(2, '0')}-${start.day.toString().padLeft(2, '0')}';

    byDay.putIfAbsent(key, () => <Map<String, dynamic>>[]);
    byDay[key]!.add(row);
  }

  final result = <Map<String, dynamic>>[];

  for (final bucket in byDay.values) {
    if (bucket.length == 1) {
      result.add(bucket.first);
      continue;
    }

    final merged = Map<String, dynamic>.from(bucket.first);
    merged['__group_rows'] =
        bucket.map((e) => Map<String, dynamic>.from(e)).toList();
    merged['__group_count'] = bucket.length;
    result.add(merged);
  }

  return result;
}

// ================= YEAR GROUPED HISTORY (WRAPPER над твоим HistorySection) =================

class YearGroupedHistorySection extends StatefulWidget {
  final bool autoExpandFromSearch;
  final List<Map<String, dynamic>> active;
  final List<Map<String, dynamic>> pending;
  final List<Map<String, dynamic>> paid;
  final Widget Function(Map<String, dynamic> row) buildCard;
  final bool showAllPaid;
  final int previewPaidCount;
  final void Function(bool showAllYears, int hiddenYearsCount)? onYearsToggleData;
  final Color accentColor;
  final WorkerHistoryFilter selectedFilter;
  final int autoOpenVersion;

  const YearGroupedHistorySection({
    super.key,
    required this.active,
    required this.pending,
    required this.paid,
    required this.buildCard,
    required this.showAllPaid,
    required this.accentColor,
    required this.selectedFilter,
    required this.autoExpandFromSearch,
    this.previewPaidCount = 2,
    this.onYearsToggleData,
    required this.autoOpenVersion,
  });

  @override
  State<YearGroupedHistorySection> createState() => _YearGroupedHistorySectionState();
}

class _YearGroupedHistorySectionState extends State<YearGroupedHistorySection> {
  final Set<int> _expandedYears = {};
  bool _showAllYears = false; // ✅ always show all years
  final Map<int, bool> _showAllMonthsInYear = {};
  @override
  void initState() {
    super.initState();
    // по умолчанию раскрываем текущий год
    _expandedYears.add(DateTime.now().year);
  }

  void toggleShowAllYears() {
    setState(() {
      _showAllYears = !_showAllYears;

      // когда закрываем обратно — оставляем раскрытым только самый новый год
      if (!_showAllYears) {
        final years = _allYearsSorted();
        if (years.isNotEmpty) {
          _expandedYears
            ..clear()
            ..add(years.first);
        }
      }
    });
  }


  int _yearOf(Map<String, dynamic> r) {
    final start = DateTime.parse(r['start_time']).toLocal();
    return start.year;
  }

  List<int> _allYearsSorted() {
    final all = <Map<String, dynamic>>[
      ...widget.active,
      ...widget.pending,
      ...widget.paid,
    ];

    final years = all.map(_yearOf).toSet().toList()..sort((a, b) => b.compareTo(a));
    return years;
  }

  List<Map<String, dynamic>> _onlyYear(List<Map<String, dynamic>> rows, int year) {
    return rows.where((r) => _yearOf(r) == year).toList();
  }

  @override
  Widget build(BuildContext context) {
    final years = _allYearsSorted();
    if (years.isEmpty) {
      return _SectionEmptyState(
        icon: Icons.history_rounded,
        title: 'No history yet',
        subtitle: 'Activity and shifts will appear here.',
        gradientColors: [
          kHistoryCardBg.withOpacity(0.97),
          kHistoryPanelBg.withOpacity(0.96),
        ],
      );
    }

    final currentYear = DateTime.now().year;

    final visibleYears = _showAllYears
        ? years
        : years.where((y) => y == currentYear).toList();

    final hiddenYearsCount = years.length - visibleYears.length;

    // ✅ сообщаем наружу текущее состояние (после построения)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      widget.onYearsToggleData?.call(_showAllYears, hiddenYearsCount);
    });

    return Column(
      children: [
        ...visibleYears.map((year) {
          final yActive  = _onlyYear(widget.active, year);
          final yPending = _onlyYear(widget.pending, year);
          final yPaid    = _onlyYear(widget.paid, year);

          // stats считаем по завершенным (end_time != null), чтобы не было "живых" сумм
          final finished = <Map<String, dynamic>>[
            ...yPending.where((r) => r['end_time'] != null),
            ...yPaid.where((r) => r['end_time'] != null),
          ];

          final totalAmount = finished.fold<double>(
            0,
                (s, r) => s + ((r['total_payment'] ?? 0) as num).toDouble(),
          );

          final totalHours = finished.fold<double>(
            0,
                (s, r) => s + ((r['total_hours'] ?? 0) as num).toDouble(),
          );

          final shiftsCount = finished.length;

          // months count
          final monthsSet = finished.map((r) {
            final d = DateTime.parse(r['start_time']).toLocal();
            return '${d.year}-${d.month.toString().padLeft(2, '0')}';
          }).toSet();
          final monthsCount = monthsSet.length;

          // unpaid badge (опционально красиво)
          final unpaidAmount = yPending.fold<double>(
            0,
                (s, r) => s + ((r['total_payment'] ?? 0) as num).toDouble(),
          );

          final expanded = _expandedYears.contains(year);

          return _YearCard(
            year: year,
            expanded: expanded,
            totalAmount: totalAmount,
            shiftsCount: shiftsCount,
            totalHours: totalHours,
            monthsCount: monthsCount,
            unpaidAmount: unpaidAmount,
            accentColor: widget.accentColor,
            onToggle: () {
              setState(() {
                if (expanded) {
                  _expandedYears.remove(year);
                } else {
                  _expandedYears.add(year);
                }
              });
            },
            child: _YearInnerGroups(
            autoOpenVersion: widget.autoOpenVersion,
            active: yActive,
            pending: yPending,
            paid: yPaid,
            selectedFilter: widget.selectedFilter,
            autoExpandFromSearch: widget.autoExpandFromSearch,
            buildCard: widget.buildCard,
              groupPaidByMonth: _groupPaidByMonth,
              monthTitleFromKey: _monthTitleFromKey,
              showAllMonths: (_showAllMonthsInYear[year] == true),
              onShowMoreMonths: () => setState(() {
                final cur = _showAllMonthsInYear[year] == true;
                _showAllMonthsInYear[year] = !cur;     // ✅ теперь и раскрывает и сворачивает
              }),

            ),
          );
        }).toList(),
      ],
    );
  }
}

class _YearInnerGroups extends StatefulWidget {
  final List<Map<String, dynamic>> active;
  final List<Map<String, dynamic>> pending;
  final List<Map<String, dynamic>> paid;
  final bool autoExpandFromSearch;

  final Widget Function(Map<String, dynamic>) buildCard;
  final WorkerHistoryFilter selectedFilter;

  final Map<String, List<Map<String, dynamic>>> Function(List<Map<String, dynamic>>)
  groupPaidByMonth;
  final String Function(String) monthTitleFromKey;

  final bool showAllMonths;
  final VoidCallback onShowMoreMonths;
  final int autoOpenVersion;

  const _YearInnerGroups({
    required this.active,
    required this.pending,
    required this.paid,
    required this.selectedFilter,
    required this.autoExpandFromSearch,
    required this.buildCard,
    required this.groupPaidByMonth,
    required this.monthTitleFromKey,
    required this.showAllMonths,
    required this.onShowMoreMonths,
    required this.autoOpenVersion,
  });

  @override
  State<_YearInnerGroups> createState() => _YearInnerGroupsState();
}

class _YearInnerGroupsState extends State<_YearInnerGroups> {
  String? _openKey;

  double _sumAmount(List<Map<String, dynamic>> rows) => rows.fold<double>(
    0,
        (s, r) => s + ((r['total_payment'] ?? 0) as num).toDouble(),
  );

  void _toggleGroup(String key) {
    setState(() {
      _openKey = _openKey == key ? null : key;
    });
  }

  @override
  Widget build(BuildContext context) {
    final bool isSearchMode = widget.autoExpandFromSearch;
    final bool isAllFilter = widget.selectedFilter == WorkerHistoryFilter.all;

    final forceActiveOpen =
        isSearchMode && widget.selectedFilter == WorkerHistoryFilter.active;

    final forceMonthOpen =
        isSearchMode &&
            ((widget.selectedFilter == WorkerHistoryFilter.unpaid &&
                widget.pending.isNotEmpty) ||
                (widget.selectedFilter == WorkerHistoryFilter.paid &&
                    widget.paid.isNotEmpty) ||
                (isAllFilter && (widget.pending.isNotEmpty || widget.paid.isNotEmpty)));

    final monthRows = _groupHistoryCardsByDay([
      ...widget.pending,
      ...widget.paid,
    ])
      ..sort((a, b) {
        final ad = DateTime.parse(a['start_time']).toLocal();
        final bd = DateTime.parse(b['start_time']).toLocal();
        return bd.compareTo(ad);
      });

    final groups = widget.groupPaidByMonth(monthRows);

    final monthKeys = groups.keys.toList()..sort((a, b) => b.compareTo(a));

    final String? lastMonthKey = monthKeys.isEmpty ? null : monthKeys.first;

    final canToggleMonths = monthKeys.length > 1;

    final List<String> visibleMonthKeys = widget.showAllMonths
        ? monthKeys
        : (lastMonthKey == null ? [] : [lastMonthKey]);

    String? forcedOpenKey;
    if (forceActiveOpen && widget.active.isNotEmpty) {
      forcedOpenKey = 'active';
    } else if (forceMonthOpen && visibleMonthKeys.isNotEmpty) {
      forcedOpenKey = 'month_${visibleMonthKeys.first}';
    }

    if (forcedOpenKey != null && forcedOpenKey != _openKey) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (_openKey == forcedOpenKey) return;
        setState(() {
          _openKey = forcedOpenKey;
        });
      });
    }

    final effectiveOpenKey = forcedOpenKey ?? _openKey;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 4, 10, 8),
          child: Column(
            children: [
              if (widget.active.isNotEmpty) ...[
                _GroupCard(
                  titleLeft: 'ACTIVE',
                  titleRight: '${widget.active.length}',
                  icon: Icons.play_circle_fill_rounded,
                  isOpen: effectiveOpenKey == 'active',
                  onToggle: () => _toggleGroup('active'),
                  child: Column(children: widget.active.map(widget.buildCard).toList()),
                ),
                const SizedBox(height: 10),
              ],

              ...visibleMonthKeys.map((k) {
                final monthItems = groups[k] ?? const <Map<String, dynamic>>[];
                if (monthItems.isEmpty) return const SizedBox.shrink();

                final groupKey = 'month_$k';

                return Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: _GroupCard(
                    titleLeft: widget.monthTitleFromKey(k),
                    titleRight: '\$${_sumAmount(monthItems).toStringAsFixed(0)}',
                    icon: Icons.calendar_month_rounded,
                    trailingChip: '${monthItems.length} shifts',
                    isOpen: effectiveOpenKey == groupKey,
                    onToggle: () => _toggleGroup(groupKey),
                    child: Column(children: monthItems.map(widget.buildCard).toList()),
                  ),
                );
              }).toList(),
            ],
          ),
        ),
        if (canToggleMonths)
          SizedBox(
            width: double.infinity,
            height: 28,
            child: _YearFooterArrowButton(
              isExpanded: widget.showAllMonths,
              onTap: widget.onShowMoreMonths,
            ),
          ),
      ],
    );
  }
}

class _GroupCard extends StatelessWidget {
  final String titleLeft;
  final String titleRight;
  final String? trailingChip;
  final IconData icon;
  final Widget child;

  final bool isOpen;
  final VoidCallback onToggle;

  const _GroupCard({
    required this.titleLeft,
    required this.titleRight,
    required this.icon,
    required this.child,
    required this.isOpen,
    required this.onToggle,
    this.trailingChip,
  });

  @override
  Widget build(BuildContext context) {
    final isUnpaid = titleLeft.toUpperCase() == 'UNPAID';
    final isActive = titleLeft.toUpperCase() == 'ACTIVE';
    final isMonth = !isUnpaid && !isActive;
    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF2A2F37),
            Color(0xFF242931),
            Color(0xFF1E232A),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: kBorderSoft),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.16),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Column(
          children: [
            InkWell(
              onTap: onToggle,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Color(0xFF323742),
                      Color(0xFF2B3038),
                      Color(0xFF242931),
                    ],
                  ),
                ),
                child: Row(
                  children: [
                    titleLeft.toUpperCase() == 'ACTIVE'
                        ? const _ActiveHeaderBlinkIcon(
                      icon: Icons.play_circle_fill_rounded,
                    )
                        : Icon(
                      icon,
                      size: 18,
                      color: Colors.white.withValues(alpha: 0.92),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      titleLeft,
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.95),
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.5,
                        fontSize: 13.5,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      titleRight,
                      style: const TextStyle(
                        color: kTextSecondary,
                        fontWeight: FontWeight.w900,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Icon(
                      isOpen ? Icons.expand_less : Icons.expand_more,
                      color: kTextSecondary,
                    ),
                  ],
                ),
              ),
            ),
            AnimatedCrossFade(
              duration: const Duration(milliseconds: 220),
              crossFadeState:
              isOpen ? CrossFadeState.showFirst : CrossFadeState.showSecond,
              firstChild: Padding(
                padding: const EdgeInsets.fromLTRB(0, 10, 0, 0),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxHeight: 340,
                  ),
                  child: ScrollConfiguration(
                    behavior: const _NoScrollbarNoGlow(),
                    child: SingleChildScrollView(
                      physics: const BouncingScrollPhysics(),
                      child: child,
                    ),
                  ),
                ),
              ),
              secondChild: const SizedBox.shrink(),
            ),
          ],
        ),
      ),
    );
  }
}

class _YearFooterArrowButton extends StatelessWidget {
  final VoidCallback onTap;
  final bool isExpanded;

  const _YearFooterArrowButton({
    super.key,
    required this.onTap,
    required this.isExpanded,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(16),
          bottomRight: Radius.circular(16),
        ),
        onTap: onTap,
        child: Container(
          width: double.infinity,
          height: double.infinity,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: kHistoryCardBg,
            borderRadius: const BorderRadius.only(
              bottomLeft: Radius.circular(16),
              bottomRight: Radius.circular(16),
            ),
            border: Border.all(
              color: kDividerSoft,
              width: 1,
            ),
          ),
          child: Icon(
            isExpanded
                ? Icons.keyboard_arrow_up_rounded
                : Icons.keyboard_arrow_down_rounded,
            size: 22,
            color: kTextSecondary,
          ),
        ),
      ),
    );
  }
}

class _HistoryFooterShowMore extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _HistoryFooterShowMore({
    required this.onTap,
    this.label = 'Show more',
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 8),
        color: kHistoryCardBg,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.keyboard_arrow_down_rounded,
              size: 20,
              color: Colors.white70,
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w900,
                color: Colors.white70,
                letterSpacing: 0.3,
              ),
            ),
          ],
        ),
      ),
    );
  }
}


class _MonthCard extends StatefulWidget {
  final String title;
  final String totalText;
  final String countText;
  final Widget child;

  const _MonthCard({
    required this.title,
    required this.totalText,
    required this.countText,
    required this.child,
  });

  @override
  State<_MonthCard> createState() => _MonthCardState();
}

class _MonthCardState extends State<_MonthCard> {
  bool _open = false; // ✅ чтобы месяцы не “шумели”, но можно true

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: kHistoryCardBg, // плоско
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Column(
          children: [
            InkWell(
              onTap: () => setState(() => _open = !_open),
              child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.035),
                    border: Border(
                      bottom: BorderSide(color: Colors.white.withOpacity(0.05)),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.calendar_month, size: 16, color: Colors.white60),
                      const SizedBox(width: 10),

                      Expanded(
                        child: Text(
                          widget.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontWeight: FontWeight.w800,
                            fontSize: 13,
                          ),
                        ),
                      ),

                      // ✅ ЛЕВАЯ мини-строка: shifts + amount (серые иконки)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.work_history_rounded, size: 14, color: kTextMuted),
                          const SizedBox(width: 6),
                          Text(
                            widget.countText, // например "2 shifts"
                            style: const TextStyle(
                              color: Colors.white60,
                              fontWeight: FontWeight.w800,
                              fontSize: 12,
                            ),
                          ),
                          const SizedBox(width: 10),
                          const Text('·', style: TextStyle(color: kTextMuted, fontSize: 16)),
                          const SizedBox(width: 10),
                          const Icon(Icons.payments_rounded, size: 14, color: kTextMuted),
                          const SizedBox(width: 6),
                          Text(
                            widget.totalText, // например "$1030"
                            style: const TextStyle(
                              color: Colors.white60, // ✅ серым
                              fontWeight: FontWeight.w900,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(width: 10),

                      Icon(_open ? Icons.expand_less : Icons.expand_more, color: Colors.white54),
                    ],
                  )

              ),
            ),

            AnimatedCrossFade(
              duration: const Duration(milliseconds: 220),
              crossFadeState: _open ? CrossFadeState.showFirst : CrossFadeState.showSecond,
              firstChild: Padding(
                padding: const EdgeInsets.fromLTRB(0, 10, 0, 0),
                child: widget.child,
              ),
              secondChild: const SizedBox.shrink(),
            ),
          ],
        ),
      ),
    );
  }
}


class _YearCard extends StatefulWidget {
  final int year;
  final bool expanded;
  final VoidCallback onToggle;
  final Color accentColor;

  final double totalAmount;
  final int shiftsCount;
  final double totalHours;
  final int monthsCount;
  final double unpaidAmount;

  final Widget child;

  const _YearCard({
    required this.year,
    required this.expanded,
    required this.onToggle,
    required this.totalAmount,
    required this.shiftsCount,
    required this.totalHours,
    required this.monthsCount,
    required this.unpaidAmount,
    required this.child,
    required this.accentColor,
  });

  @override
  State<_YearCard> createState() => _YearCardState();
}

class _YearCardState extends State<_YearCard> {
  Timer? _rot;
  int _mode = 0; // 0=unpaid, 1=total

  @override
  void initState() {
    super.initState();

    // крутим только если есть unpaid, иначе показываем total и всё
    if (widget.unpaidAmount > 0) {
      _rot = Timer.periodic(const Duration(seconds: 5), (_) {
        if (!mounted) return;
        setState(() => _mode = (_mode + 1) % 2);
      });
    } else {
      _mode = 1;
    }
  }

  @override
  void didUpdateWidget(covariant _YearCard oldWidget) {
    super.didUpdateWidget(oldWidget);

    // если unpaid появился/исчез — пересобираем таймер
    final had = oldWidget.unpaidAmount > 0;
    final has = widget.unpaidAmount > 0;

    if (had != has) {
      _rot?.cancel();
      if (has) {
        _mode = 0;
        _rot = Timer.periodic(const Duration(seconds: 5), (_) {
          if (!mounted) return;
          setState(() => _mode = (_mode + 1) % 2);
        });
      } else {
        _mode = 1; // только total
      }
    }
  }

  @override
  void dispose() {
    _rot?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const accentBlue = kTextSecondary;

    return Container(
      margin: const EdgeInsets.fromLTRB(8, 6, 8, 2),
      decoration: BoxDecoration(
        color: kHistoryPanelBg,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: kBorderSoft),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: Column(
          children: [
            // ================= HEADER =================
            InkWell(
              onTap: widget.onToggle,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: kHistoryCardHeadBg,
                  border: Border(
                    bottom: BorderSide(color: kDividerSoft),
                  ),
                ),
                child: Row(
                  children: [
                    const SizedBox(width: 10),
                    Text(
                      '${widget.year}',
                      style: const TextStyle(
                        color: kTextPrimary,
                        fontWeight: FontWeight.w900,
                        fontSize: 15,
                        letterSpacing: 0.6,
                      ),
                    ),
                    const Spacer(),
                    Icon(
                      widget.expanded ? Icons.expand_less : Icons.expand_more,
                      color: kTextSecondary,
                    ),
                  ],
                ),
              ),
            ),

            // ================= SUBLINE =================
            // тут оставь твою subline (уже поправленную по пункту #1),
            // только заменяй monthsCount/shiftsCount/totalHours на widget.*
            _buildSubline(accentBlue),

            AnimatedCrossFade(
              duration: const Duration(milliseconds: 220),
              crossFadeState: widget.expanded
                  ? CrossFadeState.showFirst
                  : CrossFadeState.showSecond,
              firstChild: widget.child,
              secondChild: const SizedBox.shrink(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSubline(Color accentBlue) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 6, 14, 2),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.center,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _miniStat(
              icon: Icons.view_module_rounded,
              text: '${fmtCompactInt(widget.monthsCount)} m.',
              color: widget.accentColor,
            ),
            _dotGap(),
            _miniStat(
              icon: Icons.work_history_rounded,
              text: '${fmtCompactInt(widget.shiftsCount)} sh.',
              color: widget.accentColor,
            ),
            _dotGap(),
            _miniStat(
              icon: Icons.timer,
              text: fmtCompactHours(widget.totalHours),
              color: widget.accentColor,
            ),
            _dotGap(),
            _miniStat(
              icon: Icons.bolt_rounded,
              text: fmtMoneyCompact(widget.totalAmount),
              color: widget.accentColor,
            ),
          ],
        ),
      ),
    );
  }

  Widget _dot() => const Text(
    '·',
    style: TextStyle(
      color: kTextMuted,
      fontSize: 16,
    ),
  );

  Widget _dotGap() => Row(
    children: const [
      SizedBox(width: 8),
      Text(
        '·',
        style: TextStyle(
          color: kTextMuted,
          fontSize: 16,
        ),
      ),
      SizedBox(width: 8),
    ],
  );

  Widget _miniStat({
    required IconData icon,
    required String text,
    required Color color,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 15, color: color),
        const SizedBox(width: 6),
        Text(
          text,
          style: const TextStyle(
            color: kTextSecondary,
            fontWeight: FontWeight.w800,
            fontSize: 13,
          ),
        ),
      ],
    );
  }

  Widget _miniUnpaid({required double amount}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.money_off_csred_rounded, size: 16, color: Colors.orangeAccent),
        const SizedBox(width: 6),
        Text(
          fmtMoneyCompact(amount),
          style: const TextStyle(
            color: Colors.white70,
            fontWeight: FontWeight.w900,
            fontSize: 12,
          ),
        ),
      ],
    );
  }
}

class YearGroupedPaymentsSection extends StatefulWidget {
  final List<Map<String, dynamic>> payments;
  final Widget Function(Map<String, dynamic> payment) buildTile;
  final Color accentColor;

  const YearGroupedPaymentsSection({
    super.key,
    required this.payments,
    required this.buildTile,
    required this.accentColor,
  });

  @override
  State<YearGroupedPaymentsSection> createState() => _YearGroupedPaymentsSectionState();
}

class _YearGroupedPaymentsSectionState extends State<YearGroupedPaymentsSection> {
  final Set<int> _expandedYears = {};
  static const int _paymentsStep = 5;
  final Map<int, int> _visibleCountByYear = {};

  @override
  void initState() {
    super.initState();

    final years = _yearsSorted();
    if (years.isNotEmpty) {
      _expandedYears.add(years.first); // newest year opened

      for (final year in years) {
        final yearList = _onlyYear(year);
        _visibleCountByYear[year] = yearList.isEmpty ? 0 : 1; // ✅ start with 1
      }
    }
  }

  int _yearOfPayment(Map<String, dynamic> p) {
    final d = DateTime.parse(p['created_at']).toLocal();
    return d.year;
  }

  List<int> _yearsSorted() {
    final years = widget.payments.map(_yearOfPayment).toSet().toList()
      ..sort((a, b) => b.compareTo(a));
    return years;
  }

  List<Map<String, dynamic>> _onlyYear(int year) {
    return widget.payments.where((p) => _yearOfPayment(p) == year).toList();
  }

  @override
  Widget build(BuildContext context) {
    final years = _yearsSorted();
    if (years.isEmpty) return const SizedBox.shrink();

    return Column(
      children: years.map((year) {
        final list = _onlyYear(year);

        final total = list.fold<double>(
          0,
              (s, p) => s + ((p['total_amount'] ?? 0) as num).toDouble(),
        );
        final shiftsCount = shiftsCountForPayments(list);
        final monthsCount = monthsCountForPayments(list);


        final expanded = _expandedYears.contains(year);

        final visibleCount = (_visibleCountByYear[year] ?? 1).clamp(0, list.length);
        final visible = list.take(visibleCount).toList();
        final hidden = list.length - visible.length;

        final isFullyExpanded = visibleCount >= list.length;
        final canToggleList = list.length > 1;


        return _PaymentsYearCard(
          year: year,
          expanded: expanded,
          accentColor: widget.accentColor,
          paymentsCount: list.length,
          shiftsCount: shiftsCount,     // ✅
          monthsCount: monthsCount,
          totalAmount: total,
          onToggle: () {
            setState(() {
              if (expanded) {
                _expandedYears.remove(year);
              } else {
                _expandedYears.add(year);
              }
            });
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6), // легкая “вкладка”
            child: Column(
              children: [
                ...visible.map(widget.buildTile).toList(),

              ],
            ),
          ),
          canToggleList: canToggleList,
          showAllInYear: isFullyExpanded,
          hiddenCount: hidden,
          onToggleShowMore: () {
            setState(() {
              final current = _visibleCountByYear[year] ?? 1;

              if (current >= list.length) {
                // ✅ back to 1
                _visibleCountByYear[year] = list.isEmpty ? 0 : 1;
              } else if (current < _paymentsStep) {
                // ✅ first expand: 1 -> 5
                _visibleCountByYear[year] =
                list.length < _paymentsStep ? list.length : _paymentsStep;
              } else {
                // ✅ next expands: 5 -> 10 -> 15 ...
                final next = current + _paymentsStep;
                _visibleCountByYear[year] = next > list.length ? list.length : next;
              }
            });
          },
        );
      }).toList(),
    );
  }
}

class _PaymentsYearCard extends StatelessWidget {
  final int hiddenCount;
  final int year;
  final bool expanded;
  final int paymentsCount;
  final double totalAmount;
  final VoidCallback onToggle;
  final Widget child;
  final int shiftsCount;
  final int monthsCount;
  final bool canToggleList;
  final bool showAllInYear;
  final VoidCallback onToggleShowMore;
  final Color accentColor;

  const _PaymentsYearCard({
    required this.hiddenCount,
    required this.year,
    required this.expanded,
    required this.paymentsCount,
    required this.totalAmount,
    required this.onToggle,
    required this.child,
    required this.shiftsCount,
    required this.monthsCount,
    required this.canToggleList,
    required this.showAllInYear,
    required this.onToggleShowMore,
    required this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(8, 6, 8, 2),
      decoration: BoxDecoration(
        color: kHistoryPanelBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: kBorderSoft,
          width: 1,
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Column(
          children: [
            InkWell(
              onTap: onToggle,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: kHistoryCardHeadBg,
                  border: Border(
                    bottom: BorderSide(color: kDividerSoft),
                  ),
                ),
                child: Row(
                  children: [
                    const SizedBox(width: 10),
                    Text(
                      '$year',
                      style: const TextStyle(
                        color: kTextPrimary,
                        fontWeight: FontWeight.w900,
                        fontSize: 15,
                        letterSpacing: 0.6,
                      ),
                    ),
                    const Spacer(),
                    Icon(
                      expanded ? Icons.expand_less : Icons.expand_more,
                      color: kTextSecondary,
                    ),
                  ],
                ),
              ),
            ),

            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 6),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.center,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _miniStat(
                      icon: Icons.view_module_rounded,
                      text: '${fmtCompactInt(monthsCount)} m.',
                    ),
                    _dotGap(),
                    _miniStat(
                      icon: Icons.work_history_rounded,
                      text: '${fmtCompactInt(shiftsCount)} sh.',
                    ),
                    _dotGap(),
                    _miniStat(
                      icon: Icons.receipt_long,
                      text: '${fmtCompactInt(paymentsCount)} pay.',
                    ),
                    _dotGap(),
                    _miniStat(
                      icon: Icons.payments_rounded,
                      text: fmtMoneyCompact(totalAmount),
                    ),
                  ],
                ),
              ),
            ),

            AnimatedCrossFade(
              duration: const Duration(milliseconds: 220),
              crossFadeState: expanded
                  ? CrossFadeState.showFirst
                  : CrossFadeState.showSecond,
              firstChild: Padding(
                padding: const EdgeInsets.fromLTRB(0, 0, 0, 10),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxHeight: 360,
                  ),
                  child: ScrollConfiguration(
                    behavior: const _NoScrollbarNoGlow(),
                    child: SingleChildScrollView(
                      physics: const BouncingScrollPhysics(),
                      child: child,
                    ),
                  ),
                ),
              ),
              secondChild: const SizedBox.shrink(),
            ),

            if (expanded && canToggleList) ...[
              Container(height: 1, color: kDividerSoft),
              InkWell(
                onTap: onToggleShowMore,
                child: Container(
                  width: double.infinity,
                  height: 38,
                  alignment: Alignment.center,
                  color: kHistoryCardBg,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        showAllInYear
                            ? Icons.keyboard_arrow_up_rounded
                            : Icons.keyboard_arrow_down_rounded,
                        size: 22,
                        color: kTextSecondary,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        showAllInYear
                            ? 'Show less'
                            : 'Show more ($hiddenCount)',
                        style: const TextStyle(
                          color: kTextSecondary,
                          fontWeight: FontWeight.w900,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _dot() => const Text(
    '·',
    style: TextStyle(color: kTextMuted, fontSize: 16),
  );

  Widget _dotGap() => Row(
    children: const [
      SizedBox(width: 8),
      Text(
        '·',
        style: TextStyle(color: kTextMuted, fontSize: 16),
      ),
      SizedBox(width: 8),
    ],
  );

  Widget _miniStat({
    required IconData icon,
    required String text,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(width: 2),
        Icon(icon, size: 14, color: accentColor),
        const SizedBox(width: 6),
        Text(
          text,
          style: const TextStyle(
            color: kTextSecondary,
            fontWeight: FontWeight.w800,
            fontSize: 13,
          ),
        ),
      ],
    );
  }
}



String fmtMoneyCompact(num value) {
  final v = value.toDouble().abs();

  String core;
  if (v < 1000) {
    core = v.toStringAsFixed(0);
  } else if (v < 10000) {
    core = (v / 1000).toStringAsFixed(2); // 1.03K
    core = core.replaceAll(RegExp(r'\.?0+$'), ''); // убрать .00 / .0
    core = '${core}K';
  } else if (v < 100000) {
    core = (v / 1000).toStringAsFixed(1); // 10.3K
    core = core.replaceAll(RegExp(r'\.?0+$'), '');
    core = '${core}K';
  } else if (v < 1000000) {
    core = (v / 1000).toStringAsFixed(0); // 120K
    core = '${core}K';
  } else if (v < 10000000) {
    core = (v / 1000000).toStringAsFixed(2); // 1.23M
    core = core.replaceAll(RegExp(r'\.?0+$'), '');
    core = '${core}M';
  } else {
    core = (v / 1000000).toStringAsFixed(1); // 12.3M
    core = core.replaceAll(RegExp(r'\.?0+$'), '');
    core = '${core}M';
  }

  final sign = value.isNegative ? '-' : '';
  return '$sign$core';
}

String _monthKeyOf(Map<String, dynamic> r) {
  final d = DateTime.parse(r['start_time']).toLocal();
  return '${d.year}-${d.month.toString().padLeft(2, '0')}';
}

String _monthTitleFromKey(String key) {
  final parts = key.split('-');
  final y = int.parse(parts[0]);
  final m = int.parse(parts[1]);
  final d = DateTime(y, m, 1);
  return DateFormat.MMMM().format(d); // "January"
}

Map<String, List<Map<String, dynamic>>> _groupPaidByMonth(
    List<Map<String, dynamic>> paid,
    ) {
  final map = <String, List<Map<String, dynamic>>>{};

  for (final r in paid) {
    final k = _monthKeyOf(r);
    map.putIfAbsent(k, () => []);
    map[k]!.add(r);
  }

  return map;
}

// class _ShowMoreButton extends StatelessWidget {
//   final String text;
//   final VoidCallback onTap;
//   const _ShowMoreButton({required this.text, required this.onTap});
//
//   @override
//   Widget build(BuildContext context) {
//     return InkWell(
//       onTap: onTap,
//       borderRadius: BorderRadius.circular(14),
//       child: Container(
//         padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
//         decoration: BoxDecoration(
//           color: Colors.white.withOpacity(0.05),
//           borderRadius: BorderRadius.circular(14),
//           border: Border.all(color: Colors.white.withOpacity(0.08)),
//         ),
//         child: Row(
//           mainAxisSize: MainAxisSize.min,
//           children: [
//             const Icon(Icons.expand_more_rounded, color: Colors.white70, size: 18),
//             const SizedBox(width: 8),
//             Text(
//               text,
//               style: const TextStyle(
//                 color: Colors.white70,
//                 fontWeight: FontWeight.w800,
//                 letterSpacing: 0.2,
//               ),
//             ),
//           ],
//         ),
//       ),
//     );
//   }
// }



Widget _dotGapTight() => const Padding(
  padding: EdgeInsets.symmetric(horizontal: 6),
  child: Text('·', style: TextStyle(color: Colors.white38, fontSize: 16)),
);

int shiftsCountForPayments(List<Map<String, dynamic>> list) {
  return list.fold<int>(0, (s, p) {
    final items = List<Map<String, dynamic>>.from(p['payment_items'] ?? const []);
    return s + items.length;
  });
}

int monthsCountForPayments(List<Map<String, dynamic>> list) {
  final months = <String>{};

  for (final p in list) {
    final items = List<Map<String, dynamic>>.from(p['payment_items'] ?? const []);
    for (final it in items) {
      final wl = it['work_logs'];
      if (wl == null) continue;

      final start = DateTime.parse(wl['start_time']).toLocal();
      final key = '${start.year}-${start.month.toString().padLeft(2, '0')}';
      months.add(key);
    }
  }

  return months.length;
}

class _NoScrollbarNoGlow extends ScrollBehavior {
  const _NoScrollbarNoGlow();

  @override
  Widget buildScrollbar(
      BuildContext context,
      Widget child,
      ScrollableDetails details,
      ) {
    return child; // скрыть бегунок
  }

  @override
  Widget buildOverscrollIndicator(
      BuildContext context,
      Widget child,
      ScrollableDetails details,
      ) {
    return child; // убрать glow
  }
}

class _ShowMoreButton extends StatelessWidget {
  final String text;
  final VoidCallback onTap;

  const _ShowMoreButton({
    required this.text,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        height: 38,
        width: double.infinity,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          color: kHistoryCardBg,
          border: Border.all(
            color: Colors.white.withOpacity(0.06),
          ),
        ),
        child: Text(
          text,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w900,
            color: Colors.white70,
            letterSpacing: 0.3,
          ),
        ),
      ),
    );
  }
}
class _WorkerDetailsBackgroundBase extends StatelessWidget {
  const _WorkerDetailsBackgroundBase();

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

class _WorkerLiveDot extends StatefulWidget {
  final bool isOnShift;
  final bool isSuspended;

  const _WorkerLiveDot({
    required this.isOnShift,
    required this.isSuspended,
  });

  @override
  State<_WorkerLiveDot> createState() => _WorkerLiveDotState();
}

class _WorkerLiveDotState extends State<_WorkerLiveDot> {
  bool _visible = true;

  @override
  void initState() {
    super.initState();
    _blink();
  }

  Future<void> _blink() async {
    while (mounted && widget.isOnShift && !widget.isSuspended) {
      await Future.delayed(const Duration(milliseconds: 700));
      if (!mounted) return;
      setState(() => _visible = !_visible);
    }
  }

  @override
  Widget build(BuildContext context) {
    final Color color = widget.isSuspended
        ? kSuspendedAccent
        : (widget.isOnShift ? Colors.greenAccent : Colors.white38);

    return AnimatedOpacity(
      opacity: (widget.isOnShift && !widget.isSuspended)
          ? (_visible ? 1 : 0.30)
          : 1,
      duration: const Duration(milliseconds: 260),
      child: Container(
        width: 22,
        height: 22,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color,
          border: Border.all(
            color: Colors.black.withOpacity(0.22),
            width: 1.2,
          ),
          boxShadow: [
            BoxShadow(
              color: color.withOpacity(
                widget.isOnShift && !widget.isSuspended ? 0.55 : 0.18,
              ),
              blurRadius: 10,
              spreadRadius: 1,
            ),
          ],
        ),
      ),
    );
  }
}

class _WorkerModePill extends StatelessWidget {
  final String mode;

  const _WorkerModePill({
    required this.mode,
  });

  @override
  Widget build(BuildContext context) {
    late final String text;
    late final Color color;

    switch (mode) {
      case 'suspended':
        text = 'SUSPENDED';
        color = kSuspendedAccent;
        break;
      case 'view_only':
        text = 'VIEW';
        color = Colors.amber;
        break;
      default:
        text = 'ACTIVE';
        color = Colors.lightBlueAccent;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withOpacity(0.22)),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w900,
          letterSpacing: 0.6,
        ),
      ),
    );
  }
}

Widget _summaryPlainRow({
  required IconData icon,
  required String value,
  Color iconColor = Colors.white,
  Color textColor = Colors.white,
}) {
  return Row(
    children: [
      Icon(
        icon,
        size: 20,
        color: iconColor,
      ),
      const SizedBox(width: 12),
      Expanded(
        child: Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: textColor,
            fontSize: 14,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    ],
  );
}

Widget _summaryLabeledPlainRow({
  required IconData icon,
  required String label,
  required String value,
  required Color accent,
}) {
  return Row(
    children: [
      Icon(
        icon,
        size: 20,
        color: accent,
      ),
      const SizedBox(width: 12),
      Text(
        label,
        style: TextStyle(
          color: Colors.white.withOpacity(0.72),
          fontSize: 13,
          fontWeight: FontWeight.w700,
        ),
      ),
      const Spacer(),
      Text(
        value,
        style: TextStyle(
          color: accent,
          fontSize: 13.5,
          fontWeight: FontWeight.w900,
        ),
      ),
    ],
  );
}
class _ActiveHeaderBlinkIcon extends StatefulWidget {
  final IconData icon;

  const _ActiveHeaderBlinkIcon({
    super.key,
    required this.icon,
  });

  @override
  State<_ActiveHeaderBlinkIcon> createState() => _ActiveHeaderBlinkIconState();
}

class _ActiveHeaderBlinkIconState extends State<_ActiveHeaderBlinkIcon>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _t;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 950),
    )..repeat(reverse: true);

    _t = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeInOut,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final baseColor = Colors.white.withValues(alpha: 0.92);

    return AnimatedBuilder(
      animation: _t,
      builder: (_, __) {
        final color = Color.lerp(baseColor, Colors.orangeAccent, _t.value)!;
        final scale = lerpDouble(1.0, 1.10, _t.value)!;
        final glow = lerpDouble(0, 10, _t.value)!;

        return Transform.scale(
          scale: scale,
          child: Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.orangeAccent.withValues(alpha: 0.28 * _t.value),
                  blurRadius: glow,
                  spreadRadius: 0.2,
                ),
              ],
            ),
            child: Icon(
              widget.icon,
              size: 18,
              color: color,
            ),
          ),
        );
      },
    );
  }
}

class _SectionEmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final List<Color> gradientColors;

  const _SectionEmptyState({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.gradientColors,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(12, 10, 12, 14),
      padding: const EdgeInsets.fromLTRB(18, 20, 18, 20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: gradientColors,
        ),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: Column(
        children: [
          Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              color: Colors.white.withOpacity(0.05),
              border: Border.all(color: Colors.white.withOpacity(0.08)),
            ),
            child: Icon(
              icon,
              size: 28,
              color: Colors.white.withOpacity(0.56),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            title,
            style: const TextStyle(
              color: kTextPrimary,
              fontWeight: FontWeight.w900,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white.withOpacity(0.56),
              fontWeight: FontWeight.w700,
              fontSize: 13,
              height: 1.25,
            ),
          ),
        ],
      ),
    );
  }
}