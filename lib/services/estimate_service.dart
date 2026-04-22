import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/estimate_item_model.dart';
import '../models/estimate_model.dart';
import '../utils/estimate_calculator.dart';

class EstimateService {
  EstimateService._();

  static final SupabaseClient _supabase = Supabase.instance.client;

  static const String _estimatesTable = 'estimates';
  static const String _itemsTable = 'estimate_items';

  static const String _documentsTable = 'estimate_documents';
  static const String _emailLogsTable = 'estimate_email_logs';
  static const String _aiLogsTable = 'ai_estimate_logs';
  static const String _invoicesTable = 'invoices';

  static String _requireUserId() {
    final user = _supabase.auth.currentUser;

    if (user == null) {
      throw Exception('User is not authenticated');
    }

    return user.id;
  }

  static List<EstimateModel> _mapEstimateList(dynamic response) {
    final list = response as List;

    return list
        .map((item) => EstimateModel.fromMap(item as Map<String, dynamic>))
        .toList();
  }

  static List<EstimateItemModel> _mapEstimateItemList(dynamic response) {
    final list = response as List;

    return list
        .map((item) => EstimateItemModel.fromMap(item as Map<String, dynamic>))
        .toList();
  }

  static String generateEstimateNumber() {
    final now = DateTime.now();

    final year = now.year.toString();
    final month = now.month.toString().padLeft(2, '0');
    final day = now.day.toString().padLeft(2, '0');
    final hour = now.hour.toString().padLeft(2, '0');
    final minute = now.minute.toString().padLeft(2, '0');
    final second = now.second.toString().padLeft(2, '0');

    return 'EST-$year$month$day-$hour$minute$second';
  }

  static Future<List<EstimateModel>> getEstimates() async {
    final userId = _requireUserId();

    final response = await _supabase
        .from(_estimatesTable)
        .select()
        .eq('admin_auth_id', userId)
        .order('created_at', ascending: false);

    return _mapEstimateList(response);
  }

  static Future<List<EstimateModel>> getEstimatesByStatus(String status) async {
    final userId = _requireUserId();

    final response = await _supabase
        .from(_estimatesTable)
        .select()
        .eq('admin_auth_id', userId)
        .eq('status', status)
        .order('created_at', ascending: false);

    return _mapEstimateList(response);
  }

  static Future<EstimateModel?> getEstimateById(String estimateId) async {
    final userId = _requireUserId();

    final response = await _supabase
        .from(_estimatesTable)
        .select()
        .eq('id', estimateId)
        .eq('admin_auth_id', userId)
        .limit(1)
        .maybeSingle();

    if (response == null) {
      return null;
    }

    return EstimateModel.fromMap(response);
  }

  static Future<List<EstimateItemModel>> getEstimateItems(String estimateId) async {
    final response = await _supabase
        .from(_itemsTable)
        .select()
        .eq('estimate_id', estimateId)
        .order('sort_order');

    return _mapEstimateItemList(response);
  }

  static Future<EstimateModel> createEstimate(EstimateModel estimate) async {
    final userId = _requireUserId();

    final payload = estimate.toInsertMap()
      ..['admin_auth_id'] = userId
      ..['estimate_number'] = estimate.estimateNumber.trim().isEmpty
          ? generateEstimateNumber()
          : estimate.estimateNumber;

    final response = await _supabase
        .from(_estimatesTable)
        .insert(payload)
        .select()
        .single();

    return EstimateModel.fromMap(response);
  }

  static Future<EstimateModel> createEstimateWithItems({
    required EstimateModel estimate,
    required List<EstimateItemModel> items,
    double taxRate = 0,
    double discountValue = 0,
    bool discountIsPercentage = false,
  }) async {
    final recalculatedItems = EstimateCalculator.recalculateItems(items);

    final totals = EstimateCalculator.calculateTotals(
      items: recalculatedItems,
      taxRate: taxRate,
      discountValue: discountValue,
      discountIsPercentage: discountIsPercentage,
    );

    final estimateToCreate = estimate.copyWith(
      subtotal: totals.subtotal,
      tax: totals.tax,
      discount: totals.discount,
      total: totals.total,
    );

    final createdEstimate = await createEstimate(estimateToCreate);

    await replaceEstimateItems(
      estimateId: createdEstimate.id,
      items: recalculatedItems,
    );

    return createdEstimate;
  }

  static Future<EstimateModel> updateEstimate(EstimateModel estimate) async {
    final userId = _requireUserId();

    if (estimate.id.trim().isEmpty) {
      throw Exception('Cannot update estimate without id');
    }

    final payload = {
      'client_id': estimate.clientId,
      'property_id': estimate.propertyId,
      'estimate_number': estimate.estimateNumber,
      'title': estimate.title,
      'status': estimate.status,
      'scope_text': estimate.scopeText,
      'notes': estimate.notes,
      'subtotal': estimate.subtotal,
      'tax': estimate.tax,
      'discount': estimate.discount,
      'total': estimate.total,
      'valid_until': estimate.validUntil?.toIso8601String().split('T').first,
    };

    final response = await _supabase
        .from(_estimatesTable)
        .update(payload)
        .eq('id', estimate.id)
        .eq('admin_auth_id', userId)
        .select()
        .single();

    return EstimateModel.fromMap(response);
  }

  static Future<EstimateModel> updateEstimateWithItems({
    required EstimateModel estimate,
    required List<EstimateItemModel> items,
    double taxRate = 0,
    double discountValue = 0,
    bool discountIsPercentage = false,
  }) async {
    final recalculatedItems = EstimateCalculator.recalculateItems(items);

    final totals = EstimateCalculator.calculateTotals(
      items: recalculatedItems,
      taxRate: taxRate,
      discountValue: discountValue,
      discountIsPercentage: discountIsPercentage,
    );

    final estimateToUpdate = estimate.copyWith(
      subtotal: totals.subtotal,
      tax: totals.tax,
      discount: totals.discount,
      total: totals.total,
    );

    final updatedEstimate = await updateEstimate(estimateToUpdate);

    await replaceEstimateItems(
      estimateId: updatedEstimate.id,
      items: recalculatedItems,
    );

    return updatedEstimate;
  }

  static Future<void> archiveEstimate(String estimateId) async {
    final userId = _requireUserId();

    await _supabase
        .from(_estimatesTable)
        .update({
      'status': 'archived',
    })
        .eq('id', estimateId)
        .eq('admin_auth_id', userId);
  }

  static Future<bool> canDeleteEstimate(String estimateId) async {
    final userId = _requireUserId();

    final estimate = await _supabase
        .from(_estimatesTable)
        .select('id, status')
        .eq('id', estimateId)
        .eq('admin_auth_id', userId)
        .maybeSingle();

    if (estimate == null) return false;

    final status = (estimate['status'] ?? '').toString().trim().toLowerCase();
    if (status != 'draft') return false;

    final linkedInvoice = await _supabase
        .from(_invoicesTable)
        .select('id')
        .eq('estimate_id', estimateId)
        .eq('admin_auth_id', userId)
        .maybeSingle();

    return linkedInvoice == null;
  }

  static Future<void> deleteEstimate(String estimateId) async {
    final userId = _requireUserId();

    final estimate = await _supabase
        .from(_estimatesTable)
        .select('id, status')
        .eq('id', estimateId)
        .eq('admin_auth_id', userId)
        .maybeSingle();

    if (estimate == null) {
      throw Exception('Estimate not found');
    }

    final status = (estimate['status'] ?? '').toString().trim().toLowerCase();
    if (status != 'draft') {
      throw Exception('Only draft estimates can be deleted permanently');
    }

    final linkedInvoice = await _supabase
        .from(_invoicesTable)
        .select('id')
        .eq('estimate_id', estimateId)
        .eq('admin_auth_id', userId)
        .maybeSingle();

    if (linkedInvoice != null) {
      throw Exception('This estimate already has a linked invoice. Archive it instead.');
    }

    await _supabase
        .from(_emailLogsTable)
        .delete()
        .eq('estimate_id', estimateId);

    await _supabase
        .from(_aiLogsTable)
        .delete()
        .eq('estimate_id', estimateId);

    await _supabase
        .from(_itemsTable)
        .delete()
        .eq('estimate_id', estimateId);

    await _supabase
        .from(_documentsTable)
        .delete()
        .eq('estimate_id', estimateId);

    await _supabase
        .from(_estimatesTable)
        .delete()
        .eq('id', estimateId)
        .eq('admin_auth_id', userId);
  }

  static Future<void> replaceEstimateItems({
    required String estimateId,
    required List<EstimateItemModel> items,
  }) async {
    await _supabase
        .from(_itemsTable)
        .delete()
        .eq('estimate_id', estimateId);

    if (items.isEmpty) {
      return;
    }

    final payload = items.asMap().entries.map((entry) {
      final index = entry.key;
      final item = EstimateCalculator.recalculateItem(entry.value);

      return {
        'estimate_id': estimateId,
        'title': item.title,
        'description': item.description,
        'unit': item.unit,
        'quantity': item.quantity,
        'unit_price': item.unitPrice,
        'line_total': item.lineTotal,
        'sort_order': index,
      };
    }).toList();

    await _supabase.from(_itemsTable).insert(payload);
  }

  static Future<List<EstimateModel>> getPreviousEstimatesByClient(String clientId) async {
    final userId = _requireUserId();

    final response = await _supabase
        .from(_estimatesTable)
        .select()
        .eq('admin_auth_id', userId)
        .eq('client_id', clientId)
        .order('created_at', ascending: false);

    return _mapEstimateList(response);
  }

  static Future<List<EstimateModel>> getPreviousEstimatesByProperty(String propertyId) async {
    final userId = _requireUserId();

    final response = await _supabase
        .from(_estimatesTable)
        .select()
        .eq('admin_auth_id', userId)
        .eq('property_id', propertyId)
        .order('created_at', ascending: false);

    return _mapEstimateList(response);
  }

  static Future<List<EstimateModel>> getPreviousEstimatesByClientAndProperty({
    required String clientId,
    required String propertyId,
  }) async {
    final userId = _requireUserId();

    final response = await _supabase
        .from(_estimatesTable)
        .select()
        .eq('admin_auth_id', userId)
        .eq('client_id', clientId)
        .eq('property_id', propertyId)
        .order('created_at', ascending: false);

    return _mapEstimateList(response);
  }

  static Future<EstimateModel> duplicateEstimate(String estimateId) async {
    final originalEstimate = await getEstimateById(estimateId);

    if (originalEstimate == null) {
      throw Exception('Original estimate was not found');
    }

    final originalItems = await getEstimateItems(estimateId);

    final duplicatedEstimate = originalEstimate.copyWith(
      id: '',
      estimateNumber: generateEstimateNumber(),
      status: 'draft',
      createdAt: null,
      updatedAt: null,
    );

    final createdEstimate = await createEstimate(duplicatedEstimate);

    await replaceEstimateItems(
      estimateId: createdEstimate.id,
      items: originalItems
          .map(
            (item) => item.copyWith(
          id: '',
          estimateId: createdEstimate.id,
          createdAt: null,
        ),
      )
          .toList(),
    );

    return createdEstimate;
  }
}