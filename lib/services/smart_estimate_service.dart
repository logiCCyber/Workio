import '../models/ai_assumption_model.dart';
import '../models/ai_estimate_result_model.dart';
import '../models/ai_parsed_request_model.dart';
import 'estimate_ai_service.dart';
import 'estimate_draft_builder_service.dart';
import 'estimate_history_suggestion_service.dart';
import 'estimate_prompt_parser_service.dart';
import 'estimate_question_service.dart';
import 'estimate_dynamic_service_type_service.dart';
import 'parse_estimate_mini_service.dart';

class SmartEstimateService {
  SmartEstimateService._();

  static Future<AiEstimateResultModel> generate({
    required String prompt,
    String? propertyCity,
    String? clientId,
    String? propertyId,
    bool useFallbackOnError = true,
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
        usedFallback: false,
      );
    }

    try {
      final localParsed = EstimatePromptParserService.parse(trimmedPrompt);

      final mergedParsed = await _applyMiniParseIfNeeded(
        prompt: trimmedPrompt,
        localParsed: localParsed,
      );

      final parsedWithDynamicType =
      await EstimateDynamicServiceTypeService.apply(mergedParsed);
      final enriched = await EstimateQuestionService.enrich(parsedWithDynamicType);

      final historyContext = await EstimateHistorySuggestionService.buildContext(
        prompt: trimmedPrompt,
        clientId: clientId,
        propertyId: propertyId,
      );

      final result = await EstimateDraftBuilderService.build(
        parsed: enriched,
        propertyCity: propertyCity,
      );

      final resultWithHistory = result.copyWith(
        historyContext: historyContext,
      );

      final hasGeneratedDraft =
          resultWithHistory.canAutoGenerate && resultWithHistory.items.isNotEmpty;

      if (hasGeneratedDraft) {
        return resultWithHistory;
      }

      if (!useFallbackOnError) {
        return resultWithHistory;
      }

      if (resultWithHistory.canAutoGenerate && resultWithHistory.items.isEmpty) {
        return _buildFallbackResult(
          prompt: trimmedPrompt,
          propertyCity: propertyCity,
          parsedRequest: enriched,
          historyContext: historyContext,
          previousResult: resultWithHistory,
          reason:
          'Smart pricing engine returned no items, so legacy generator was used.',
        );
      }

      return resultWithHistory;
    } catch (_) {
      if (!useFallbackOnError) {
        rethrow;
      }

      final parsed = await _safeParse(trimmedPrompt);
      final historyContext = await EstimateHistorySuggestionService.buildContext(
        prompt: trimmedPrompt,
        clientId: clientId,
        propertyId: propertyId,
      );

      return _buildFallbackResult(
        prompt: trimmedPrompt,
        propertyCity: propertyCity,
        parsedRequest: parsed,
        historyContext: historyContext,
        previousResult: null,
        reason:
        'Smart estimate engine failed unexpectedly, so legacy generator was used.',
      );
    }
  }

  static Future<AiEstimateResultModel> regenerateWithAnswers({
    required String prompt,
    required Map<String, dynamic> answers,
    String? propertyCity,
    String? clientId,
    String? propertyId,
    bool useFallbackOnError = true,
  }) async {
    final trimmedPrompt = prompt.trim();

    if (trimmedPrompt.isEmpty) {
      return generate(
        prompt: trimmedPrompt,
        propertyCity: propertyCity,
        clientId: clientId,
        propertyId: propertyId,
        useFallbackOnError: useFallbackOnError,
      );
    }

    try {
      final localParsed = EstimatePromptParserService.parse(trimmedPrompt);

      final mergedParsed = await _applyMiniParseIfNeeded(
        prompt: trimmedPrompt,
        localParsed: localParsed,
      );

      final parsedWithDynamicType =
      await EstimateDynamicServiceTypeService.apply(mergedParsed);
      final enriched = await EstimateQuestionService.enrich(parsedWithDynamicType);
      final updated = await EstimateQuestionService.applyAnswers(enriched, answers);

      final historyContext = await EstimateHistorySuggestionService.buildContext(
        prompt: trimmedPrompt,
        clientId: clientId,
        propertyId: propertyId,
      );

      final result = await EstimateDraftBuilderService.build(
        parsed: updated,
        propertyCity: propertyCity,
      );

      final resultWithHistory = result.copyWith(
        historyContext: historyContext,
      );

      final hasGeneratedDraft =
          resultWithHistory.canAutoGenerate && resultWithHistory.items.isNotEmpty;

      if (hasGeneratedDraft) {
        return resultWithHistory;
      }

      if (!useFallbackOnError) {
        return resultWithHistory;
      }

      if (resultWithHistory.canAutoGenerate && resultWithHistory.items.isEmpty) {
        return _buildFallbackResult(
          prompt: trimmedPrompt,
          propertyCity: propertyCity,
          parsedRequest: updated,
          historyContext: historyContext,
          previousResult: resultWithHistory,
          reason:
          'Smart pricing engine returned no items after answers were applied, so legacy generator was used.',
        );
      }

      return resultWithHistory;
    } catch (_) {
      if (!useFallbackOnError) {
        rethrow;
      }

      final parsed = await _safeParse(trimmedPrompt);
      final historyContext = await EstimateHistorySuggestionService.buildContext(
        prompt: trimmedPrompt,
        clientId: clientId,
        propertyId: propertyId,
      );

      return _buildFallbackResult(
        prompt: trimmedPrompt,
        propertyCity: propertyCity,
        parsedRequest: parsed,
        historyContext: historyContext,
        previousResult: null,
        reason:
        'Smart estimate engine failed after answers were applied, so legacy generator was used.',
      );
    }
  }

  static AiEstimateResultModel _buildFallbackResult({
    required String prompt,
    required String? propertyCity,
    required AiParsedRequestModel parsedRequest,
    required dynamic historyContext,
    required AiEstimateResultModel? previousResult,
    required String reason,
  }) {
    final fallbackDraft = EstimateAiService.generateDraft(
      prompt: prompt,
      propertyCity: propertyCity,
    );

    final fallbackAssumptions = _mergeAssumptions(
      previousResult?.assumptions ?? parsedRequest.assumptions,
      [
        AiAssumptionModel(
          key: 'fallback_generation',
          label: 'Fallback Generation',
          value: 'Legacy estimate generator',
          reason: reason,
        ),
      ],
    );

    return AiEstimateResultModel(
      title: fallbackDraft.title,
      scope: fallbackDraft.scope,
      notes: fallbackDraft.notes,
      items: fallbackDraft.items,
      parsedRequest: parsedRequest,
      historyContext: historyContext,
      assumptions: fallbackAssumptions,
      missingFields: previousResult?.missingFields ?? parsedRequest.missingFields,
      confidence: _resolveFallbackConfidence(
        previousResult: previousResult,
        parsedRequest: parsedRequest,
      ),
      usedFallback: true,
    );
  }

  static Future<AiParsedRequestModel> _safeParse(String prompt) async {
    try {
      final localParsed = EstimatePromptParserService.parse(prompt);
      final mergedParsed = await _applyMiniParseIfNeeded(
        prompt: prompt,
        localParsed: localParsed,
      );
      return await EstimateQuestionService.enrich(mergedParsed);
    } catch (_) {
      return AiParsedRequestModel.empty(prompt);
    }
  }

  static List<AiAssumptionModel> _mergeAssumptions(
      List<AiAssumptionModel> first,
      List<AiAssumptionModel> second,
      ) {
    final map = <String, AiAssumptionModel>{};

    for (final item in [...first, ...second]) {
      final key = item.key.trim();
      if (key.isEmpty) continue;
      map[key] = item;
    }

    return map.values.toList();
  }

  static double _resolveFallbackConfidence({
    required AiEstimateResultModel? previousResult,
    required AiParsedRequestModel parsedRequest,
  }) {
    final previousConfidence = previousResult?.confidence ?? 0;
    final parsedConfidence = parsedRequest.confidence;

    final resolved = previousConfidence > 0
        ? previousConfidence
        : (parsedConfidence > 0 ? parsedConfidence : 0.55);

    return double.parse(resolved.toStringAsFixed(2));
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
    final builtInOnly = const {
      'painting',
      'drywall',
      'cleaning',
      'flooring',
      'general',
    }.contains((parsed.serviceType ?? '').trim().toLowerCase());

    return hasDetailedMaterials || lowConfidence || builtInOnly;
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
      projectSizeRequired: mini.projectSizeRequired,
      reasoningHints: mini.reasoningHints.isNotEmpty
          ? mini.reasoningHints
          : localParsed.reasoningHints,
      followupHints: mini.followupHints.isNotEmpty
          ? mini.followupHints
          : localParsed.followupHints,
    );
  }
}