import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../models/client_model.dart';
import '../models/invoice_item_model.dart';
import '../models/invoice_model.dart';
import '../models/property_model.dart';
import '../utils/estimate_formatters.dart';
import '../utils/company_logo_helper.dart';

class InvoicePdfService {
  InvoicePdfService._();

  static Future<Uint8List> buildInvoicePdf({
    required InvoiceModel invoice,
    required List<InvoiceItemModel> items,
    ClientModel? client,
    PropertyModel? property,
    String companyName = 'Your Company Name',
    String? companyEmail,
    String? companyPhone,
    String? companyAddress,
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
              invoice: invoice,
              companyName: companyName,
              companyEmail: companyEmail,
              companyPhone: companyPhone,
              companyAddress: companyAddress,
              logoImage: logoImage,
            ),
            pw.SizedBox(height: 18),
            _buildInfoSection(
              invoice: invoice,
              clientName: clientName,
              companyName: company,
              address: address,
            ),
            pw.SizedBox(height: 20),
            _buildItemsTable(items),
            pw.SizedBox(height: 20),
            _buildTotalsSection(invoice),
            pw.SizedBox(height: 20),
            _buildTermsSection(invoice.terms),
            pw.SizedBox(height: 16),
            _buildPaymentInstructionsSection(invoice.paymentInstructions),
            pw.SizedBox(height: 16),
            _buildNotesSection(invoice.notes),
            pw.SizedBox(height: 28),
            _buildFooter(),
          ];
        },
      ),
    );

    return pdf.save();
  }

  static Future<void> previewInvoicePdf({
    required InvoiceModel invoice,
    required List<InvoiceItemModel> items,
    ClientModel? client,
    PropertyModel? property,
    String companyName = 'Your Company Name',
    String? companyEmail,
    String? companyPhone,
    String? companyAddress,
    String? companyLogoUrl,
  }) async {
    await Printing.layoutPdf(
      name: _fileNameFromInvoice(invoice),
      onLayout: (_) => buildInvoicePdf(
        invoice: invoice,
        items: items,
        client: client,
        property: property,
        companyName: companyName,
        companyEmail: companyEmail,
        companyPhone: companyPhone,
        companyAddress: companyAddress,
        companyLogoUrl: companyLogoUrl,
      ),
    );
  }

  static Future<void> shareInvoicePdf({
    required InvoiceModel invoice,
    required List<InvoiceItemModel> items,
    ClientModel? client,
    PropertyModel? property,
    String companyName = 'Your Company Name',
    String? companyEmail,
    String? companyPhone,
    String? companyAddress,
    String? companyLogoUrl,
  }) async {
    final bytes = await buildInvoicePdf(
      invoice: invoice,
      items: items,
      client: client,
      property: property,
      companyName: companyName,
      companyEmail: companyEmail,
      companyPhone: companyPhone,
      companyAddress: companyAddress,
      companyLogoUrl: companyLogoUrl,
    );

    await Printing.sharePdf(
      bytes: bytes,
      filename: _fileNameFromInvoice(invoice),
    );
  }

  static String _fileNameFromInvoice(InvoiceModel invoice) {
    final invoiceNumber = invoice.invoiceNumber.trim().isEmpty
        ? 'invoice'
        : invoice.invoiceNumber.trim();

    return '$invoiceNumber.pdf';
  }

  static pw.Widget _buildHeader({
    required InvoiceModel invoice,
    required String companyName,
    String? companyEmail,
    String? companyPhone,
    String? companyAddress,
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
                if ((companyAddress ?? '').trim().isNotEmpty)
                  pw.Text(
                    companyAddress!.trim(),
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
                  'INVOICE',
                  style: pw.TextStyle(
                    fontSize: 14,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.SizedBox(height: 4),
                pw.Text(
                  invoice.invoiceNumber,
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
    required InvoiceModel invoice,
    required String clientName,
    required String companyName,
    required String address,
  }) {
    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Expanded(
          child: _infoCard(
            title: 'Bill To',
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
            title: 'Invoice Info',
            lines: [
              'Status: ${_statusLabel(invoice.status)}',
              'Issue Date: ${EstimateFormatters.formatDate(invoice.issueDate)}',
              'Due Date: ${EstimateFormatters.formatDate(invoice.dueDate)}',
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

  static pw.Widget _buildItemsTable(List<InvoiceItemModel> items) {
    final rows = items.isEmpty
        ? [
      ['No items', '', '', '', '']
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
          cellStyle: const pw.TextStyle(fontSize: 9.5),
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

  static pw.Widget _buildTotalsSection(InvoiceModel invoice) {
    return pw.Align(
      alignment: pw.Alignment.centerRight,
      child: pw.Container(
        width: 240,
        padding: const pw.EdgeInsets.all(12),
        decoration: pw.BoxDecoration(
          border: pw.Border.all(color: PdfColors.grey400, width: 0.8),
          borderRadius: pw.BorderRadius.circular(8),
        ),
        child: pw.Column(
          children: [
            _totalRow('Subtotal', EstimateFormatters.formatCurrency(invoice.subtotal)),
            pw.SizedBox(height: 6),
            _totalRow('Tax', EstimateFormatters.formatCurrency(invoice.tax)),
            pw.SizedBox(height: 6),
            _totalRow(
              'Discount',
              '- ${EstimateFormatters.formatCurrency(invoice.discount)}',
            ),
            pw.Divider(height: 16, color: PdfColors.grey500),
            _totalRow('Total', EstimateFormatters.formatCurrency(invoice.total), bold: true),
            pw.SizedBox(height: 8),
            _totalRow('Paid', EstimateFormatters.formatCurrency(invoice.paidAmount)),
            pw.SizedBox(height: 6),
            _totalRow(
              'Balance Due',
              EstimateFormatters.formatCurrency(invoice.balanceDue),
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

  static pw.Widget _buildTermsSection(String? termsText) {
    final terms = (termsText ?? '').trim();

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          'Terms',
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
            terms.isEmpty ? 'No terms provided.' : terms,
            style: const pw.TextStyle(fontSize: 10, lineSpacing: 3),
          ),
        ),
      ],
    );
  }

  static pw.Widget _buildPaymentInstructionsSection(String? instructionsText) {
    final instructions = (instructionsText ?? '').trim();

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          'Payment Instructions',
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
            instructions.isEmpty
                ? 'No payment instructions provided.'
                : instructions,
            style: const pw.TextStyle(fontSize: 10, lineSpacing: 3),
          ),
        ),
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
          'Thank you for your business.',
          style: const pw.TextStyle(fontSize: 10),
        ),
      ],
    );
  }

  static String _statusLabel(String status) {
    switch (status) {
      case 'draft':
        return 'Draft';
      case 'sent':
        return 'Sent';
      case 'partial':
        return 'Partial';
      case 'paid':
        return 'Paid';
      case 'overdue':
        return 'Overdue';
      case 'void':
        return 'Void';
      default:
        return 'Unknown';
    }
  }
}