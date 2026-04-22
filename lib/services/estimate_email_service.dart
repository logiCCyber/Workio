import 'package:supabase_flutter/supabase_flutter.dart';

import '../dialogs/send_estimate_dialog.dart';
import '../models/client_model.dart';
import '../models/company_settings_model.dart';
import '../models/estimate_document_model.dart';
import '../models/estimate_email_log_model.dart';
import '../models/estimate_item_model.dart';
import '../models/estimate_model.dart';
import '../models/property_model.dart';
import 'estimate_document_service.dart';
import 'estimate_service.dart';
import '../utils/company_logo_helper.dart';

class SendEstimateExecutionResult {
  final EstimateEmailLogModel emailLog;
  final EstimateDocumentModel attachedDocument;
  final EstimateModel updatedEstimate;
  final String? providerMessageId;

  const SendEstimateExecutionResult({
    required this.emailLog,
    required this.attachedDocument,
    required this.updatedEstimate,
    this.providerMessageId,
  });
}

class EstimateEmailService {
  EstimateEmailService._();

  static final SupabaseClient _supabase = Supabase.instance.client;
  static const String _logsTable = 'estimate_email_logs';
  static const String _functionName = 'send-estimate-email';

  static String _requireUserId() {
    final user = _supabase.auth.currentUser;

    if (user == null) {
      throw Exception('User is not authenticated');
    }

    return user.id;
  }

  static List<EstimateEmailLogModel> _mapEmailLogList(dynamic response) {
    final list = response as List;

    return list
        .map(
          (item) => EstimateEmailLogModel.fromMap(
        item as Map<String, dynamic>,
      ),
    )
        .toList();
  }

  static Future<List<EstimateEmailLogModel>> getEmailLogsByEstimate(
      String estimateId,
      ) async {
    final userId = _requireUserId();

    final response = await _supabase
        .from(_logsTable)
        .select()
        .eq('estimate_id', estimateId)
        .eq('admin_auth_id', userId)
        .order('sent_at', ascending: false);

    return _mapEmailLogList(response);
  }

  static Future<EstimateDocumentModel?> getLatestDocumentForEstimate(
      String estimateId,
      ) async {
    final docs = await EstimateDocumentService.getDocumentsByEstimate(estimateId);

    if (docs.isEmpty) return null;
    return docs.first;
  }

  static Future<SendEstimateExecutionResult> sendEstimate({
    required EstimateModel estimate,
    required List<EstimateItemModel> items,
    required SendEstimateDialogResult dialogResult,
    ClientModel? client,
    PropertyModel? property,
    CompanySettingsModel? companySettings,
  }) async {
    final userId = _requireUserId();

    if (estimate.id.trim().isEmpty) {
      throw Exception('Save the estimate first');
    }

    final attachedDocument = await _resolvePdfDocument(
      estimate: estimate,
      items: items,
      dialogResult: dialogResult,
      client: client,
      property: property,
      companySettings: companySettings,
    );

    final signedUrl = await EstimateDocumentService.createSignedUrl(
      attachedDocument,
      expiresInSeconds: 60 * 60,
    );

    final companyLogoUrl = CompanyLogoHelper.resolvedLogoUrl(companySettings);

    final payload = {
      'to': dialogResult.recipientEmail,
      'subject': dialogResult.subject,
      'text': dialogResult.messageBody,
      'estimate_id': estimate.id,
      'client_name': client?.fullName,
      'company_name': _companyName(companySettings),
      'company_email': _companyEmail(companySettings),
      'company_phone': _companyPhone(companySettings),
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
        estimateId: estimate.id,
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

      final updatedEstimate = await EstimateService.updateEstimate(
        estimate.copyWith(status: 'sent'),
      );

      return SendEstimateExecutionResult(
        emailLog: emailLog,
        attachedDocument: attachedDocument,
        updatedEstimate: updatedEstimate,
        providerMessageId: providerMessageId,
      );
    } catch (e) {
      await _insertEmailLog(
        estimateId: estimate.id,
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

  static Future<EstimateDocumentModel> _resolvePdfDocument({
    required EstimateModel estimate,
    required List<EstimateItemModel> items,
    required SendEstimateDialogResult dialogResult,
    ClientModel? client,
    PropertyModel? property,
    CompanySettingsModel? companySettings,
  }) async {
    final existingDocs =
    await EstimateDocumentService.getDocumentsByEstimate(estimate.id);

    EstimateDocumentModel? selectedDocument;

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
      throw Exception('No PDF available to send');
    }

    return EstimateDocumentService.saveEstimatePdf(
      estimate: estimate,
      items: items,
      client: client,
      property: property,
      companyName: _companyName(companySettings),
      companyEmail: _companyEmail(companySettings),
      companyPhone: _companyPhone(companySettings),
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

  static Future<EstimateEmailLogModel> _insertEmailLog({
    required String estimateId,
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
      'estimate_id': estimateId,
      'admin_auth_id': adminAuthId,
      'recipient_email': recipientEmail,
      'subject': subject,
      'template_type': templateType,
      'message_body': messageBody,
      'pdf_document_id': pdfDocumentId,
      'status': status,
      'provider_name': providerName,
      'provider_message_id': providerMessageId,
    })
        .select()
        .single();

    return EstimateEmailLogModel.fromMap(response);
  }
}