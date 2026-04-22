class EstimatePriceRuleModel {
  final String id;
  final String? adminAuthId;
  final String serviceType;
  final String category;
  final String unit;
  final double baseRate;
  final double? materialRatePerSqft;
  final double? materialFixedRate;
  final double? prepFixedRate;
  final double? rushFixedRate;
  final double? singleCoatRate;
  final double? multiCoatRate;
  final bool isActive;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final String? displayName;
  final List<String> aliases;
  final List<String> aiKeywords;
  final String? aiScopeTemplate;
  final String? aiNotesTemplate;
  final String? aiLaborTitle;
  final String? aiLaborDescription;
  final String? aiMaterialsTitle;
  final String? aiMaterialsDescription;
  final String? aiPrepTitle;
  final String? aiPrepDescription;
  final String? aiRushTitle;
  final String? aiRushDescription;
  final List<Map<String, dynamic>> aiFollowupQuestions;

  const EstimatePriceRuleModel({
    required this.id,
    this.adminAuthId,
    required this.serviceType,
    required this.category,
    required this.unit,
    required this.baseRate,
    this.materialRatePerSqft,
    this.materialFixedRate,
    this.prepFixedRate,
    this.rushFixedRate,
    this.singleCoatRate,
    this.multiCoatRate,
    this.isActive = true,
    this.createdAt,
    this.updatedAt,
    this.displayName,
    this.aliases = const [],
    this.aiKeywords = const [],
    this.aiScopeTemplate,
    this.aiNotesTemplate,
    this.aiLaborTitle,
    this.aiLaborDescription,
    this.aiMaterialsTitle,
    this.aiMaterialsDescription,
    this.aiPrepTitle,
    this.aiPrepDescription,
    this.aiRushTitle,
    this.aiRushDescription,
    this.aiFollowupQuestions = const [],
  });

  factory EstimatePriceRuleModel.fromMap(Map<String, dynamic> map) {
    return EstimatePriceRuleModel(
      id: map['id']?.toString() ?? '',
      adminAuthId: map['admin_auth_id']?.toString(),
      serviceType: map['service_type']?.toString() ?? '',
      category: map['category']?.toString() ?? '',
      unit: map['unit']?.toString() ?? '',
      baseRate: _toDouble(map['base_rate']),
      displayName: map['display_name']?.toString(),
      aliases: _toStringList(map['aliases']),
      materialRatePerSqft: _toNullableDouble(map['material_rate_per_sqft']),
      materialFixedRate: _toNullableDouble(map['material_fixed_rate']),
      prepFixedRate: _toNullableDouble(map['prep_fixed_rate']),
      rushFixedRate: _toNullableDouble(map['rush_fixed_rate']),
      singleCoatRate: _toNullableDouble(map['single_coat_rate']),
      multiCoatRate: _toNullableDouble(map['multi_coat_rate']),
      aiFollowupQuestions: _toJsonMapList(map['ai_followup_questions']),
      aiKeywords: _toStringList(map['ai_keywords']),
      aiScopeTemplate: map['ai_scope_template']?.toString(),
      aiNotesTemplate: map['ai_notes_template']?.toString(),
      aiLaborTitle: map['ai_labor_title']?.toString(),
      aiLaborDescription: map['ai_labor_description']?.toString(),
      aiMaterialsTitle: map['ai_materials_title']?.toString(),
      aiMaterialsDescription: map['ai_materials_description']?.toString(),
      aiPrepTitle: map['ai_prep_title']?.toString(),
      aiPrepDescription: map['ai_prep_description']?.toString(),
      aiRushTitle: map['ai_rush_title']?.toString(),
      aiRushDescription: map['ai_rush_description']?.toString(),
      isActive: _toBool(map['is_active'], fallback: true),
      createdAt: map['created_at'] != null
          ? DateTime.tryParse(map['created_at'].toString())
          : null,
      updatedAt: map['updated_at'] != null
          ? DateTime.tryParse(map['updated_at'].toString())
          : null,
    );
  }

  static List<String> _toStringList(dynamic value) {
    if (value is List) {
      return value.map((item) => item.toString()).toList();
    }
    return const [];
  }

  static double _toDouble(dynamic value) {
    if (value == null) return 0;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString()) ?? 0;
  }

  static List<Map<String, dynamic>> _toJsonMapList(dynamic value) {
    if (value is! List) return const [];

    return value
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
  }

  static double? _toNullableDouble(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString());
  }

  static bool _toBool(dynamic value, {bool fallback = false}) {
    if (value == null) return fallback;
    if (value is bool) return value;

    final normalized = value.toString().trim().toLowerCase();

    if (normalized == 'true' || normalized == '1' || normalized == 'yes') {
      return true;
    }

    if (normalized == 'false' || normalized == '0' || normalized == 'no') {
      return false;
    }

    return fallback;
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'admin_auth_id': adminAuthId,
      'service_type': serviceType,
      'category': category,
      'unit': unit,
      'base_rate': baseRate,
      'display_name': displayName,
      'aliases': aliases,
      'material_rate_per_sqft': materialRatePerSqft,
      'material_fixed_rate': materialFixedRate,
      'prep_fixed_rate': prepFixedRate,
      'rush_fixed_rate': rushFixedRate,
      'single_coat_rate': singleCoatRate,
      'multi_coat_rate': multiCoatRate,
      'is_active': isActive,
      'created_at': createdAt?.toIso8601String(),
      'updated_at': updatedAt?.toIso8601String(),
      'ai_keywords': aiKeywords,
      'ai_scope_template': aiScopeTemplate,
      'ai_notes_template': aiNotesTemplate,
      'ai_labor_title': aiLaborTitle,
      'ai_labor_description': aiLaborDescription,
      'ai_materials_title': aiMaterialsTitle,
      'ai_materials_description': aiMaterialsDescription,
      'ai_prep_title': aiPrepTitle,
      'ai_prep_description': aiPrepDescription,
      'ai_rush_title': aiRushTitle,
      'ai_rush_description': aiRushDescription,
      'ai_followup_questions': aiFollowupQuestions,
    };
  }

  EstimatePriceRuleModel copyWith({
    String? id,
    String? adminAuthId,
    String? serviceType,
    String? category,
    String? unit,
    String? displayName,
    List<String>? aiKeywords,
    String? aiScopeTemplate,
    String? aiNotesTemplate,
    String? aiLaborTitle,
    String? aiLaborDescription,
    String? aiMaterialsTitle,
    String? aiMaterialsDescription,
    String? aiPrepTitle,
    String? aiPrepDescription,
    String? aiRushTitle,
    String? aiRushDescription,
    List<String>? aliases,
    double? baseRate,
    double? materialRatePerSqft,
    double? materialFixedRate,
    double? prepFixedRate,
    double? rushFixedRate,
    double? singleCoatRate,
    double? multiCoatRate,
    bool? isActive,
    DateTime? createdAt,
    DateTime? updatedAt,
    List<Map<String, dynamic>>? aiFollowupQuestions,
  }) {
    return EstimatePriceRuleModel(
      id: id ?? this.id,
      adminAuthId: adminAuthId ?? this.adminAuthId,
      serviceType: serviceType ?? this.serviceType,
      category: category ?? this.category,
      unit: unit ?? this.unit,
      baseRate: baseRate ?? this.baseRate,
      displayName: displayName ?? this.displayName,
      aliases: aliases ?? this.aliases,
      materialRatePerSqft: materialRatePerSqft ?? this.materialRatePerSqft,
      materialFixedRate: materialFixedRate ?? this.materialFixedRate,
      prepFixedRate: prepFixedRate ?? this.prepFixedRate,
      rushFixedRate: rushFixedRate ?? this.rushFixedRate,
      singleCoatRate: singleCoatRate ?? this.singleCoatRate,
      multiCoatRate: multiCoatRate ?? this.multiCoatRate,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      aiKeywords: aiKeywords ?? this.aiKeywords,
      aiScopeTemplate: aiScopeTemplate ?? this.aiScopeTemplate,
      aiNotesTemplate: aiNotesTemplate ?? this.aiNotesTemplate,
      aiLaborTitle: aiLaborTitle ?? this.aiLaborTitle,
      aiLaborDescription: aiLaborDescription ?? this.aiLaborDescription,
      aiMaterialsTitle: aiMaterialsTitle ?? this.aiMaterialsTitle,
      aiMaterialsDescription: aiMaterialsDescription ?? this.aiMaterialsDescription,
      aiPrepTitle: aiPrepTitle ?? this.aiPrepTitle,
      aiPrepDescription: aiPrepDescription ?? this.aiPrepDescription,
      aiRushTitle: aiRushTitle ?? this.aiRushTitle,
      aiRushDescription: aiRushDescription ?? this.aiRushDescription,
      aiFollowupQuestions: aiFollowupQuestions ?? this.aiFollowupQuestions,
    );
  }
}