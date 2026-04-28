import '../models/ai_history_context_model.dart';
import '../models/ai_history_suggestion_model.dart';
import '../models/estimate_model.dart';
import '../models/estimate_price_rule_model.dart';
import 'estimate_prompt_parser_service.dart';
import 'estimate_service.dart';
import 'estimate_dynamic_service_type_service.dart';
import 'estimate_price_rules_service.dart';

class EstimateHistorySuggestionService {
  EstimateHistorySuggestionService._();

  static Future<AiHistoryContextModel> buildContext({
    required String prompt,
    String? clientId,
    String? propertyId,
  }) async {
    final rawPrompt = prompt.trim();
    final normalizedPrompt = _normalize(rawPrompt);

    final parsed = EstimatePromptParserService.parse(rawPrompt);
    final parsedWithDynamicType =
    await EstimateDynamicServiceTypeService.apply(parsed);
    final detectedServiceType =
    parsedWithDynamicType.serviceType?.trim().toLowerCase();

    final promptRule = await _loadMainRule(detectedServiceType);
    final promptIntentKeywords = _extractIntentKeywords(
      normalizedText: normalizedPrompt,
      rule: promptRule,
    );

    final List<EstimateModel> clientHistory;
    final List<EstimateModel> propertyHistory;

    if ((clientId ?? '').trim().isNotEmpty) {
      clientHistory =
      await EstimateService.getPreviousEstimatesByClient(clientId!.trim());
    } else {
      clientHistory = const [];
    }

    if ((propertyId ?? '').trim().isNotEmpty) {
      propertyHistory =
      await EstimateService.getPreviousEstimatesByProperty(propertyId!.trim());
    } else {
      propertyHistory = const [];
    }

    final Map<String, EstimateModel> unique = {};

    for (final estimate in clientHistory) {
      unique[estimate.id] = estimate;
    }

    for (final estimate in propertyHistory) {
      unique[estimate.id] = estimate;
    }

    final rawSuggestions = await Future.wait(
      unique.values.map(
            (estimate) => _toSuggestion(
          estimate: estimate,
          normalizedPrompt: normalizedPrompt,
          detectedServiceType: detectedServiceType,
          promptIntentKeywords: promptIntentKeywords,
          isSameClient: (clientId ?? '').trim().isNotEmpty &&
              estimate.clientId == clientId!.trim(),
          isSameProperty: (propertyId ?? '').trim().isNotEmpty &&
              estimate.propertyId == propertyId!.trim(),
        ),
      ),
    );

    final suggestions = rawSuggestions
        .where((suggestion) => suggestion.score >= 0.40)
        .toList()
      ..sort((a, b) => b.score.compareTo(a.score));

    final topSuggestions = suggestions.take(3).toList();

    return AiHistoryContextModel(
      rawPrompt: rawPrompt,
      normalizedPrompt: normalizedPrompt,
      clientId: clientId,
      propertyId: propertyId,
      detectedServiceType: detectedServiceType,
      suggestions: topSuggestions,
    );
  }

  static Future<AiHistorySuggestionModel> _toSuggestion({
    required EstimateModel estimate,
    required String normalizedPrompt,
    required String? detectedServiceType,
    required Set<String> promptIntentKeywords,
    required bool isSameClient,
    required bool isSameProperty,
  }) async {
    final estimateText = _normalize(
      [
        estimate.title,
        estimate.scopeText ?? '',
        estimate.notes ?? '',
      ].join(' '),
    );

    final estimateParsed = EstimatePromptParserService.parse(estimateText);
    final estimateParsedWithDynamicType =
    await EstimateDynamicServiceTypeService.apply(estimateParsed);
    final estimateServiceType =
    estimateParsedWithDynamicType.serviceType?.trim().toLowerCase();

    final isCompatibleService =
    _isCompatibleServiceType(detectedServiceType, estimateServiceType);

    if ((detectedServiceType ?? '').isNotEmpty &&
        (estimateServiceType ?? '').isNotEmpty &&
        !isCompatibleService) {
      return AiHistorySuggestionModel(
        estimateId: estimate.id,
        title: estimate.title,
        serviceType: estimateServiceType,
        sourceType: _resolveSourceType(
          isSameClient: isSameClient,
          isSameProperty: isSameProperty,
        ),
        reason: 'Different service type',
        score: 0,
        total: estimate.total,
        createdAt: estimate.createdAt,
        isSameClient: isSameClient,
        isSameProperty: isSameProperty,
        matchedFields: const ['different_service_type'],
        suggestedAction: 'use_as_baseline',
      );
    }

    final estimateRule = await _loadMainRule(estimateServiceType);
    final estimateIntentKeywords = _extractIntentKeywords(
      normalizedText: estimateText,
      rule: estimateRule,
    );

    final matchedFields = <String>[];
    double score = 0;

    if (isSameClient) {
      score += 0.12;
      matchedFields.add('same_client');
    }

    if (isSameProperty) {
      score += 0.18;
      matchedFields.add('same_property');
    }

    if ((detectedServiceType ?? '').isNotEmpty && isCompatibleService) {
      score += 0.40;
      matchedFields.add('service_type');
    }

    final intentScore = _calculateIntentOverlapScore(
      promptIntentKeywords: promptIntentKeywords,
      estimateIntentKeywords: estimateIntentKeywords,
    );

    if (intentScore > 0) {
      score += intentScore;
      matchedFields.add('intent_keywords');
    }

    final wordOverlapScore = _calculateWordOverlapScore(
      normalizedPrompt: normalizedPrompt,
      estimateText: estimateText,
    );

    if (wordOverlapScore > 0) {
      score += wordOverlapScore;
      matchedFields.add('scope_keywords');
    }

    final recencyScore = _calculateRecencyScore(estimate.createdAt);
    if (recencyScore > 0) {
      score += recencyScore;
      matchedFields.add('recent_history');
    }

    score = score.clamp(0, 0.98);

    return AiHistorySuggestionModel(
      estimateId: estimate.id,
      title: estimate.title,
      serviceType: estimateServiceType,
      sourceType: _resolveSourceType(
        isSameClient: isSameClient,
        isSameProperty: isSameProperty,
      ),
      reason: _buildReason(
        isSameClient: isSameClient,
        isSameProperty: isSameProperty,
        matchedFields: matchedFields,
      ),
      score: double.parse(score.toStringAsFixed(2)),
      total: estimate.total,
      createdAt: estimate.createdAt,
      isSameClient: isSameClient,
      isSameProperty: isSameProperty,
      matchedFields: matchedFields,
      suggestedAction: 'use_as_baseline',
    );
  }

  static bool _isCompatibleServiceType(String? promptType, String? estimateType) {
    final left = _normalize(promptType ?? '');
    final right = _normalize(estimateType ?? '');

    if (left.isEmpty || right.isEmpty) return true;
    if (left == right) return true;
    if (left.startsWith('$right ') || right.startsWith('$left ')) return true;

    final leftAnchor = _serviceAnchor(left);
    final rightAnchor = _serviceAnchor(right);

    if (leftAnchor.isEmpty || rightAnchor.isEmpty) return false;
    return leftAnchor == rightAnchor;
  }

  static String _serviceAnchor(String value) {
    final words = value
        .split(' ')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .where((e) => !_genericServiceWords.contains(e))
        .toList();

    if (words.isEmpty) return '';
    return words.first;
  }

  static String _resolveSourceType({
    required bool isSameClient,
    required bool isSameProperty,
  }) {
    if (isSameClient && isSameProperty) {
      return 'same_client_and_property';
    }

    if (isSameProperty) {
      return 'same_property';
    }

    if (isSameClient) {
      return 'same_client';
    }

    return 'similar_history';
  }

  static String _buildReason({
    required bool isSameClient,
    required bool isSameProperty,
    required List<String> matchedFields,
  }) {
    final reasons = <String>[];

    if (isSameClient) {
      reasons.add('Same client');
    }

    if (isSameProperty) {
      reasons.add('Same property');
    }

    if (matchedFields.contains('service_type')) {
      reasons.add('Matching service type');
    }

    if (matchedFields.contains('intent_keywords')) {
      reasons.add('Matching AI keywords');
    }

    if (matchedFields.contains('scope_keywords')) {
      reasons.add('Similar scope keywords');
    }

    if (reasons.isEmpty) {
      return 'Similar estimate found in history';
    }

    return reasons.join(' • ');
  }

  static double _calculateIntentOverlapScore({
    required Set<String> promptIntentKeywords,
    required Set<String> estimateIntentKeywords,
  }) {
    if (promptIntentKeywords.isEmpty || estimateIntentKeywords.isEmpty) {
      return 0;
    }

    final overlap = promptIntentKeywords.intersection(estimateIntentKeywords);
    if (overlap.isEmpty) {
      return 0;
    }

    final ratio = overlap.length / promptIntentKeywords.length;

    if (ratio >= 0.60) return 0.18;
    if (ratio >= 0.40) return 0.12;
    if (ratio >= 0.25) return 0.08;
    return 0.04;
  }

  static double _calculateWordOverlapScore({
    required String normalizedPrompt,
    required String estimateText,
  }) {
    final promptWords = _meaningfulWords(normalizedPrompt);
    final estimateWords = _meaningfulWords(estimateText);

    if (promptWords.isEmpty || estimateWords.isEmpty) {
      return 0;
    }

    final overlap = promptWords.intersection(estimateWords);
    if (overlap.isEmpty) {
      return 0;
    }

    final ratio = overlap.length / promptWords.length;

    if (ratio >= 0.60) return 0.20;
    if (ratio >= 0.40) return 0.15;
    if (ratio >= 0.25) return 0.10;
    return 0.05;
  }

  static double _calculateRecencyScore(DateTime? createdAt) {
    if (createdAt == null) return 0;

    final now = DateTime.now();
    final difference = now.difference(createdAt).inDays;

    if (difference <= 30) return 0.08;
    if (difference <= 90) return 0.05;
    if (difference <= 180) return 0.03;
    return 0.01;
  }

  static Future<EstimatePriceRuleModel?> _loadMainRule(String? serviceType) async {
    final normalized = (serviceType ?? '').trim().toLowerCase();
    if (normalized.isEmpty) return null;

    try {
      return await EstimatePriceRulesService.findMainRule(normalized);
    } catch (_) {
      return null;
    }
  }

  static Set<String> _extractIntentKeywords({
    required String normalizedText,
    required EstimatePriceRuleModel? rule,
  }) {
    final result = <String>{};
    if (rule == null) return result;

    final candidates = <String>{
      ...rule.aiKeywords.map(_normalize),
      ...rule.aliases.map(_normalize),
      _normalize(rule.displayName ?? ''),
      _normalize(rule.serviceType),
    }.where((e) => e.isNotEmpty);

    for (final keyword in candidates) {
      if (keyword.contains(' ')) {
        if (normalizedText.contains(keyword)) {
          result.add(keyword);
        }
      } else {
        if (_containsWord(normalizedText, keyword)) {
          result.add(keyword);
        }
      }
    }

    return result;
  }

  static Set<String> _meaningfulWords(String value) {
    final words = value
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9\s]'), ' ')
        .split(RegExp(r'\s+'))
        .where((word) => word.trim().isNotEmpty)
        .where((word) => word.length >= 3)
        .where((word) => !_stopWords.contains(word))
        .toSet();

    return words;
  }

  static bool _containsWord(String source, String word) {
    return RegExp(r'\b' + RegExp.escape(word) + r'\b').hasMatch(source);
  }

  static String _normalize(String value) {
    return value
        .toLowerCase()
        .replaceAll('_', ' ')
        .replaceAll('-', ' ')
        .replaceAll(RegExp(r'[^a-z0-9\s]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  static const Set<String> _genericServiceWords = {
    'repair',
    'replacement',
    'replace',
    'installation',
    'install',
    'inspection',
    'diagnostic',
    'diagnostics',
    'troubleshooting',
    'service',
    'work',
    'general',
    'main',
    'minor',
  };

  static const Set<String> _stopWords = {
    'the',
    'and',
    'for',
    'with',
    'job',
    'work',
    'this',
    'that',
    'are',
    'was',
    'from',
    'into',
    'only',
    'need',
    'needs',
    'have',
    'has',
    'had',
    'your',
    'about',
    'will',
    'but',
    'not',
  };
}