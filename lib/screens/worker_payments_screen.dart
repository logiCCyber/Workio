import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'dart:typed_data';
import 'dart:ui';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';

import '../services/worker_service.dart';
import '../widgets/worker_range_calendar_sheet.dart';
import '../widgets/quick_calculator_sheet.dart';
import 'worker_history_screen.dart' show HistoryPalette;

const _kBlueTintTop = Color(0xFF31343B);
const _kBlueTintMid = Color(0xFF272A31);
const _kBlueTintBot = Color(0xFF1D2027);

const _kBlueCardTop = Color(0xFF262A31);
const _kBlueCardMid = Color(0xFF21252D);
const _kBlueCardBot = Color(0xFF1C2027);

const _kBlueInnerTop = Color(0xFF242A32);
const _kBlueInnerBot = Color(0xFF171C23);

class WorkerPaymentsScreen extends StatefulWidget {
  final String workerEmail;
  final String? avatarUrl;
  final double hourlyRate;
  final String? workerId;

  const WorkerPaymentsScreen({
    super.key,
    required this.workerEmail,
    required this.avatarUrl,
    required this.hourlyRate,
    required this.workerId,
  });

  @override
  State<WorkerPaymentsScreen> createState() => _WorkerPaymentsScreenState();
}

enum _WorkerPaymentsFilter {
  all,
  paid,
  pending,
}

const Duration _kExpandDuration = Duration(milliseconds: 260);
const Duration _kFastDuration = Duration(milliseconds: 220);

class _WorkerPaymentsScreenState extends State<WorkerPaymentsScreen> {
  final WorkerService _service = WorkerService();

  bool _loading = true;
  DateTimeRange? _searchRange;
  _WorkerPaymentsFilter _filter = _WorkerPaymentsFilter.all;

  final Map<String, bool> _expandedGroups = {};
  final Map<int, bool> _expandedYears = {};
  final Map<String, bool> _expandedMonths = {};
  List<Map<String, dynamic>> _rows = [];

  @override
  void initState() {
    super.initState();
    _load();
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
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;

      setState(() => _loading = false);

      _showGlassSnack(
        text: 'Failed to load payments',
        icon: Icons.error_outline_rounded,
        accent: const Color(0xFFFF8A7A),
      );
    }
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

  bool _isPaid(Map<String, dynamic> row) {
    final paidAt = row['paid_at'];
    final status = (row['payment_status'] ?? '').toString().toLowerCase();
    return paidAt != null || status == 'paid';
  }

  String _money(double v) => '\$${v.toStringAsFixed(2)}';

  Future<void> _pickSearchRange() async {
    final picked = await showWorkerRangeCalendarSheet(
      context: context,
      initialRange: _searchRange,
      workDays: _workDays,
      isPayments: true,
    );

    if (picked == null) return;

    setState(() {
      _searchRange = picked;
    });
  }

  Future<void> _exportPdf() async {
    if (_searchRange == null) {
      if (!mounted) return;
      _showGlassSnack(
        text: 'Select a period first',
        icon: Icons.date_range_rounded,
        accent: const Color(0xFFFFC14D),
      );
      return;
    }

    if (_paidGroupsForTopPdf.isEmpty) {
      if (!mounted) return;
      _showGlassSnack(
        text: 'No paid payments found for the selected period',
        icon: Icons.info_outline_rounded,
        accent: const Color(0xFF68A8FF),
      );
      return;
    }

    await _showTopPdfActionsSheet();
  }

  String _workerDisplayName() {
    final email = widget.workerEmail.trim();
    if (email.isEmpty) return 'Worker';

    final raw = email
        .split('@')
        .first
        .replaceAll('.', ' ')
        .replaceAll('_', ' ')
        .trim();

    if (raw.isEmpty) return email;

    return raw
        .split(' ')
        .where((e) => e.trim().isNotEmpty)
        .map((e) => e[0].toUpperCase() + e.substring(1))
        .join(' ');
  }

  String _workerInitial() {
    final name = _workerDisplayName().trim();
    if (name.isEmpty) return 'W';
    return name[0].toUpperCase();
  }

  String _pdfRangeText() {
    if (_searchRange == null) return 'All periods';

    final from = DateFormat('MMM d, yyyy').format(_searchRange!.start);
    final to = DateFormat('MMM d, yyyy').format(_searchRange!.end);
    return '$from - $to';
  }

  String _pdfFilterText() {
    switch (_filter) {
      case _WorkerPaymentsFilter.all:
        return 'All';
      case _WorkerPaymentsFilter.paid:
        return 'Paid only';
      case _WorkerPaymentsFilter.pending:
        return 'Pending only';
    }
  }

  String _pdfFileName({_WorkerPaymentGroup? group}) {
    if (group == null) {
      final stamp = DateFormat('yyyyMMdd-HHmm').format(DateTime.now());
      return 'worker-payments-report-$stamp.pdf';
    }

    final start = DateFormat('yyyyMMdd').format(group.periodStart);
    final end = DateFormat('yyyyMMdd').format(group.periodEnd);
    return 'worker-payment-$start-$end.pdf';
  }

  double _rowHours(Map<String, dynamic> row) {
    final start = _dt(row['start_time']);
    final end = _dt(row['end_time']);
    if (start == null || end == null) return 0;
    return end.difference(start).inMinutes / 60.0;
  }

  String _hoursText(double hours) {
    return hours.toStringAsFixed(2);
  }

  bool get _canExportTopPdf {
    return _searchRange != null && _paidGroupsForTopPdf.isNotEmpty;
  }

  Future<Uint8List> _buildTopRangePdfBytes() async {
    return _buildPdfBytes(
      groups: _paidGroupsForTopPdf,
      title: 'Paid Payments Report',
      rangeText: _pdfRangeText(),
      filterText: 'Paid only',
    );
  }

  Future<void> _previewTopPdf() async {
    try {
      final bytes = await _buildTopRangePdfBytes();

      if (!mounted) return;

      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => _PdfPreviewScreen(
            title: 'Paid report preview',
            bytes: bytes,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      _showGlassSnack(
        text: 'Preview failed: $e',
        icon: Icons.visibility_off_rounded,
        accent: const Color(0xFFFF8A7A),
      );
    }
  }

  Future<void> _sendTopPdf() async {
    try {
      final bytes = await _buildTopRangePdfBytes();

      await Printing.sharePdf(
        bytes: bytes,
        filename:
        'paid-payments-${DateFormat('yyyyMMdd').format(_searchRange!.start)}-${DateFormat('yyyyMMdd').format(_searchRange!.end)}.pdf',
      );
    } catch (e) {
      if (!mounted) return;
      _showGlassSnack(
        text: 'Send failed: $e',
        icon: Icons.send_rounded,
        accent: const Color(0xFFFF8A7A),
      );
    }
  }

  Future<void> _saveTopPdf() async {
    try {
      final bytes = await _buildTopRangePdfBytes();
      final dir = await getApplicationDocumentsDirectory();
      final path =
          '${dir.path}/paid-payments-${DateFormat('yyyyMMdd').format(_searchRange!.start)}-${DateFormat('yyyyMMdd').format(_searchRange!.end)}.pdf';

      final file = File(path);
      await file.writeAsBytes(bytes, flush: true);

      if (!mounted) return;

      _showGlassSnack(
        text: 'Saved to: $path',
        icon: Icons.download_done_rounded,
        accent: const Color(0xFF59F0A7),
      );
    } catch (e) {
      if (!mounted) return;
      _showGlassSnack(
        text: 'Save failed: $e',
        icon: Icons.error_outline_rounded,
        accent: const Color(0xFFFF8A7A),
      );
    }
  }

  Future<void> _showTopPdfActionsSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: false,
      builder: (sheetContext) {
        return Container(
          margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                HistoryPalette.cardTop,
                HistoryPalette.cardBottom,
              ],
            ),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: HistoryPalette.cardBorder.withOpacity(0.82),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.28),
                blurRadius: 20,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 42,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.18),
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: const [
                  Icon(
                    Icons.picture_as_pdf_rounded,
                    size: 20,
                    color: Colors.white,
                  ),
                  SizedBox(width: 8),
                  Text(
                    'Paid report PDF',
                    style: TextStyle(
                      color: HistoryPalette.textMain,
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              const Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Only paid payments from the selected period',
                  style: TextStyle(
                    color: HistoryPalette.textSoft,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              _PdfActionTile(
                icon: Icons.visibility_rounded,
                iconColor: const Color(0xFFFFC14D),
                title: 'Preview report',
                subtitle: 'Open PDF preview before sending or saving',
                onTap: () {
                  Navigator.pop(sheetContext);
                  _previewTopPdf();
                },
              ),
              const SizedBox(height: 8),
              _PdfActionTile(
                icon: Icons.send_rounded,
                iconColor: const Color(0xFF68A8FF),
                title: 'Send report',
                subtitle: 'Open share sheet for PDF',
                onTap: () {
                  Navigator.pop(sheetContext);
                  _sendTopPdf();
                },
              ),
              const SizedBox(height: 8),
              _PdfActionTile(
                icon: Icons.download_rounded,
                iconColor: const Color(0xFF59F0A7),
                title: 'Save report',
                subtitle: 'Save PDF file to app documents',
                onTap: () {
                  Navigator.pop(sheetContext);
                  _saveTopPdf();
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<Uint8List> _buildPdfBytesForAction({_WorkerPaymentGroup? group}) async {
    final groups = group == null ? _groups : <_WorkerPaymentGroup>[group];

    final title = group == null
        ? 'Payments Report'
        : 'Payment Statement';

    final rangeText = group == null
        ? _pdfRangeText()
        : _periodText(group.periodStart, group.periodEnd);

    final filterText = group == null
        ? _pdfFilterText()
        : (group.isPaid ? 'Paid' : 'Pending');

    return _buildPdfBytes(
      groups: groups,
      title: title,
      rangeText: rangeText,
      filterText: filterText,
    );
  }

  Future<void> _showPdfActionsSheet({_WorkerPaymentGroup? group}) async {
    final isSingle = group != null;

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: false,
      builder: (sheetContext) {
        return Container(
          margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                HistoryPalette.cardTop,
                HistoryPalette.cardBottom,
              ],
            ),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: HistoryPalette.cardBorder.withOpacity(0.82),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.28),
                blurRadius: 20,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 42,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.18),
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              const SizedBox(height: 14),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  isSingle ? 'Payment PDF' : 'Payments report PDF',
                  style: const TextStyle(
                    color: HistoryPalette.textMain,
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  isSingle
                      ? 'Preview, send or save this payment statement'
                      : 'Preview, send or save the whole payments report',
                  style: const TextStyle(
                    color: HistoryPalette.textSoft,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              _PdfActionTile(
                icon: Icons.visibility_rounded,
                iconColor: const Color(0xFFFFC14D),
                title: 'Preview this payment',
                subtitle: 'Open PDF preview before sending or saving',
                onTap: () {
                  Navigator.pop(sheetContext);
                  _previewPdf(group: group);
                },
              ),
              const SizedBox(height: 8),
              _PdfActionTile(
                icon: Icons.send_rounded,
                iconColor: const Color(0xFF68A8FF),
                title: 'Send this payment',
                subtitle: 'Open share sheet for PDF',
                onTap: () {
                  Navigator.pop(sheetContext);
                  _sendPdf(group: group);
                },
              ),
              const SizedBox(height: 8),
              _PdfActionTile(
                icon: Icons.download_rounded,
                iconColor: const Color(0xFF59F0A7),
                title: 'Save this payment',
                subtitle: 'Save PDF file to app documents',
                onTap: () {
                  Navigator.pop(sheetContext);
                  _savePdf(group: group);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _previewPdf({_WorkerPaymentGroup? group}) async {
    try {
      final bytes = await _buildPdfBytesForAction(group: group);

      if (!mounted) return;

      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => _PdfPreviewScreen(
            title: group == null
                ? 'Payments report preview'
                : 'Payment preview',
            bytes: bytes,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      _showGlassSnack(
        text: 'Preview failed: $e',
        icon: Icons.visibility_off_rounded,
        accent: const Color(0xFFFF8A7A),
      );
    }
  }

  Future<void> _sendPdf({_WorkerPaymentGroup? group}) async {
    try {
      final bytes = await _buildPdfBytesForAction(group: group);

      await Printing.sharePdf(
        bytes: bytes,
        filename: _pdfFileName(group: group),
      );
    } catch (e) {
      if (!mounted) return;
      _showGlassSnack(
        text: 'Send failed: $e',
        icon: Icons.send_rounded,
        accent: const Color(0xFFFF8A7A),
      );
    }
  }

  Future<void> _savePdf({_WorkerPaymentGroup? group}) async {
    try {
      final bytes = await _buildPdfBytesForAction(group: group);
      final dir = await getApplicationDocumentsDirectory();
      final path = '${dir.path}/${_pdfFileName(group: group)}';
      final file = File(path);

      await file.writeAsBytes(bytes, flush: true);

      if (!mounted) return;

      _showGlassSnack(
        text: 'Saved to: $path',
        icon: Icons.download_done_rounded,
        accent: const Color(0xFF59F0A7),
      );
    } catch (e) {
      if (!mounted) return;
      _showGlassSnack(
        text: 'Save failed: $e',
        icon: Icons.error_outline_rounded,
        accent: const Color(0xFFFF8A7A),
      );
    }
  }

  Future<pw.ImageProvider?> _loadAvatarForPdf() async {
    final url = widget.avatarUrl?.trim();
    if (url == null || url.isEmpty) return null;

    try {
      return await networkImage(url);
    } catch (_) {
      return null;
    }
  }

  Future<Uint8List> _buildPdfBytes({
    required List<_WorkerPaymentGroup> groups,
    required String title,
    required String rangeText,
    required String filterText,
  }) async {
    final pdf = pw.Document();
    final avatarImage = await _loadAvatarForPdf();
    final generatedAt =
    DateFormat('MMM d, yyyy - HH:mm').format(DateTime.now());

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(24, 24, 24, 24),
        build: (context) => [
          _buildPdfDocumentHeader(
            title: title,
            generatedAt: generatedAt,
            group: groups.length == 1 ? groups.first : null,
          ),
          pw.SizedBox(height: 14),
          _buildPdfWorkerSection(
            avatarImage: avatarImage,
            group: groups.length == 1 ? groups.first : null,
          ),
          pw.SizedBox(height: 14),
          groups.length == 1
              ? _buildPdfSingleSummarySection(groups.first)
              : _buildPdfSummaryFromGroups(groups),
          pw.SizedBox(height: 18),
          ..._buildPdfPaymentSections(groups),
          pw.SizedBox(height: 16),
          _buildPdfFooterNote(),
        ],
      ),
    );

    return pdf.save();
  }

  pw.Widget _buildPdfDocumentHeader({
    required String title,
    required String generatedAt,
    required _WorkerPaymentGroup? group,
  }) {
    return pw.Container(
      padding: const pw.EdgeInsets.fromLTRB(18, 16, 18, 16),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(
          color: PdfColor.fromHex('#D9DEE6'),
          width: 1,
        ),
        borderRadius: pw.BorderRadius.circular(14),
        color: PdfColors.white,
      ),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  title,
                  style: pw.TextStyle(
                    fontSize: 20,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColor.fromHex('#101828'),
                  ),
                ),
                pw.SizedBox(height: 6),
                pw.Text(
                  'Generated: $generatedAt',
                  style: pw.TextStyle(
                    fontSize: 10,
                    color: PdfColor.fromHex('#667085'),
                  ),
                ),
                pw.SizedBox(height: 3),
                pw.Text(
                  group == null
                      ? 'Range: ${_pdfRangeText()}'
                      : 'Period: ${_periodText(group.periodStart, group.periodEnd)}',
                  style: pw.TextStyle(
                    fontSize: 10,
                    color: PdfColor.fromHex('#667085'),
                  ),
                ),
                pw.SizedBox(height: 3),
                pw.Text(
                  group == null
                      ? 'Filter: ${_pdfFilterText()}'
                      : 'Status: ${group.isPaid ? 'Paid' : 'Pending'}',
                  style: pw.TextStyle(
                    fontSize: 10,
                    color: PdfColor.fromHex('#667085'),
                  ),
                ),
              ],
            ),
          ),
          pw.Container(
            padding: const pw.EdgeInsets.symmetric(
              horizontal: 10,
              vertical: 7,
            ),
            decoration: pw.BoxDecoration(
              color: PdfColors.white,
              borderRadius: pw.BorderRadius.circular(10),
              border: pw.Border.all(
                color: PdfColor.fromHex('#D9DEE6'),
                width: 1,
              ),
            ),
            child: pw.Text(
              group == null
                  ? 'REPORT'
                  : (group.isPaid ? 'PAID' : 'PENDING'),
              style: pw.TextStyle(
                fontSize: 9,
                fontWeight: pw.FontWeight.bold,
                color: group == null
                    ? PdfColor.fromHex('#1D4ED8')
                    : (group.isPaid
                    ? PdfColor.fromHex('#027A48')
                    : PdfColor.fromHex('#B54708')),
              ),
            ),
          ),
        ],
      ),
    );
  }

  pw.Widget _buildPdfWorkerSection({
    required pw.ImageProvider? avatarImage,
    required _WorkerPaymentGroup? group,
  }) {
    final periodOrRange = group == null
        ? _pdfRangeText()
        : _periodText(group.periodStart, group.periodEnd);

    final accountingStatus = group == null
        ? _pdfFilterText()
        : (group.isPaid ? 'Paid' : 'Pending');

    return pw.Container(
      padding: const pw.EdgeInsets.fromLTRB(18, 16, 18, 16),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(
          color: PdfColor.fromHex('#D9DEE6'),
          width: 1,
        ),
        borderRadius: pw.BorderRadius.circular(14),
        color: PdfColors.white,
      ),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Container(
            width: 68,
            height: 68,
            decoration: pw.BoxDecoration(
              color: PdfColor.fromHex('#F2F4F7'),
              borderRadius: pw.BorderRadius.circular(14),
              border: pw.Border.all(
                color: PdfColor.fromHex('#D9DEE6'),
                width: 1,
              ),
            ),
            child: avatarImage != null
                ? pw.ClipRRect(
              horizontalRadius: 14,
              verticalRadius: 14,
              child: pw.Image(
                avatarImage,
                fit: pw.BoxFit.cover,
              ),
            )
                : pw.Center(
              child: pw.Text(
                _workerInitial(),
                style: pw.TextStyle(
                  fontSize: 24,
                  fontWeight: pw.FontWeight.bold,
                  color: PdfColor.fromHex('#344054'),
                ),
              ),
            ),
          ),
          pw.SizedBox(width: 16),
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                _buildPdfInfoLine('Worker', _workerDisplayName()),
                pw.SizedBox(height: 6),
                _buildPdfInfoLine(
                  'Email',
                  widget.workerEmail.trim().isEmpty
                      ? '—'
                      : widget.workerEmail.trim(),
                ),
                pw.SizedBox(height: 6),
                _buildPdfInfoLine(
                  'Shifts',
                  group == null ? '—' : '${group.shiftsCount}',
                ),
                pw.SizedBox(height: 6),
                _buildPdfInfoLine(
                  'Rate',
                  widget.hourlyRate > 0 ? _money(widget.hourlyRate) : '—',
                ),
                pw.SizedBox(height: 6),
                _buildPdfInfoLine(
                  'Payment period',
                  periodOrRange,
                ),
                pw.SizedBox(height: 6),
                _buildPdfInfoLine(
                  'Accounting status',
                  accountingStatus,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }


  pw.Widget _buildPdfInfoLine(String label, String value) {
    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.SizedBox(
          width: 98,
          child: pw.Text(
            '$label:',
            style: pw.TextStyle(
              fontSize: 10,
              fontWeight: pw.FontWeight.bold,
              color: PdfColor.fromHex('#667085'),
            ),
          ),
        ),
        pw.Expanded(
          child: pw.Text(
            value,
            style: pw.TextStyle(
              fontSize: 10.5,
              fontWeight: pw.FontWeight.bold,
              color: PdfColor.fromHex('#101828'),
            ),
          ),
        ),
      ],
    );
  }

  pw.Widget _buildPdfReportSummarySection() {
    return pw.Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        _buildPdfStatCard('Total earned', _money(_visibleTotal)),
        _buildPdfStatCard('Paid', _money(_visiblePaid)),
        _buildPdfStatCard('Pending', _money(_visiblePending)),
        _buildPdfStatCard('Periods', '$_visiblePeriods'),
      ],
    );
  }

  pw.Widget _buildPdfSingleSummarySection(_WorkerPaymentGroup group) {
    final paidAmount = group.isPaid ? group.totalAmount : 0.0;
    final pendingAmount = group.isPaid ? 0.0 : group.totalAmount;
    final paidDateText = group.paidAt == null
        ? '—'
        : DateFormat('MMM d, yyyy').format(group.paidAt!);

    return pw.Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        _buildPdfStatCard('Total earned', _money(group.totalAmount)),
        _buildPdfStatCard('Paid', _money(paidAmount)),
        _buildPdfStatCard('Pending', _money(pendingAmount)),
        _buildPdfStatCard('Paid date', paidDateText),
      ],
    );
  }

  pw.Widget _buildPdfStatCard(String title, String value) {
    return pw.Container(
      width: 120,
      height: 68,
      padding: const pw.EdgeInsets.fromLTRB(10, 8, 10, 8),
      decoration: pw.BoxDecoration(
        borderRadius: pw.BorderRadius.circular(12),
        border: pw.Border.all(
          color: PdfColor.fromHex('#D9DEE6'),
          width: 1,
        ),
        color: PdfColors.white,
      ),
      child: pw.Column(
        mainAxisAlignment: pw.MainAxisAlignment.center,
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        children: [
          pw.Text(
            title.toUpperCase(),
            textAlign: pw.TextAlign.center,
            style: pw.TextStyle(
              fontSize: 8,
              fontWeight: pw.FontWeight.bold,
              color: PdfColor.fromHex('#667085'),
            ),
          ),
          pw.SizedBox(height: 6),
          pw.Text(
            value,
            textAlign: pw.TextAlign.center,
            style: pw.TextStyle(
              fontSize: 13,
              fontWeight: pw.FontWeight.bold,
              color: PdfColor.fromHex('#101828'),
            ),
          ),
        ],
      ),
    );
  }

  pw.Widget _buildPdfSummaryFromGroups(List<_WorkerPaymentGroup> groups) {
    final total = groups.fold<double>(0, (sum, g) => sum + g.totalAmount);
    final paid = groups
        .where((g) => g.isPaid)
        .fold<double>(0, (sum, g) => sum + g.totalAmount);
    final pending = groups
        .where((g) => !g.isPaid)
        .fold<double>(0, (sum, g) => sum + g.totalAmount);

    final paidDates = groups
        .map((g) => g.paidAt)
        .whereType<DateTime>()
        .toList();

    final paidDateText = paidDates.isEmpty
        ? '—'
        : paidDates.length == 1
        ? DateFormat('MMM d, yyyy').format(paidDates.first)
        : 'Multiple';

    return pw.Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        _buildPdfStatCard('Total earned', _money(total)),
        _buildPdfStatCard('Paid', _money(paid)),
        _buildPdfStatCard('Pending', _money(pending)),
        _buildPdfStatCard('Paid date', paidDateText),
      ],
    );
  }

  List<pw.Widget> _buildPdfPaymentSections(List<_WorkerPaymentGroup> groups) {
    final widgets = <pw.Widget>[];
    String? lastMonth;

    for (final group in groups) {
      final monthTitle = DateFormat('MMMM yyyy').format(group.sortDate);

      if (groups.length > 1 && lastMonth != monthTitle) {
        widgets.add(
          pw.Padding(
            padding: const pw.EdgeInsets.only(bottom: 8, top: 2),
            child: pw.Row(
              children: [
                pw.Text(
                  monthTitle.toUpperCase(),
                  style: pw.TextStyle(
                    fontSize: 11,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColor.fromHex('#667085'),
                  ),
                ),
                pw.SizedBox(width: 8),
                pw.Expanded(
                  child: pw.Container(
                    height: 1,
                    color: PdfColor.fromHex('#D9DEE6'),
                  ),
                ),
              ],
            ),
          ),
        );

        lastMonth = monthTitle;
      }

      widgets.add(_buildPdfPaymentSection(group));
      widgets.add(pw.SizedBox(height: 12));
    }

    return widgets;
  }

  pw.Widget _buildPdfPaymentSection(_WorkerPaymentGroup group) {
    final periodText = _periodText(group.periodStart, group.periodEnd);
    final paidText = _paidText(group);
    final paidAmount = group.isPaid ? group.totalAmount : 0.0;
    final pendingAmount = group.isPaid ? 0.0 : group.totalAmount;

    return pw.Container(
      padding: const pw.EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: pw.BoxDecoration(
        borderRadius: pw.BorderRadius.circular(14),
        border: pw.Border.all(
          color: PdfColor.fromHex('#D9DEE6'),
          width: 1,
        ),
        color: PdfColors.white,
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      periodText,
                      style: pw.TextStyle(
                        fontSize: 14,
                        fontWeight: pw.FontWeight.bold,
                        color: PdfColor.fromHex('#101828'),
                      ),
                    ),
                    pw.SizedBox(height: 5),
                    pw.Text(
                      '$paidText - ${group.shiftsCount} shifts - ${_money(group.totalAmount)}',
                      style: pw.TextStyle(
                        fontSize: 10,
                        color: group.isPaid
                            ? PdfColor.fromHex('#027A48')
                            : PdfColor.fromHex('#B54708'),
                      ),
                    ),
                  ],
                ),
              ),
              pw.Container(
                padding: const pw.EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: pw.BoxDecoration(
                  color: PdfColors.white,
                  borderRadius: pw.BorderRadius.circular(10),
                  border: pw.Border.all(
                    color: PdfColor.fromHex('#D9DEE6'),
                    width: 1,
                  ),
                ),
                child: pw.Text(
                  group.isPaid ? 'PAID' : 'PENDING',
                  style: pw.TextStyle(
                    fontSize: 8,
                    fontWeight: pw.FontWeight.bold,
                    color: group.isPaid
                        ? PdfColor.fromHex('#027A48')
                        : PdfColor.fromHex('#B54708'),
                  ),
                ),
              ),
            ],
          ),
          pw.SizedBox(height: 12),
          _buildPdfShiftTable(group.rows),
        ],
      ),
    );
  }

  pw.Widget _buildPdfShiftTable(List<Map<String, dynamic>> rows) {
    return pw.Table(
      border: pw.TableBorder.all(
        color: PdfColor.fromHex('#D9DEE6'),
        width: 0.7,
      ),
      columnWidths: {
        0: const pw.FlexColumnWidth(2.0),
        1: const pw.FlexColumnWidth(1.0),
        2: const pw.FlexColumnWidth(1.0),
        3: const pw.FlexColumnWidth(0.9),
        4: const pw.FlexColumnWidth(0.9),
        5: const pw.FlexColumnWidth(1.2),
      },
      children: [
        pw.TableRow(
          decoration: pw.BoxDecoration(
            color: PdfColor.fromHex('#F2F4F7'),
          ),
          children: [
            _buildPdfTableCell('Date', header: true),
            _buildPdfTableCell('Start', header: true),
            _buildPdfTableCell('End', header: true),
            _buildPdfTableCell('Hours', header: true, align: pw.TextAlign.right),
            _buildPdfTableCell('Rate', header: true, align: pw.TextAlign.right),
            _buildPdfTableCell('Amount', header: true, align: pw.TextAlign.right),
          ],
        ),
        ...rows.map((row) {
          final start = _dt(row['start_time']);
          final end = _dt(row['end_time']);
          final hours = _rowHours(row);
          final dateText =
          start == null ? '—' : DateFormat('MMM d, yyyy').format(start);
          final startText =
          start == null ? '—' : DateFormat('HH:mm').format(start);
          final endText =
          end == null ? '—' : DateFormat('HH:mm').format(end);

          return pw.TableRow(
            children: [
              _buildPdfTableCell(dateText),
              _buildPdfTableCell(startText),
              _buildPdfTableCell(endText),
              _buildPdfTableCell(
                _hoursText(hours),
                align: pw.TextAlign.right,
              ),
              _buildPdfTableCell(
                widget.hourlyRate > 0 ? _money(widget.hourlyRate) : '—',
                align: pw.TextAlign.right,
              ),
              _buildPdfTableCell(
                _money(_num(row['total_payment'])),
                align: pw.TextAlign.right,
              ),
            ],
          );
        }),
      ],
    );
  }

  pw.Widget _buildPdfTableCell(
      String text, {
        bool header = false,
        pw.TextAlign align = pw.TextAlign.left,
      }) {
    return pw.Padding(
      padding: const pw.EdgeInsets.fromLTRB(8, 7, 8, 7),
      child: pw.Text(
        text,
        textAlign: align,
        style: pw.TextStyle(
          fontSize: header ? 8.5 : 9.5,
          fontWeight: header ? pw.FontWeight.bold : pw.FontWeight.normal,
          color: header
              ? PdfColor.fromHex('#344054')
              : PdfColor.fromHex('#101828'),
        ),
      ),
    );
  }

  pw.Widget _buildPdfFooterNote() {
    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.fromLTRB(14, 10, 14, 10),
      decoration: pw.BoxDecoration(
        color: PdfColor.fromHex('#F8FAFC'),
        borderRadius: pw.BorderRadius.circular(12),
        border: pw.Border.all(
          color: PdfColor.fromHex('#E4E7EC'),
          width: 1,
        ),
      ),
      child: pw.Center(
        child: pw.Text(
          'Workio © 2026  Generated automatically for accounting use',
          textAlign: pw.TextAlign.center,
          style: pw.TextStyle(
            fontSize: 9,
            color: PdfColor.fromHex('#667085'),
            fontWeight: pw.FontWeight.bold,
          ),
        ),
      ),
    );
  }

  String _periodText(DateTime start, DateTime end) {
    final sameYear = start.year == end.year;
    final sameMonth = sameYear && start.month == end.month;
    final sameDay = sameMonth && start.day == end.day;

    if (sameDay) {
      return '${start.day}';
    }

    if (sameMonth) {
      return '${start.day} - ${end.day}';
    }

    if (sameYear) {
      return '${DateFormat('MMM d').format(start)} - ${DateFormat('MMM d').format(end)}';
    }

    return '${DateFormat('MMM d, yyyy').format(start)} - ${DateFormat('MMM d, yyyy').format(end)}';
  }

  String _paidText(_WorkerPaymentGroup group) {
    if (group.isPaid && group.paidAt != null) {
      return 'Paid ${DateFormat('MMM d').format(group.paidAt!)}';
    }
    return 'Pending';
  }

  List<Map<String, dynamic>> get _completedRows {
    return _rows.where((row) => _dt(row['end_time']) != null).toList();
  }

  Map<DateTime, List<Map<String, dynamic>>> get _workDays {
    final map = <DateTime, List<Map<String, dynamic>>>{};

    for (final row in _completedRows) {
      final start = _dt(row['start_time']);
      if (start == null) continue;

      final day = DateTime(start.year, start.month, start.day);
      map.putIfAbsent(day, () => []);
      map[day]!.add(row);
    }

    return map;
  }

  bool _matchesSearchRange(Map<String, dynamic> row) {
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
  }

  List<_WorkerPaymentGroup> get _groups {
    final map = <String, List<Map<String, dynamic>>>{};

    for (final row in _completedRows) {
      if (!_matchesSearchRange(row)) continue;

      final paid = _isPaid(row);

      if (_filter == _WorkerPaymentsFilter.paid && !paid) continue;
      if (_filter == _WorkerPaymentsFilter.pending && paid) continue;

      final start = _dt(row['start_time']);
      if (start == null) continue;

      final paidAt = _dt(row['paid_at']);

      String key;

      if (paid && paidAt != null) {
        final paidDay = DateTime(paidAt.year, paidAt.month, paidAt.day);
        key = 'paid-${DateFormat('yyyy-MM-dd').format(paidDay)}';
      } else {
        key =
        'pending-${start.year}-${start.month.toString().padLeft(2, '0')}';
      }

      map.putIfAbsent(key, () => []);
      map[key]!.add(row);
    }

    final groups = map.entries
        .map((e) => _buildGroup(e.key, e.value))
        .toList()
      ..sort((a, b) => b.sortDate.compareTo(a.sortDate));

    return groups;
  }

  List<_WorkerPaymentGroup> get _paidGroupsForTopPdf {
    final map = <String, List<Map<String, dynamic>>>{};

    for (final row in _completedRows) {
      if (!_matchesSearchRange(row)) continue;
      if (!_isPaid(row)) continue;

      final start = _dt(row['start_time']);
      final paidAt = _dt(row['paid_at']);

      if (start == null || paidAt == null) continue;

      final paidDay = DateTime(paidAt.year, paidAt.month, paidAt.day);
      final key = 'paid-${DateFormat('yyyy-MM-dd').format(paidDay)}';

      map.putIfAbsent(key, () => []);
      map[key]!.add(row);
    }

    final groups = map.entries
        .map((e) => _buildGroup(e.key, e.value))
        .toList()
      ..sort((a, b) => b.sortDate.compareTo(a.sortDate));

    return groups;
  }

  _WorkerPaymentGroup _buildGroup(
      String key,
      List<Map<String, dynamic>> rows,
      ) {
    final sorted = List<Map<String, dynamic>>.from(rows)
      ..sort((a, b) {
        final ad = _dt(a['start_time']) ?? DateTime(1970);
        final bd = _dt(b['start_time']) ?? DateTime(1970);
        return ad.compareTo(bd);
      });

    final starts = sorted
        .map((e) => _dt(e['start_time']))
        .whereType<DateTime>()
        .toList();

    final ends = sorted
        .map((e) => _dt(e['end_time']) ?? _dt(e['start_time']))
        .whereType<DateTime>()
        .toList();

    final paidDates = sorted
        .map((e) => _dt(e['paid_at']))
        .whereType<DateTime>()
        .toList();

    final total = sorted.fold<double>(
      0,
          (sum, row) => sum + _num(row['total_payment']),
    );

    final isPaid = sorted.any(_isPaid);

    final start = starts.isNotEmpty ? starts.first : DateTime.now();
    final end = ends.isNotEmpty ? ends.last : start;
    final paidAt = paidDates.isNotEmpty ? paidDates.last : null;
    final sortDate = paidAt ?? end;

    return _WorkerPaymentGroup(
      key: key,
      isPaid: isPaid,
      paidAt: paidAt,
      periodStart: start,
      periodEnd: end,
      shiftsCount: sorted.length,
      totalAmount: total,
      rows: sorted,
      sortDate: sortDate,
    );
  }

  double get _visibleTotal {
    return _groups.fold<double>(0, (sum, g) => sum + g.totalAmount);
  }

  double get _visiblePaid {
    return _groups
        .where((g) => g.isPaid)
        .fold<double>(0, (sum, g) => sum + g.totalAmount);
  }

  double get _visiblePending {
    return _groups
        .where((g) => !g.isPaid)
        .fold<double>(0, (sum, g) => sum + g.totalAmount);
  }

  int get _visibleShifts {
    return _groups.fold<int>(0, (sum, g) => sum + g.shiftsCount);
  }

  int get _visiblePeriods => _groups.length;

  List<_PaymentsYearSection> _buildYearSections(List<_WorkerPaymentGroup> groups) {
    final yearMap = <int, Map<String, List<_WorkerPaymentGroup>>>{};

    for (final group in groups) {
      final year = group.sortDate.year;
      final monthKey =
          '${year}-${group.sortDate.month.toString().padLeft(2, '0')}';

      yearMap.putIfAbsent(year, () => {});
      yearMap[year]!.putIfAbsent(monthKey, () => []);
      yearMap[year]![monthKey]!.add(group);
    }

    final years = yearMap.keys.toList()..sort((a, b) => b.compareTo(a));

    return years.map((year) {
      final monthMap = yearMap[year]!;
      final monthKeys = monthMap.keys.toList()..sort((a, b) => b.compareTo(a));

      final months = monthKeys.map((key) {
        final monthGroups = monthMap[key]!
          ..sort((a, b) => b.sortDate.compareTo(a.sortDate));

        return _PaymentsMonthSection(
          key: key,
          date: monthGroups.first.sortDate,
          groups: monthGroups,
        );
      }).toList();

      return _PaymentsYearSection(
        year: year,
        months: months,
      );
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final groups = _groups;
    final yearSections = _buildYearSections(groups);
    final now = DateTime.now().toLocal();

    final int? defaultYear = yearSections.isEmpty
        ? null
        : yearSections.any((y) => y.year == now.year)
        ? now.year
        : yearSections.first.year;
    return Scaffold(

      backgroundColor: HistoryPalette.bg,
      body: Stack(
        children: [
          const _PaymentsBackground(),
          SafeArea(
            child: Column(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.only(bottom: 18),
                    child: Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                          child: _PaymentsControls(
                            onBack: () => Navigator.pop(context),
                            selectedRange: _searchRange,
                            onPickRange: _pickSearchRange,
                            onClearRange: () {
                              setState(() => _searchRange = null);
                            },
                            onExportPdf: _exportPdf,
                            onOpenCalculator: () => showQuickCalculatorSheet(context: context),
                            pdfEnabled: _canExportTopPdf,
                            current: _filter,
                            onChanged: (value) {
                              setState(() => _filter = value);
                            },
                            periodsCount: '$_visiblePeriods',
                            paidMoney: _money(_visiblePaid),
                            pendingMoney: _money(_visiblePending),
                            shiftsCount: '$_visibleShifts',
                          ),
                        ),
                        if (_loading)
                          const Padding(
                            padding: EdgeInsets.only(top: 120),
                            child: Center(
                              child: CircularProgressIndicator(),
                            ),
                          )
                        else if (yearSections.isEmpty)
                          const Padding(
                            padding: EdgeInsets.only(top: 80),
                            child: _PaymentsEmptyState(),
                          )
                        else
                          AnimatedSwitcher(
                            duration: _kExpandDuration,
                            switchInCurve: Curves.easeOutCubic,
                            switchOutCurve: Curves.easeInCubic,
                            transitionBuilder: (child, animation) {
                              return FadeTransition(
                                opacity: animation,
                                child: SlideTransition(
                                  position: Tween<Offset>(
                                    begin: const Offset(0, 0.03),
                                    end: Offset.zero,
                                  ).animate(animation),
                                  child: child,
                                ),
                              );
                            },
                            child: Padding(
                              key: ValueKey(
                                '${_filter.name}-'
                                    '${_searchRange?.start.toIso8601String() ?? 'no-start'}-'
                                    '${_searchRange?.end.toIso8601String() ?? 'no-end'}-'
                                    '${yearSections.length}',
                              ),
                              padding: const EdgeInsets.fromLTRB(14, 0, 14, 0),
                              child: Column(
                                children: yearSections.map((yearSection) {
                                  final hasCurrentMonth = yearSection.months.any(
                                        (m) => m.date.year == now.year && m.date.month == now.month,
                                  );

                                  final String? defaultMonthKey = yearSection.months.isEmpty
                                      ? null
                                      : hasCurrentMonth
                                      ? yearSection.months.firstWhere(
                                        (m) => m.date.year == now.year && m.date.month == now.month,
                                  ).key
                                      : yearSection.months.first.key;

                                  final yearExpanded =
                                      _expandedYears[yearSection.year] ??
                                          (defaultYear != null && yearSection.year == defaultYear);

                                  return Padding(
                                    padding: const EdgeInsets.only(bottom: 14),
                                    child: _PaymentsYearCard(
                                      year: yearSection.year,
                                      expanded: yearExpanded,
                                      onTap: () {
                                        setState(() {
                                          final willOpen = !yearExpanded;

                                          _expandedYears.clear();
                                          _expandedMonths.clear();
                                          _expandedGroups.clear();

                                          if (willOpen) {
                                            _expandedYears[yearSection.year] = true;

                                            final now = DateTime.now().toLocal();
                                            final hasCurrentMonth = yearSection.months.any(
                                                  (m) => m.date.year == now.year && m.date.month == now.month,
                                            );

                                            if (yearSection.months.isNotEmpty) {
                                              final monthKey = hasCurrentMonth
                                                  ? yearSection.months.firstWhere(
                                                    (m) => m.date.year == now.year && m.date.month == now.month,
                                              ).key
                                                  : yearSection.months.first.key;

                                              _expandedMonths[monthKey] = true;
                                            }
                                          } else {
                                            _expandedYears[yearSection.year] = false;
                                          }
                                        });
                                      },
                                      child: Column(
                                        children: yearSection.months.map((monthSection) {
                                          final monthExpanded =
                                              _expandedMonths[monthSection.key] ??
                                                  (yearExpanded &&
                                                      defaultMonthKey != null &&
                                                      monthSection.key == defaultMonthKey);

                                          return Padding(
                                            padding: const EdgeInsets.only(bottom: 12),
                                            child: _PaymentsMonthCard(
                                              title: DateFormat('MMMM').format(monthSection.date),
                                              expanded: monthExpanded,
                                              onTap: () {
                                                setState(() {
                                                  final willOpen = !monthExpanded;

                                                  _expandedMonths.clear();
                                                  _expandedGroups.clear();

                                                  if (willOpen) {
                                                    _expandedMonths[monthSection.key] = true;
                                                  } else {
                                                    _expandedMonths[monthSection.key] = false;
                                                  }
                                                });
                                              },
                                              child: Column(
                                                children: [
                                                  const SizedBox(height: 12),
                                                  ...monthSection.groups.map((group) {
                                                    final expanded =
                                                        _expandedGroups[group.key] ?? false;

                                                    return Padding(
                                                      padding: const EdgeInsets.only(bottom: 12),
                                                      child: _WorkerPaymentCard(
                                                        group: group,
                                                        expanded: expanded,
                                                        periodText: _periodText(
                                                          group.periodStart,
                                                          group.periodEnd,
                                                        ),
                                                        moneyText: _money(group.totalAmount),
                                                        onTap: () {
                                                          setState(() {
                                                            final willOpen = !expanded;
                                                            _expandedGroups.clear();

                                                            if (willOpen) {
                                                              _expandedGroups[group.key] = true;
                                                            } else {
                                                              _expandedGroups[group.key] = false;
                                                            }
                                                          });
                                                        },
                                                        onPdfTap: () =>
                                                            _showPdfActionsSheet(group: group),
                                                      ),
                                                    );
                                                  }).toList(),
                                                ],
                                              ),
                                            ),
                                          );
                                        }).toList(),
                                      ),
                                    ),
                                  );
                                }).toList(),
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
    );
  }
}

class _WorkerPaymentGroup {
  final String key;
  final bool isPaid;
  final DateTime? paidAt;
  final DateTime periodStart;
  final DateTime periodEnd;
  final int shiftsCount;
  final double totalAmount;
  final List<Map<String, dynamic>> rows;
  final DateTime sortDate;

  const _WorkerPaymentGroup({
    required this.key,
    required this.isPaid,
    required this.paidAt,
    required this.periodStart,
    required this.periodEnd,
    required this.shiftsCount,
    required this.totalAmount,
    required this.rows,
    required this.sortDate,
  });
}

class _PaymentsYearSection {
  final int year;
  final List<_PaymentsMonthSection> months;

  const _PaymentsYearSection({
    required this.year,
    required this.months,
  });
}

class _PaymentsMonthSection {
  final String key;
  final DateTime date;
  final List<_WorkerPaymentGroup> groups;

  const _PaymentsMonthSection({
    required this.key,
    required this.date,
    required this.groups,
  });
}

class _PaymentsYearCard extends StatelessWidget {
  final int year;
  final bool expanded;
  final VoidCallback onTap;
  final Widget child;

  const _PaymentsYearCard({
    required this.year,
    required this.expanded,
    required this.onTap,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            _kBlueCardTop,
            _kBlueCardBot,
          ],
        ),
        borderRadius: BorderRadius.circular(26),
        border: Border.all(
          color: Colors.white.withOpacity(0.08),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.32),
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
              borderRadius: BorderRadius.circular(18),
              onTap: onTap,
              child: Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: const Color(0xFF414449),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: Colors.white.withOpacity(0.08),
                      ),
                    ),
                    child: AnimatedRotation(
                      duration: _kExpandDuration,
                      curve: Curves.easeInOutCubic,
                      turns: expanded ? 0.25 : 0.0,
                      child: const Icon(
                        Icons.chevron_right_rounded,
                        color: Colors.white70,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    '$year',
                    style: const TextStyle(
                      color: HistoryPalette.textMain,
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Container(
                      height: 1,
                      color: Colors.white.withOpacity(0.06),
                    ),
                  ),
                ],
              ),
            ),
          ),
          AnimatedSize(
            duration: _kExpandDuration,
            curve: Curves.easeInOutCubic,
            alignment: Alignment.topCenter,
            child: expanded
                ? Padding(
              padding: const EdgeInsets.only(top: 16),
              child: child,
            )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }
}

class _PaymentsMonthCard extends StatelessWidget {
  final String title;
  final bool expanded;
  final VoidCallback onTap;
  final Widget child;

  const _PaymentsMonthCard({
    required this.title,
    required this.expanded,
    required this.onTap,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF262A31),
            Color(0xFF1C2027),
          ],
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: Colors.white.withOpacity(0.09),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.26),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
          BoxShadow(
            color: Colors.white.withOpacity(0.02),
            blurRadius: 1,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Column(
        children: [
          Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(18),
              onTap: onTap,
              child: Row(
                children: [
                  AnimatedRotation(
                    duration: _kExpandDuration,
                    curve: Curves.easeInOutCubic,
                    turns: expanded ? 0.25 : 0.0,
                    child: const Icon(
                      Icons.chevron_right_rounded,
                      color: Colors.white70,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      '${title[0].toUpperCase()}${title.substring(1)}',
                      style: const TextStyle(
                        color: HistoryPalette.textMain,
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          AnimatedSize(
            duration: _kExpandDuration,
            curve: Curves.easeInOutCubic,
            alignment: Alignment.topCenter,
            child: expanded ? child : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }
}

class _PaymentsBackground extends StatelessWidget {
  const _PaymentsBackground();

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

class _PaymentsListItem {
  final String? header;
  final _WorkerPaymentGroup? group;

  const _PaymentsListItem.header(this.header) : group = null;

  const _PaymentsListItem.group(this.group) : header = null;
}

class _PaymentsMonthHeader extends StatelessWidget {
  final String title;

  const _PaymentsMonthHeader({
    required this.title,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 2, right: 2),
      child: Row(
        children: [
          Text(
            title.toUpperCase(),
            style: const TextStyle(
              color: HistoryPalette.textMute,
              fontSize: 11,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.0,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Container(
              height: 1,
              color: Colors.white.withOpacity(0.08),
            ),
          ),
        ],
      ),
    );
  }
}

class _PaymentsHeader extends StatelessWidget {
  final VoidCallback onBack;

  const _PaymentsHeader({
    required this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0xFF35383C),
            Color(0xFF202327),
          ],
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: Colors.white.withOpacity(0.07),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.30),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          _HeaderActionButton(
            icon: Icons.arrow_back_ios_new_rounded,
            onTap: onBack,
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              'Payments',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: HistoryPalette.textMain,
                fontSize: 20,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.2,
              ),
            ),
          ),
          SizedBox(
            width: 44,
            height: 44,
          ),
        ],
      ),
    );
  }
}

class _HeaderActionButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _HeaderActionButton({
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
                Color(0xFF34373B),
                Color(0xFF23262A),
              ],
            ),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: Colors.white.withOpacity(0.07),
            ),
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

class _PaymentsControls extends StatelessWidget {
  final DateTimeRange? selectedRange;
  final VoidCallback onPickRange;
  final VoidCallback onClearRange;
  final VoidCallback onExportPdf;
  final VoidCallback onOpenCalculator;
  final VoidCallback onBack;
  final bool pdfEnabled;
  final _WorkerPaymentsFilter current;
  final ValueChanged<_WorkerPaymentsFilter> onChanged;

  final String periodsCount;
  final String paidMoney;
  final String pendingMoney;
  final String shiftsCount;

  const _PaymentsControls({
    required this.selectedRange,
    required this.onPickRange,
    required this.onClearRange,
    required this.onBack,
    required this.onExportPdf,
    required this.onOpenCalculator,
    required this.pdfEnabled,
    required this.current,
    required this.onChanged,
    required this.periodsCount,
    required this.paidMoney,
    required this.pendingMoney,
    required this.shiftsCount,
  });

  String _rangeText() {
    if (selectedRange == null) {
      return 'All periods';
    }

    final f = DateFormat('MMM d').format(selectedRange!.start);
    final t = DateFormat('MMM d').format(selectedRange!.end);
    return '$f - $t';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            _kBlueTintTop,
            _kBlueTintMid,
            _kBlueTintBot,
          ],
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: Colors.white.withOpacity(0.07),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.26),
            blurRadius: 22,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              _HeaderActionButton(
                icon: Icons.arrow_back_ios_new_rounded,
                onTap: onBack,
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Payments',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: HistoryPalette.textMain,
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.1,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Track payouts, periods and payment status',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: HistoryPalette.textSoft,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0xFF343941),
                  Color(0xFF262B32),
                ],
              ),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: Colors.white.withOpacity(0.08),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.28),
                  blurRadius: 14,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Row(
              children: [
                Expanded(
                  child: Container(
                    height: 50,
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Color(0xFF242A32),
                          Color(0xFF171C23),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: Colors.white.withOpacity(0.08),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.22),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.date_range_rounded,
                          color: Colors.white54,
                          size: 18,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            _rangeText(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: HistoryPalette.textMain,
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                            ),
                          ),
                        ),
                        if (selectedRange != null)
                          GestureDetector(
                            onTap: onClearRange,
                            child: const Icon(
                              Icons.close_rounded,
                              color: Colors.white54,
                              size: 18,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                _PanelActionButton(
                  icon: Icons.search_rounded,
                  onTap: onPickRange,
                  iconColor: Colors.white.withOpacity(0.92),
                ),
                const SizedBox(width: 8),
                _PanelActionButton(
                  icon: Icons.calculate_rounded,
                  onTap: onOpenCalculator,
                  iconColor: Colors.white.withOpacity(0.92),
                ),
                const SizedBox(width: 8),
                _PanelActionButton(
                  icon: Icons.picture_as_pdf_rounded,
                  onTap: onExportPdf,
                  iconColor: pdfEnabled
                      ? Colors.white.withOpacity(0.92)
                      : Colors.white.withOpacity(0.28),
                  enabled: pdfEnabled,
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              const rightWidth = 118.0;
              const gap = 10.0;
              const statsPanelPadding = 10.0;
              const tileGap = 8.0;

              return IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.all(statsPanelPadding),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Color(0xFF262A31),
                              Color(0xFF1C2027),
                            ],
                          ),
                          borderRadius: BorderRadius.circular(22),
                          border: Border.all(
                            color: Colors.white.withOpacity(0.07),
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.30),
                              blurRadius: 18,
                              offset: const Offset(0, 8),
                            ),
                          ],
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: _CompactStatTile(
                                    width: double.infinity,
                                    title: 'Paid',
                                    value: paidMoney,
                                    accent: HistoryPalette.green,
                                    icon: Icons.check_circle_rounded,
                                  ),
                                ),
                                const SizedBox(width: tileGap),
                                Expanded(
                                  child: _CompactStatTile(
                                    width: double.infinity,
                                    title: 'Pending',
                                    value: pendingMoney,
                                    accent: HistoryPalette.orange,
                                    icon: Icons.schedule_rounded,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: tileGap),
                            Row(
                              children: [
                                Expanded(
                                  child: _CompactStatTile(
                                    width: double.infinity,
                                    title: 'Periods',
                                    value: periodsCount,
                                    accent: const Color(0xFFFFC83A),
                                    icon: Icons.calendar_month_rounded,
                                  ),
                                ),
                                const SizedBox(width: tileGap),
                                Expanded(
                                  child: _CompactStatTile(
                                    width: double.infinity,
                                    title: 'Shifts',
                                    value: shiftsCount,
                                    accent: HistoryPalette.blue,
                                    icon: Icons.work_history_rounded,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: gap),
                    SizedBox(
                      width: rightWidth,
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Color(0xFF262A31),
                              Color(0xFF1C2027),
                            ],
                          ),
                          borderRadius: BorderRadius.circular(22),
                          border: Border.all(
                            color: Colors.white.withOpacity(0.08),
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.36),
                              blurRadius: 18,
                              offset: const Offset(0, 10),
                            ),
                          ],
                        ),
                        child: Column(
                          children: [
                            Expanded(
                              child: _FilterButton(
                                title: 'All',
                                icon: Icons.apps_rounded,
                                accent: const Color(0xFFF5A623),
                                active: current == _WorkerPaymentsFilter.all,
                                onTap: () => onChanged(_WorkerPaymentsFilter.all),
                              ),
                            ),
                            const SizedBox(height: 6),
                            Expanded(
                              child: _FilterButton(
                                title: 'Paid',
                                icon: Icons.check_circle_rounded,
                                accent: const Color(0xFF59F0A7),
                                active: current == _WorkerPaymentsFilter.paid,
                                onTap: () => onChanged(_WorkerPaymentsFilter.paid),
                              ),
                            ),
                            const SizedBox(height: 6),
                            Expanded(
                              child: _FilterButton(
                                title: 'Pending',
                                icon: Icons.schedule_rounded,
                                accent: const Color(0xFF68A8FF),
                                active: current == _WorkerPaymentsFilter.pending,
                                onTap: () => onChanged(_WorkerPaymentsFilter.pending),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _FilterButton extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color accent;
  final bool active;
  final VoidCallback onTap;

  const _FilterButton({
    required this.title,
    required this.icon,
    required this.accent,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedScale(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      scale: active ? 1.0 : 0.985,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            width: double.infinity,
            constraints: const BoxConstraints(minHeight: 46),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: const [
                  Color(0xFF242A32),
                  Color(0xFF171C23),
                ],
              ),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: active
                    ? accent.withOpacity(0.30)
                    : Colors.white.withOpacity(0.07),
                width: active ? 1.1 : 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.22),
                  blurRadius: active ? 14 : 10,
                  offset: const Offset(0, 6),
                ),
                BoxShadow(
                  color: Colors.white.withOpacity(active ? 0.05 : 0.02),
                  blurRadius: 1,
                  offset: const Offset(0, 1),
                ),
              ],
            ),
            child: Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  TweenAnimationBuilder<double>(
                    tween: Tween(begin: 1, end: active ? 1.08 : 1.0),
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeOutBack,
                    builder: (context, scale, child) {
                      return Transform.scale(
                        scale: scale,
                        child: child,
                      );
                    },
                    child: Icon(
                      icon,
                      size: 16,
                      color: active
                          ? accent
                          : Colors.white.withOpacity(0.50),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    title,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: active
                          ? accent
                          : Colors.white.withOpacity(0.50),
                      fontWeight: FontWeight.w800,
                      fontSize: 12.5,
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

class _PaymentsStatTile extends StatelessWidget {
  final String title;
  final String value;
  final Color accent;

  const _PaymentsStatTile({
    required this.title,
    required this.value,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    final width = (MediaQuery.of(context).size.width - 14 - 14 - 10) / 2;

    return Container(
      width: width,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            HistoryPalette.cardTop,
            HistoryPalette.cardBottom,
          ],
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: HistoryPalette.cardBorder.withOpacity(0.82),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title.toUpperCase(),
            style: const TextStyle(
              color: HistoryPalette.textMute,
              fontSize: 10,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(
              color: accent,
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _WorkerPaymentCard extends StatelessWidget {
  final _WorkerPaymentGroup group;
  final bool expanded;
  final String periodText;
  final String moneyText;
  final VoidCallback onTap;
  final VoidCallback onPdfTap;

  const _WorkerPaymentCard({
    required this.group,
    required this.expanded,
    required this.periodText,
    required this.moneyText,
    required this.onTap,
    required this.onPdfTap,
  });

  Color get _statusColor {
    return group.isPaid ? HistoryPalette.green : HistoryPalette.orange;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF343941),
            Color(0xFF262B32),
          ],
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: Colors.white.withOpacity(0.08),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.30),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
          BoxShadow(
            color: Colors.white.withOpacity(0.02),
            blurRadius: 1,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(24),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
            child: Column(
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Row(
                        children: [
                          const Icon(
                            Icons.date_range_rounded,
                            size: 15,
                            color: Colors.white54,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              periodText,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 15,
                                color: HistoryPalette.textMain,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _CardPdfButton(onTap: onPdfTap),
                        const SizedBox(width: 6),
                        AnimatedRotation(
                          duration: _kExpandDuration,
                          curve: Curves.easeInOutCubic,
                          turns: expanded ? 0.25 : 0.0,
                          child: const Icon(
                            Icons.chevron_right_rounded,
                            color: Colors.white70,
                            size: 22,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                AnimatedSize(
                  duration: _kExpandDuration,
                  curve: Curves.easeInOutCubic,
                  alignment: Alignment.topCenter,
                  child: expanded
                      ? Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Color(0xFF1F2328),
                            Color(0xFF14181D),
                          ],
                        ),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(
                          color: Colors.white.withOpacity(0.08),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.18),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [
                                  Color(0xFF223044),
                                  Color(0xFF16202D),
                                ],
                              ),
                              borderRadius: BorderRadius.circular(18),
                              border: Border.all(
                                color: Colors.white.withOpacity(0.08),
                              ),
                            ),
                            child: IntrinsicHeight(
                              child: Row(
                                children: [
                                  Expanded(
                                    child: _ExpandedPaymentStat(
                                      title: 'Earned',
                                      value: moneyText,
                                      color: HistoryPalette.textMain,
                                    ),
                                  ),
                                  Container(
                                    width: 1,
                                    margin: const EdgeInsets.symmetric(vertical: 4),
                                    color: Colors.white.withOpacity(0.08),
                                  ),
                                  Expanded(
                                    child: _ExpandedPaymentStat(
                                      title: 'Paid',
                                      value: group.isPaid ? moneyText : '\$0.00',
                                      color: HistoryPalette.green,
                                    ),
                                  ),
                                  Container(
                                    width: 1,
                                    margin: const EdgeInsets.symmetric(vertical: 4),
                                    color: Colors.white.withOpacity(0.08),
                                  ),
                                  Expanded(
                                    child: _ExpandedPaymentStat(
                                      title: 'Pending',
                                      value: group.isPaid ? '\$0.00' : moneyText,
                                      color: HistoryPalette.orange,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 10),
                          for (int i = 0; i < group.rows.length; i++) ...[
                            _PaymentDetailLine(row: group.rows[i]),
                            if (i != group.rows.length - 1)
                              const SizedBox(height: 8),
                          ],
                        ],
                      ),
                    ),
                  )
                      : const SizedBox.shrink(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ExpandedPaymentStat extends StatelessWidget {
  final String title;
  final String value;
  final Color color;

  const _ExpandedPaymentStat({
    required this.title,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            title.toUpperCase(),
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: HistoryPalette.textMute,
              fontSize: 10,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.7,
            ),
          ),
          const SizedBox(height: 8),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              value,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: color,
                fontSize: 15,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PaymentDetailLine extends StatelessWidget {
  final Map<String, dynamic> row;

  const _PaymentDetailLine({
    required this.row,
  });

  DateTime? _dt(dynamic v) {
    if (v == null) return null;
    try {
      return DateTime.parse(v.toString()).toLocal();
    } catch (_) {
      return null;
    }
  }

  double _num(dynamic v) {
    if (v == null) return 0;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? 0;
  }

  String _money(double v) => '\$${v.toStringAsFixed(2)}';

  String _linePeriodText(DateTime? start, DateTime? end) {
    if (start == null) return '—';

    final safeEnd = end ?? start;
    final sameYear = start.year == safeEnd.year;
    final sameMonth = sameYear && start.month == safeEnd.month;
    final sameDay = sameMonth && start.day == safeEnd.day;

    if (sameDay) {
      return '${start.day} • ${DateFormat('HH:mm').format(start)} - ${DateFormat('HH:mm').format(safeEnd)}';
    }

    if (sameMonth) {
      return '${start.day} - ${safeEnd.day} • ${DateFormat('HH:mm').format(start)} - ${DateFormat('HH:mm').format(safeEnd)}';
    }

    if (sameYear) {
      return '${DateFormat('MMM d').format(start)} • ${DateFormat('HH:mm').format(start)} - ${DateFormat('MMM d').format(safeEnd)} • ${DateFormat('HH:mm').format(safeEnd)}';
    }

    return '${DateFormat('MMM d, yyyy').format(start)} • ${DateFormat('HH:mm').format(start)} - ${DateFormat('MMM d, yyyy').format(safeEnd)} • ${DateFormat('HH:mm').format(safeEnd)}';
  }

  @override
  Widget build(BuildContext context) {
    final start = _dt(row['start_time']);
    final end = _dt(row['end_time']);
    final periodText = _linePeriodText(start, end);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 11, 12, 11),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF242A32),
            Color(0xFF171C23),
          ],
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: Colors.white.withOpacity(0.07),
        ),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.work_history_rounded,
            color: HistoryPalette.textSoft,
            size: 16,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              periodText,
              style: const TextStyle(
                color: HistoryPalette.textMain,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Text(
            _money(_num(row['total_payment'])),
            style: const TextStyle(
              color: HistoryPalette.textMain,
              fontSize: 12,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _PaymentsEmptyState extends StatelessWidget {
  const _PaymentsEmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(18, 20, 18, 20),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                HistoryPalette.cardTop,
                HistoryPalette.cardBottom,
              ],
            ),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: HistoryPalette.cardBorder.withOpacity(0.82),
            ),
          ),
          child: const Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.account_balance_wallet_outlined,
                size: 34,
                color: HistoryPalette.textSoft,
              ),
              SizedBox(height: 10),
              Text(
                'No payments found',
                style: TextStyle(
                  color: HistoryPalette.textMain,
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                ),
              ),
              SizedBox(height: 6),
              Text(
                'Later we will connect real grouped payouts here.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: HistoryPalette.textSoft,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CardPdfButton extends StatelessWidget {
  final VoidCallback onTap;

  const _CardPdfButton({
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: const Color(0xFF2A2F37),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: Colors.white.withOpacity(0.08),
            ),
          ),
          child: const Icon(
            Icons.picture_as_pdf_rounded,
            size: 18,
            color: Colors.white70,
          ),
        ),
      ),
    );
  }
}

class _PdfActionTile extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _PdfActionTile({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
          decoration: BoxDecoration(
            color: HistoryPalette.pill.withOpacity(0.92),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: HistoryPalette.pillBorder.withOpacity(0.95),
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: const Color(0xFF2A2F37),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  icon,
                  color: iconColor,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: HistoryPalette.textMain,
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: HistoryPalette.textSoft,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.chevron_right_rounded,
                color: Colors.white54,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PdfPreviewScreen extends StatelessWidget {
  final String title;
  final Uint8List bytes;

  const _PdfPreviewScreen({
    required this.title,
    required this.bytes,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: HistoryPalette.bg,
      appBar: AppBar(
        backgroundColor: const Color(0xFF12161D),
        elevation: 0,
        title: Text(title),
      ),
      body: PdfPreview(
        build: (_) async => bytes,
        canChangePageFormat: false,
        canChangeOrientation: false,
        canDebug: false,
      ),
    );
  }
}

class _PanelActionButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final Color iconColor;
  final bool enabled;

  const _PanelActionButton({
    required this.icon,
    required this.onTap,
    required this.iconColor,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      duration: _kFastDuration,
      opacity: enabled ? 1 : 0.46,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: enabled ? onTap : null,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0xFF343941),
                  Color(0xFF262B32),
                ],
              ),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: Colors.white.withOpacity(0.07),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.22),
                  blurRadius: 10,
                  offset: const Offset(0, 6),
                ),
                BoxShadow(
                  color: Colors.white.withOpacity(0.02),
                  blurRadius: 1,
                  offset: const Offset(0, 1),
                ),
              ],
            ),
            child: Center(
              child: AnimatedScale(
                duration: _kFastDuration,
                scale: enabled ? 1.0 : 0.96,
                child: Icon(
                  icon,
                  color: iconColor,
                  size: 20,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CompactStatTile extends StatelessWidget {
  final double width;
  final String title;
  final String value;
  final Color accent;
  final IconData icon;

  const _CompactStatTile({
    required this.width,
    required this.title,
    required this.value,
    required this.accent,
    required this.icon,
  });

  bool _looksWhole(double v) {
    return (v - v.roundToDouble()).abs() < 0.05;
  }

  String _compactNumber(double number) {
    final abs = number.abs();

    if (abs >= 1000000000) {
      final short = number / 1000000000;
      return _looksWhole(short)
          ? '${short.toStringAsFixed(0)}B'
          : '${short.toStringAsFixed(1)}B';
    }

    if (abs >= 1000000) {
      final short = number / 1000000;
      return _looksWhole(short)
          ? '${short.toStringAsFixed(0)}M'
          : '${short.toStringAsFixed(1)}M';
    }

    if (abs >= 1000) {
      final short = number / 1000;
      return _looksWhole(short)
          ? '${short.toStringAsFixed(0)}K'
          : '${short.toStringAsFixed(1)}K';
    }

    return _looksWhole(number)
        ? number.toStringAsFixed(0)
        : number.toStringAsFixed(1);
  }

  String _displayValue() {
    final isMoney = value.trim().startsWith('\$');
    final raw = value.replaceAll(RegExp(r'[^0-9.\-]'), '');
    final number = double.tryParse(raw);

    if (number == null) return value;

    if (isMoney) {
      return '\$${_compactNumber(number)}';
    }

    return _compactNumber(number);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: 82,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            _kBlueInnerTop,
            _kBlueInnerBot,
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Colors.white.withOpacity(0.08),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.30),
            blurRadius: 12,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 14,
                color: accent.withOpacity(0.92),
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  title.toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: HistoryPalette.textMute,
                    fontSize: 9,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.8,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            _displayValue(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: accent,
              fontSize: 15,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}