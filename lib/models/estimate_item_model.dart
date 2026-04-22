class EstimateItemModel {
  final String id;
  final String estimateId;
  final String title;
  final String? description;
  final String unit;
  final double quantity;
  final double unitPrice;
  final double lineTotal;
  final int sortOrder;
  final DateTime? createdAt;

  const EstimateItemModel({
    required this.id,
    required this.estimateId,
    required this.title,
    this.description,
    required this.unit,
    required this.quantity,
    required this.unitPrice,
    required this.lineTotal,
    required this.sortOrder,
    this.createdAt,
  });

  factory EstimateItemModel.fromMap(Map<String, dynamic> map) {
    return EstimateItemModel(
      id: map['id']?.toString() ?? '',
      estimateId: map['estimate_id']?.toString() ?? '',
      title: map['title']?.toString() ?? '',
      description: map['description']?.toString(),
      unit: map['unit']?.toString() ?? 'fixed',
      quantity: _toDouble(map['quantity']),
      unitPrice: _toDouble(map['unit_price']),
      lineTotal: _toDouble(map['line_total']),
      sortOrder: _toInt(map['sort_order']),
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

  static int _toInt(dynamic value) {
    if (value == null) return 0;
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value.toString()) ?? 0;
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'estimate_id': estimateId,
      'title': title,
      'description': description,
      'unit': unit,
      'quantity': quantity,
      'unit_price': unitPrice,
      'line_total': lineTotal,
      'sort_order': sortOrder,
      'created_at': createdAt?.toIso8601String(),
    };
  }

  Map<String, dynamic> toInsertMap() {
    return {
      'estimate_id': estimateId,
      'title': title,
      'description': description,
      'unit': unit,
      'quantity': quantity,
      'unit_price': unitPrice,
      'line_total': lineTotal,
      'sort_order': sortOrder,
    };
  }

  EstimateItemModel copyWith({
    String? id,
    String? estimateId,
    String? title,
    String? description,
    String? unit,
    double? quantity,
    double? unitPrice,
    double? lineTotal,
    int? sortOrder,
    DateTime? createdAt,
  }) {
    return EstimateItemModel(
      id: id ?? this.id,
      estimateId: estimateId ?? this.estimateId,
      title: title ?? this.title,
      description: description ?? this.description,
      unit: unit ?? this.unit,
      quantity: quantity ?? this.quantity,
      unitPrice: unitPrice ?? this.unitPrice,
      lineTotal: lineTotal ?? this.lineTotal,
      sortOrder: sortOrder ?? this.sortOrder,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  EstimateItemModel recalculate() {
    final total = quantity * unitPrice;
    return copyWith(lineTotal: total);
  }
}