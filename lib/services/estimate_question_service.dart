import '../models/ai_assumption_model.dart';
import '../models/ai_missing_field_model.dart';
import '../models/ai_parsed_request_model.dart';
import 'estimate_price_rules_service.dart';

class EstimateQuestionService {
  EstimateQuestionService._();

  static Future<AiParsedRequestModel> enrich(AiParsedRequestModel parsed) async {
    final assumptions = <AiAssumptionModel>[
      ...parsed.assumptions,
    ];

    String? serviceType = _cleanString(parsed.serviceType);
    double? sqft = _positiveDoubleOrNull(parsed.sqft);
    int? rooms = _positiveIntOrNull(parsed.rooms);
    final parsedMaterials = parsed.parsedMaterials;
    final projectSizeRequired = parsed.projectSizeRequired;

    bool? materialsIncluded = parsed.materialsIncluded;
    bool? laborOnly = parsed.laborOnly;

    final rush = parsed.rush;
    final prep = parsed.prep;

    if (laborOnly == true) {
      materialsIncluded = false;
    }

    if (materialsIncluded == true) {
      laborOnly = false;
    }

    final serviceTypeOptions = await _loadServiceTypeOptions();
    final currentRule = await _loadMainRule(serviceType);

    final missingFields = _buildMissingFields(
      projectSizeRequired: projectSizeRequired,
      parsedMaterials: parsedMaterials,
      serviceType: serviceType,
      sqft: sqft,
      rooms: rooms,
      materialsIncluded: materialsIncluded,
      laborOnly: laborOnly,
      serviceTypeOptions: serviceTypeOptions,
      currentRule: currentRule,
    );

    final confidence = _recalculateConfidence(
      parsed: parsed,
      serviceType: serviceType,
      sqft: sqft,
      rooms: rooms,
      materialsIncluded: materialsIncluded,
      laborOnly: laborOnly,
      missingFields: missingFields,
      parsedMaterials: parsedMaterials,
    );

    return parsed.copyWith(
      serviceType: serviceType,
      sqft: sqft,
      rooms: rooms,
      materialsIncluded: materialsIncluded,
      laborOnly: laborOnly,
      assumptions: _uniqueAssumptions(assumptions),
      missingFields: missingFields,
      confidence: confidence,
      rush: rush,
      prep: prep,
      projectSizeRequired: projectSizeRequired,
    );
  }

  static Future<AiParsedRequestModel> applyAnswers(
      AiParsedRequestModel parsed,
      Map<String, dynamic> answers,
      ) async {
    String? serviceType = parsed.serviceType;
    double? sqft = parsed.sqft;
    int? rooms = parsed.rooms;

    bool? materialsIncluded = parsed.materialsIncluded;
    bool? laborOnly = parsed.laborOnly;

    bool rush = parsed.rush;
    bool prep = parsed.prep;

    if (answers.containsKey('service_type')) {
      serviceType = _normalizeServiceType(answers['service_type']);
    }

    if (answers.containsKey('sqft')) {
      sqft = _parseNullableDouble(answers['sqft']);
      if ((sqft ?? 0) <= 0) {
        sqft = null;
      }
    }

    if (answers.containsKey('rooms')) {
      rooms = _parseNullableInt(answers['rooms']);
      if ((rooms ?? 0) <= 0) {
        rooms = null;
      }
    }

    if (answers.containsKey('project_size')) {
      final projectSize = answers['project_size']?.toString().trim() ?? '';
      final parsedSqft = _extractSqftFromText(projectSize);
      final parsedRooms = _extractRoomsFromText(projectSize);

      if ((parsedSqft ?? 0) > 0) {
        sqft = parsedSqft;
      } else if ((parsedRooms ?? 0) > 0) {
        rooms = parsedRooms;
      }
    }

    if (answers.containsKey('materials_included')) {
      materialsIncluded = _parseNullableBool(answers['materials_included']);
    }

    if (answers.containsKey('labor_only')) {
      laborOnly = _parseNullableBool(answers['labor_only']);
    }

    if (answers.containsKey('materials')) {
      final value = answers['materials']?.toString().trim().toLowerCase() ?? '';

      if (value == 'materials included') {
        materialsIncluded = true;
        laborOnly = false;
      } else if (value == 'labor only') {
        laborOnly = true;
        materialsIncluded = false;
      }
    }

    if (answers.containsKey('rush')) {
      rush = _parseNullableBool(answers['rush']) ?? rush;
    }

    if (answers.containsKey('prep')) {
      prep = _parseNullableBool(answers['prep']) ?? prep;
    }

    final updated = parsed.copyWith(
      serviceType: serviceType,
      sqft: sqft,
      rooms: rooms,
      materialsIncluded: materialsIncluded,
      laborOnly: laborOnly,
      rush: rush,
      prep: prep,
    );

    return await enrich(updated);
  }

  static Future<List<String>> _loadServiceTypeOptions() async {
    final result = <String>[];
    final seen = <String>{};

    try {
      final rules = await EstimatePriceRulesService.getRules();

      for (final rule in rules) {
        final value = rule.serviceType.trim().toLowerCase();
        if (value.isEmpty) continue;

        if (seen.add(value)) {
          result.add(value);
        }
      }
    } catch (_) {}

    return result;
  }

  static List<AiMissingFieldModel> _buildMissingFields({
    required String? serviceType,
    required double? sqft,
    required int? rooms,
    required bool? materialsIncluded,
    required bool? laborOnly,
    required List<Map<String, dynamic>> parsedMaterials,
    required List<String> serviceTypeOptions,
    required dynamic currentRule,
    required bool? projectSizeRequired,
  }) {
    final fields = <AiMissingFieldModel>[];

    if (_isBlank(serviceType)) {
      fields.add(
        AiMissingFieldModel(
          key: 'service_type',
          question: 'What kind of work is this?',
          isRequired: true,
          answerType: 'single_select',
          options: serviceTypeOptions,
          hint: 'Choose the main job type before estimate generation.',
        ),
      );
    }

    final hasAreaInfo = (sqft ?? 0) > 0 || (rooms ?? 0) > 0;
    final hasDetailedMaterials = parsedMaterials.isNotEmpty;

    final requiresProjectSize = _resolveProjectSizeRequired(
      serviceType: serviceType,
      currentRule: currentRule,
      projectSizeRequired: projectSizeRequired,
      hasDetailedMaterials: hasDetailedMaterials,
    );

    if (requiresProjectSize && !hasAreaInfo) {
      fields.add(
        const AiMissingFieldModel(
          key: 'project_size',
          question: 'What is the approximate size: sqft or number of rooms?',
          isRequired: true,
          answerType: 'text',
          hint: 'Example: 1200 sqft or 3 rooms.',
        ),
      );
    }

    if (materialsIncluded == null && laborOnly == null) {
      fields.add(
        const AiMissingFieldModel(
          key: 'materials',
          question: 'Are materials included, or is this labor only?',
          isRequired: true,
          answerType: 'single_select',
          options: [
            'materials included',
            'labor only',
          ],
          hint: 'This affects pricing and item structure.',
        ),
      );
    }

    fields.addAll(
      _buildRuleFollowupFields(
        rule: currentRule,
        serviceType: serviceType,
        parsedMaterials: parsedMaterials,
        sqft: sqft,
        rooms: rooms,
        materialsIncluded: materialsIncluded,
        laborOnly: laborOnly,
      ),
    );
    return _uniqueMissingFields(fields);
  }

  static bool _resolveProjectSizeRequired({
    required String? serviceType,
    required dynamic currentRule,
    required bool? projectSizeRequired,
    required bool hasDetailedMaterials,
  }) {
    final normalizedUnit =
    (currentRule?.unit ?? '').toString().trim().toLowerCase();

    // Price Rule unit is the main truth.
    // Fixed/item/hour services should NOT ask for sqft or rooms.
    if (normalizedUnit == 'fixed' ||
        normalizedUnit == 'item' ||
        normalizedUnit == 'hour') {
      return false;
    }

    // Only size-based rules require size.
    if (normalizedUnit == 'sqft' || normalizedUnit == 'room') {
      return true;
    }

    // Fallback only when unit is unknown.
    if (projectSizeRequired == true && !hasDetailedMaterials) {
      return true;
    }

    return false;
  }

  static double _recalculateConfidence({
    required AiParsedRequestModel parsed,
    required String? serviceType,
    required double? sqft,
    required int? rooms,
    required bool? materialsIncluded,
    required bool? laborOnly,
    required List<AiMissingFieldModel> missingFields,
    required List<Map<String, dynamic>> parsedMaterials,
  }) {
    double score = 0.12;

    if (!_isBlank(serviceType)) {
      score += 0.24;
    }

    if ((sqft ?? 0) > 0 || (rooms ?? 0) > 0) {
      score += 0.20;
    }

    if (materialsIncluded != null || laborOnly != null) {
      score += 0.16;
    }

    if (parsedMaterials.isNotEmpty) {
      score += 0.12;
    }

    if (!_isBlank(serviceType)) {
      score += 0.08;
    }

    if (parsed.rush) {
      score += 0.03;
    }

    if (parsed.prep) {
      score += 0.03;
    }

    final requiredMissingCount =
        missingFields.where((field) => field.isRequired).length;
    final optionalMissingCount =
        missingFields.where((field) => !field.isRequired).length;

    score -= requiredMissingCount * 0.10;
    score -= optionalMissingCount * 0.03;

    final clamped = score.clamp(0.05, 0.98);
    return double.parse(clamped.toStringAsFixed(2));
  }

  static List<AiMissingFieldModel> _uniqueMissingFields(
      List<AiMissingFieldModel> fields,
      ) {
    final map = <String, AiMissingFieldModel>{};

    for (final field in fields) {
      final key = field.key.trim();
      if (key.isEmpty) continue;
      map[key] = field;
    }

    return map.values.toList();
  }

  static List<AiAssumptionModel> _uniqueAssumptions(
      List<AiAssumptionModel> assumptions,
      ) {
    final map = <String, AiAssumptionModel>{};

    for (final item in assumptions) {
      final key = item.key.trim();
      if (key.isEmpty) continue;
      map[key] = item;
    }

    return map.values.toList();
  }

  static String? _normalizeServiceType(dynamic value) {
    final text = value?.toString().trim().toLowerCase() ?? '';
    return text.isEmpty ? null : text;
  }

  static double? _parseNullableDouble(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();

    final normalized = value.toString().trim().replaceAll(',', '.');
    return double.tryParse(normalized);
  }

  static int? _parseNullableInt(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is num) return value.toInt();

    return int.tryParse(value.toString().trim());
  }

  static bool? _parseNullableBool(dynamic value) {
    if (value == null) return null;
    if (value is bool) return value;

    final normalized = value.toString().trim().toLowerCase();

    if (normalized == 'true' ||
        normalized == '1' ||
        normalized == 'yes' ||
        normalized == 'y') {
      return true;
    }

    if (normalized == 'false' ||
        normalized == '0' ||
        normalized == 'no' ||
        normalized == 'n') {
      return false;
    }

    return null;
  }

  static double? _extractSqftFromText(String value) {
    final text = value.toLowerCase().trim();

    final leadingUnitPatterns = [
      RegExp(
        r'\b(?:sq\s*\.?\s*ft|sqft|sf|square feet|square foot)\s*(\d+(?:[.,]\d+)?)\b',
      ),
    ];

    final trailingUnitPatterns = [
      RegExp(
        r'\b(\d+(?:[.,]\d+)?)\s*(?:sq\s*\.?\s*ft|sqft|sf|square feet|square foot)\b',
      ),
      RegExp(r'^(\d+(?:[.,]\d+)?)$'),
    ];

    for (final pattern in leadingUnitPatterns) {
      final match = pattern.firstMatch(text);
      if (match == null) continue;

      final raw = (match.group(1) ?? '').replaceAll(',', '.');
      final parsed = double.tryParse(raw);

      if (parsed != null && parsed > 0) {
        return parsed;
      }
    }

    for (final pattern in trailingUnitPatterns) {
      final match = pattern.firstMatch(text);
      if (match == null) continue;

      final raw = (match.group(1) ?? '').replaceAll(',', '.');
      final parsed = double.tryParse(raw);

      if (parsed != null && parsed > 0) {
        return parsed;
      }
    }

    return null;
  }

  static int? _extractRoomsFromText(String value) {
    final text = value.toLowerCase().trim();

    final leadingUnitPatterns = [
      RegExp(r'\b(?:room|rooms|bedroom|bedrooms)\s*(\d+)\b'),
      RegExp(r'\b(?:комната|комнаты|комнат)\s*(\d+)\b'),
    ];

    final trailingUnitPatterns = [
      RegExp(r'\b(\d+)\s*(?:room|rooms|bedroom|bedrooms)\b'),
      RegExp(r'\b(\d+)\s*(?:комната|комнаты|комнат)\b'),
    ];

    for (final pattern in leadingUnitPatterns) {
      final match = pattern.firstMatch(text);
      if (match == null) continue;

      final parsed = int.tryParse(match.group(1) ?? '');
      if (parsed != null && parsed > 0) {
        return parsed;
      }
    }

    for (final pattern in trailingUnitPatterns) {
      final match = pattern.firstMatch(text);
      if (match == null) continue;

      final parsed = int.tryParse(match.group(1) ?? '');
      if (parsed != null && parsed > 0) {
        return parsed;
      }
    }

    return null;
  }

  static String? _cleanString(String? value) {
    final cleaned = value?.trim();
    if (cleaned == null || cleaned.isEmpty) return null;
    return cleaned;
  }

  static double? _positiveDoubleOrNull(double? value) {
    if (value == null || value <= 0) return null;
    return value;
  }

  static int? _positiveIntOrNull(int? value) {
    if (value == null || value <= 0) return null;
    return value;
  }

  static bool _isBlank(String? value) {
    return value == null || value.trim().isEmpty;
  }

  static Future<dynamic> _loadMainRule(String? serviceType) async {
    final normalized = (serviceType ?? '').trim().toLowerCase();
    if (normalized.isEmpty) return null;

    try {
      return await EstimatePriceRulesService.findMainRule(normalized);
    } catch (_) {
      return null;
    }
  }

  static List<AiMissingFieldModel> _buildRuleFollowupFields({
    required dynamic rule,
    required String? serviceType,
    required List<Map<String, dynamic>> parsedMaterials,
    required double? sqft,
    required int? rooms,
    required bool? materialsIncluded,
    required bool? laborOnly,
  }) {
    if (rule == null) return const [];

    final raw = rule.aiFollowupQuestions;
    if (raw is! List || raw.isEmpty) return const [];

    final fields = <AiMissingFieldModel>[];

    for (final item in raw) {
      if (item is! Map) continue;

      final map = Map<String, dynamic>.from(item);
      final key = (map['key'] ?? '').toString().trim();
      final answerType = (map['answerType'] ?? '').toString().trim();
      final rawQuestion = (map['question'] ?? '').toString().trim();
      final rawHint = (map['hint'] ?? '').toString().trim();
      final isRequired = map['isRequired'] == true;

      final question = _applyFollowupTemplate(
        rawQuestion,
        serviceType: serviceType,
        rule: rule,
      );

      final hint = _applyFollowupTemplate(
        rawHint,
        serviceType: serviceType,
        rule: rule,
      );

      final effectiveIsRequired = false;

      if (key.isEmpty || question.isEmpty || answerType.isEmpty) {
        continue;
      }

      final options = (map['options'] is List)
          ? (map['options'] as List)
          .map((e) => e.toString().trim())
          .where((e) => e.isNotEmpty)
          .toList()
          : const <String>[];

      if (_shouldSkipRuleQuestion(
        key: key,
        sqft: sqft,
        rooms: rooms,
        materialsIncluded: materialsIncluded,
        laborOnly: laborOnly,
        parsedMaterials: parsedMaterials,
      )) {
        continue;
      }

      fields.add(
        AiMissingFieldModel(
          key: key,
          question: question,
          isRequired: effectiveIsRequired,
          answerType: answerType,
          options: options,
          hint: hint.isEmpty ? null : hint,
        ),
      );
    }

    return fields;
  }

  static bool _shouldSkipRuleQuestion({
    required String key,
    required double? sqft,
    required int? rooms,
    required bool? materialsIncluded,
    required bool? laborOnly,
    required List<Map<String, dynamic>> parsedMaterials,
  }) {
    final normalizedKey = key.trim().toLowerCase();

    if (normalizedKey == 'project_size' &&
        ((sqft ?? 0) > 0 || (rooms ?? 0) > 0)) {
      return true;
    }

    if (normalizedKey == 'materials_selection' && parsedMaterials.isNotEmpty) {
      return true;
    }

    if ((normalizedKey == 'materials' ||
        normalizedKey == 'materials_included' ||
        normalizedKey == 'labor_only') &&
        (materialsIncluded != null || laborOnly != null)) {
      return true;
    }

    return false;
  }

  static String _applyFollowupTemplate(
      String text, {
        required String? serviceType,
        required dynamic rule,
      }) {
    final displayName = (rule?.displayName ?? '').toString().trim();

    final serviceLabel = displayName.isNotEmpty
        ? displayName
        : (serviceType ?? '')
        .trim()
        .split(RegExp(r'[_\-\s]+'))
        .where((e) => e.isNotEmpty)
        .map((part) => part[0].toUpperCase() + part.substring(1))
        .join(' ');

    return text
        .replaceAll('{service_label}', serviceLabel)
        .replaceAll('{service_type}', (serviceType ?? '').trim())
        .trim();
  }

}

