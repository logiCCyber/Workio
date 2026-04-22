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
      usedFallback: false,
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
    final details = <String>[];

    final serviceType = (parsed.serviceType ?? '').trim().toLowerCase();
    final sqft = parsed.sqft;
    final rooms = parsed.rooms;
    final coats = parsed.coats ?? 2;
    final materialsIncluded = parsed.materialsIncluded == true;
    final laborOnly = parsed.laborOnly == true;
    final walls = parsed.walls == true;
    final ceiling = parsed.ceiling == true;
    final prep = parsed.prep;
    final rush = parsed.rush;

    final aiTemplate = aiScopeTemplate?.trim() ?? '';
    if (aiTemplate.isNotEmpty) {
      return _applyAiTemplate(
        aiTemplate,
        parsed,
      );
    }

    final ruleLabel = _resolveRuleLabel(
      serviceType: serviceType,
      currentRule: currentRule,
    );

    switch (serviceType) {
      case 'painting':
        details.add('Prepare and protect work areas before painting.');

        if (prep) {
          details.add(
            'Complete minor patching and surface preparation where needed.',
          );
        }

        if (walls && ceiling) {
          details.add(
            'Apply $coats coat${coats > 1 ? 's' : ''} of paint to walls and ceiling areas.',
          );
        } else if (walls) {
          details.add(
            'Apply $coats coat${coats > 1 ? 's' : ''} of paint to wall surfaces.',
          );
        } else if (ceiling) {
          details.add(
            'Apply $coats coat${coats > 1 ? 's' : ''} of paint to ceiling areas.',
          );
        } else {
          details.add(
            'Apply $coats coat${coats > 1 ? 's' : ''} of paint to the requested areas.',
          );
        }
        break;

      case 'drywall':
        details.add(
          'Prepare work area and complete drywall-related labor as requested.',
        );

        if (prep) {
          details.add(
            'Include sanding and surface preparation where required.',
          );
        }
        break;

      case 'cleaning':
        details.add(
          'Complete detailed cleaning of the requested areas.',
        );
        break;

      case 'flooring':
        details.add(
          'Prepare floor surfaces and complete flooring installation.',
        );

        if (prep) {
          details.add(
            'Include subfloor preparation where needed.',
          );
        }
        break;

      default:
        details.add(
          'Complete the requested ${ruleLabel.toLowerCase()} work as discussed with the client.',
        );

        if (prep) {
          details.add(
            'Include basic setup and preparation before main work begins.',
          );
        }
        break;
    }

    final hasSqft = (sqft ?? 0) > 0;
    final hasRooms = (rooms ?? 0) > 0;

    if (hasSqft) {
      details.add(
        'Estimated project size: ${sqft!.toStringAsFixed(0)} sqft.',
      );
    } else if (hasRooms) {
      details.add(
        'Estimated project size based on ${rooms!.toInt()} room${rooms > 1 ? 's' : ''}.',
      );
    }

    if (materialsIncluded) {
      details.add('Materials are included in this estimate.');
    } else if (laborOnly) {
      details.add('This estimate is for labor only.');
    }

    if (rush) {
      details.add('Rush scheduling is included.');
    }

    details.add('Final cleanup of the work area upon completion.');

    return details.join(' ');
  }

  static String _buildCustomServiceIntro({
    required String serviceType,
    required String prompt,
  }) {
    switch (serviceType) {
      case 'plumbing':
        if (_containsAny(prompt, [
          'toilet leak',
          'leaking toilet',
          'toilet issue',
          'toilet repair',
        ])) {
          return 'Diagnose and complete the requested toilet leak repair work.';
        }

        if (_containsAny(prompt, [
          'drain',
          'clog',
          'clogged',
          'drain issue',
          'drain repair',
        ])) {
          return 'Diagnose and complete the requested drain-related plumbing work.';
        }

        if (_containsAny(prompt, [
          'faucet',
          'tap',
          'fixture',
          'sink faucet',
        ])) {
          return 'Complete the requested faucet or fixture plumbing service.';
        }

        if (_containsAny(prompt, [
          'sink',
          'sink leak',
          'sink repair',
        ])) {
          return 'Complete the requested sink-related plumbing work.';
        }

        if (_containsAny(prompt, [
          'pipe',
          'pipe leak',
          'water leak',
          'leak',
        ])) {
          return 'Diagnose and repair the requested plumbing leak issue.';
        }

        return 'Complete the requested plumbing work as discussed with the client.';

      case 'electrical':
        if (_containsAny(prompt, [
          'outlet',
          'socket',
          'plug',
        ])) {
          return 'Complete the requested outlet or socket electrical work.';
        }

        if (_containsAny(prompt, [
          'switch',
          'light switch',
        ])) {
          return 'Complete the requested switch-related electrical work.';
        }

        if (_containsAny(prompt, [
          'panel',
          'breaker',
          'electrical panel',
        ])) {
          return 'Complete the requested electrical panel or breaker service.';
        }

        if (_containsAny(prompt, [
          'wire',
          'wiring',
          'rewire',
        ])) {
          return 'Complete the requested wiring-related electrical work.';
        }

        return 'Complete the requested electrical work as discussed with the client.';

      case 'hvac':
        if (_containsAny(prompt, [
          'thermostat',
        ])) {
          return 'Complete the requested thermostat-related HVAC service.';
        }

        if (_containsAny(prompt, [
          'furnace',
          'heating',
          'heater',
        ])) {
          return 'Complete the requested heating-related HVAC work.';
        }

        if (_containsAny(prompt, [
          'ac',
          'air conditioner',
          'cooling',
        ])) {
          return 'Complete the requested cooling-related HVAC service.';
        }

        return 'Complete the requested HVAC work as discussed with the client.';

      default:
        final label = serviceType.trim().isEmpty
            ? 'requested'
            : serviceType.trim().toLowerCase();

        return 'Complete the requested $label work as discussed with the client.';
    }
  }

  static String _buildCustomPrepText({
    required String serviceType,
  }) {
    switch (serviceType) {
      case 'plumbing':
        return 'Include basic site protection, access preparation, and setup before plumbing work begins.';
      case 'electrical':
        return 'Include basic setup and preparation before electrical work begins.';
      case 'hvac':
        return 'Include basic access preparation and setup before HVAC work begins.';
      default:
        return 'Include basic setup and preparation before main work begins.';
    }
  }

  static String _buildRushText({
    required String serviceType,
  }) {
    switch (serviceType) {
      case 'plumbing':
        return 'Priority plumbing scheduling is included.';
      case 'electrical':
        return 'Priority electrical scheduling is included.';
      case 'hvac':
        return 'Priority HVAC scheduling is included.';
      default:
        return 'Rush scheduling is included.';
    }
  }

  static String _buildClosingText({
    required String serviceType,
  }) {
    switch (serviceType) {
      case 'plumbing':
        return 'Final cleanup of the plumbing work area upon completion.';
      case 'electrical':
        return 'Final cleanup of the electrical work area upon completion.';
      case 'hvac':
        return 'Final cleanup of the HVAC work area upon completion.';
      default:
        return 'Final cleaning of the work area upon completion.';
    }
  }

  static bool _containsAny(String source, List<String> patterns) {
    for (final pattern in patterns) {
      if (source.contains(pattern)) {
        return true;
      }
    }
    return false;
  }

  static String _buildNotes(
      AiParsedRequestModel parsed, {
        EstimatePriceRuleModel? currentRule,
        String? aiNotesTemplate,
      }) {
    final notes = <String>[];

    final serviceType = (parsed.serviceType ?? '').trim().toLowerCase();
    final materialsIncluded = parsed.materialsIncluded == true;
    final laborOnly = parsed.laborOnly == true;
    final coats = parsed.coats;
    final prep = parsed.prep;
    final rush = parsed.rush;

    final aiTemplate = aiNotesTemplate?.trim() ?? '';
    if (aiTemplate.isNotEmpty) {
      return _applyAiTemplate(
        aiTemplate,
        parsed,
      );
    }

    final ruleLabel = _resolveRuleLabel(
      serviceType: serviceType,
      currentRule: currentRule,
    );

    switch (serviceType) {
      case 'painting':
        notes.add(
          'Final price may change if hidden damage or additional work is discovered.',
        );
        notes.add(
          'Final color, material, and finish selections must be confirmed before work begins.',
        );
        break;

      case 'drywall':
        notes.add(
          'Final price may change if hidden damage, framing issues, or additional repair work is discovered.',
        );
        notes.add(
          'Surface condition and final finish level must be confirmed before work begins.',
        );
        break;

      case 'cleaning':
        notes.add(
          'Final price may change if the actual cleaning condition requires additional labor or specialty treatment.',
        );
        notes.add(
          'Final cleaning scope must be confirmed based on site condition at the time of service.',
        );
        break;

      case 'flooring':
        notes.add(
          'Final price may change if hidden subfloor issues or leveling work are discovered.',
        );
        notes.add(
          'Final material and finish selections must be confirmed before installation begins.',
        );
        break;

      default:
        notes.add(
          'Final price may change if hidden conditions, access limitations, or additional work are discovered during the ${ruleLabel.toLowerCase()} service.',
        );
        notes.add(
          'Final materials, finish selections, and work conditions must be confirmed before work begins.',
        );
        break;
    }



    if (materialsIncluded) {
      notes.add('Materials are included in the current estimate.');
    } else if (laborOnly) {
      notes.add('Labor only. Materials are not included unless listed separately.');
    } else {
      notes.add('Materials are not included unless specifically listed.');
    }

    if (serviceType == 'painting' && (coats ?? 0) > 0) {
      notes.add(
        'Estimate is based on $coats coat${coats! > 1 ? 's' : ''}.',
      );
    }

    if (prep) {
      notes.add('Minor prep work is included where specified.');
    }

    if (rush) {
      notes.add('Rush timeline may affect scheduling availability.');
    }

    return notes.join(' ');
  }

  static List<String> _buildServiceSpecificNotes({
    required String serviceType,
    required String prompt,
  }) {
    switch (serviceType) {
      case 'plumbing':
        final notes = <String>[
          'Final price may change if hidden plumbing damage or access limitations are discovered during service.',
        ];

        if (_containsAny(prompt, [
          'toilet',
          'toilet leak',
          'leaking toilet',
        ])) {
          notes.add(
            'Any internal toilet component replacement, if needed after inspection, may affect final pricing.',
          );
        } else if (_containsAny(prompt, [
          'drain',
          'clog',
          'clogged',
        ])) {
          notes.add(
            'Drain condition and blockage severity must be confirmed on site before final completion scope is confirmed.',
          );
        } else if (_containsAny(prompt, [
          'faucet',
          'tap',
          'fixture',
        ])) {
          notes.add(
            'Fixture compatibility and final product selection must be confirmed before installation.',
          );
        } else if (_containsAny(prompt, [
          'pipe',
          'pipe leak',
          'water leak',
          'leak',
        ])) {
          notes.add(
            'Leak source and affected plumbing sections must be confirmed during on-site inspection.',
          );
        } else {
          notes.add(
            'Final plumbing scope may change depending on on-site inspection findings and access conditions.',
          );
        }

        return notes;

      case 'electrical':
        return [
          'Final price may change if hidden wiring issues, code-related corrections, or access limitations are discovered.',
          'Electrical components, compatibility, and final installation conditions must be confirmed on site before completion.',
        ];

      case 'hvac':
        return [
          'Final price may change if hidden equipment issues, airflow problems, or access limitations are discovered.',
          'Equipment condition, compatibility, and final HVAC service requirements must be confirmed on site.',
        ];

      case 'painting':
        return [
          'Final price may change if hidden damage or additional work is discovered.',
          'Final color, material, and finish selections must be confirmed before work begins.',
        ];

      case 'drywall':
        return [
          'Final price may change if hidden damage, framing issues, or additional repair work is discovered.',
          'Surface condition and final finish level must be confirmed before work begins.',
        ];

      case 'cleaning':
        return [
          'Final price may change if the actual cleaning condition requires additional labor or specialty treatment.',
          'Final cleaning scope must be confirmed based on site condition at the time of service.',
        ];

      case 'flooring':
        return [
          'Final price may change if hidden subfloor issues or leveling work are discovered.',
          'Final material and finish selections must be confirmed before installation begins.',
        ];

      default:
        return [
          'Final price may change if hidden damage or additional work is discovered.',
          'Final materials, finish selections, and work conditions must be confirmed before work begins.',
        ];
    }
  }

  static String _buildPrepNote({
    required String serviceType,
  }) {
    switch (serviceType) {
      case 'plumbing':
        return 'Minor prep and access setup are included where specified.';
      case 'electrical':
        return 'Basic setup and access preparation are included where specified.';
      case 'hvac':
        return 'Basic access preparation and setup are included where specified.';
      default:
        return 'Minor prep work is included where specified.';
    }
  }

  static String _buildRushNote({
    required String serviceType,
  }) {
    switch (serviceType) {
      case 'plumbing':
        return 'Rush plumbing scheduling may affect technician availability and final timing.';
      case 'electrical':
        return 'Rush electrical scheduling may affect technician availability and final timing.';
      case 'hvac':
        return 'Rush HVAC scheduling may affect technician availability and final timing.';
      default:
        return 'Rush timeline may affect scheduling availability.';
    }
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

    if (normalized.isEmpty) return 'General';

    switch (normalized) {
      case 'painting':
        return 'Painting';
      case 'drywall':
        return 'Drywall';
      case 'cleaning':
        return 'Cleaning';
      case 'flooring':
        return 'Flooring';
      case 'general':
        return 'General';
      default:
        return normalized
            .split(RegExp(r'[_\-\s]+'))
            .where((e) => e.isNotEmpty)
            .map((part) => part[0].toUpperCase() + part.substring(1))
            .join(' ');
    }
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
    final coats = parsed.coats ?? 2;

    return template
        .replaceAll('{service_type}', serviceType)
        .replaceAll('{service_label}', serviceLabel)
        .replaceAll('{sqft}', sqft?.toStringAsFixed(0) ?? '')
        .replaceAll('{rooms}', rooms?.toString() ?? '')
        .replaceAll('{coats}', coats.toString())
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

