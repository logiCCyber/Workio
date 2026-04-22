class EstimateTemplateModel {
  final String id;
  final String adminAuthId;
  final String name;
  final String? serviceType;
  final String? defaultScopeText;
  final String? defaultNotes;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const EstimateTemplateModel({
    required this.id,
    required this.adminAuthId,
    required this.name,
    this.serviceType,
    this.defaultScopeText,
    this.defaultNotes,
    this.createdAt,
    this.updatedAt,
  });

  factory EstimateTemplateModel.fromMap(Map<String, dynamic> map) {
    return EstimateTemplateModel(
      id: map['id']?.toString() ?? '',
      adminAuthId: map['admin_auth_id']?.toString() ?? '',
      name: map['name']?.toString() ?? '',
      serviceType: map['service_type']?.toString(),
      defaultScopeText: map['default_scope_text']?.toString(),
      defaultNotes: map['default_notes']?.toString(),
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
      'name': name,
      'service_type': serviceType,
      'default_scope_text': defaultScopeText,
      'default_notes': defaultNotes,
      'created_at': createdAt?.toIso8601String(),
      'updated_at': updatedAt?.toIso8601String(),
    };
  }

  Map<String, dynamic> toInsertMap() {
    return {
      'admin_auth_id': adminAuthId,
      'name': name,
      'service_type': serviceType,
      'default_scope_text': defaultScopeText,
      'default_notes': defaultNotes,
    };
  }

  EstimateTemplateModel copyWith({
    String? id,
    String? adminAuthId,
    String? name,
    String? serviceType,
    String? defaultScopeText,
    String? defaultNotes,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return EstimateTemplateModel(
      id: id ?? this.id,
      adminAuthId: adminAuthId ?? this.adminAuthId,
      name: name ?? this.name,
      serviceType: serviceType ?? this.serviceType,
      defaultScopeText: defaultScopeText ?? this.defaultScopeText,
      defaultNotes: defaultNotes ?? this.defaultNotes,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}