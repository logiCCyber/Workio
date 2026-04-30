import '../models/ai_estimate_result_model.dart';
import '../models/ai_parsed_request_model.dart';
import '../models/estimate_item_model.dart';
import 'estimate_pricing_engine_service.dart';
import 'estimate_price_rules_service.dart';
import '../models/estimate_price_rule_model.dart';

class EstimateDraftBuilderService {
  EstimateDraftBuilderService._();

  static Future<AiEstimateResultModel> build({
    required AiParsedRequestModel parsed,
    String? propertyCity,
  }) async {
    final missingFields = parsed.missingFields;
    final assumptions = parsed.assumptions;
    final canAutoGenerate = parsed.canBuildDraft;

    final rule = await _loadMainRule(parsed.serviceType);

    final title = _buildTitle(
      serviceType: parsed.serviceType,
      propertyCity: propertyCity,
      currentRule: rule,
    );

    final scope = _buildScope(
      parsed,
      currentRule: rule,
      aiScopeTemplate: rule?.aiScopeTemplate,
    );

    final notes = _buildNotes(
      parsed,
      currentRule: rule,
      aiNotesTemplate: rule?.aiNotesTemplate,
    );

    final items = canAutoGenerate
        ? await EstimatePricingEngineService.buildItems(parsed)
        : <EstimateItemModel>[];

    return AiEstimateResultModel(
      title: title,
      scope: scope,
      notes: notes,
      items: items,
      parsedRequest: parsed,
      assumptions: assumptions,
      missingFields: missingFields,
      confidence: parsed.confidence,
    );
  }

  static String _buildTitle({
    required String? serviceType,
    String? propertyCity,
    EstimatePriceRuleModel? currentRule,
  }) {
    final normalizedServiceType = (serviceType ?? '').trim().toLowerCase();

    final serviceLabel = _resolveRuleLabel(
      serviceType: normalizedServiceType,
      currentRule: currentRule,
    );

    final city = (propertyCity ?? '').trim();
    final citySuffix = city.isEmpty ? '' : ' • $city';

    return '$serviceLabel Estimate$citySuffix';
  }

  static String _buildScope(
      AiParsedRequestModel parsed, {
        EstimatePriceRuleModel? currentRule,
        String? aiScopeTemplate,
      }) {
    final serviceType = (parsed.serviceType ?? '').trim().toLowerCase();

    final ruleLabel = _resolveRuleLabel(
      serviceType: serviceType,
      currentRule: currentRule,
    );

    final requestText = _extractScopeRequestText(
      parsed.rawPrompt,
      ruleLabel: ruleLabel,
    );
    final details = <String>[];

    if (requestText.isNotEmpty) {
      details.add(
        'Complete the requested work for ${ruleLabel.toLowerCase()}: $requestText.',
      );
    } else {
      final aiTemplate = aiScopeTemplate?.trim() ?? '';

      if (aiTemplate.isNotEmpty) {
        details.add(_applyAiTemplate(aiTemplate, parsed));
      } else {
        details.add(
          'Complete the requested ${ruleLabel.toLowerCase()} work as described by the client.',
        );
      }
    }

    final laborDescription = currentRule?.aiLaborDescription?.trim() ?? '';
    if (laborDescription.isNotEmpty) {
      details.add(_applyAiTemplate(laborDescription, parsed));
    }

    final materialText = _buildScopeMaterialsText(parsed);
    if (materialText.isNotEmpty) {
      details.add(materialText);
    }

    final hasSqft = (parsed.sqft ?? 0) > 0;
    final hasRooms = (parsed.rooms ?? 0) > 0;
    final hasHours = (parsed.hours ?? 0) > 0;

    if (hasSqft) {
      details.add(
        'Estimated project size: ${parsed.sqft!.toStringAsFixed(0)} sqft.',
      );
    } else if (hasRooms) {
      details.add(
        'Estimated project size: ${parsed.rooms} room${parsed.rooms == 1 ? '' : 's'}.',
      );
    } else if (hasHours) {
      details.add(
        'Estimated labor time: ${parsed.hours!.toStringAsFixed(1)} hour${parsed.hours == 1 ? '' : 's'}.',
      );
    }

    if (parsed.prep) {
      final prepDescription = currentRule?.aiPrepDescription?.trim() ?? '';

      details.add(
        prepDescription.isNotEmpty
            ? _applyAiTemplate(prepDescription, parsed)
            : 'Include required preparation and setup before the main work begins.',
      );
    }

    if (parsed.rush) {
      final rushDescription = currentRule?.aiRushDescription?.trim() ?? '';

      final cleanRushDescription = rushDescription.isNotEmpty
          ? _applyAiTemplate(rushDescription, parsed)
          .replaceAll(RegExp(r'\{[^}]*\}'), ' ')
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim()
          : '';

      details.add(
        cleanRushDescription.isNotEmpty
            ? cleanRushDescription
            : 'Provide expedited scheduling where available.',
      );
    }

    details.add(
      'Verify the completed work where applicable and leave the work area clean upon completion.',
    );

    return _cleanScopeText(details.join(' '));
  }

  static String _extractScopeRequestText(
      String rawPrompt, {
        String? ruleLabel,
      }) {
    var text = rawPrompt.trim();

    if (text.isEmpty) return '';

    final requestMatch = RegExp(
      r'request\s*:\s*(.*)$',
      caseSensitive: false,
      dotAll: true,
    ).firstMatch(text);

    if (requestMatch != null) {
      text = requestMatch.group(1)?.trim() ?? text;
    }

    text = text
        .replaceAll(
      RegExp(
        r'\bservice_type\s*:\s*[^.]+\.?',
        caseSensitive: false,
      ),
      '',
    )
        .replaceAll(
      RegExp(
        r'\bservice_label\s*:\s*[^.]+\.?',
        caseSensitive: false,
      ),
      '',
    )
        .trim();

    final materialMarker = RegExp(
      r'\b(materials?\s+(are\s+)?included|materials?)\s*:',
      caseSensitive: false,
    ).firstMatch(text);

    if (materialMarker != null) {
      text = text.substring(0, materialMarker.start).trim();
    }

    final label = (ruleLabel ?? '').trim();

    if (label.isNotEmpty) {
      text = text.replaceFirst(
        RegExp(
          '^\\s*need\\s+(a\\s+|an\\s+)?${RegExp.escape(label)}\\s+'
              '(repair|service|work|job)'
              '(\\s+(in|at)\\s+[a-z\\s]+)?\\.?\\s*',
          caseSensitive: false,
        ),
        '',
      );
    }

    text = text.replaceFirst(
      RegExp(
        r'^\s*(we\s+)?need\s+(a\s+|an\s+)?[^.]*?\s+work\s+(in|at)\s+[a-z\s]+\.?\s*',
        caseSensitive: false,
      ),
      '',
    );

    text = text
        .replaceAll(
      RegExp(
        r'\binclude\s+(basic|standard)?\s*materials?\.?',
        caseSensitive: false,
      ),
      '',
    )

        .replaceAll(
      RegExp(
        r'\bthe\s+work\s+is\s*\.?',
        caseSensitive: false,
      ),
      '',
    )

        .replaceAll(
      RegExp(
        r'\bmaterials?\s+(are\s+)?included\.?',
        caseSensitive: false,
      ),
      '',
    )
        .replaceAll(
      RegExp(
        r'\b(labor|labour)\s+only\b',
        caseSensitive: false,
      ),
      '',
    )
        .replaceAll(
      RegExp(
        r'\b(urgent|rush|asap|priority)\b',
        caseSensitive: false,
      ),
      '',
    )
        .replaceAll(RegExp(r'\s+'), ' ')
        .replaceAllMapped(
      RegExp(r'\s+([,.;:])'),
          (match) => match.group(1) ?? '',
    )
        .replaceAll(RegExp(r'^[,.;:\s]+'), '')
        .trim();

    if (text.endsWith('.') || text.endsWith(',') || text.endsWith(':')) {
      text = text.substring(0, text.length - 1).trim();
    }

    return text;
  }

  static String _buildScopeMaterialsText(AiParsedRequestModel parsed) {
    if (parsed.laborOnly == true) {
      return 'This estimate is for labor only; materials are not included unless listed separately.';
    }

    final parsedMaterials = parsed.parsedMaterials;

    final pricedMaterials = parsedMaterials.where((item) {
      final unitPrice = _toPositiveDouble(item['unit_price']);
      final lineTotal = _toPositiveDouble(item['line_total']);
      return unitPrice != null || lineTotal != null;
    }).toList();

    if (pricedMaterials.isNotEmpty) {
      final names = <String>[];

      for (final item in pricedMaterials) {
        final name = (item['name'] ?? '').toString().trim();
        final quantity = item['quantity'];

        final measureValue = _toPositiveDouble(item['measure_value']);
        final measureUnit = (item['measure_unit'] ?? '').toString().trim();

        if (name.isEmpty) continue;

        if (measureValue != null &&
            measureUnit.isNotEmpty &&
            !['each', 'item', 'items', 'pc', 'pcs'].contains(measureUnit.toLowerCase())) {
          final valueText = measureValue % 1 == 0
              ? measureValue.toInt().toString()
              : measureValue.toString();

          names.add('$valueText $measureUnit of $name');
        } else if (quantity is num && quantity > 0) {
          final qtyText = quantity % 1 == 0
              ? quantity.toInt().toString()
              : quantity.toString();

          names.add('$qtyText $name');
        } else {
          names.add(name);
        }
      }

      if (names.isNotEmpty) {
        return 'Include listed materials: ${_joinHumanList(names)}.';
      }
    }

    if (parsed.materialsIncluded == true) {
      return 'Include basic materials and parts required for the requested work.';
    }

    return '';
  }

  static String _joinHumanList(List<String> values) {
    final cleanValues = values
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList();

    if (cleanValues.isEmpty) return '';
    if (cleanValues.length == 1) return cleanValues.first;
    if (cleanValues.length == 2) {
      return '${cleanValues.first} and ${cleanValues.last}';
    }

    return '${cleanValues.take(cleanValues.length - 1).join(', ')}, and ${cleanValues.last}';
  }

  static double? _toPositiveDouble(dynamic value) {
    if (value == null) return null;

    if (value is num) {
      final result = value.toDouble();
      return result > 0 ? result : null;
    }

    final parsed = double.tryParse(value.toString().replaceAll(',', '.'));
    if (parsed == null || parsed <= 0) return null;

    return parsed;
  }

  static String _cleanScopeText(String value) {
    return value
        .replaceAll(RegExp(r'\s+'), ' ')
        .replaceAllMapped(
      RegExp(r'\s+([,.;:])'),
          (match) => match.group(1) ?? '',
    )
        .replaceAll(RegExp(r'\.\s*\.'), '.')
        .replaceAll(RegExp(r'\s+\.'), '.')
        .trim();
  }


  static String _buildNotes(
      AiParsedRequestModel parsed, {
        EstimatePriceRuleModel? currentRule,
        String? aiNotesTemplate,
      }) {
    final aiTemplate = aiNotesTemplate?.trim() ?? '';
    if (aiTemplate.isNotEmpty) {
      return _applyAiTemplate(aiTemplate, parsed);
    }

    final serviceType = (parsed.serviceType ?? '').trim().toLowerCase();

    final ruleLabel = _resolveRuleLabel(
      serviceType: serviceType,
      currentRule: currentRule,
    );

    final notes = <String>[
      'Final price may change if hidden conditions, access limitations, or additional work are discovered during the ${ruleLabel.toLowerCase()} service.',
      'Final materials, finish selections, and work conditions must be confirmed before work begins.',
    ];

    if (parsed.materialsIncluded == true) {
      notes.add('Materials are included in the current estimate.');
    } else if (parsed.laborOnly == true) {
      notes.add('Labor only. Materials are not included unless listed separately.');
    } else {
      notes.add('Materials are not included unless specifically listed.');
    }

    if (parsed.prep) {
      notes.add('Prep work is included where specified.');
    }

    if (parsed.rush) {
      notes.add('Rush timeline may affect scheduling availability.');
    }

    return notes.join(' ');
  }

  static String _resolveRuleLabel({
    required String serviceType,
    required EstimatePriceRuleModel? currentRule,
  }) {
    final displayName = currentRule?.displayName?.trim() ?? '';
    if (displayName.isNotEmpty) {
      return displayName;
    }

    final laborTitle = currentRule?.aiLaborTitle?.trim() ?? '';
    if (laborTitle.isNotEmpty) {
      return laborTitle;
    }

    return _serviceLabel(serviceType);
  }

  static String _serviceLabel(String serviceType) {
    final normalized = serviceType.trim().toLowerCase();

    if (normalized.isEmpty) return 'Service';

    return normalized
        .split(RegExp(r'[_\-\s]+'))
        .where((e) => e.isNotEmpty)
        .map((part) => part[0].toUpperCase() + part.substring(1))
        .join(' ');
  }

  static Future<EstimatePriceRuleModel?> _loadMainRule(String? serviceType) async {
    final normalized = (serviceType ?? '').trim().toLowerCase();
    if (normalized.isEmpty) return null;

    try {
      return await EstimatePriceRulesService.findBestRuleByServiceType(normalized);
    } catch (_) {
      return null;
    }
  }

  static String _applyAiTemplate(
      String template,
      AiParsedRequestModel parsed,
      ) {
    final serviceType = (parsed.serviceType ?? '').trim();
    final serviceLabel = _serviceLabel(serviceType.toLowerCase());
    final sqft = parsed.sqft;
    final rooms = parsed.rooms;

    return template
        .replaceAll('{service_type}', serviceType)
        .replaceAll('{service_label}', serviceLabel)
        .replaceAll('{sqft}', sqft?.toStringAsFixed(0) ?? '')
        .replaceAll('{rooms}', rooms?.toString() ?? '')
        .replaceAll(
      '{materials}',
      parsed.materialsIncluded == true
          ? 'materials included'
          : parsed.laborOnly == true
          ? 'labor only'
          : 'materials not specified',
    )
        .replaceAll(
      '{rush}',
      parsed.rush ? 'rush service included' : '',
    )
        .replaceAll(
      '{prep}',
      parsed.prep ? 'prep included' : '',
    )
        .trim();
  }
}

