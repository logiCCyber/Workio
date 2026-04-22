class InvoicePaymentModel {
  final String id;
  final String invoiceId;
  final String adminAuthId;
  final double amount;
  final DateTime? paymentDate;
  final String? paymentMethod;
  final String? referenceNumber;
  final String? notes;
  final DateTime? createdAt;

  const InvoicePaymentModel({
    required this.id,
    required this.invoiceId,
    required this.adminAuthId,
    required this.amount,
    this.paymentDate,
    this.paymentMethod,
    this.referenceNumber,
    this.notes,
    this.createdAt,
  });

  factory InvoicePaymentModel.fromMap(Map<String, dynamic> map) {
    return InvoicePaymentModel(
      id: map['id']?.toString() ?? '',
      invoiceId: map['invoice_id']?.toString() ?? '',
      adminAuthId: map['admin_auth_id']?.toString() ?? '',
      amount: _toDouble(map['amount']),
      paymentDate: map['payment_date'] != null
          ? DateTime.tryParse(map['payment_date'].toString())
          : null,
      paymentMethod: map['payment_method']?.toString(),
      referenceNumber: map['reference_number']?.toString(),
      notes: map['notes']?.toString(),
      createdAt: map['created_at'] != null
          ? DateTime.tryParse(map['created_at'].toString())
          : null,
    );
  }

  static double _toDouble(dynamic value) {
    if (value == null) return 0;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString()) ?? 0;
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'invoice_id': invoiceId,
      'admin_auth_id': adminAuthId,
      'amount': amount,
      'payment_date': paymentDate?.toIso8601String().split('T').first,
      'payment_method': paymentMethod,
      'reference_number': referenceNumber,
      'notes': notes,
      'created_at': createdAt?.toIso8601String(),
    };
  }

  Map<String, dynamic> toInsertMap() {
    return {
      'invoice_id': invoiceId,
      'admin_auth_id': adminAuthId,
      'amount': amount,
      'payment_date': paymentDate?.toIso8601String().split('T').first,
      'payment_method': paymentMethod,
      'reference_number': referenceNumber,
      'notes': notes,
    };
  }

  InvoicePaymentModel copyWith({
    String? id,
    String? invoiceId,
    String? adminAuthId,
    double? amount,
    DateTime? paymentDate,
    String? paymentMethod,
    String? referenceNumber,
    String? notes,
    DateTime? createdAt,
  }) {
    return InvoicePaymentModel(
      id: id ?? this.id,
      invoiceId: invoiceId ?? this.invoiceId,
      adminAuthId: adminAuthId ?? this.adminAuthId,
      amount: amount ?? this.amount,
      paymentDate: paymentDate ?? this.paymentDate,
      paymentMethod: paymentMethod ?? this.paymentMethod,
      referenceNumber: referenceNumber ?? this.referenceNumber,
      notes: notes ?? this.notes,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}