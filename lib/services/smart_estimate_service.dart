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

      final resultWithRush = _appendRushFeeIfNeeded(
        result: result,
        prompt: trimmedPrompt,
        selectedRule: selectedRule,
      );

      final resultWithHistory = resultWithRush.copyWith(
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

      final resultWithRush = _appendRushFeeIfNeeded(
        result: result,
        prompt: trimmedPrompt,
        selectedRule: selectedRule,
      );

      final resultWithHistory = resultWithRush.copyWith(
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
      r'\b(no rush|not urgent|not rush|not priority|standard timing|normal schedule|not srochnaya|ne srochnaya|rabota ne srochnaya)\b',
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

    final double rushFixed = selectedRule.rushFixedRate ?? 0;
    if (rushFixed <= 0) return polishedResult;

    final alreadyHasRush = polishedResult.items.any((item) {
      final title = item.title.toLowerCase();
      return title.contains('rush') ||
          title.contains('urgent') ||
          title.contains('priority') ||
          title.contains('expedited');
    });

    if (alreadyHasRush) return polishedResult;

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
      sortOrder: polishedResult.items.length,
      createdAt: null,
    );

    return polishedResult.copyWith(
      items: [
        ...polishedResult.items,
        rushItem,
      ],
    );
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