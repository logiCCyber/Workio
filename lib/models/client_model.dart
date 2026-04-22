class ClientModel {
  final String id;
  final String adminAuthId;
  final String fullName;
  final String? phone;
  final String? email;
  final String? companyName;
  final String? notes;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final bool isArchived;

  const ClientModel({
    required this.id,
    required this.adminAuthId,
    required this.fullName,
    this.phone,
    this.email,
    this.companyName,
    this.notes,
    this.createdAt,
    this.updatedAt,
    this.isArchived = false,
  });

  factory ClientModel.fromMap(Map<String, dynamic> map) {
    return ClientModel(
      id: map['id']?.toString() ?? '',
      adminAuthId: map['admin_auth_id']?.toString() ?? '',
      fullName: map['full_name']?.toString() ?? '',
      phone: map['phone']?.toString(),
      email: map['email']?.toString(),
      companyName: map['company_name']?.toString(),
      notes: map['notes']?.toString(),
      isArchived: map['is_archived'] == true,
      createdAt: map['created_at'] != null
          ? DateTime.tryParse(map['created_at'].toString())
          : null,
      updatedAt: map['updated_at'] != null
          ? DateTime.tryParse(map['updated_at'].toString())
          : null,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'admin_auth_id': adminAuthId,
      'full_name': fullName,
      'phone': phone,
      'email': email,
      'company_name': companyName,
      'is_archived': isArchived,
      'notes': notes,
      'created_at': createdAt?.toIso8601String(),
      'updated_at': updatedAt?.toIso8601String(),
    };
  }

  Map<String, dynamic> toInsertMap() {
    return {
      'admin_auth_id': adminAuthId,
      'full_name': fullName,
      'is_archived': isArchived,
      'phone': phone,
      'email': email,
      'company_name': companyName,
      'notes': notes,
    };
  }

  ClientModel copyWith({
    String? id,
    String? adminAuthId,
    String? fullName,
    String? phone,
    String? email,
    String? companyName,
    String? notes,
    DateTime? createdAt,
    DateTime? updatedAt,
    bool? isArchived,
  }) {
    return ClientModel(
      id: id ?? this.id,
      adminAuthId: adminAuthId ?? this.adminAuthId,
      fullName: fullName ?? this.fullName,
      phone: phone ?? this.phone,
      email: email ?? this.email,
      companyName: companyName ?? this.companyName,
      notes: notes ?? this.notes,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      isArchived: isArchived ?? this.isArchived,
    );
  }
}