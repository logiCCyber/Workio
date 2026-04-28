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

    final title = _buildTitle(
      serviceType: parsed.serviceType,
      propertyCity: propertyCity,
    );

    final rule = await _loadMainRule(parsed.serviceType);

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
  }) {
    final normalizedServiceType = (serviceType ?? '').trim().toLowerCase();
    final serviceLabel = _serviceLabel(normalizedServiceType);

    final city = (propertyCity ?? '').trim();
    final citySuffix = city.isEmpty ? '' : ' • $city';

    return '$serviceLabel Estimate$citySuffix';
  }

  static String _buildScope(
      AiParsedRequestModel parsed, {
        EstimatePriceRuleModel? currentRule,
        String? aiScopeTemplate,
      }) {
    final aiTemplate = aiScopeTemplate?.trim() ?? '';
    if (aiTemplate.isNotEmpty) {
      return _applyAiTemplate(aiTemplate, parsed);
    }

    final serviceType = (parsed.serviceType ?? '').trim().toLowerCase();

    final ruleLabel = _resolveRuleLabel(
      serviceType: serviceType,
      currentRule: currentRule,
    );

    final details = <String>[];

    details.add(
      'Complete the requested ${ruleLabel.toLowerCase()} work as described by the client.',
    );

    final laborDescription = currentRule?.aiLaborDescription?.trim() ?? '';
    if (laborDescription.isNotEmpty) {
      details.add(laborDescription);
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

    if (parsed.materialsIncluded == true) {
      details.add('Materials are included in this estimate.');
    } else if (parsed.laborOnly == true) {
      details.add('This estimate is for labor only.');
    }

    if (parsed.prep) {
      final prepDescription = currentRule?.aiPrepDescription?.trim() ?? '';
      details.add(
        prepDescription.isNotEmpty
            ? prepDescription
            : 'Preparation and setup are included where specified.',
      );
    }

    if (parsed.rush) {
      final rushDescription = currentRule?.aiRushDescription?.trim() ?? '';
      details.add(
        rushDescription.isNotEmpty
            ? rushDescription
            : 'Rush scheduling is included where specified.',
      );
    }

    details.add('Final cleanup of the work area upon completion.');

    return details.join(' ');
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

  static Future<dynamic> _loadMainRule(String? serviceType) async {
    final normalized = (serviceType ?? '').trim().toLowerCase();
    if (normalized.isEmpty) return null;

    try {
      return await EstimatePriceRulesService.findMainRule(normalized);
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
      parsed.rush ? 'rush service included' : 'standard scheduling',
    )
        .replaceAll(
      '{prep}',
      parsed.prep ? 'prep included' : 'prep not included',
    )
        .trim();
  }
}

