class PropertyModel {
  final String id;
  final String adminAuthId;
  final String clientId;
  final String addressLine1;
  final String? addressLine2;
  final String? city;
  final String? province;
  final String? postalCode;
  final double squareFootage;
  final String? propertyType;
  final String? notes;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final bool isArchived;

  const PropertyModel({
    required this.id,
    required this.adminAuthId,
    required this.clientId,
    required this.addressLine1,
    this.addressLine2,
    this.city,
    this.province,
    this.postalCode,
    this.squareFootage = 0,
    this.propertyType,
    this.notes,
    this.createdAt,
    this.updatedAt,
    this.isArchived = false,
  });

  factory PropertyModel.fromMap(Map<String, dynamic> map) {
    return PropertyModel(
      id: map['id']?.toString() ?? '',
      adminAuthId: map['admin_auth_id']?.toString() ?? '',
      clientId: map['client_id']?.toString() ?? '',
      isArchived: map['is_archived'] == true,
      addressLine1: map['address_line_1']?.toString() ?? '',
      addressLine2: map['address_line_2']?.toString(),
      city: map['city']?.toString(),
      province: map['province']?.toString(),
      postalCode: map['postal_code']?.toString(),
      squareFootage: _toDouble(map['square_footage']),
      propertyType: map['property_type']?.toString(),
      notes: map['notes']?.toString(),
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
      'address_line_1': addressLine1,
      'address_line_2': addressLine2,
      'city': city,
      'province': province,
      'postal_code': postalCode,
      'square_footage': squareFootage,
      'property_type': propertyType,
      'notes': notes,
      'is_archived': isArchived,
      'created_at': createdAt?.toIso8601String(),
      'updated_at': updatedAt?.toIso8601String(),
    };
  }

  Map<String, dynamic> toInsertMap() {
    return {
      'admin_auth_id': adminAuthId,
      'client_id': clientId,
      'address_line_1': addressLine1,
      'address_line_2': addressLine2,
      'city': city,
      'province': province,
      'postal_code': postalCode,
      'square_footage': squareFootage,
      'property_type': propertyType,
      'notes': notes,
      'is_archived': isArchived,
    };
  }

  PropertyModel copyWith({
    String? id,
    String? adminAuthId,
    bool? isArchived,
    String? clientId,
    String? addressLine1,
    String? addressLine2,
    String? city,
    String? province,
    String? postalCode,
    double? squareFootage,
    String? propertyType,
    String? notes,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return PropertyModel(
      id: id ?? this.id,
      adminAuthId: adminAuthId ?? this.adminAuthId,
      isArchived: isArchived ?? this.isArchived,
      clientId: clientId ?? this.clientId,
      addressLine1: addressLine1 ?? this.addressLine1,
      addressLine2: addressLine2 ?? this.addressLine2,
      city: city ?? this.city,
      province: province ?? this.province,
      postalCode: postalCode ?? this.postalCode,
      squareFootage: squareFootage ?? this.squareFootage,
      propertyType: propertyType ?? this.propertyType,
      notes: notes ?? this.notes,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  String get fullAddress {
    final parts = [
      addressLine1,
      if ((addressLine2 ?? '').trim().isNotEmpty) addressLine2,
      if ((city ?? '').trim().isNotEmpty) city,
      if ((province ?? '').trim().isNotEmpty) province,
      if ((postalCode ?? '').trim().isNotEmpty) postalCode,
    ];
    return parts.whereType<String>().join(', ');
  }
}