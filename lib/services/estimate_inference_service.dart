import '../models/ai_parsed_request_model.dart';
import '../models/estimate_price_rule_model.dart';

/// Universal inference layer.
/// Анализирует prompt + rule и выдаёт contextual hints для AI.
/// НЕ привязан к стране или конкретному trade — работает универсально.
class EstimateInferenceService {
  EstimateInferenceService._();

  static InferenceContext analyze({
    required String prompt,
    required AiParsedRequestModel parsed,
    required EstimatePriceRuleModel? selectedRule,
  }) {
    final text = _normalize(prompt);

    // Location: где работа
    final location = _detectLocation(text);

    // Object: что чинят/устанавливают
    final object = _detectObject(text);

    // Trade hints: универсальные подсказки для AI
    final hints = _buildTradeHints(
      text: text,
      location: location,
      object: object,
      tradeCategory: selectedRule?.category ?? '',
      rule: selectedRule,
    );

    // Assumed answers: ответы которые AI может дать сам без вопроса
    final assumed = _buildAssumedAnswers(
      text: text,
      location: location,
      object: object,
      parsed: parsed,
    );

    return InferenceContext(
      locationContext: location,
      objectContext: object,
      tradeHints: hints,
      assumedAnswers: assumed,
    );
  }

  /// Где работа происходит — универсальные локации.
  static String? _detectLocation(String text) {
    const locations = {
      'kitchen': ['kitchen', 'cuisine', 'kuhnya', 'oshxona'],
      'bathroom': ['bathroom', 'bath', 'washroom', 'salle de bain', 'vannaya', 'hammom'],
      'bedroom': ['bedroom', 'master bedroom', 'chambre', 'spalnya', 'yotoq xona'],
      'living_room': ['living room', 'living', 'salon', 'gostinaya', 'mehmonxona'],
      'basement': ['basement', 'cellar', 'sous-sol', 'podval', 'yerto\'la'],
      'attic': ['attic', 'loft', 'grenier', 'cherdak'],
      'garage': ['garage', 'garaj'],
      'outdoor': ['outdoor', 'outside', 'exterior', 'backyard', 'frontyard', 'patio', 'deck', 'extérieur', 'snaruzhi', 'tashqari'],
      'office': ['office', 'study', 'bureau', 'kabinet', 'ofis'],
      'laundry': ['laundry', 'utility', 'mudroom', 'buanderie', 'prachka', 'kir yuvish'],
      'dining_room': ['dining', 'dining room', 'salle à manger', 'stolovaya', 'oshxona'],
      'hallway': ['hallway', 'corridor', 'couloir', 'koridor', 'dahliz'],
      'stairs': ['stairs', 'staircase', 'escalier', 'lestnitsa', 'zinapoya'],
    };

    for (final entry in locations.entries) {
      for (final keyword in entry.value) {
        if (RegExp(r'\b' + RegExp.escape(keyword) + r'\b').hasMatch(text)) {
          return entry.key;
        }
      }
    }

    return null;
  }

  /// Что за объект работы — универсальный объект.
  static String? _detectObject(String text) {
    const objects = {
      // Electrical
      'outlet': ['outlet', 'receptacle', 'rozetka', 'priza'],
      'switch': ['switch', 'vyklyuchatel', 'kalit'],
      'breaker': ['breaker', 'panel', 'electrical panel', 'avtomat', 'avtomatik'],
      'light': ['light', 'fixture', 'lampa', 'svet', 'chiroq'],
      'wiring': ['wiring', 'cable', 'wire', 'provod', 'sim'],
      'fan': ['ceiling fan', 'fan', 'ventilateur', 'ventilator', 'shamollatgich'],
      // Plumbing
      'faucet': ['faucet', 'tap', 'kran', 'jo\'mrak'],
      'toilet': ['toilet', 'wc', 'tualet', 'hojatxona'],
      'sink': ['sink', 'rakovina', 'lavan'],
      'shower': ['shower', 'dush'],
      'bathtub': ['bathtub', 'bath', 'vanna'],
      'drain': ['drain', 'slivnoy', 'oqava'],
      'pipe': ['pipe', 'plumbing pipe', 'truba', 'quvur'],
      'water_heater': ['water heater', 'hot water tank', 'boiler', 'titan'],
      // HVAC
      'thermostat': ['thermostat', 'termostat'],
      'furnace': ['furnace', 'pech', 'pich'],
      'ac': ['air conditioner', 'ac unit', 'kondisioner'],
      'duct': ['duct', 'ductwork', 'vozduhovod'],
      // Appliances
      'dishwasher': ['dishwasher', 'posudomoechka', 'idish yuvgich'],
      'washer': ['washing machine', 'washer', 'stiralka'],
      'dryer': ['dryer', 'sushilka'],
      'fridge': ['fridge', 'refrigerator', 'holodilnik', 'muzlatkich'],
      'oven': ['oven', 'stove', 'range', 'plita'],
      'microwave': ['microwave', 'mikrovolnovka'],
      // General
      'door': ['door', 'dver', 'eshik'],
      'window': ['window', 'okno', 'deraza'],
      'floor': ['floor', 'flooring', 'pol', 'pol'],
      'wall': ['wall', 'drywall', 'stena', 'devor'],
      'ceiling': ['ceiling', 'potolok', 'shift'],
    };

    for (final entry in objects.entries) {
      for (final keyword in entry.value) {
        if (RegExp(r'\b' + RegExp.escape(keyword) + r'\b').hasMatch(text)) {
          return entry.key;
        }
      }
    }

    return null;
  }

  /// Универсальные trade hints для AI.
  /// НЕ говорим конкретный стандарт (CSA/NEC) — AI сам знает.
  static List<String> _buildTradeHints({
    required String text,
    required String? location,
    required String? object,
    required String tradeCategory,
    required EstimatePriceRuleModel? rule,
  }) {
    final hints = <String>[];

    // Wet locations require special protection (universal across all codes)
    if (location == 'kitchen' || location == 'bathroom' || location == 'laundry') {
      hints.add('wet/damp location — protection devices required per local electrical code');
    }

    if (location == 'outdoor') {
      hints.add('outdoor installation — weatherproof rated equipment required');
    }

    if (location == 'basement') {
      hints.add('below-grade location — moisture and clearance considerations apply');
    }

    if (location == 'attic') {
      hints.add('attic installation — accessibility and thermal considerations apply');
    }

    // Electrical specifics
    if (tradeCategory.toLowerCase() == 'electrical') {
      if (object == 'outlet' && (location == 'kitchen' || location == 'bathroom' || location == 'outdoor' || location == 'laundry')) {
        hints.add('ground-fault protection required at this location per local code');
      }

      if (object == 'outlet' && location == 'bedroom') {
        hints.add('arc-fault protection may be required at this location per local code');
      }

      if (object == 'breaker' || object == 'panel') {
        hints.add('main service work — coordinate with utility shutoff if needed');
      }
    }

    // Plumbing specifics
    if (tradeCategory.toLowerCase() == 'plumbing') {
      if (object == 'sink' || object == 'bathtub' || object == 'shower') {
        hints.add('trap and venting required per local plumbing code');
      }

      if (object == 'water_heater') {
        hints.add('temperature-pressure relief valve and proper venting required');
      }
    }

    // Appliance install specifics
    if (object == 'dishwasher' || object == 'washer' || object == 'dryer') {
      hints.add('dedicated circuit and proper supply/drain connections per manufacturer specs');
    }

    // High-traffic / commercial hints
    if (text.contains('commercial') || text.contains('office') || text.contains('retail')) {
      hints.add('commercial installation — heavy-duty rated equipment recommended');
    }

    return hints;
  }

  /// Assumed answers — то что AI может сам ответить без вопроса админу.
  static Map<String, String> _buildAssumedAnswers({
    required String text,
    required String? location,
    required String? object,
    required AiParsedRequestModel parsed,
  }) {
    final answers = <String, String>{};

    // Rush detection в промпте → assume rush answer
    if (parsed.rush) {
      answers['rush'] = 'yes';
      answers['urgency'] = 'rush';
      answers['priority'] = 'high';
      answers['schedule_priority'] = 'expedited';
    } else {
      answers['rush'] = 'no';
      answers['urgency'] = 'standard';
    }

    // Materials в промпте → assume materials answer
    if (parsed.materialsIncluded == true) {
      answers['materials'] = 'materials included';
      answers['materials_included'] = 'yes';
    } else if (parsed.laborOnly == true) {
      answers['materials'] = 'labor only';
      answers['labor_only'] = 'yes';
    }

    // Location-based protection device inference
    if (location == 'kitchen' || location == 'bathroom' || location == 'outdoor' || location == 'laundry') {
      answers['gfci_required'] = 'yes';
      answers['gfci'] = 'yes';
      answers['protection_required'] = 'gfci';
    }

    if (location == 'bedroom' && object == 'outlet') {
      answers['afci_required'] = 'yes';
      answers['afci'] = 'yes';
    }

    if (location == 'outdoor') {
      answers['weatherproof'] = 'yes';
      answers['weatherproof_required'] = 'yes';
    }

    // Dedicated circuit assumption for major appliances
    if (object == 'dishwasher' ||
        object == 'washer' ||
        object == 'dryer' ||
        object == 'oven' ||
        object == 'water_heater' ||
        object == 'ac') {
      answers['dedicated_circuit'] = 'yes';
      answers['dedicated_circuit_required'] = 'yes';
    }

    // Multi-job detection
    if (parsed.parsedMaterials.isNotEmpty) {
      answers['materials_listed'] = 'yes';
      answers['has_materials'] = 'yes';
    }

    return answers;
  }

  static String _normalize(String value) {
    return value
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-zà-ÿа-я0-9\s\-]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }
}

/// Контекст вывода — что AI понял о работе.
class InferenceContext {
  final String? locationContext;
  final String? objectContext;
  final List<String> tradeHints;
  final Map<String, String> assumedAnswers;

  const InferenceContext({
    this.locationContext,
    this.objectContext,
    this.tradeHints = const [],
    this.assumedAnswers = const {},
  });

  bool get isEmpty =>
      locationContext == null &&
          objectContext == null &&
          tradeHints.isEmpty &&
          assumedAnswers.isEmpty;

  Map<String, dynamic> toEdgePayload() {
    return {
      'location': locationContext ?? '',
      'object': objectContext ?? '',
      'tradeHints': tradeHints,
      'assumedAnswersCount': assumedAnswers.length,
    };
  }
}