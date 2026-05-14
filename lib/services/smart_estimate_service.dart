import '../models/ai_estimate_result_model.dart';
import '../models/ai_parsed_request_model.dart';
import 'estimate_draft_builder_service.dart';
import 'estimate_history_suggestion_service.dart';
import 'estimate_prompt_parser_service.dart';
import 'estimate_question_service.dart';
import 'estimate_dynamic_service_type_service.dart';
import 'parse_estimate_mini_service.dart';
import '../models/estimate_price_rule_model.dart';
import '../models/estimate_item_model.dart';

class _ActionQuantityPart {
  final String intent;
  final double quantity;
  final String rawText;

  const _ActionQuantityPart({
    required this.intent,
    required this.quantity,
    required this.rawText,
  });
}

class SmartEstimateService {
  SmartEstimateService._();

  static Future<AiEstimateResultModel> generate({
    required String prompt,
    String? propertyCity,
    String? clientId,
    String? propertyId,
    String? ruleUnit,
    bool allowDraftWithExplicitService = false,
    EstimatePriceRuleModel? selectedRule,
  }) async {
    final trimmedPrompt = prompt.trim();

    if (trimmedPrompt.isEmpty) {
      final emptyParsed = AiParsedRequestModel.empty(trimmedPrompt);

      return AiEstimateResultModel(
        title: null,
        scope: null,
        notes: null,
        items: const [],
        parsedRequest: emptyParsed,
        historyContext: null,
        assumptions: const [],
        missingFields: const [],
        confidence: 0,
      );
    }

    try {
      final localParsed = EstimatePromptParserService.parse(
        trimmedPrompt,
        ruleUnit: ruleUnit,
      );

      final mergedParsed = await _applyMiniParseIfNeeded(
        prompt: trimmedPrompt,
        localParsed: localParsed,
      );

      final explicitServiceType = _extractExplicitServiceType(trimmedPrompt);

      final selectedServiceType = selectedRule?.serviceType.trim().toLowerCase();

      final parsedBeforeQuestions =
      selectedServiceType != null && selectedServiceType.isNotEmpty
          ? mergedParsed.copyWith(
        serviceType: selectedServiceType,
        confidence: mergedParsed.confidence < 0.85
            ? 0.85
            : mergedParsed.confidence,
      )
          : explicitServiceType == null
          ? await EstimateDynamicServiceTypeService.apply(mergedParsed)
          : mergedParsed.copyWith(
        serviceType: explicitServiceType,
        confidence: mergedParsed.confidence < 0.75
            ? 0.75
            : mergedParsed.confidence,
      );

      final enriched = await EstimateQuestionService.enrich(
        parsedBeforeQuestions,
        selectedRule: selectedRule,
      );

      final finalParsed = allowDraftWithExplicitService && explicitServiceType != null
          ? enriched.copyWith(
        missingFields: const [],
      )
          : enriched;

      final historyContext = await EstimateHistorySuggestionService.buildContext(
        prompt: trimmedPrompt,
        clientId: clientId,
        propertyId: propertyId,
      );

      final result = await EstimateDraftBuilderService.build(
        parsed: finalParsed,
        propertyCity: propertyCity,
        selectedRule: selectedRule,
      );

      final resultWithGuaranteedLabor = _ensureMainLaborItemIfNeeded(
        result: result,
        prompt: trimmedPrompt,
        selectedRule: selectedRule,
      );

      final resultWithActionPricing = _applyActionPricingIfNeeded(
        result: resultWithGuaranteedLabor,
        prompt: trimmedPrompt,
        selectedRule: selectedRule,
      );

      final resultWithConditionalDiagnostic =
      _appendConditionalDiagnosticFeeIfNeeded(
        result: resultWithActionPricing,
        prompt: trimmedPrompt,
        selectedRule: selectedRule,
      );

      final resultWithRush = _appendRushFeeIfNeeded(
        result: resultWithConditionalDiagnostic,
        prompt: trimmedPrompt,
        selectedRule: selectedRule,
      );

      final resultWithIntentText = _applyIntentBasedScopeAndNotes(
        result: resultWithRush,
        prompt: trimmedPrompt,
        selectedRule: selectedRule,
      );

      final resultWithHistory = resultWithIntentText.copyWith(
        historyContext: historyContext,
      );

      final hasGeneratedDraft =
          resultWithHistory.canAutoGenerate && resultWithHistory.items.isNotEmpty;

      if (hasGeneratedDraft) {
        return resultWithHistory;
      }

      return resultWithHistory;
    } catch (_) {
      rethrow;
    }
  }



  static Future<AiEstimateResultModel> regenerateWithAnswers({
    required String prompt,
    required Map<String, dynamic> answers,
    String? propertyCity,
    String? clientId,
    String? propertyId,
    String? ruleUnit,
    EstimatePriceRuleModel? selectedRule,
  }) async {
    final trimmedPrompt = prompt.trim();

    if (trimmedPrompt.isEmpty) {
      return generate(
        prompt: trimmedPrompt,
        propertyCity: propertyCity,
        clientId: clientId,
        propertyId: propertyId,
      );
    }

    try {
      final localParsed = EstimatePromptParserService.parse(
        trimmedPrompt,
        ruleUnit: ruleUnit,
      );

      final mergedParsed = await _applyMiniParseIfNeeded(
        prompt: trimmedPrompt,
        localParsed: localParsed,
      );

      final explicitServiceType = _extractExplicitServiceType(trimmedPrompt);

      final parsedBeforeQuestions = explicitServiceType == null
          ? await EstimateDynamicServiceTypeService.apply(mergedParsed)
          : mergedParsed.copyWith(
        serviceType: explicitServiceType,
        confidence: mergedParsed.confidence < 0.75
            ? 0.75
            : mergedParsed.confidence,
      );

      final enriched = await EstimateQuestionService.enrich(parsedBeforeQuestions);
      final updated = await EstimateQuestionService.applyAnswers(
        enriched,
        answers,
        selectedRule: selectedRule,
      );

      final historyContext = await EstimateHistorySuggestionService.buildContext(
        prompt: trimmedPrompt,
        clientId: clientId,
        propertyId: propertyId,
      );

      final result = await EstimateDraftBuilderService.build(
        parsed: updated,
        propertyCity: propertyCity,
        selectedRule: selectedRule,
      );

      final resultWithGuaranteedLabor = _ensureMainLaborItemIfNeeded(
        result: result,
        prompt: trimmedPrompt,
        selectedRule: selectedRule,
      );

      final resultWithActionPricing = _applyActionPricingIfNeeded(
        result: resultWithGuaranteedLabor,
        prompt: trimmedPrompt,
        selectedRule: selectedRule,
      );

      final resultWithConditionalDiagnostic =
      _appendConditionalDiagnosticFeeIfNeeded(
        result: resultWithActionPricing,
        prompt: trimmedPrompt,
        selectedRule: selectedRule,
      );

      final resultWithRush = _appendRushFeeIfNeeded(
        result: resultWithConditionalDiagnostic,
        prompt: trimmedPrompt,
        selectedRule: selectedRule,
      );

      final resultWithIntentText = _applyIntentBasedScopeAndNotes(
        result: resultWithRush,
        prompt: trimmedPrompt,
        selectedRule: selectedRule,
      );

      final resultWithHistory = resultWithIntentText.copyWith(
        historyContext: historyContext,
      );

      final hasGeneratedDraft =
          resultWithHistory.canAutoGenerate && resultWithHistory.items.isNotEmpty;

      if (hasGeneratedDraft) {
        return resultWithHistory;
      }

      return resultWithHistory;
    } catch (_) {
      rethrow;
    }
  }

  static String _rushClean(String value) {
    return value
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9\s]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  static bool _hasRushSignal(String prompt) {
    final text = _rushClean(prompt);

    if (text.isEmpty) return false;

    final noRush = RegExp(
      r'\b(no rush|not urgent|not rush|not priority|standard timing|normal schedule|normal service|not expedited|no expedited|ne srochnaya|nesrochnaya|rabota ne srochnaya|ne srochno|bez srochnosti|obychnaya rabota|regular schedule)\b',
    ).hasMatch(text);

    if (noRush) return false;

    return RegExp(
      r'\b(urgent|rush|asap|same day|emergency|priority|expedited|srochno|srochnaya|rabota srochnaya|shoshilinch)\b',
    ).hasMatch(text);
  }

  static String? _polishRushEstimateText(String? value) {
    final text = (value ?? '').trim();
    if (text.isEmpty) return value;

    var cleaned = text
        .replaceAll(
      RegExp(
        r'Expedited scheduling requested;\s*availability may be limited and subject to additional fees\.?',
        caseSensitive: false,
      ),
      'Expedited scheduling requested. Rush fee is included where applicable.',
    )
        .replaceAll(
      RegExp(
        r'Requesting may reduce scheduling lead time;\s*additional fees may apply\.?',
        caseSensitive: false,
      ),
      'Expedited scheduling requested. Rush fee is included where applicable.',
    )
        .replaceAll(
      RegExp(
        r'Request may reduce scheduling lead time;\s*additional fees may apply\.?',
        caseSensitive: false,
      ),
      'Expedited scheduling requested. Rush fee is included where applicable.',
    )
        .replaceAll(
      RegExp(
        r'Rush service requested;\s*additional fees may apply\.?',
        caseSensitive: false,
      ),
      'Expedited scheduling requested. Rush fee is included where applicable.',
    );

    cleaned = cleaned
        .replaceAll(RegExp(r'[ \t]{2,}'), ' ')
        .replaceAll(RegExp(r'\n{3,}'), '\n\n')
        .trim();

    return cleaned;
  }

  static bool _hasConditionalDiagnosticSignal(String prompt) {
    final text = _rushClean(prompt);

    final hasConditional = RegExp(
      r'\b(if needed|as needed|if necessary|when needed|po neobhodimosti|po nado|as required)\b',
    ).hasMatch(text);

    final hasDiagnostic = RegExp(
      r'\b(inspect|inspection|diagnose|diagnostic|check|verify|troubleshoot|proverit|diagnostika)\b',
    ).hasMatch(text);

    return hasConditional && hasDiagnostic;
  }

  static bool _hasDefiniteActionAfterDiagnostic(String prompt) {
    final text = _rushClean(prompt);

    return RegExp(
      r'\b(install|installation|replace|replacement|repair|fix|swap|change|zamenit|ustanovit|remont|pochinit|otremontirovat)\b',
    ).hasMatch(text);
  }

  static bool _alreadyHasDiagnosticItem(AiEstimateResultModel result) {
    return result.items.any((item) {
      final text = _rushClean('${item.title} ${item.description}');
      return RegExp(
        r'\b(diagnostic|diagnose|inspection|inspect|check|troubleshoot)\b',
      ).hasMatch(text);
    });
  }

  static AiEstimateResultModel _appendConditionalDiagnosticFeeIfNeeded({
    required AiEstimateResultModel result,
    required String prompt,
    required EstimatePriceRuleModel? selectedRule,
  }) {
    if (selectedRule == null) return result;

    if (!_hasConditionalDiagnosticSignal(prompt)) return result;
    if (!_hasDefiniteActionAfterDiagnostic(prompt)) return result;

    final diagnosticFee = selectedRule.diagnosticFixedRate ?? 0;

    // Diagnostic = 0 or empty means free, so do not add separate item.
    if (diagnosticFee <= 0) return result;

    if (_alreadyHasDiagnosticItem(result)) return result;

    final serviceLabel = selectedRule.displayName?.trim().isNotEmpty == true
        ? selectedRule.displayName!.trim()
        : selectedRule.serviceType.trim();

    final diagnosticItem = EstimateItemModel(
      id: '',
      estimateId: '',
      title: '$serviceLabel Diagnostic',
      description: 'Diagnostic / inspection fee from Price Rule.',
      unit: 'fixed',
      quantity: 1,
      unitPrice: double.parse(diagnosticFee.toStringAsFixed(2)),
      lineTotal: double.parse(diagnosticFee.toStringAsFixed(2)),
      sortOrder: 0,
      createdAt: null,
    );

    final combined = [
      diagnosticItem,
      ...result.items,
    ];

    final normalized = combined.asMap().entries.map((entry) {
      return entry.value.copyWith(sortOrder: entry.key);
    }).toList();

    return result.copyWith(items: normalized);
  }

  static AiEstimateResultModel _ensureMainLaborItemIfNeeded({
    required AiEstimateResultModel result,
    required String prompt,
    required EstimatePriceRuleModel? selectedRule,
  }) {
    if (selectedRule == null) return result;

    final hasMainLabor = result.items.any(_isMainLaborItem);
    if (hasMainLabor) return result;

    final intent = _detectActionPricingIntent(prompt);

    final promptOverride = _extractPromptLaborOverrideRate(prompt);
    final ruleRate = _rateForAction(
      rule: selectedRule,
      intent: intent,
    );

    final resolvedRate = promptOverride ?? ruleRate;

    if (intent == 'diagnostic' && (resolvedRate == null || resolvedRate <= 0)) {
      return result;
    }

    if (resolvedRate == null || resolvedRate <= 0) return result;

    final serviceLabel = selectedRule.displayName?.trim().isNotEmpty == true
        ? selectedRule.displayName!.trim()
        : selectedRule.serviceType.trim();

    final quantity = intent == 'diagnostic' ? 1.0 : _extractActionQuantity(prompt) ?? 1.0;

    final title = intent == 'diagnostic'
        ? '$serviceLabel Diagnostic'
        : (intent == 'install' || intent == 'replace' || intent == 'repair')
        ? '$serviceLabel ${_actionTitle(intent)}'
        : serviceLabel;

    final item = EstimateItemModel(
      id: '',
      estimateId: '',
      title: title,
      description: intent == 'diagnostic'
          ? 'Diagnostic / inspection fee from Price Rule.'
          : 'Labor for the requested service.',
      unit: intent == 'diagnostic' ? 'fixed' : selectedRule.unit,
      quantity: quantity,
      unitPrice: double.parse(resolvedRate.toStringAsFixed(2)),
      lineTotal: double.parse((quantity * resolvedRate).toStringAsFixed(2)),
      sortOrder: 0,
      createdAt: null,
    );

    return result.copyWith(
      items: [
        item,
        ...result.items,
      ].asMap().entries.map((entry) {
        return entry.value.copyWith(sortOrder: entry.key);
      }).toList(),
    );
  }

  static AiEstimateResultModel _normalizeRushItemTitles({
    required AiEstimateResultModel result,
    required EstimatePriceRuleModel? selectedRule,
  }) {
    if (selectedRule == null) return result;

    final serviceLabel = selectedRule.displayName?.trim().isNotEmpty == true
        ? selectedRule.displayName!.trim()
        : selectedRule.serviceType.trim();

    final items = result.items.map((item) {
      final text = _rushClean('${item.title} ${item.description} ${item.unit}');

      final isRush = RegExp(
        r'\b(rush|urgent|priority|expedited)\b',
      ).hasMatch(text);

      if (!isRush) return item;

      return item.copyWith(
        title: '$serviceLabel Rush Fee',
      );
    }).toList();

    return result.copyWith(
      items: items.asMap().entries.map((entry) {
        return entry.value.copyWith(sortOrder: entry.key);
      }).toList(),
    );
  }

  static AiEstimateResultModel _applyIntentBasedScopeAndNotes({
    required AiEstimateResultModel result,
    required String prompt,
    required EstimatePriceRuleModel? selectedRule,
  }) {
    if (selectedRule == null) return result;

    final intent = _detectActionPricingIntent(prompt);

    final serviceLabel = selectedRule.displayName?.trim().isNotEmpty == true
        ? selectedRule.displayName!.trim()
        : selectedRule.serviceType.trim();

    final objectLabel = _cleanServiceObjectLabel(
      serviceLabel: serviceLabel,
      selectedRule: selectedRule,
    );

    final scope = _buildIntentScopeText(
      intent: intent,
      objectLabel: objectLabel,
      prompt: prompt,
      result: result,
      selectedRule: selectedRule,
    );

    final notes = _buildIntentNotesText(
      intent: intent,
      objectLabel: objectLabel,
      prompt: prompt,
    );

    return result.copyWith(
      scope: scope,
      notes: notes,
    );
  }

  static String _cleanServiceObjectLabel({
    required String serviceLabel,
    required EstimatePriceRuleModel selectedRule,
  }) {
    var text = serviceLabel.trim().toLowerCase();

    if (text.isEmpty) {
      text = selectedRule.serviceType.trim().toLowerCase();
    }

    text = text
        .replaceAll(
      RegExp(
        r'\b(service|services|installation|install|replacement|replace|repair|diagnostic|diagnostics|inspection|inspect|labor|labour|work|job)\b',
        caseSensitive: false,
      ),
      ' ',
    )
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    if (text.isEmpty) {
      text = selectedRule.serviceType.trim().toLowerCase();
    }

    return text;
  }

  static double _mainLaborQuantityForScope(AiEstimateResultModel result) {
    for (final item in result.items) {
      if (_isMainLaborItem(item)) {
        return item.quantity <= 0 ? 1.0 : item.quantity;
      }
    }

    return 1.0;
  }

  static String _formatScopeQuantity(double value) {
    if (value % 1 == 0) return value.toInt().toString();
    return value.toStringAsFixed(1);
  }

  static String _pluralizeScopeObject(String value) {
    final clean = value.trim();
    if (clean.isEmpty) return clean;

    final parts = clean.split(RegExp(r'\s+'));
    final last = parts.removeLast();

    String plural;

    if (RegExp(r'[^aeiou]y$', caseSensitive: false).hasMatch(last)) {
      plural = '${last.substring(0, last.length - 1)}ies';
    } else if (RegExp(r'(s|x|z|ch|sh)$', caseSensitive: false).hasMatch(last)) {
      plural = '${last}es';
    } else {
      plural = '${last}s';
    }

    return [...parts, plural].join(' ');
  }

  static String _scopeObjectText(String objectLabel, double quantity) {
    if (quantity <= 1) return objectLabel;

    return '${_formatScopeQuantity(quantity)} ${_pluralizeScopeObject(objectLabel)}';
  }

  static String _scopeUnitText(
      EstimatePriceRuleModel rule,
      double quantity,
      ) {
    final unit = rule.unit
        .trim()
        .toLowerCase()
        .replaceAll('_', ' ')
        .replaceAll('-', ' ')
        .replaceAll(RegExp(r'\s+'), ' ');

    if (unit.isEmpty || unit == 'fixed') return '';

    final cleanQty = quantity <= 0 ? 1.0 : quantity;
    final unitLabel = cleanQty > 1 ? _pluralizeScopeObject(unit) : unit;

    return '${_formatScopeQuantity(cleanQty)} $unitLabel';
  }

  static String _buildIntentScopeText({
    required String intent,
    required String objectLabel,
    required String prompt,
    required AiEstimateResultModel result,
    required EstimatePriceRuleModel selectedRule,
  }) {
    final quantity = _mainLaborQuantityForScope(result);
    final objectText = _scopeObjectText(objectLabel, quantity);
    final unitText = _scopeUnitText(selectedRule, quantity);
    final unitPhrase = unitText.isEmpty ? '' : ' covering $unitText';
    final parsed = result.parsedRequest;

    final action = <String>[];

    if (intent == 'install') {
      action.add('Supply and install $objectText$unitPhrase.');
      action.add('Work includes standard connection, fitting, and functional testing upon completion.');
    } else if (intent == 'replace') {
      action.add('Remove existing $objectText and install replacement unit$unitPhrase.');
      action.add('Includes disconnection, safe removal, installation, and post-work testing.');
    } else if (intent == 'repair') {
      action.add('Diagnose and repair $objectText$unitPhrase.');
      action.add('Scope includes fault identification, repair of the confirmed issue, and operational verification.');
    } else if (intent == 'diagnostic') {
      action.add('Perform a diagnostic inspection of $objectText.');
      action.add('Technician will assess the condition, identify the root cause, and provide a written summary of findings and recommended next steps.');
    } else {
      action.add('Perform $objectLabel service$unitPhrase as outlined in this estimate.');
      action.add('Work includes all standard labor required to complete the job to a professional standard.');
    }

    if (parsed.laborOnly == true) {
      action.add('Labor only. Client supplies all required materials unless otherwise specified.');
    } else if (parsed.materialsIncluded == true) {
      action.add('Materials are included as itemized in this estimate.');
    } else {
      action.add('Materials are not included unless listed as separate line items.');
    }

    if (_hasRushSignal(prompt)) {
      action.add('Priority scheduling applied. Rush service fee is reflected in the pricing.');
    }

    action.add('Work area will be left clean and clear upon job completion.');

    return _cleanGeneratedEstimateText(action.join(' '));
  }

  static String _buildIntentNotesText({
    required String intent,
    required String objectLabel,
    required String prompt,
  }) {
    final notes = <String>[];

    if (intent == 'install') {
      notes.add('Pricing assumes standard installation conditions with accessible connection points and no pre-existing damage or code deficiencies.');
      notes.add('Any required upgrades, non-standard configurations, permit fees, or structural modifications will be assessed separately.');
    } else if (intent == 'replace') {
      notes.add('Estimate is based on a straightforward like-for-like replacement under normal site conditions.');
      notes.add('Concealed damage, incompatible fittings, code upgrade requirements, or disposal fees not included in this estimate may be invoiced separately.');
    } else if (intent == 'repair') {
      notes.add('Final repair scope is subject to on-site assessment. Price may be adjusted if the issue is more extensive than initially described.');
      notes.add('Parts, additional labor, or follow-up visits required beyond the confirmed repair will require separate authorization.');
    } else if (intent == 'diagnostic') {
      notes.add('Diagnostic fee covers inspection and written assessment only. No repair or replacement work is included unless separately approved.');
      notes.add('A follow-up estimate will be provided for any recommended corrective work identified during the inspection.');
    } else {
      notes.add('Pricing is based on the information provided at the time of estimate. Final invoice may vary if site conditions differ materially from the scope described.');
      notes.add('Any work outside the defined scope requires written approval prior to commencement.');
    }

    return _cleanGeneratedEstimateText(notes.join(' '));
  }

  static String _cleanGeneratedEstimateText(String value) {
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

  static AiEstimateResultModel _appendRushFeeIfNeeded({
    required AiEstimateResultModel result,
    required String prompt,
    required EstimatePriceRuleModel? selectedRule,
  }) {
    final polishedResult = result.copyWith(
      scope: _polishRushEstimateText(result.scope),
      notes: _polishRushEstimateText(result.notes),
    );

    if (selectedRule == null) return polishedResult;
    if (!_hasRushSignal(prompt)) return polishedResult;

    if (!polishedResult.items.any(_isMainLaborItem)) {
      return polishedResult;
    }

    final normalizedRushTitles = _normalizeRushItemTitles(
      result: polishedResult,
      selectedRule: selectedRule,
    );

    final double rushFixed = selectedRule.rushFixedRate ?? 0;
    if (rushFixed <= 0) return normalizedRushTitles;

    final alreadyHasRush = normalizedRushTitles.items.any((item) {
      final title = item.title.toLowerCase();
      return title.contains('rush') ||
          title.contains('urgent') ||
          title.contains('priority') ||
          title.contains('expedited');
    });

    if (alreadyHasRush) return normalizedRushTitles;

    final serviceLabel = selectedRule.displayName?.trim().isNotEmpty == true
        ? selectedRule.displayName!.trim()
        : selectedRule.serviceType.trim();

    final rushItem = EstimateItemModel(
      id: '',
      estimateId: '',
      title: '$serviceLabel Rush Fee',
      description: 'Expedited scheduling fee from Price Rule.',
      unit: 'fixed',
      quantity: 1,
      unitPrice: double.parse(rushFixed.toStringAsFixed(2)),
      lineTotal: double.parse(rushFixed.toStringAsFixed(2)),
      sortOrder: normalizedRushTitles.items.length,
      createdAt: null,
    );

    final withRush = normalizedRushTitles.copyWith(
      items: [
        ...normalizedRushTitles.items,
        rushItem,
      ],
    );

    return _normalizeRushItemTitles(
      result: withRush,
      selectedRule: selectedRule,
    );
  }

  static String _detectActionPricingIntent(String prompt) {
    final text = _rushClean(prompt);

    if (RegExp(
      r'\b(inspection diagnostic only|diagnostic only|inspection only)\b',
    ).hasMatch(text)) {
      return 'diagnostic';
    }

    if (RegExp(
      r'\b(install|installation|mount|setup|connect|ustanovit|ornatish)\b',
    ).hasMatch(text)) {
      return 'install';
    }

    if (RegExp(
      r'\b(replace|replacement|swap|change|zamenit|almashtir)\b',
    ).hasMatch(text)) {
      return 'replace';
    }

    if (RegExp(
      r'\b(repair|fix|troubleshoot|leak|broken|not working|remont|pochinit|otremontirovat)\b',
    ).hasMatch(text)) {
      return 'repair';
    }

    if (RegExp(
      r'\b(inspect|inspection|diagnose|diagnostic|check|verify|proverit|diagnostika)\b',
    ).hasMatch(text)) {
      return 'diagnostic';
    }

    return 'base';
  }

  static double? _extractPromptLaborOverrideRate(String prompt) {
    final raw = prompt.trim().toLowerCase();
    if (raw.isEmpty) return null;

    final clauses = raw
        .split(RegExp(r'[.;,\n\r]+'))
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();

    double? parseMoney(String value) {
      final clean = value
          .replaceAll('\$', '')
          .replaceAll(',', '.')
          .trim();

      final parsed = double.tryParse(clean);
      if (parsed == null || parsed <= 0) return null;

      return parsed;
    }

    bool hasLaborSignal(String text) {
      return RegExp(
        r'\b(labor|labour|work|service|price|rate|cost|install|installation|replace|replacement|repair|fix|zamenit|ustanovit|remont|pochinit|otremontirovat)\b',
      ).hasMatch(text);
    }

    bool hasMaterialSignal(String text) {
      return RegExp(
        r'\b(material|materials|materiali|part|parts|supply|supplies|each|per item|total materials|at|vklyuchen|vklyucheni)\b',
      ).hasMatch(text);
    }

    for (final clause in clauses) {
      final labor = hasLaborSignal(clause);
      final material = hasMaterialSignal(clause);

      // If this clause is only about materials, never use it as labor price.
      if (material && !labor) continue;

      // $200 or 200$
      final moneyMatch = RegExp(
        r'(\$\s*\d+(?:[.,]\d+)?|\d+(?:[.,]\d+)?\s*\$)',
      ).firstMatch(clause);

      if (moneyMatch != null) {
        final value = parseMoney(moneyMatch.group(0)!);
        if (value != null) return value;
      }

      // price 200 / rate 200 / labor 200 / za 200 / for 200
      final keywordPriceMatch = RegExp(
        r'\b(price|rate|cost|labor|labour|work|service|za|for)\s*(is|=|:)?\s*(\d+(?:[.,]\d+)?)\b',
      ).firstMatch(clause);

      if (keywordPriceMatch != null && labor) {
        final value = parseMoney(keywordPriceMatch.group(3)!);
        if (value != null) return value;
      }
    }

    return null;
  }

  static double? _rateForAction({
    required EstimatePriceRuleModel rule,
    required String intent,
  }) {
    if (intent == 'install') {
      return rule.installFixedRate ?? rule.baseRate;
    }

    if (intent == 'replace') {
      return rule.replaceFixedRate ?? rule.baseRate;
    }

    if (intent == 'repair') {
      return rule.repairFixedRate ?? rule.baseRate;
    }

    if (intent == 'diagnostic') {
      return rule.diagnosticFixedRate;
    }

    return rule.baseRate;
  }

  static bool _isMainLaborItem(EstimateItemModel item) {
    final text = _rushClean('${item.title} ${item.description} ${item.unit}');

    if (RegExp(
      r'\b(material|materials|part|parts|supply|supplies|prep|preparation|rush|urgent|priority|expedited)\b',
    ).hasMatch(text)) {
      return false;
    }

    return true;
  }

  static String _actionTitle(String intent) {
    if (intent == 'install') return 'Installation';
    if (intent == 'replace') return 'Replacement';
    if (intent == 'repair') return 'Repair';
    if (intent == 'diagnostic') return 'Diagnostic';
    return 'Service';
  }

  static List<_ActionQuantityPart> _parseActionQuantityBreakdown({
    required String prompt,
    required double fallbackQuantity,
  }) {
    final text = _rushClean(prompt);
    if (text.isEmpty) return const [];

    final cleaned = text
        .replaceAll(RegExp(r'\bservice_type\s+[a-z0-9\s]+'), ' ')
        .replaceAll(RegExp(r'\bservice_label\s+[a-z0-9\s]+'), ' ')
        .replaceAll(RegExp(r'\brequest\s+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    final parts = cleaned
        .split(RegExp(r'[.;,\n\r]+|\band\b|\bi\b|\btakje\b|\balso\b'))
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();

    final result = <_ActionQuantityPart>[];

    for (final part in parts) {
      final intent = _detectActionPricingIntent(part);

      if (intent == 'base') continue;

      final qty = _extractActionQuantity(part) ?? fallbackQuantity;

      result.add(
        _ActionQuantityPart(
          intent: intent,
          quantity: qty,
          rawText: part,
        ),
      );
    }

    final hasRealActionMix = result
        .where((e) => e.intent == 'install' || e.intent == 'replace' || e.intent == 'repair')
        .map((e) => e.intent)
        .toSet()
        .length >= 2;

    if (!hasRealActionMix && result.length < 2) return const [];

    return result;
  }

  static double? _extractActionQuantity(String value) {
    final text = _rushClean(value);
    if (text.isEmpty) return null;

    final directAfterAction = RegExp(
      r'\b(install|installation|mount|setup|connect|ustanovit|ornatish|replace|replacement|swap|change|zamenit|almashtir|repair|fix|service|remont|pochinit)\s+(\d+(?:[.,]\d+)?)\b',
    ).firstMatch(text);

    if (directAfterAction != null) {
      return double.tryParse(
        directAfterAction.group(2)!.replaceAll(',', '.'),
      );
    }

    final directBeforeAction = RegExp(
      r'\b(\d+(?:[.,]\d+)?)\s+(install|installation|mount|setup|connect|ustanovit|ornatish|replace|replacement|swap|change|zamenit|almashtir|repair|fix|service|remont|pochinit|otremontirovat)\b',
    ).firstMatch(text);

    if (directBeforeAction != null) {
      return double.tryParse(
        directBeforeAction.group(1)!.replaceAll(',', '.'),
      );
    }

    final anyNumber = RegExp(r'\b(\d+(?:[.,]\d+)?)\b').firstMatch(text);

    if (anyNumber != null) {
      return double.tryParse(
        anyNumber.group(1)!.replaceAll(',', '.'),
      );
    }

    return null;
  }

  static AiEstimateResultModel _applyActionPricingIfNeeded({
    required AiEstimateResultModel result,
    required String prompt,
    required EstimatePriceRuleModel? selectedRule,
  }) {
    if (selectedRule == null) return result;
    if (result.items.isEmpty) return result;

    final intent = _detectActionPricingIntent(prompt);

    final promptOverride = _extractPromptLaborOverrideRate(prompt);
    final ruleRate = _rateForAction(
      rule: selectedRule,
      intent: intent,
    );

    final resolvedRate = promptOverride ?? ruleRate;

    final laborIndex = result.items.indexWhere(_isMainLaborItem);
    if (laborIndex < 0) return result;

    // Diagnostic / inspection = 0 or empty means free/ignored.
    if (intent == 'diagnostic' && (resolvedRate == null || resolvedRate <= 0)) {
      final filtered = <EstimateItemModel>[
        for (var i = 0; i < result.items.length; i++)
          if (i != laborIndex) result.items[i],
      ];

      return result.copyWith(items: filtered);
    }

    if (resolvedRate == null || resolvedRate <= 0) {
      return result;
    }

    final items = [...result.items];
    final laborItem = items[laborIndex];

    final quantity = intent == 'diagnostic'
        ? 1.0
        : (laborItem.quantity <= 0 ? 1.0 : laborItem.quantity);

    final serviceLabel = selectedRule.displayName?.trim().isNotEmpty == true
        ? selectedRule.displayName!.trim()
        : selectedRule.serviceType.trim();

    final title = intent == 'diagnostic'
        ? '$serviceLabel Diagnostic'
        : (intent == 'install' || intent == 'replace' || intent == 'repair')
        ? '$serviceLabel ${_actionTitle(intent)}'
        : laborItem.title;

    final description = intent == 'diagnostic'
        ? 'Diagnostic / inspection fee from Price Rule.'
        : laborItem.description;

    items[laborIndex] = laborItem.copyWith(
      title: title,
      description: description,
      unit: intent == 'diagnostic' ? 'fixed' : laborItem.unit,
      quantity: quantity,
      unitPrice: double.parse(resolvedRate.toStringAsFixed(2)),
      lineTotal: double.parse((quantity * resolvedRate).toStringAsFixed(2)),
    );

    return result.copyWith(items: items);
  }

  static Future<AiParsedRequestModel> _applyMiniParseIfNeeded({
    required String prompt,
    required AiParsedRequestModel localParsed,
  }) async {
    if (!_shouldUseMiniParse(localParsed)) {
      return localParsed;
    }

    try {
      final mini = await ParseEstimateMiniService.parse(
        prompt: prompt,
        localParsed: localParsed.toMap(),
      );

      return _mergeMiniParse(
        localParsed: localParsed,
        mini: mini,
      );
    } catch (_) {
      return localParsed;
    }
  }

  static bool _shouldUseMiniParse(AiParsedRequestModel parsed) {
    final hasDetailedMaterials = parsed.parsedMaterials.isNotEmpty;
    final lowConfidence = parsed.confidence < 0.60;
    return hasDetailedMaterials || lowConfidence;
  }

  static AiParsedRequestModel _mergeMiniParse({
    required AiParsedRequestModel localParsed,
    required ParseEstimateMiniResult mini,
  }) {
    return localParsed.copyWith(
      serviceType: (mini.serviceType ?? '').trim().isNotEmpty
          ? mini.serviceType
          : localParsed.serviceType,
      sqft: mini.sqft ?? localParsed.sqft,
      rooms: mini.rooms ?? localParsed.rooms,
      hours: mini.hours ?? localParsed.hours,
      materialsIncluded: mini.materialsIncluded ?? localParsed.materialsIncluded,
      laborOnly: mini.laborOnly ?? localParsed.laborOnly,
      parsedMaterials: mini.parsedMaterials.isNotEmpty
          ? mini.parsedMaterials
          : localParsed.parsedMaterials,
      projectSizeRequired: localParsed.projectSizeRequired,
      reasoningHints: mini.reasoningHints.isNotEmpty
          ? mini.reasoningHints
          : localParsed.reasoningHints,
      followupHints: mini.followupHints.isNotEmpty
          ? mini.followupHints
          : localParsed.followupHints,
    );
  }

  static String? _extractExplicitServiceType(String prompt) {
    final match = RegExp(
      r'\bservice_type\s*:\s*([^.,\n\r]+)',
      caseSensitive: false,
    ).firstMatch(prompt);

    final value = match?.group(1)?.trim().toLowerCase();

    if (value == null || value.isEmpty) {
      return null;
    }

    return value
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }


}

