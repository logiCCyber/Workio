class InvoiceModel {
  final String id;
  final String adminAuthId;
  final String? estimateId;
  final String clientId;
  final String propertyId;

  final String invoiceNumber;
  final String title;
  final String status;

  final DateTime? issueDate;
  final DateTime? dueDate;

  final String? notes;
  final String? terms;
  final String? paymentInstructions;

  final double subtotal;
  final double tax;
  final double discount;
  final double total;

  final double paidAmount;
  final double balanceDue;

  final DateTime? createdAt;
  final DateTime? updatedAt;

  const InvoiceModel({
    required this.id,
    required this.adminAuthId,
    this.estimateId,
    required this.clientId,
    required this.propertyId,
    required this.invoiceNumber,
    required this.title,
    required this.status,
    this.issueDate,
    this.dueDate,
    this.notes,
    this.terms,
    this.paymentInstructions,
    required this.subtotal,
    required this.tax,
    required this.discount,
    required this.total,
    required this.paidAmount,
    required this.balanceDue,
    this.createdAt,
    this.updatedAt,
  });

  factory InvoiceModel.fromMap(Map<String, dynamic> map) {
    return InvoiceModel(
      id: map['id']?.toString() ?? '',
      adminAuthId: map['admin_auth_id']?.toString() ?? '',
      estimateId: map['estimate_id']?.toString(),
      clientId: map['client_id']?.toString() ?? '',
      propertyId: map['property_id']?.toString() ?? '',
      invoiceNumber: map['invoice_number']?.toString() ?? '',
      title: map['title']?.toString() ?? '',
      status: map['status']?.toString() ?? 'draft',
      issueDate: map['issue_date'] != null
          ? DateTime.tryParse(map['issue_date'].toString())
          : null,
      dueDate: map['due_date'] != null
          ? DateTime.tryParse(map['due_date'].toString())
          : null,
      notes: map['notes']?.toString(),
      terms: map['terms']?.toString(),
      paymentInstructions: map['payment_instructions']?.toString(),
      subtotal: _toDouble(map['subtotal']),
      tax: _toDouble(map['tax']),
      discount: _toDouble(map['discount']),
      total: _toDouble(map['total']),
      paidAmount: _toDouble(map['paid_amount']),
      balanceDue: _toDouble(map['balance_due']),
      createdAt: map['created_at'] != null
          ? DateTime.tryParse(map['created_at'].toString())
          : null,
      updatedAt: map['updated_at'] != null
          ? DateTime.tryParse(map['updated_at'].toString())
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
      'admin_auth_id': adminAuthId,
      'estimate_id': estimateId,
      'client_id': clientId,
      'property_id': propertyId,
      'invoice_number': invoiceNumber,
      'title': title,
      'status': status,
      'issue_date': issueDate?.toIso8601String().split('T').first,
      'due_date': dueDate?.toIso8601String().split('T').first,
      'notes': notes,
      'terms': terms,
      'payment_instructions': paymentInstructions,
      'subtotal': subtotal,
      'tax': tax,
      'discount': discount,
      'total': total,
      'paid_amount': paidAmount,
      'balance_due': balanceDue,
      'created_at': createdAt?.toIso8601String(),
      'updated_at': updatedAt?.toIso8601String(),
    };
  }

  Map<String, dynamic> toInsertMap() {
    return {
      'estimate_id': estimateId,
      'client_id': clientId,
      'property_id': propertyId,
      'invoice_number': invoiceNumber,
      'title': title,
      'status': status,
      'issue_date': issueDate?.toIso8601String().split('T').first,
      'due_date': dueDate?.toIso8601String().split('T').first,
      'notes': notes,
      'terms': terms,
      'payment_instructions': paymentInstructions,
      'subtotal': subtotal,
      'tax': tax,
      'discount': discount,
      'total': total,
      'paid_amount': paidAmount,
      'balance_due': balanceDue,
    };
  }

  InvoiceModel copyWith({
    String? id,
    String? adminAuthId,
    String? estimateId,
    String? clientId,
    String? propertyId,
    String? invoiceNumber,
    String? title,
    String? status,
    DateTime? issueDate,
    DateTime? dueDate,
    String? notes,
    String? terms,
    String? paymentInstructions,
    double? subtotal,
    double? tax,
    double? discount,
    double? total,
    double? paidAmount,
    double? balanceDue,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return InvoiceModel(
      id: id ?? this.id,
      adminAuthId: adminAuthId ?? this.adminAuthId,
      estimateId: estimateId ?? this.estimateId,
      clientId: clientId ?? this.clientId,
      propertyId: propertyId ?? this.propertyId,
      invoiceNumber: invoiceNumber ?? this.invoiceNumber,
      title: title ?? this.title,
      status: status ?? this.status,
      issueDate: issueDate ?? this.issueDate,
      dueDate: dueDate ?? this.dueDate,
      notes: notes ?? this.notes,
      terms: terms ?? this.terms,
      paymentInstructions: paymentInstructions ?? this.paymentInstructions,
      subtotal: subtotal ?? this.subtotal,
      tax: tax ?? this.tax,
      discount: discount ?? this.discount,
      total: total ?? this.total,
      paidAmount: paidAmount ?? this.paidAmount,
      balanceDue: balanceDue ?? this.balanceDue,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  bool get isDraft => status == 'draft';
  bool get isSent => status == 'sent';
  bool get isPartial => status == 'partial';
  bool get isPaid => status == 'paid';
  bool get isOverdue => status == 'overdue';
  bool get isVoid => status == 'void';
}