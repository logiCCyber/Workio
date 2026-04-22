import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/estimate_model.dart';
import '../models/invoice_item_model.dart';
import '../models/invoice_model.dart';
import '../models/invoice_payment_model.dart';
import '../utils/estimate_calculator.dart';
import 'estimate_service.dart';

class InvoiceService {
  InvoiceService._();

  static final SupabaseClient _supabase = Supabase.instance.client;

  static const String _invoicesTable = 'invoices';
  static const String _itemsTable = 'invoice_items';
  static const String _paymentsTable = 'invoice_payments';

  static const String _documentsTable = 'invoice_documents';
  static const String _emailLogsTable = 'invoice_email_logs';

  static String _requireUserId() {
    final user = _supabase.auth.currentUser;

    if (user == null) {
      throw Exception('Пользователь не авторизован');
    }

    return user.id;
  }

  static List<InvoiceModel> _mapInvoiceList(dynamic response) {
    final list = response as List;

    return list
        .map((item) => InvoiceModel.fromMap(item as Map<String, dynamic>))
        .toList();
  }

  static List<InvoiceItemModel> _mapInvoiceItemList(dynamic response) {
    final list = response as List;

    return list
        .map((item) => InvoiceItemModel.fromMap(item as Map<String, dynamic>))
        .toList();
  }

  static List<InvoicePaymentModel> _mapInvoicePaymentList(dynamic response) {
    final list = response as List;

    return list
        .map((item) => InvoicePaymentModel.fromMap(item as Map<String, dynamic>))
        .toList();
  }

  static String generateInvoiceNumber() {
    final now = DateTime.now();

    final year = now.year.toString();
    final month = now.month.toString().padLeft(2, '0');
    final day = now.day.toString().padLeft(2, '0');
    final hour = now.hour.toString().padLeft(2, '0');
    final minute = now.minute.toString().padLeft(2, '0');
    final second = now.second.toString().padLeft(2, '0');

    return 'INV-$year$month$day-$hour$minute$second';
  }

  static Future<List<InvoiceModel>> getInvoices() async {
    final userId = _requireUserId();

    final response = await _supabase
        .from(_invoicesTable)
        .select()
        .eq('admin_auth_id', userId)
        .order('created_at', ascending: false);

    return _mapInvoiceList(response);
  }

  static Future<List<InvoiceModel>> getInvoicesByStatus(String status) async {
    final userId = _requireUserId();

    final response = await _supabase
        .from(_invoicesTable)
        .select()
        .eq('admin_auth_id', userId)
        .eq('status', status)
        .order('created_at', ascending: false);

    return _mapInvoiceList(response);
  }

  static Future<InvoiceModel?> getInvoiceById(String invoiceId) async {
    final userId = _requireUserId();

    final response = await _supabase
        .from(_invoicesTable)
        .select()
        .eq('id', invoiceId)
        .eq('admin_auth_id', userId)
        .limit(1)
        .maybeSingle();

    if (response == null) {
      return null;
    }

    return InvoiceModel.fromMap(response);
  }

  static Future<List<InvoiceItemModel>> getInvoiceItems(String invoiceId) async {
    final response = await _supabase
        .from(_itemsTable)
        .select()
        .eq('invoice_id', invoiceId)
        .order('sort_order');

    return _mapInvoiceItemList(response);
  }

  static Future<List<InvoicePaymentModel>> getInvoicePayments(
      String invoiceId,
      ) async {
    final userId = _requireUserId();

    final response = await _supabase
        .from(_paymentsTable)
        .select()
        .eq('invoice_id', invoiceId)
        .eq('admin_auth_id', userId)
        .order('payment_date', ascending: false)
        .order('created_at', ascending: false);

    return _mapInvoicePaymentList(response);
  }

  static Future<InvoiceModel> createInvoice(InvoiceModel invoice) async {
    final userId = _requireUserId();

    final payload = invoice.toInsertMap()
      ..['admin_auth_id'] = userId
      ..['invoice_number'] = invoice.invoiceNumber.trim().isEmpty
          ? generateInvoiceNumber()
          : invoice.invoiceNumber;

    final response = await _supabase
        .from(_invoicesTable)
        .insert(payload)
        .select()
        .single();

    return InvoiceModel.fromMap(response);
  }

  static Future<InvoiceModel> createInvoiceWithItems({
    required InvoiceModel invoice,
    required List<InvoiceItemModel> items,
  }) async {
    final recalculatedItems = _recalculateItems(items);

    final double subtotal = _calculateSubtotal(recalculatedItems);
    final double paidAmount = invoice.paidAmount < 0 ? 0.0 : invoice.paidAmount;
    final double total = invoice.total;
    final double balanceDue =
    _roundMoney((total - paidAmount) < 0 ? 0.0 : (total - paidAmount));

    final invoiceToCreate = invoice.copyWith(
      subtotal: subtotal,
      tax: invoice.tax,
      discount: invoice.discount,
      total: total,
      paidAmount: paidAmount,
      balanceDue: balanceDue,
    );

    final createdInvoice = await createInvoice(invoiceToCreate);

    await replaceInvoiceItems(
      invoiceId: createdInvoice.id,
      items: recalculatedItems,
    );

    return createdInvoice;
  }

  static Future<InvoiceModel> updateInvoice(InvoiceModel invoice) async {
    final userId = _requireUserId();

    if (invoice.id.trim().isEmpty) {
      throw Exception('Нельзя обновить invoice без id');
    }

    final payload = {
      'estimate_id': invoice.estimateId,
      'client_id': invoice.clientId,
      'property_id': invoice.propertyId,
      'invoice_number': invoice.invoiceNumber,
      'title': invoice.title,
      'status': invoice.status,
      'issue_date': invoice.issueDate?.toIso8601String().split('T').first,
      'due_date': invoice.dueDate?.toIso8601String().split('T').first,
      'notes': invoice.notes,
      'terms': invoice.terms,
      'payment_instructions': invoice.paymentInstructions,
      'subtotal': invoice.subtotal,
      'tax': invoice.tax,
      'discount': invoice.discount,
      'total': invoice.total,
      'paid_amount': invoice.paidAmount,
      'balance_due': invoice.balanceDue,
    };

    final response = await _supabase
        .from(_invoicesTable)
        .update(payload)
        .eq('id', invoice.id)
        .eq('admin_auth_id', userId)
        .select()
        .single();

    return InvoiceModel.fromMap(response);
  }

  static Future<InvoiceModel> updateInvoiceWithItems({
    required InvoiceModel invoice,
    required List<InvoiceItemModel> items,
  }) async {
    final recalculatedItems = _recalculateItems(items);
    final double subtotal = _calculateSubtotal(recalculatedItems);
    final double paidAmount = invoice.paidAmount < 0 ? 0.0 : invoice.paidAmount;
    final double total = invoice.total;
    final double balanceDue =
    _roundMoney((total - paidAmount) < 0 ? 0.0 : (total - paidAmount));

    final invoiceToUpdate = invoice.copyWith(
      subtotal: subtotal,
      paidAmount: paidAmount,
      balanceDue: balanceDue,
    );

    final updatedInvoice = await updateInvoice(invoiceToUpdate);

    await replaceInvoiceItems(
      invoiceId: updatedInvoice.id,
      items: recalculatedItems,
    );

    return updatedInvoice;
  }

  static Future<void> archiveInvoice(String invoiceId) async {
    final userId = _requireUserId();

    await _supabase
        .from(_invoicesTable)
        .update({
      'status': 'archived',
    })
        .eq('id', invoiceId)
        .eq('admin_auth_id', userId);
  }

  static Future<bool> canDeleteInvoice(String invoiceId) async {
    final userId = _requireUserId();

    final invoice = await _supabase
        .from(_invoicesTable)
        .select('id, status')
        .eq('id', invoiceId)
        .eq('admin_auth_id', userId)
        .maybeSingle();

    if (invoice == null) return false;

    final status = (invoice['status'] ?? '').toString().trim().toLowerCase();
    if (status != 'draft') return false;

    final payment = await _supabase
        .from(_paymentsTable)
        .select('id')
        .eq('invoice_id', invoiceId)
        .eq('admin_auth_id', userId)
        .maybeSingle();

    return payment == null;
  }

  static Future<void> deleteInvoice(String invoiceId) async {
    final userId = _requireUserId();

    final invoice = await _supabase
        .from(_invoicesTable)
        .select('id, status')
        .eq('id', invoiceId)
        .eq('admin_auth_id', userId)
        .maybeSingle();

    if (invoice == null) {
      throw Exception('Invoice not found');
    }

    final status = (invoice['status'] ?? '').toString().trim().toLowerCase();
    if (status != 'draft') {
      throw Exception('Only draft invoices can be deleted permanently');
    }

    final payment = await _supabase
        .from(_paymentsTable)
        .select('id')
        .eq('invoice_id', invoiceId)
        .eq('admin_auth_id', userId)
        .maybeSingle();

    if (payment != null) {
      throw Exception('This invoice already has payments. Archive it instead.');
    }

    await _supabase
        .from(_emailLogsTable)
        .delete()
        .eq('invoice_id', invoiceId);

    await _supabase
        .from(_paymentsTable)
        .delete()
        .eq('invoice_id', invoiceId)
        .eq('admin_auth_id', userId);

    await _supabase
        .from(_itemsTable)
        .delete()
        .eq('invoice_id', invoiceId);

    await _supabase
        .from(_documentsTable)
        .delete()
        .eq('invoice_id', invoiceId);

    await _supabase
        .from(_invoicesTable)
        .delete()
        .eq('id', invoiceId)
        .eq('admin_auth_id', userId);
  }

  static Future<void> replaceInvoiceItems({
    required String invoiceId,
    required List<InvoiceItemModel> items,
  }) async {
    await _supabase
        .from(_itemsTable)
        .delete()
        .eq('invoice_id', invoiceId);

    if (items.isEmpty) {
      return;
    }

    final payload = items.asMap().entries.map((entry) {
      final index = entry.key;
      final item = _recalculateItem(entry.value);

      return {
        'invoice_id': invoiceId,
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

  static Future<InvoicePaymentModel> addPayment(
      InvoicePaymentModel payment,
      ) async {
    final userId = _requireUserId();

    final payload = payment.toInsertMap()
      ..['admin_auth_id'] = userId;

    final response = await _supabase
        .from(_paymentsTable)
        .insert(payload)
        .select()
        .single();

    return InvoicePaymentModel.fromMap(response);
  }

  static Future<InvoicePaymentModel> updatePayment(
      InvoicePaymentModel payment,
      ) async {
    final userId = _requireUserId();

    if (payment.id.trim().isEmpty) {
      throw Exception('Нельзя обновить payment без id');
    }

    final payload = {
      'amount': payment.amount,
      'payment_date': payment.paymentDate?.toIso8601String().split('T').first,
      'payment_method': payment.paymentMethod,
      'reference_number': payment.referenceNumber,
      'notes': payment.notes,
    };

    final response = await _supabase
        .from(_paymentsTable)
        .update(payload)
        .eq('id', payment.id)
        .eq('admin_auth_id', userId)
        .select()
        .single();

    return InvoicePaymentModel.fromMap(response);
  }

  static Future<void> deletePayment(String paymentId) async {
    final userId = _requireUserId();

    await _supabase
        .from(_paymentsTable)
        .delete()
        .eq('id', paymentId)
        .eq('admin_auth_id', userId);
  }

  static Future<InvoiceModel> createInvoiceFromEstimate({
    required EstimateModel estimate,
    int dueInDays = 14,
    String? terms,
    String? paymentInstructions,
  }) async {
    if (estimate.id.trim().isEmpty) {
      throw Exception('Estimate id обязателен для convert');
    }

    final estimateItems = await EstimateService.getEstimateItems(estimate.id);

    final invoiceItems = estimateItems.asMap().entries.map((entry) {
      final index = entry.key;
      final item = entry.value;

      return InvoiceItemModel(
        id: '',
        invoiceId: '',
        title: item.title,
        description: item.description,
        unit: item.unit,
        quantity: item.quantity,
        unitPrice: item.unitPrice,
        lineTotal: item.lineTotal,
        sortOrder: index,
        createdAt: null,
      );
    }).toList();

    final now = DateTime.now();
    final dueDate = now.add(Duration(days: dueInDays));

    final invoice = InvoiceModel(
      id: '',
      adminAuthId: '',
      estimateId: estimate.id,
      clientId: estimate.clientId,
      propertyId: estimate.propertyId,
      invoiceNumber: '',
      title: estimate.title,
      status: 'draft',
      issueDate: DateTime(now.year, now.month, now.day),
      dueDate: DateTime(dueDate.year, dueDate.month, dueDate.day),
      notes: estimate.notes,
      terms: terms,
      paymentInstructions: paymentInstructions,
      subtotal: estimate.subtotal,
      tax: estimate.tax,
      discount: estimate.discount,
      total: estimate.total,
      paidAmount: 0,
      balanceDue: estimate.total,
      createdAt: null,
      updatedAt: null,
    );

    return createInvoiceWithItems(
      invoice: invoice,
      items: invoiceItems,
    );
  }

  static InvoiceItemModel _recalculateItem(InvoiceItemModel item) {
    final lineTotal = EstimateCalculator.calculateLineTotal(
      quantity: item.quantity,
      unitPrice: item.unitPrice,
    );

    return item.copyWith(lineTotal: lineTotal);
  }

  static List<InvoiceItemModel> _recalculateItems(List<InvoiceItemModel> items) {
    return items.map(_recalculateItem).toList();
  }

  static double _calculateSubtotal(List<InvoiceItemModel> items) {
    double sum = 0;

    for (final item in items) {
      final lineTotal = item.lineTotal > 0
          ? item.lineTotal
          : EstimateCalculator.calculateLineTotal(
        quantity: item.quantity,
        unitPrice: item.unitPrice,
      );

      sum += lineTotal;
    }

    return _roundMoney(sum);
  }

  static double _roundMoney(double value) {
    return double.parse(value.toStringAsFixed(2));
  }
}