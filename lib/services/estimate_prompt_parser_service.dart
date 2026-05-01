import '../models/ai_assumption_model.dart';
import '../models/ai_missing_field_model.dart';
import '../models/ai_parsed_request_model.dart';

class EstimatePromptParserService {
  EstimatePromptParserService._();

  static AiParsedRequestModel parse(
      String prompt, {
        String? ruleUnit,
      }) {
    final rawPrompt = prompt.trim();
    final normalizedPrompt = _normalize(rawPrompt);
    final normalizedRuleUnit = (ruleUnit ?? '').trim().toLowerCase();

    double? sqft = _extractSquareFootage(normalizedPrompt);
    int? rooms = _extractRooms(normalizedPrompt);
    double? hours = _extractHours(normalizedPrompt);
    final parsedMaterials = _extractParsedMaterials(normalizedPrompt);

    bool? materialsIncluded = _detectMaterialsIncluded(normalizedPrompt);
    bool? laborOnly = _detectLaborOnly(normalizedPrompt);

    String? serviceType;

    final rush = _detectRush(normalizedPrompt);

    final prep = _hasAny(normalizedPrompt, [
      'prep',
      'preparation',
      'surface prep',
      'surface preparation',
      'patch',
      'patching',
      'подготовка',
      'шпаклевка',
      'заделка',
    ]);

    final assumptions = <AiAssumptionModel>[];
    final missingFields = <AiMissingFieldModel>[];

    if (laborOnly == true && materialsIncluded == null) {
      materialsIncluded = false;
      assumptions.add(
        const AiAssumptionModel(
          key: 'materials_included',
          label: 'Materials',
          value: 'Not included',
          reason: 'Labor only usually means materials are not included.',
        ),
      );
    }

    if (parsedMaterials.isNotEmpty &&
        materialsIncluded == null &&
        laborOnly != true) {
      materialsIncluded = true;
      assumptions.add(
        const AiAssumptionModel(
          key: 'materials_included',
          label: 'Materials',
          value: 'Included',
          reason: 'Detailed material list was detected in the prompt.',
        ),
      );
    }

    final hasAreaInfo = (sqft ?? 0) > 0 || (rooms ?? 0) > 0;
    final requiresProjectSize = _requiresProjectSize(
      normalizedPrompt: normalizedPrompt,
      ruleUnit: normalizedRuleUnit,
    );

    if (requiresProjectSize && !hasAreaInfo) {
      missingFields.add(
        AiMissingFieldModel(
          key: 'project_size',
          question: _quantityQuestionForUnit(normalizedRuleUnit),
          isRequired: true,
          answerType: 'text',
          hint: _quantityHintForUnit(normalizedRuleUnit),
        ),
      );
    }

    final hasMaterialDecision =
        materialsIncluded != null || laborOnly != null;

    if (!hasMaterialDecision) {
      missingFields.add(
        const AiMissingFieldModel(
          key: 'materials',
          question: 'Are materials included, or is this labor only?',
          isRequired: true,
          answerType: 'single_select',
          options: [
            'materials included',
            'labor only',
          ],
          hint: 'Pricing changes a lot depending on materials.',
        ),
      );
    }

    final confidence = _calculateConfidence(
      normalizedPrompt: normalizedPrompt,
      serviceType: serviceType,
      sqft: sqft,
      rooms: rooms,
      hours: hours,
      materialsIncluded: materialsIncluded,
      laborOnly: laborOnly,
      rush: rush,
      prep: prep,
      missingFields: missingFields,
      parsedMaterials: parsedMaterials,
    );

    return AiParsedRequestModel(
      rawPrompt: rawPrompt,
      normalizedPrompt: normalizedPrompt,
      serviceType: serviceType,
      sqft: sqft,
      rooms: rooms,
      hours: hours,
      materialsIncluded: materialsIncluded,
      laborOnly: laborOnly,
      rush: rush,
      prep: prep,
      confidence: confidence,
      missingFields: missingFields,
      assumptions: assumptions,
      parsedMaterials: parsedMaterials,
    );
  }

  static String _normalize(String value) {
    return value.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();
  }


  static bool _requiresProjectSize({
    required String normalizedPrompt,
    required String ruleUnit,
  }) {
    if (ruleUnit.isNotEmpty) {
      return ruleUnit == 'sqft' || ruleUnit == 'room';
    }

    final hasExplicitSqft = _extractSquareFootage(normalizedPrompt) != null;
    final hasExplicitRooms = _extractRooms(normalizedPrompt) != null;

    if (hasExplicitSqft || hasExplicitRooms) {
      return true;
    }

    return false;
  }
  static String _quantityQuestionForUnit(String unit) {
    final cleanUnit = unit.trim().toLowerCase();

    if (cleanUnit.isEmpty) {
      return 'What quantity or size should be used for this estimate?';
    }

    return 'What is the approximate quantity in $cleanUnit?';
  }

  static String _quantityHintForUnit(String unit) {
    final cleanUnit = unit.trim().toLowerCase();

    if (cleanUnit.isEmpty) {
      return 'Example: 2 loads, 3 hours, 40 sqft, or 5 items.';
    }

    return 'Example: 2 $cleanUnit.';
  }


  static double? _extractSquareFootage(String text) {
    final leadingUnitPatterns = [
      RegExp(
        r'\b(?:sq\s*\.?\s*ft|sqft|sf|square feet|square foot)\s*(\d+(?:[.,]\d+)?)\b',
      ),
      RegExp(
        r'\b(?:кв\.?\s*фут|кв фут|квфут)\s*(\d+(?:[.,]\d+)?)\b',
      ),
    ];

    final trailingUnitPatterns = [
      RegExp(
        r'\b(\d+(?:[.,]\d+)?)\s*(?:sq\s*\.?\s*ft|sqft|sf|square feet|square foot)\b',
      ),
      RegExp(
        r'\b(\d+(?:[.,]\d+)?)\s*(?:кв\.?\s*фут|кв фут|квфут)\b',
      ),
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

  static int? _extractRooms(String text) {
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

  static double? _extractHours(String text) {
    final patterns = [
      RegExp(r'(\d+(?:[.,]\d+)?)\s*(hour|hours|hr|hrs)\b'),
    ];

    for (final pattern in patterns) {
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


  static List<Map<String, dynamic>> _extractParsedMaterials(String text) {
    final normalized = text
        .replaceAll('\n', ', ')
        .replaceAll(';', ', ')
        .replaceAllMapped(RegExp(r'\s+\band\b\s+'), (_) => ', ');

    final parts = normalized
        .split(',')
        .map((part) => part.trim())
        .where((part) => part.isNotEmpty)
        .toList();

    final materials = <Map<String, dynamic>>[];

    for (final part in parts) {
      final parsed = _parseMaterialPart(part);
      if (parsed != null) {
        materials.add(parsed);
      }
    }

    return materials;
  }

  static Map<String, dynamic>? _parseMaterialPart(String part) {
    final quantityMatch = RegExp(r'^(\d+(?:[.,]\d+)?)\s+').firstMatch(part);
    if (quantityMatch == null) return null;

    final quantity = _toPositiveDouble(quantityMatch.group(1));
    if (quantity == null || quantity <= 0) return null;

    var rest = part.substring(quantityMatch.end).trim();
    if (rest.isEmpty) return null;

    double? unitPrice;
    final priceMatch = RegExp(
      r'(?:\b(?:at|@)\s*)?\$?(\d+(?:[.,]\d+)?)\s*(?:each|ea)\b',
    ).firstMatch(rest);

    if (priceMatch != null) {
      unitPrice = _toPositiveDouble(priceMatch.group(1));
      rest = rest.replaceRange(priceMatch.start, priceMatch.end, '').trim();
    }

    double? measureValue;
    String? measureUnit;

    final measureMatch = RegExp(
      r'(?:x\s*)?(\d+(?:[.,]\d+)?)\s*(m|ft|cm|mm|pcs|pc|piece|pieces|sheet|sheets|bag|bags|roll|rolls)\b',
    ).firstMatch(rest);

    if (measureMatch != null) {
      measureValue = _toPositiveDouble(measureMatch.group(1));
      measureUnit = measureMatch.group(2)?.toLowerCase();
      rest = rest.replaceRange(measureMatch.start, measureMatch.end, '').trim();
    }

    final name = rest.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (name.isEmpty || name.length < 2) return null;

    return {
      'name': name,
      'quantity': quantity,
      'measure_value': measureValue,
      'measure_unit': measureUnit,
      'unit_price': unitPrice,
      'line_total': unitPrice != null ? quantity * unitPrice : null,
      'raw_text': part,
    };
  }

  static double? _toPositiveDouble(String? value) {
    if (value == null) return null;
    final parsed = double.tryParse(value.replaceAll(',', '.'));
    if (parsed == null || parsed <= 0) return null;
    return parsed;
  }

  static bool? _detectMaterialsIncluded(String text) {
    if (_matchesAnyFlexible(text, [
      ['materials', 'included'],
      ['material', 'included'],
      ['with', 'materials'],
      ['including', 'materials'],
      ['materials', 'only'],
      ['material', 'only'],
    ])) {
      return true;
    }

    if (_matchesAnyFlexible(text, [
      ['materials', 'not', 'included'],
      ['material', 'not', 'included'],
      ['without', 'materials'],
      ['no', 'materials'],
      ['materials', 'excluded'],
    ])) {
      return false;
    }

    return null;
  }

  static bool? _detectLaborOnly(String text) {
    if (_matchesAnyFlexible(text, [
      ['labor', 'only'],
      ['labour', 'only'],
      ['only', 'labor'],
      ['only', 'labour'],
      ['just', 'labor'],
      ['just', 'labour'],
      ['labor', 'work', 'only'],
      ['labour', 'work', 'only'],
    ])) {
      return true;
    }

    if (_matchesAnyFlexible(text, [
      ['materials', 'included'],
      ['material', 'included'],
      ['with', 'materials'],
      ['including', 'materials'],
      ['materials', 'only'],
      ['material', 'only'],
    ])) {
      return false;
    }

    return null;
  }

  static bool _detectRush(String text) {
    if (_matchesAnyFlexible(text, [
      ['no', 'rush'],
      ['not', 'urgent'],
      ['no', 'urgent'],
      ['no', 'asap'],
      ['not', 'asap'],
      ['no', 'expedite'],
      ['no', 'expedited'],
      ['not', 'expedited'],
      ['no', 'priority'],
      ['no', 'rush', 'fee'],
      ['without', 'rush'],
      ['standard', 'timing'],
      ['regular', 'timing'],
      ['normal', 'schedule'],
    ])) {
      return false;
    }

    return _hasAny(text, [
      'rush',
      'urgent',
      'urgent job',
      'asap',
      'expedite',
      'expedited',
      'priority',
      'after hours',
      'after-hours',
    ]);
  }



  static bool _matchesAnyFlexible(
      String source,
      List<List<String>> patterns,
      ) {
    final sourceTokens = _tokenizeFlexible(source);

    if (sourceTokens.isEmpty) return false;

    for (final pattern in patterns) {
      if (_containsFlexiblePhrase(sourceTokens, pattern)) {
        return true;
      }
    }

    return false;
  }

  static bool _containsFlexiblePhrase(
      List<String> sourceTokens,
      List<String> patternTokens,
      ) {
    final normalizedPattern = patternTokens
        .map(_normalizeFlexibleToken)
        .where((token) => token.isNotEmpty)
        .toList();

    if (normalizedPattern.isEmpty) return false;

    for (final expected in normalizedPattern) {
      bool matched = false;

      for (final actual in sourceTokens) {
        if (_isFlexibleTokenMatch(expected, actual)) {
          matched = true;
          break;
        }
      }

      if (!matched) {
        return false;
      }
    }

    return true;
  }

  static List<String> _tokenizeFlexible(String value) {
    return value
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-zA-Z0-9\s]+'), ' ')
        .split(RegExp(r'\s+'))
        .map((part) => _normalizeFlexibleToken(part))
        .where((part) => part.isNotEmpty)
        .toList();
  }

  static String _normalizeFlexibleToken(String value) {
    return value
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-zA-Z0-9]+'), '');
  }

  static bool _isFlexibleTokenMatch(String expected, String actual) {
    if (expected == actual) return true;
    if (expected.isEmpty || actual.isEmpty) return false;

    final maxLen = expected.length > actual.length
        ? expected.length
        : actual.length;

    final distance = _levenshtein(expected, actual);

    if (maxLen <= 4) {
      return distance == 0;
    }

    if (maxLen <= 7) {
      return distance <= 1;
    }

    return distance <= 2;
  }

  static int _levenshtein(String a, String b) {
    final aLen = a.length;
    final bLen = b.length;

    if (aLen == 0) return bLen;
    if (bLen == 0) return aLen;

    final matrix = List.generate(
      aLen + 1,
          (_) => List<int>.filled(bLen + 1, 0),
    );

    for (int i = 0; i <= aLen; i++) {
      matrix[i][0] = i;
    }

    for (int j = 0; j <= bLen; j++) {
      matrix[0][j] = j;
    }

    for (int i = 1; i <= aLen; i++) {
      for (int j = 1; j <= bLen; j++) {
        final cost = a[i - 1] == b[j - 1] ? 0 : 1;

        final deletion = matrix[i - 1][j] + 1;
        final insertion = matrix[i][j - 1] + 1;
        final substitution = matrix[i - 1][j - 1] + cost;

        int best = deletion < insertion ? deletion : insertion;
        if (substitution < best) {
          best = substitution;
        }

        matrix[i][j] = best;
      }
    }

    return matrix[aLen][bLen];
  }

  static double _calculateConfidence({
    required String normalizedPrompt,
    required String? serviceType,
    required double? sqft,
    required int? rooms,
    required double? hours,
    required bool? materialsIncluded,
    required bool? laborOnly,
    required bool rush,
    required bool prep,
    required List<Map<String, dynamic>> parsedMaterials,
    required List<AiMissingFieldModel> missingFields,
  }) {
    double score = 0.10;

    if ((serviceType ?? '').trim().isNotEmpty) {
      score += 0.25;
    }

    if ((sqft ?? 0) > 0 || (rooms ?? 0) > 0) {
      score += 0.20;
    }

    if ((hours ?? 0) > 0) {
      score += 0.12;
    }

    if (materialsIncluded != null || laborOnly != null) {
      score += 0.15;
    }

    if (parsedMaterials.isNotEmpty) {
      score += 0.12;
    }

    if (rush) {
      score += 0.04;
    }

    if (prep) {
      score += 0.04;
    }

    final wordsCount = normalizedPrompt
        .split(' ')
        .where((part) => part.trim().isNotEmpty)
        .length;

    if (wordsCount >= 6) {
      score += 0.08;
    }

    if (wordsCount >= 10) {
      score += 0.05;
    }

    final requiredMissingCount =
        missingFields.where((field) => field.isRequired).length;

    score -= requiredMissingCount * 0.10;


    final clamped = score.clamp(0.05, 0.98);
    return double.parse(clamped.toStringAsFixed(2));
  }

  static bool _hasAny(String source, List<String> patterns) {
    for (final pattern in patterns) {
      if (_containsPattern(source, pattern)) {
        return true;
      }
    }
    return false;
  }

  static bool _hasWord(String source, String word) {
    return RegExp(r'\b' + RegExp.escape(word) + r'\b').hasMatch(source);
  }

  static bool _containsPattern(String source, String pattern) {
    final normalizedPattern = pattern.trim().toLowerCase();

    if (normalizedPattern.isEmpty) return false;

    if (normalizedPattern.contains(' ')) {
      return source.contains(normalizedPattern);
    }

    return _hasWord(source, normalizedPattern);
  }
}