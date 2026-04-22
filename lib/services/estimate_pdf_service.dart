import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../models/client_model.dart';
import '../models/estimate_item_model.dart';
import '../models/estimate_model.dart';
import '../models/property_model.dart';
import '../utils/estimate_formatters.dart';
import '../utils/company_logo_helper.dart';

class EstimatePdfService {
  EstimatePdfService._();

  static Future<Uint8List> buildEstimatePdf({
    required EstimateModel estimate,
    required List<EstimateItemModel> items,
    ClientModel? client,
    PropertyModel? property,
    String companyName = 'Your Company Name',
    String? companyEmail,
    String? companyPhone,
    String? companyLogoUrl,
  }) async {
    final pdf = pw.Document();

    final clientName = client?.fullName.trim().isNotEmpty == true
        ? client!.fullName
        : 'No client';

    final company = (client?.companyName ?? '').trim();
    final address = property?.fullAddress ?? 'No property address';

    pw.ImageProvider? logoImage;

    try {
      final resolvedLogo = (companyLogoUrl ?? '').trim().isNotEmpty
          ? companyLogoUrl!.trim()
          : CompanyLogoHelper.defaultLogoUrl;

      logoImage = await networkImage(resolvedLogo);
    } catch (_) {}

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.letter,
        margin: const pw.EdgeInsets.all(28),
        build: (context) {
          return [
            _buildHeader(
              estimate: estimate,
              companyName: companyName,
              companyEmail: companyEmail,
              companyPhone: companyPhone,
              logoImage: logoImage,
            ),
            pw.SizedBox(height: 18),
            _buildInfoSection(
              estimate: estimate,
              clientName: clientName,
              companyName: company,
              address: address,
            ),
            pw.SizedBox(height: 20),
            _buildScopeSection(estimate.scopeText),
            pw.SizedBox(height: 20),
            _buildItemsTable(items),
            pw.SizedBox(height: 20),
            _buildTotalsSection(estimate),
            pw.SizedBox(height: 20),
            _buildNotesSection(estimate.notes),
            pw.SizedBox(height: 28),
            _buildFooter(),
          ];
        },
      ),
    );

    return pdf.save();
  }

  static Future<void> previewEstimatePdf({
    required EstimateModel estimate,
    required List<EstimateItemModel> items,
    ClientModel? client,
    PropertyModel? property,
    String companyName = 'Your Company Name',
    String? companyEmail,
    String? companyPhone,
    String? companyLogoUrl,
  }) async {
    await Printing.layoutPdf(
      name: _fileNameFromEstimate(estimate),
      onLayout: (_) => buildEstimatePdf(
        estimate: estimate,
        items: items,
        client: client,
        property: property,
        companyName: companyName,
        companyEmail: companyEmail,
        companyPhone: companyPhone,
        companyLogoUrl: companyLogoUrl,
      ),
    );
  }

  static Future<void> shareEstimatePdf({
    required EstimateModel estimate,
    required List<EstimateItemModel> items,
    ClientModel? client,
    PropertyModel? property,
    String companyName = 'Your Company Name',
    String? companyEmail,
    String? companyPhone,
    String? companyLogoUrl,
  }) async {
    final bytes = await buildEstimatePdf(
      estimate: estimate,
      items: items,
      client: client,
      property: property,
      companyName: companyName,
      companyEmail: companyEmail,
      companyPhone: companyPhone,
      companyLogoUrl: companyLogoUrl,
    );

    await Printing.sharePdf(
      bytes: bytes,
      filename: _fileNameFromEstimate(estimate),
    );
  }

  static String _fileNameFromEstimate(EstimateModel estimate) {
    final estimateNumber = estimate.estimateNumber.trim().isEmpty
        ? 'estimate'
        : estimate.estimateNumber.trim();

    return '$estimateNumber.pdf';
  }

  static pw.Widget _buildHeader({
    required EstimateModel estimate,
    required String companyName,
    String? companyEmail,
    String? companyPhone,
    pw.ImageProvider? logoImage,
  }) {
    return pw.Container(
      padding: const pw.EdgeInsets.only(bottom: 14),
      decoration: const pw.BoxDecoration(
        border: pw.Border(
          bottom: pw.BorderSide(
            color: PdfColors.grey400,
            width: 0.8,
          ),
        ),
      ),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          if (logoImage != null)
            pw.Container(
              width: 75,
              height: 56,
              margin: const pw.EdgeInsets.only(right: 12),
              alignment: pw.Alignment.center,
              child: pw.Image(
                logoImage,
                fit: pw.BoxFit.contain,
              ),
            ),
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  companyName,
                  style: pw.TextStyle(
                    fontSize: 24,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.SizedBox(height: 6),
                if ((companyEmail ?? '').trim().isNotEmpty)
                  pw.Text(
                    companyEmail!.trim(),
                    style: const pw.TextStyle(fontSize: 10),
                  ),
                if ((companyPhone ?? '').trim().isNotEmpty)
                  pw.Text(
                    companyPhone!.trim(),
                    style: const pw.TextStyle(fontSize: 10),
                  ),
              ],
            ),
          ),
          pw.Container(
            padding: const pw.EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: pw.BoxDecoration(
              color: PdfColors.grey200,
              borderRadius: pw.BorderRadius.circular(8),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: [
                pw.Text(
                  'ESTIMATE',
                  style: pw.TextStyle(
                    fontSize: 14,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.SizedBox(height: 4),
                pw.Text(
                  estimate.estimateNumber,
                  style: const pw.TextStyle(fontSize: 10),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static pw.Widget _buildInfoSection({
    required EstimateModel estimate,
    required String clientName,
    required String companyName,
    required String address,
  }) {
    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Expanded(
          child: _infoCard(
            title: 'Client',
            lines: [
              clientName,
              if (companyName.trim().isNotEmpty) companyName,
              address,
            ],
          ),
        ),
        pw.SizedBox(width: 14),
        pw.Expanded(
          child: _infoCard(
            title: 'Estimate Info',
            lines: [
              'Status: ${EstimateFormatters.formatStatus(estimate.status)}',
              'Created: ${EstimateFormatters.formatDate(estimate.createdAt)}',
              'Valid Until: ${EstimateFormatters.formatDate(estimate.validUntil)}',
            ],
          ),
        ),
      ],
    );
  }

  static pw.Widget _infoCard({
    required String title,
    required List<String> lines,
  }) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(12),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey400, width: 0.8),
        borderRadius: pw.BorderRadius.circular(8),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            title,
            style: pw.TextStyle(
              fontSize: 11,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          pw.SizedBox(height: 8),
          ...lines.map(
                (line) => pw.Padding(
              padding: const pw.EdgeInsets.only(bottom: 3),
              child: pw.Text(
                line,
                style: const pw.TextStyle(fontSize: 10, lineSpacing: 2),
              ),
            ),
          ),
        ],
      ),
    );
  }

  static pw.Widget _buildScopeSection(String? scopeText) {
    final scope = (scopeText ?? '').trim();

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          'Scope of Work',
          style: pw.TextStyle(
            fontSize: 13,
            fontWeight: pw.FontWeight.bold,
          ),
        ),
        pw.SizedBox(height: 8),
        pw.Container(
          width: double.infinity,
          padding: const pw.EdgeInsets.all(12),
          decoration: pw.BoxDecoration(
            color: PdfColors.grey100,
            borderRadius: pw.BorderRadius.circular(8),
          ),
          child: pw.Text(
            scope.isEmpty ? 'No scope provided.' : scope,
            style: const pw.TextStyle(fontSize: 10, lineSpacing: 3),
          ),
        ),
      ],
    );
  }

  static pw.Widget _buildItemsTable(List<EstimateItemModel> items) {
    final rows = items.isEmpty
        ? [
      [
        'No items',
        '',
        '',
        '',
        '',
      ]
    ]
        : items.map((item) {
      return [
        item.title,
        EstimateFormatters.formatQuantity(item.quantity),
        EstimateFormatters.formatUnit(item.unit),
        EstimateFormatters.formatCurrency(item.unitPrice),
        EstimateFormatters.formatCurrency(item.lineTotal),
      ];
    }).toList();

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          'Items',
          style: pw.TextStyle(
            fontSize: 13,
            fontWeight: pw.FontWeight.bold,
          ),
        ),
        pw.SizedBox(height: 8),
        pw.TableHelper.fromTextArray(
          headerDecoration: const pw.BoxDecoration(
            color: PdfColors.grey300,
          ),
          headerStyle: pw.TextStyle(
            fontSize: 10,
            fontWeight: pw.FontWeight.bold,
          ),
          cellStyle: const pw.TextStyle(
            fontSize: 9.5,
          ),
          cellPadding: const pw.EdgeInsets.all(8),
          columnWidths: {
            0: const pw.FlexColumnWidth(3.2),
            1: const pw.FlexColumnWidth(1),
            2: const pw.FlexColumnWidth(1),
            3: const pw.FlexColumnWidth(1.4),
            4: const pw.FlexColumnWidth(1.5),
          },
          headers: const [
            'Item',
            'Qty',
            'Unit',
            'Unit Price',
            'Line Total',
          ],
          data: rows,
        ),
      ],
    );
  }

  static pw.Widget _buildTotalsSection(EstimateModel estimate) {
    return pw.Align(
      alignment: pw.Alignment.centerRight,
      child: pw.Container(
        width: 230,
        padding: const pw.EdgeInsets.all(12),
        decoration: pw.BoxDecoration(
          border: pw.Border.all(color: PdfColors.grey400, width: 0.8),
          borderRadius: pw.BorderRadius.circular(8),
        ),
        child: pw.Column(
          children: [
            _totalRow('Subtotal', EstimateFormatters.formatCurrency(estimate.subtotal)),
            pw.SizedBox(height: 6),
            _totalRow('Tax', EstimateFormatters.formatCurrency(estimate.tax)),
            pw.SizedBox(height: 6),
            _totalRow(
              'Discount',
              '- ${EstimateFormatters.formatCurrency(estimate.discount)}',
            ),
            pw.Divider(height: 16, color: PdfColors.grey500),
            _totalRow(
              'Total',
              EstimateFormatters.formatCurrency(estimate.total),
              bold: true,
            ),
          ],
        ),
      ),
    );
  }

  static pw.Widget _totalRow(String label, String value, {bool bold = false}) {
    final style = pw.TextStyle(
      fontSize: bold ? 11.5 : 10,
      fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
    );

    return pw.Row(
      children: [
        pw.Text(label, style: style),
        pw.Spacer(),
        pw.Text(value, style: style),
      ],
    );
  }

  static pw.Widget _buildNotesSection(String? notesText) {
    final notes = (notesText ?? '').trim();

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          'Notes',
          style: pw.TextStyle(
            fontSize: 13,
            fontWeight: pw.FontWeight.bold,
          ),
        ),
        pw.SizedBox(height: 8),
        pw.Container(
          width: double.infinity,
          padding: const pw.EdgeInsets.all(12),
          decoration: pw.BoxDecoration(
            color: PdfColors.grey100,
            borderRadius: pw.BorderRadius.circular(8),
          ),
          child: pw.Text(
            notes.isEmpty ? 'No notes provided.' : notes,
            style: const pw.TextStyle(fontSize: 10, lineSpacing: 3),
          ),
        ),
      ],
    );
  }

  static pw.Widget _buildFooter() {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Divider(color: PdfColors.grey400),
        pw.SizedBox(height: 12),
        pw.Text(
          'Thank you for the opportunity to provide this estimate.',
          style: const pw.TextStyle(fontSize: 10),
        ),
        pw.SizedBox(height: 18),
        pw.Row(
          children: [
            pw.Expanded(
              child: pw.Container(
                height: 1,
                color: PdfColors.grey500,
              ),
            ),
            pw.SizedBox(width: 12),
             pw.Text(
              'Authorized Signature',
              style: pw.TextStyle(fontSize: 9),
            ),
          ],
        ),
      ],
    );
  }
}