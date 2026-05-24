import '../models/ai_estimate_result_model.dart';
import '../models/ai_parsed_request_model.dart';
import '../models/ai_generated_text_model.dart';
import 'estimate_draft_builder_service.dart';
import 'estimate_history_suggestion_service.dart';
import 'estimate_prompt_parser_service.dart';
import 'estimate_question_service.dart';
import 'estimate_dynamic_service_type_service.dart';
import 'parse_estimate_mini_service.dart';
import 'ai_estimate_text_service.dart';
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
    List<EstimateItemModel> promptMaterials = const [], // ← ДОБАВЬ
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
      final selectedServiceType =
      selectedRule?.serviceType.trim().toLowerCase();

      final parsedBeforeQuestions = selectedServiceType != null &&
          selectedServiceType.isNotEmpty
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

      final finalParsed =
      allowDraftWithExplicitService && explicitServiceType != null
          ? enriched.copyWith(missingFields: const [])
          : enriched;

      final historyContext = await EstimateHistorySuggestionService.buildContext(
        prompt: trimmedPrompt,
        clientId: clientId,
        propertyId: propertyId,
      );

      // Билдер строит items (через PricingEngine) и базовый scope/notes.
      // Базовый текст всё равно перетрётся через AI text service ниже,
      // но билдер нужен чтобы получить items с правильными ценами.
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

      // === КРИТИЧНО: добавляем материалы из промпта ДО AI text ===
      final resultWithPromptMaterials = _attachPromptMaterials(
        result: resultWithRush,
        promptMaterials: promptMaterials,
      );

      // === Фаза 3: профессиональный AI-текст ===
      final aiText = await _generateAiText(
        result: resultWithPromptMaterials,
        prompt: trimmedPrompt,
        parsed: finalParsed,
        selectedRule: selectedRule,
        propertyCity: propertyCity,
      );

      final resultWithAiText = _mergeAiText(
        result: resultWithPromptMaterials,
        aiText: aiText,
      );

      final resultWithRealConfidence = _calculateRealConfidence(
        result: resultWithAiText,
        parsed: finalParsed,
      );

      final resultWithHistory = resultWithRealConfidence.copyWith(
        historyContext: historyContext,
      );

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
    List<EstimateItemModel> promptMaterials = const [], // ← ДОБАВЬ
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

      final enriched =
      await EstimateQuestionService.enrich(parsedBeforeQuestions);
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

// === КРИТИЧНО: добавляем материалы из промпта ДО AI text ===
// Чтобы AI видел полную картину items и не писал "materials not included"
// когда они на самом деле есть.
      final resultWithPromptMaterials = _attachPromptMaterials(
        result: resultWithRush,
        promptMaterials: promptMaterials,
      );

// === Фаза 3: профессиональный AI-текст ===
      final aiText = await _generateAiText(
        result: resultWithPromptMaterials,
        prompt: trimmedPrompt,
        parsed: updated,
        selectedRule: selectedRule,
        propertyCity: propertyCity,
      );

      final resultWithAiText = _mergeAiText(
        result: resultWithPromptMaterials, // ← было resultWithRush
        aiText: aiText,
      );

      final resultWithRealConfidence = _calculateRealConfidence(
        result: resultWithAiText,
        parsed: updated,
      );

      final resultWithHistory = resultWithRealConfidence.copyWith(
        historyContext: historyContext,
      );

      return resultWithHistory;
    } catch (_) {
      rethrow;
    }
  }

  // =====================================================================
  // Фаза 3: AI Text Generation
  // =====================================================================

  static Future<AiGeneratedTextModel> _generateAiText({
    required AiEstimateResultModel result,
    required String prompt,
    required AiParsedRequestModel parsed,
    required EstimatePriceRuleModel? selectedRule,
    String? propertyCity,
  }) async {
    if (result.items.isEmpty || selectedRule == null) {
      return AiGeneratedTextModel.empty();
    }

    final intent = _detectActionPricingIntent(prompt);
    final hasRush = _hasRushSignal(prompt);

    // Materials mode определяется в порядке приоритета:
// 1. Явный labor_only из парсинга → labor_only
// 2. В items есть material — значит included (источник правды)
// 3. parsed.materialsIncluded подтверждает → included
// 4. Иначе → unknown
    final hasMaterialItem = result.items.any(_isPromptMaterialItem);

    final materialsMode = parsed.laborOnly == true
        ? 'labor_only'
        : hasMaterialItem
        ? 'included'
        : parsed.materialsIncluded == true
        ? 'included'
        : 'unknown';

    print('🔴 MATERIALS MODE: $materialsMode');
    print('🔴 hasMaterialItem: $hasMaterialItem');
    print('🔴 items in result: ${result.items.length}');
    for (final item in result.items) {
      print('   - ${item.title} | \$${item.unitPrice}');
    }

    try {
      return await AiEstimateTextService.generate(
        items: result.items,
        selectedRule: selectedRule,
        originalPrompt: prompt,
        intent: intent,
        hasRush: hasRush,
        materialsMode: materialsMode,
        propertyCity: propertyCity,
      );
    } catch (_) {
      // Тихий fallback: AI упал — оставляем то что построил билдер.
      // Логирование подключим отдельно когда будет нужно.
      return AiGeneratedTextModel.empty();
    }
  }

  static AiEstimateResultModel _mergeAiText({
    required AiEstimateResultModel result,
    required AiGeneratedTextModel aiText,
  }) {
    if (aiText.isEmpty) return result;

    return result.copyWith(
      title: aiText.title.isNotEmpty ? aiText.title : result.title,
      scope: aiText.scopeOfWork.isNotEmpty ? aiText.scopeOfWork : result.scope,
      notes: aiText.notes.isNotEmpty ? aiText.notes : result.notes,
      generatedText: aiText,
    );
  }

  // =====================================================================
  // Rush detection
  // =====================================================================

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

  // =====================================================================
  // Conditional diagnostic
  // =====================================================================

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

    final combined = [diagnosticItem, ...result.items];
    final normalized = combined.asMap().entries.map((entry) {
      return entry.value.copyWith(sortOrder: entry.key);
    }).toList();

    return result.copyWith(items: normalized);
  }

  // =====================================================================
  // Main labor item guarantee
  // =====================================================================

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
    final ruleRate = _rateForAction(rule: selectedRule, intent: intent);
    final resolvedRate = promptOverride ?? ruleRate;

    if (intent == 'diagnostic' && (resolvedRate == null || resolvedRate <= 0)) {
      return result;
    }

    if (resolvedRate == null || resolvedRate <= 0) return result;

    final serviceLabel = selectedRule.displayName?.trim().isNotEmpty == true
        ? selectedRule.displayName!.trim()
        : selectedRule.serviceType.trim();

    final quantity =
    intent == 'diagnostic' ? 1.0 : _extractActionQuantity(prompt) ?? 1.0;

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
      items: [item, ...result.items].asMap().entries.map((entry) {
        return entry.value.copyWith(sortOrder: entry.key);
      }).toList(),
    );
  }

  // =====================================================================
  // Rush items normalization
  // =====================================================================

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
      final isRush =
      RegExp(r'\b(rush|urgent|priority|expedited)\b').hasMatch(text);

      if (!isRush) return item;
      return item.copyWith(title: '$serviceLabel Rush Fee');
    }).toList();

    return result.copyWith(
      items: items.asMap().entries.map((entry) {
        return entry.value.copyWith(sortOrder: entry.key);
      }).toList(),
    );
  }

  static AiEstimateResultModel _appendRushFeeIfNeeded({
    required AiEstimateResultModel result,
    required String prompt,
    required EstimatePriceRuleModel? selectedRule,
  }) {
    if (selectedRule == null) return result;
    if (!_hasRushSignal(prompt)) return result;
    if (!result.items.any(_isMainLaborItem)) return result;

    final normalizedRushTitles = _normalizeRushItemTitles(
      result: result,
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
      items: [...normalizedRushTitles.items, rushItem],
    );

    return _normalizeRushItemTitles(
      result: withRush,
      selectedRule: selectedRule,
    );
  }

  // =====================================================================
  // Intent detection
  // =====================================================================

  static String _detectActionPricingIntent(String prompt) {
    final text = _rushClean(prompt);

    if (RegExp(r'\b(inspection diagnostic only|diagnostic only|inspection only)\b')
        .hasMatch(text)) {
      return 'diagnostic';
    }

    if (RegExp(r'\b(install|installation|mount|setup|connect|ustanovit|ornatish)\b')
        .hasMatch(text)) {
      return 'install';
    }

    if (RegExp(r'\b(replace|replacement|swap|change|zamenit|almashtir)\b')
        .hasMatch(text)) {
      return 'replace';
    }

    if (RegExp(r'\b(repair|fix|troubleshoot|leak|broken|not working|remont|pochinit|otremontirovat)\b')
        .hasMatch(text)) {
      return 'repair';
    }

    if (RegExp(r'\b(inspect|inspection|diagnose|diagnostic|check|verify|proverit|diagnostika)\b')
        .hasMatch(text)) {
      return 'diagnostic';
    }

    return 'base';
  }

  // =====================================================================
  // Labor override from prompt (e.g. "rush 200", "labor 150")
  // =====================================================================

  static double? _extractPromptLaborOverrideRate(String prompt) {
    final raw = prompt.trim().toLowerCase();
    if (raw.isEmpty) return null;

    final clauses = raw
        .split(RegExp(r'[.;,\n\r]+'))
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();

    double? parseMoney(String value) {
      final clean = value.replaceAll('\$', '').replaceAll(',', '.').trim();
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

      if (material && !labor) continue;

      final moneyMatch = RegExp(
        r'(\$\s*\d+(?:[.,]\d+)?|\d+(?:[.,]\d+)?\s*\$)',
      ).firstMatch(clause);

      if (moneyMatch != null) {
        final value = parseMoney(moneyMatch.group(0)!);
        if (value != null) return value;
      }

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

  // =====================================================================
  // Rate selection (action > base > diagnostic)
  // =====================================================================

  static double? _rateForAction({
    required EstimatePriceRuleModel rule,
    required String intent,
  }) {
    if (intent == 'install') {
      final actionRate = rule.installFixedRate ?? 0;
      return actionRate > 0 ? actionRate : rule.baseRate;
    }

    if (intent == 'replace') {
      final actionRate = rule.replaceFixedRate ?? 0;
      return actionRate > 0 ? actionRate : rule.baseRate;
    }

    if (intent == 'repair') {
      final actionRate = rule.repairFixedRate ?? 0;
      return actionRate > 0 ? actionRate : rule.baseRate;
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

  // =====================================================================
  // Action quantity extraction
  // =====================================================================

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
      return double.tryParse(anyNumber.group(1)!.replaceAll(',', '.'));
    }

    return null;
  }

  // =====================================================================
  // Action pricing application
  // =====================================================================

  static AiEstimateResultModel _applyActionPricingIfNeeded({
    required AiEstimateResultModel result,
    required String prompt,
    required EstimatePriceRuleModel? selectedRule,
  }) {
    if (selectedRule == null) return result;
    if (result.items.isEmpty) return result;

    final intent = _detectActionPricingIntent(prompt);
    final promptOverride = _extractPromptLaborOverrideRate(prompt);
    final ruleRate = _rateForAction(rule: selectedRule, intent: intent);
    final resolvedRate = promptOverride ?? ruleRate;

    final laborIndex = result.items.indexWhere(_isMainLaborItem);
    if (laborIndex < 0) return result;

    if (intent == 'diagnostic' && (resolvedRate == null || resolvedRate <= 0)) {
      final filtered = <EstimateItemModel>[
        for (var i = 0; i < result.items.length; i++)
          if (i != laborIndex) result.items[i],
      ];
      return result.copyWith(items: filtered);
    }

    if (resolvedRate == null || resolvedRate <= 0) return result;

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

  // =====================================================================
  // Mini parse helpers
  // =====================================================================

  static Future<AiParsedRequestModel> _applyMiniParseIfNeeded({
    required String prompt,
    required AiParsedRequestModel localParsed,
  }) async {
    if (!_shouldUseMiniParse(localParsed)) return localParsed;

    try {
      final mini = await ParseEstimateMiniService.parse(
        prompt: prompt,
        localParsed: localParsed.toMap(),
      );

      return _mergeMiniParse(localParsed: localParsed, mini: mini);
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
    if (value == null || value.isEmpty) return null;

    return value.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  /// Реальная confidence: насколько estimate готов к отправке клиенту.
  /// Считается из реальных факторов готовности, а не из парсинг-уверенности.
  static AiEstimateResultModel _calculateRealConfidence({
    required AiEstimateResultModel result,
    required AiParsedRequestModel parsed,
  }) {
    double score = 0;

    // 1. Items найдены (есть price) — 30%
    if (result.items.isNotEmpty) {
      final hasValidPrices = result.items.every((item) => item.lineTotal > 0);
      score += hasValidPrices ? 0.30 : 0.15;
    }

    // 2. Materials handling — 20%
    // Либо явно labor only, либо явно included с ценами, либо unknown но labor стоит
    final materialsMode = parsed.laborOnly == true
        ? 'labor_only'
        : parsed.materialsIncluded == true
        ? 'included'
        : 'unknown';

    if (materialsMode == 'labor_only' || materialsMode == 'included') {
      score += 0.20;
    } else if (result.items.isNotEmpty) {
      score += 0.10; // unknown но есть labor — частичный балл
    }

    // 3. AI text сгенерирован (Фаза 3) — 25%
    final aiText = result.generatedText;
    if (aiText != null && !aiText.isEmpty) {
      final hasRichText = aiText.inclusions.isNotEmpty &&
          aiText.exclusions.isNotEmpty &&
          aiText.scopeOfWork.isNotEmpty;
      score += hasRichText ? 0.25 : 0.10;
    }

    // 4. Missing fields заполнены — 15%
    final hasRequiredMissing = result.missingFields.any((f) => f.isRequired);
    if (!hasRequiredMissing) {
      score += 0.15;
    }

    // 5. History context подтверждает — 10%
    final history = result.historyContext;
    if (history != null && history.bestSuggestion != null) {
      final bestScore = history.bestSuggestion!.score;
      if (bestScore >= 0.85) {
        score += 0.10;
      } else if (bestScore >= 0.70) {
        score += 0.05;
      }
    }

    // Зажимаем в [0.0, 1.0]
    final finalScore = score.clamp(0.0, 1.0);

    return result.copyWith(confidence: finalScore);
  }

  // =====================================================================
// Prompt materials handling
// =====================================================================

  /// Прикрепляет материалы из промпта к items с дедупом.
  /// Вызывается ДО AI text generation, чтобы AI видел полную картину.
  static AiEstimateResultModel _attachPromptMaterials({
    required AiEstimateResultModel result,
    required List<EstimateItemModel> promptMaterials,
  }) {
    if (promptMaterials.isEmpty) return result;

    // Дедуп: если material уже есть в items (по qty + unitPrice + объект) — пропускаем
    final existingItems = result.items;

    final filteredMaterials = promptMaterials.where((material) {
      return !existingItems.any((existing) {
        return _isDuplicateMaterial(existing, material);
      });
    }).toList();

    if (filteredMaterials.isEmpty) return result;

    final normalizedMaterials = filteredMaterials.asMap().entries.map((entry) {
      final index = existingItems.length + entry.key;
      return entry.value.copyWith(sortOrder: index);
    }).toList();

    return result.copyWith(
      items: [...existingItems, ...normalizedMaterials],
    );
  }

  /// Item, который похож на материал из промпта.
  static bool _isPromptMaterialItem(EstimateItemModel item) {
    final text = _rushClean('${item.title} ${item.description} ${item.unit}');

    // 1. Явный признак материала по словам
    final hasMaterialWord = RegExp(
      r'\b(material|materials|part|parts|supply|supplies)\b',
    ).hasMatch(text);

    if (hasMaterialWord) return true;

    // 2. Признак материала по типу работы — НЕ labor
    // Если в title нет действия (Installation/Repair/Replacement/Diagnostic/Service/Rush/Prep)
    // и есть unit "item" или "fixed" — скорее всего это материал из промпта
    final hasActionWord = RegExp(
      r'\b(installation|install|repair|replace|replacement|diagnostic|diagnose|inspection|inspect|service|rush|urgent|prep|preparation|labor|labour)\b',
    ).hasMatch(text);

    if (hasActionWord) return false;

    // 3. Если описание говорит "Parsed from prompt" — это материал из промпта
    final isFromPrompt = RegExp(
      r'\bparsed from prompt\b',
    ).hasMatch(text);

    return isFromPrompt;
  }

  static bool _isDuplicateMaterial(
      EstimateItemModel existing,
      EstimateItemModel material,
      ) {
    bool closeMoney(double a, double b) => (a - b).abs() < 0.01;

    if (!closeMoney(existing.quantity, material.quantity)) return false;
    if (!closeMoney(existing.unitPrice, material.unitPrice)) return false;

    final eText = _rushClean('${existing.title} ${existing.description}');
    final mText = _rushClean('${material.title} ${material.description}');

    // Если в обоих есть общее слово длиной >= 4 (объект) — считаем дубликатом
    final eWords = eText.split(' ').where((w) => w.length >= 4).toSet();
    final mWords = mText.split(' ').where((w) => w.length >= 4).toSet();

    return eWords.intersection(mWords).isNotEmpty;
  }
}

