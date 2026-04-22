class EstimateModel {
  final String id;
  final String adminAuthId;
  final String clientId;
  final String propertyId;
  final String estimateNumber;
  final String title;
  final String status;
  final String? scopeText;
  final String? notes;
  final double subtotal;
  final double tax;
  final double discount;
  final double total;
  final DateTime? validUntil;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const EstimateModel({
    required this.id,
    required this.adminAuthId,
    required this.clientId,
    required this.propertyId,
    required this.estimateNumber,
    required this.title,
    required this.status,
    this.scopeText,
    this.notes,
    required this.subtotal,
    required this.tax,
    required this.discount,
    required this.total,
    this.validUntil,
    this.createdAt,
    this.updatedAt,
  });

  factory EstimateModel.fromMap(Map<String, dynamic> map) {
    return EstimateModel(
      id: map['id']?.toString() ?? '',
      adminAuthId: map['admin_auth_id']?.toString() ?? '',
      clientId: map['client_id']?.toString() ?? '',
      propertyId: map['property_id']?.toString() ?? '',
      estimateNumber: map['estimate_number']?.toString() ?? '',
      title: map['title']?.toString() ?? '',
      status: map['status']?.toString() ?? 'draft',
      scopeText: map['scope_text']?.toString(),
      notes: map['notes']?.toString(),
      subtotal: _toDouble(map['subtotal']),
      tax: _toDouble(map['tax']),
      discount: _toDouble(map['discount']),
      total: _toDouble(map['total']),
      validUntil: map['valid_until'] != null
          ? DateTime.tryParse(map['valid_until'].toString())
          : null,
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
      'client_id': clientId,
      'property_id': propertyId,
      'estimate_number': estimateNumber,
      'title': title,
      'status': status,
      'scope_text': scopeText,
      'notes': notes,
      'subtotal': subtotal,
      'tax': tax,
      'discount': discount,
      'total': total,
      'valid_until': validUntil?.toIso8601String().split('T').first,
      'created_at': createdAt?.toIso8601String(),
      'updated_at': updatedAt?.toIso8601String(),
    };
  }

  Map<String, dynamic> toInsertMap() {
    return {
      'admin_auth_id': adminAuthId,
      'client_id': clientId,
      'property_id': propertyId,
      'estimate_number': estimateNumber,
      'title': title,
      'status': status,
      'scope_text': scopeText,
      'notes': notes,
      'subtotal': subtotal,
      'tax': tax,
      'discount': discount,
      'total': total,
      'valid_until': validUntil?.toIso8601String().split('T').first,
    };
  }

  EstimateModel copyWith({
    String? id,
    String? adminAuthId,
    String? clientId,
    String? propertyId,
    String? estimateNumber,
    String? title,
    String? status,
    String? scopeText,
    String? notes,
    double? subtotal,
    double? tax,
    double? discount,
    double? total,
    DateTime? validUntil,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return EstimateModel(
      id: id ?? this.id,
      adminAuthId: adminAuthId ?? this.adminAuthId,
      clientId: clientId ?? this.clientId,
      propertyId: propertyId ?? this.propertyId,
      estimateNumber: estimateNumber ?? this.estimateNumber,
      title: title ?? this.title,
      status: status ?? this.status,
      scopeText: scopeText ?? this.scopeText,
      notes: notes ?? this.notes,
      subtotal: subtotal ?? this.subtotal,
      tax: tax ?? this.tax,
      discount: discount ?? this.discount,
      total: total ?? this.total,
      validUntil: validUntil ?? this.validUntil,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  bool get isDraft => status == 'draft';
  bool get isSent => status == 'sent';
  bool get isApproved => status == 'approved';
  bool get isRejected => status == 'rejected';
  bool get isArchived => status == 'archived';
}