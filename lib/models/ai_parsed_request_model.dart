import 'ai_assumption_model.dart';
import 'ai_missing_field_model.dart';

class AiParsedRequestModel {
  final String rawPrompt;
  final String normalizedPrompt;

  final String? serviceType;
  final double? sqft;
  final int? rooms;
  final double? hours;

  final bool? materialsIncluded;
  final bool? laborOnly;

  final bool rush;
  final bool prep;

  final double confidence;

  final List<AiMissingFieldModel> missingFields;
  final List<AiAssumptionModel> assumptions;

  final List<Map<String, dynamic>> parsedMaterials;

  final bool? projectSizeRequired;
  final List<String> reasoningHints;
  final List<String> followupHints;

  const AiParsedRequestModel({
    required this.rawPrompt,
    required this.normalizedPrompt,
    this.serviceType,
    this.sqft,
    this.rooms,
    this.hours,
    this.materialsIncluded,
    this.laborOnly,
    this.rush = false,
    this.prep = false,
    this.confidence = 0,
    this.missingFields = const [],
    this.assumptions = const [],
    this.parsedMaterials = const [],
    this.projectSizeRequired,
    this.reasoningHints = const [],
    this.followupHints = const [],
  });

  factory AiParsedRequestModel.empty(String prompt) {
    return AiParsedRequestModel(
      rawPrompt: prompt,
      normalizedPrompt: prompt.trim().toLowerCase(),
    );
  }

  factory AiParsedRequestModel.fromMap(Map<String, dynamic> map) {
    return AiParsedRequestModel(
      rawPrompt: map['raw_prompt']?.toString() ?? '',
      normalizedPrompt: map['normalized_prompt']?.toString() ?? '',
      serviceType: map['service_type']?.toString(),
      sqft: _toNullableDouble(map['sqft']),
      hours: _toNullableDouble(map['hours']),
      rooms: _toNullableInt(map['rooms']),
      materialsIncluded: _toNullableBool(map['materials_included']),
      laborOnly: _toNullableBool(map['labor_only']),
      rush: _toBool(map['rush']),
      prep: _toBool(map['prep']),
      confidence: _toDouble(map['confidence']),
      missingFields: _toMissingFields(map['missing_fields']),
      assumptions: _toAssumptions(map['assumptions']),
      parsedMaterials: _toJsonMapList(map['parsed_materials']),
      projectSizeRequired: _toNullableBool(map['project_size_required']),
      reasoningHints: _toStringList(map['reasoning_hints']),
      followupHints: _toStringList(map['followup_hints']),
    );
  }

  static double _toDouble(dynamic value) {
    if (value == null) return 0;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString()) ?? 0;
  }

  static List<String> _toStringList(dynamic value) {
    if (value is! List) return const [];

    return value
        .map((item) => item.toString().trim())
        .where((item) => item.isNotEmpty)
        .toList();
  }

  static double? _toNullableDouble(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();

    final parsed = double.tryParse(value.toString());
    return parsed;
  }

  static int? _toNullableInt(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is num) return value.toInt();

    final parsed = int.tryParse(value.toString());
    return parsed;
  }

  static bool _toBool(dynamic value) {
    return _toNullableBool(value) ?? false;
  }

  static bool? _toNullableBool(dynamic value) {
    if (value == null) return null;
    if (value is bool) return value;

    final normalized = value.toString().trim().toLowerCase();

    if (normalized == 'true' || normalized == '1' || normalized == 'yes') {
      return true;
    }

    if (normalized == 'false' || normalized == '0' || normalized == 'no') {
      return false;
    }

    return null;
  }

  static List<AiMissingFieldModel> _toMissingFields(dynamic value) {
    if (value is! List) return const [];

    return value
        .whereType<Map>()
        .map((item) => AiMissingFieldModel.fromMap(
      Map<String, dynamic>.from(item),
    ))
        .toList();
  }

  static List<AiAssumptionModel> _toAssumptions(dynamic value) {
    if (value is! List) return const [];

    return value
        .whereType<Map>()
        .map((item) => AiAssumptionModel.fromMap(
      Map<String, dynamic>.from(item),
    ))
        .toList();
  }

  static List<Map<String, dynamic>> _toJsonMapList(dynamic value) {
    if (value is! List) return const [];

    return value
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
  }

  bool get hasMissingRequiredFields {
    return missingFields.any((field) => field.isRequired);
  }

  bool get hasAreaInfo {
    return (sqft ?? 0) > 0 || (rooms ?? 0) > 0;
  }

  bool get hasParsedMaterials {
    return parsedMaterials.isNotEmpty;
  }

  bool get canBuildDraft {
    final hasServiceType = (serviceType ?? '').trim().isNotEmpty;
    if (!hasServiceType) return false;

    if (parsedMaterials.isNotEmpty) {
      return true;
    }

    return !hasMissingRequiredFields;
  }

  Map<String, dynamic> toMap() {
    return {
      'raw_prompt': rawPrompt,
      'normalized_prompt': normalizedPrompt,
      'service_type': serviceType,
      'sqft': sqft,
      'rooms': rooms,
      'hours': hours,
      'materials_included': materialsIncluded,
      'labor_only': laborOnly,
      'rush': rush,
      'prep': prep,
      'confidence': confidence,
      'missing_fields': missingFields.map((item) => item.toMap()).toList(),
      'assumptions': assumptions.map((item) => item.toMap()).toList(),
      'parsed_materials': parsedMaterials,
      'project_size_required': projectSizeRequired,
      'reasoning_hints': reasoningHints,
      'followup_hints': followupHints,
    };
  }

  AiParsedRequestModel copyWith({
    String? rawPrompt,
    String? normalizedPrompt,
    String? serviceType,
    double? sqft,
    int? rooms,
    double? hours,
    bool? materialsIncluded,
    bool? laborOnly,
    bool? rush,
    bool? prep,
    double? confidence,
    List<AiMissingFieldModel>? missingFields,
    List<AiAssumptionModel>? assumptions,
    List<Map<String, dynamic>>? parsedMaterials,
    bool? projectSizeRequired,
    List<String>? reasoningHints,
    List<String>? followupHints,
  }) {
    return AiParsedRequestModel(
      rawPrompt: rawPrompt ?? this.rawPrompt,
      normalizedPrompt: normalizedPrompt ?? this.normalizedPrompt,
      serviceType: serviceType ?? this.serviceType,
      sqft: sqft ?? this.sqft,
      rooms: rooms ?? this.rooms,
      hours: hours ?? this.hours,
      materialsIncluded: materialsIncluded ?? this.materialsIncluded,
      laborOnly: laborOnly ?? this.laborOnly,
      rush: rush ?? this.rush,
      prep: prep ?? this.prep,
      confidence: confidence ?? this.confidence,
      missingFields: missingFields ?? this.missingFields,
      assumptions: assumptions ?? this.assumptions,
      parsedMaterials: parsedMaterials ?? this.parsedMaterials,
      projectSizeRequired: projectSizeRequired ?? this.projectSizeRequired,
      reasoningHints: reasoningHints ?? this.reasoningHints,
      followupHints: followupHints ?? this.followupHints,
    );
  }
}