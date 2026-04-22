import 'package:supabase_flutter/supabase_flutter.dart';

import '../dialogs/send_invoice_dialog.dart';
import '../models/client_model.dart';
import '../models/company_settings_model.dart';
import '../models/invoice_document_model.dart';
import '../models/invoice_email_log_model.dart';
import '../models/invoice_item_model.dart';
import '../models/invoice_model.dart';
import '../models/property_model.dart';
import 'invoice_document_service.dart';
import 'invoice_service.dart';
import '../utils/company_logo_helper.dart';

class SendInvoiceExecutionResult {
  final InvoiceEmailLogModel emailLog;
  final InvoiceDocumentModel attachedDocument;
  final InvoiceModel updatedInvoice;
  final String? providerMessageId;

  const SendInvoiceExecutionResult({
    required this.emailLog,
    required this.attachedDocument,
    required this.updatedInvoice,
    this.providerMessageId,
  });
}

class InvoiceEmailService {
  InvoiceEmailService._();

  static final SupabaseClient _supabase = Supabase.instance.client;
  static const String _logsTable = 'invoice_email_logs';
  static const String _functionName = 'send-invoice-email';

  static String _requireUserId() {
    final user = _supabase.auth.currentUser;

    if (user == null) {
      throw Exception('Пользователь не авторизован');
    }

    return user.id;
  }

  static List<InvoiceEmailLogModel> _mapEmailLogList(dynamic response) {
    final list = response as List;

    return list
        .map(
          (item) => InvoiceEmailLogModel.fromMap(
        item as Map<String, dynamic>,
      ),
    )
        .toList();
  }

  static Future<List<InvoiceEmailLogModel>> getEmailLogsByInvoice(
      String invoiceId,
      ) async {
    final userId = _requireUserId();

    final response = await _supabase
        .from(_logsTable)
        .select()
        .eq('invoice_id', invoiceId)
        .eq('admin_auth_id', userId)
        .order('sent_at', ascending: false);

    return _mapEmailLogList(response);
  }

  static Future<InvoiceDocumentModel?> getLatestDocumentForInvoice(
      String invoiceId,
      ) async {
    final docs = await InvoiceDocumentService.getDocumentsByInvoice(invoiceId);
    if (docs.isEmpty) return null;
    return docs.first;
  }

  static Future<SendInvoiceExecutionResult> sendInvoice({
    required InvoiceModel invoice,
    required List<InvoiceItemModel> items,
    required SendInvoiceDialogResult dialogResult,
    ClientModel? client,
    PropertyModel? property,
    CompanySettingsModel? companySettings,
  }) async {
    final userId = _requireUserId();

    if (invoice.id.trim().isEmpty) {
      throw Exception('Сначала нужно сохранить invoice');
    }

    final attachedDocument = await _resolvePdfDocument(
      invoice: invoice,
      items: items,
      dialogResult: dialogResult,
      client: client,
      property: property,
      companySettings: companySettings,
    );

    final signedUrl = await InvoiceDocumentService.createSignedUrl(
      attachedDocument,
      expiresInSeconds: 60 * 60,
    );

    final companyLogoUrl = CompanyLogoHelper.resolvedLogoUrl(companySettings);

    final payload = {
      'to': dialogResult.recipientEmail,
      'subject': dialogResult.subject,
      'text': dialogResult.messageBody,
      'invoice_id': invoice.id,
      'client_name': client?.fullName,
      'company_name': _companyName(companySettings),
      'company_email': _companyEmail(companySettings),
      'company_phone': _companyPhone(companySettings),
      'company_address': _companyAddress(companySettings),
      'company_logo_url': companyLogoUrl,
      'attachment': {
        'filename': attachedDocument.fileName,
        'path': signedUrl,
      },
    };

    try {
      final response = await _supabase.functions.invoke(
        _functionName,
        body: payload,
      );

      final data = (response.data is Map<String, dynamic>)
          ? response.data as Map<String, dynamic>
          : <String, dynamic>{};

      final providerMessageId = data['id']?.toString() ??
          data['provider_message_id']?.toString();

      final emailLog = await _insertEmailLog(
        invoiceId: invoice.id,
        adminAuthId: userId,
        recipientEmail: dialogResult.recipientEmail,
        subject: dialogResult.subject,
        messageBody: dialogResult.messageBody,
        pdfDocumentId: attachedDocument.id,
        templateType: dialogResult.templateType,
        status: 'sent',
        providerName: 'resend',
        providerMessageId: providerMessageId,
      );

      final shouldMoveToSent =
          invoice.status == 'draft' || invoice.status == 'overdue';

      final updatedInvoice = shouldMoveToSent
          ? await InvoiceService.updateInvoice(
        invoice.copyWith(status: 'sent'),
      )
          : invoice;

      return SendInvoiceExecutionResult(
        emailLog: emailLog,
        attachedDocument: attachedDocument,
        updatedInvoice: updatedInvoice,
        providerMessageId: providerMessageId,
      );
    } catch (e) {
      await _insertEmailLog(
        invoiceId: invoice.id,
        adminAuthId: userId,
        recipientEmail: dialogResult.recipientEmail,
        subject: dialogResult.subject,
        messageBody: dialogResult.messageBody,
        pdfDocumentId: attachedDocument.id,
        templateType: dialogResult.templateType,
        status: 'failed',
        providerName: 'resend',
        providerMessageId: null,
      );

      rethrow;
    }
  }

  static Future<InvoiceDocumentModel> _resolvePdfDocument({
    required InvoiceModel invoice,
    required List<InvoiceItemModel> items,
    required SendInvoiceDialogResult dialogResult,
    ClientModel? client,
    PropertyModel? property,
    CompanySettingsModel? companySettings,
  }) async {
    final existingDocs =
    await InvoiceDocumentService.getDocumentsByInvoice(invoice.id);

    InvoiceDocumentModel? selectedDocument;

    if (dialogResult.useLatestSavedPdf &&
        dialogResult.selectedDocumentId != null &&
        dialogResult.selectedDocumentId!.trim().isNotEmpty) {
      for (final doc in existingDocs) {
        if (doc.id == dialogResult.selectedDocumentId) {
          selectedDocument = doc;
          break;
        }
      }
    }

    selectedDocument ??= existingDocs.isNotEmpty ? existingDocs.first : null;

    if (selectedDocument != null && dialogResult.useLatestSavedPdf) {
      return selectedDocument;
    }

    if (!dialogResult.generateNewPdfIfMissing && selectedDocument == null) {
      throw Exception('Нет PDF для отправки');
    }

    return InvoiceDocumentService.saveInvoicePdf(
      invoice: invoice,
      items: items,
      client: client,
      property: property,
      companyName: _companyName(companySettings),
      companyEmail: _companyEmail(companySettings),
      companyPhone: _companyPhone(companySettings),
      companyAddress: _companyAddress(companySettings),
      companyLogoUrl: CompanyLogoHelper.customLogoUrl(companySettings),
    );
  }

  static String _companyName(CompanySettingsModel? settings) {
    final value = settings?.companyName.trim() ?? '';
    return value.isEmpty ? 'Your Company Name' : value;
  }

  static String? _companyEmail(CompanySettingsModel? settings) {
    final value = settings?.companyEmail?.trim() ?? '';
    return value.isEmpty ? null : value;
  }

  static String? _companyPhone(CompanySettingsModel? settings) {
    final value = settings?.companyPhone?.trim() ?? '';
    return value.isEmpty ? null : value;
  }

  static String? _companyAddress(CompanySettingsModel? settings) {
    final value = settings?.companyAddress?.trim() ?? '';
    return value.isEmpty ? null : value;
  }

  static Future<InvoiceEmailLogModel> _insertEmailLog({
    required String invoiceId,
    required String adminAuthId,
    required String recipientEmail,
    required String subject,
    required String messageBody,
    String? templateType,
    String? pdfDocumentId,
    required String status,
    String? providerName,
    String? providerMessageId,
  }) async {
    final response = await _supabase
        .from(_logsTable)
        .insert({
      'invoice_id': invoiceId,
      'admin_auth_id': adminAuthId,
      'recipient_email': recipientEmail,
      'subject': subject,
      'message_body': messageBody,
      'pdf_document_id': pdfDocumentId,
      'template_type': templateType,
      'status': status,
      'provider_name': providerName,
      'provider_message_id': providerMessageId,
    })
        .select()
        .single();

    return InvoiceEmailLogModel.fromMap(response);
  }
}