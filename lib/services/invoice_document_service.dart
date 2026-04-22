import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/client_model.dart';
import '../models/invoice_document_model.dart';
import '../models/invoice_item_model.dart';
import '../models/invoice_model.dart';
import '../models/property_model.dart';
import 'invoice_pdf_service.dart';

class InvoiceDocumentService {
  InvoiceDocumentService._();

  static final SupabaseClient _supabase = Supabase.instance.client;

  static const String _bucket = 'invoice-pdfs';
  static const String _table = 'invoice_documents';

  static String _requireUserId() {
    final user = _supabase.auth.currentUser;

    if (user == null) {
      throw Exception('Пользователь не авторизован');
    }

    return user.id;
  }

  static List<InvoiceDocumentModel> _mapDocumentList(dynamic response) {
    final list = response as List;

    return list
        .map(
          (item) => InvoiceDocumentModel.fromMap(
        item as Map<String, dynamic>,
      ),
    )
        .toList();
  }

  static String _sanitizeFileName(String value) {
    final cleaned = value
        .trim()
        .replaceAll(RegExp(r'[^\w\-.]+'), '_')
        .replaceAll('__', '_');

    return cleaned.isEmpty ? 'invoice' : cleaned;
  }

  static String _buildFileName(InvoiceModel invoice) {
    final base = invoice.invoiceNumber.trim().isNotEmpty
        ? invoice.invoiceNumber.trim()
        : 'invoice';

    return '${_sanitizeFileName(base)}.pdf';
  }

  static String _buildStoragePath({
    required String userId,
    required String invoiceId,
    required String fileName,
  }) {
    final now = DateTime.now().millisecondsSinceEpoch;
    return '$userId/$invoiceId/$now-$fileName';
  }

  static Future<InvoiceDocumentModel> saveInvoicePdf({
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
    final userId = _requireUserId();

    if (invoice.id.trim().isEmpty) {
      throw Exception('Нельзя сохранить PDF без invoice id');
    }

    final Uint8List pdfBytes = await InvoicePdfService.buildInvoicePdf(
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

    final fileName = _buildFileName(invoice);
    final filePath = _buildStoragePath(
      userId: userId,
      invoiceId: invoice.id,
      fileName: fileName,
    );

    await _supabase.storage.from(_bucket).uploadBinary(
      filePath,
      pdfBytes,
      fileOptions: const FileOptions(
        cacheControl: '3600',
        upsert: false,
        contentType: 'application/pdf',
      ),
    );

    final signedUrl = await _supabase.storage
        .from(_bucket)
        .createSignedUrl(filePath, 60 * 60 * 24 * 7);

    final response = await _supabase
        .from(_table)
        .insert({
      'invoice_id': invoice.id,
      'file_name': fileName,
      'file_path': filePath,
      'file_url': signedUrl,
    })
        .select()
        .single();

    return InvoiceDocumentModel.fromMap(response);
  }

  static Future<List<InvoiceDocumentModel>> getDocumentsByInvoice(
      String invoiceId,
      ) async {
    final response = await _supabase
        .from(_table)
        .select()
        .eq('invoice_id', invoiceId)
        .order('created_at', ascending: false);

    return _mapDocumentList(response);
  }

  static Future<String> createSignedUrl(
      InvoiceDocumentModel document, {
        int expiresInSeconds = 60 * 60,
      }) async {
    return _supabase.storage
        .from(_bucket)
        .createSignedUrl(document.filePath, expiresInSeconds);
  }

  static Future<void> deleteDocument(InvoiceDocumentModel document) async {
    await _supabase.storage.from(_bucket).remove([document.filePath]);

    await _supabase
        .from(_table)
        .delete()
        .eq('id', document.id);
  }
}