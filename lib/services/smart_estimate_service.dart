import '../models/ai_estimate_result_model.dart';
import '../models/ai_parsed_request_model.dart';
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
    String? ruleUnit,
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

      return resultWithHistory;
    } catch (_) {
      rethrow;
    }
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