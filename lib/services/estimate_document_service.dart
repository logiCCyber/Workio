import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/client_model.dart';
import '../models/estimate_document_model.dart';
import '../models/estimate_item_model.dart';
import '../models/estimate_model.dart';
import '../models/property_model.dart';
import 'estimate_pdf_service.dart';

class EstimateDocumentService {
  EstimateDocumentService._();

  static final SupabaseClient _supabase = Supabase.instance.client;

  static const String _bucket = 'estimate-pdfs';
  static const String _table = 'estimate_documents';

  static String _requireUserId() {
    final user = _supabase.auth.currentUser;

    if (user == null) {
      throw Exception('Пользователь не авторизован');
    }

    return user.id;
  }

  static List<EstimateDocumentModel> _mapDocumentList(dynamic response) {
    final list = response as List;

    return list
        .map(
          (item) => EstimateDocumentModel.fromMap(
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

    return cleaned.isEmpty ? 'estimate' : cleaned;
  }

  static String _buildFileName(EstimateModel estimate) {
    final base = estimate.estimateNumber.trim().isNotEmpty
        ? estimate.estimateNumber.trim()
        : 'estimate';

    return '${_sanitizeFileName(base)}.pdf';
  }

  static String _buildStoragePath({
    required String userId,
    required String estimateId,
    required String fileName,
  }) {
    final now = DateTime.now().millisecondsSinceEpoch;
    return '$userId/$estimateId/$now-$fileName';
  }

  static Future<EstimateDocumentModel> saveEstimatePdf({
    required EstimateModel estimate,
    required List<EstimateItemModel> items,
    ClientModel? client,
    PropertyModel? property,
    String companyName = 'Your Company Name',
    String? companyEmail,
    String? companyPhone,
    String? companyLogoUrl,
  }) async {
    final userId = _requireUserId();

    if (estimate.id.trim().isEmpty) {
      throw Exception('Нельзя сохранить PDF без estimate id');
    }

    final Uint8List pdfBytes = await EstimatePdfService.buildEstimatePdf(
      estimate: estimate,
      items: items,
      client: client,
      property: property,
      companyName: companyName,
      companyEmail: companyEmail,
      companyPhone: companyPhone,
      companyLogoUrl: companyLogoUrl,
    );

    final fileName = _buildFileName(estimate);
    final filePath = _buildStoragePath(
      userId: userId,
      estimateId: estimate.id,
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
      'estimate_id': estimate.id,
      'file_name': fileName,
      'file_path': filePath,
      'file_url': signedUrl,
    })
        .select()
        .single();

    return EstimateDocumentModel.fromMap(response);
  }

  static Future<List<EstimateDocumentModel>> getDocumentsByEstimate(
      String estimateId,
      ) async {
    final response = await _supabase
        .from(_table)
        .select()
        .eq('estimate_id', estimateId)
        .order('created_at', ascending: false);

    return _mapDocumentList(response);
  }

  static Future<String> createSignedUrl(
      EstimateDocumentModel document, {
        int expiresInSeconds = 60 * 60,
      }) async {
    return _supabase.storage
        .from(_bucket)
        .createSignedUrl(document.filePath, expiresInSeconds);
  }

  static Future<void> deleteDocument(EstimateDocumentModel document) async {
    await _supabase.storage.from(_bucket).remove([document.filePath]);

    await _supabase
        .from(_table)
        .delete()
        .eq('id', document.id);
  }
}