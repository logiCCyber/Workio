import 'package:supabase_flutter/supabase_flutter.dart';

class EstimateRuleResolverResult {
  final String? selectedRuleId;
  final double confidence;
  final String normalizedRequestedWork;
  final bool shouldAskClarifyingQuestion;
  final String clarifyingQuestion;
  final List<String> suppressQuestionKeys;
  final String reasoningSummary;

  const EstimateRuleResolverResult({
    required this.selectedRuleId,
    required this.confidence,
    required this.normalizedRequestedWork,
    required this.shouldAskClarifyingQuestion,
    required this.clarifyingQuestion,
    required this.suppressQuestionKeys,
    required this.reasoningSummary,
  });

  factory EstimateRuleResolverResult.fromMap(Map<String, dynamic> map) {
    return EstimateRuleResolverResult(
      selectedRuleId: (map['selectedRuleId'] ?? '').toString().trim().isEmpty
          ? null
          : map['selectedRuleId'].toString().trim(),
      confidence: ((map['confidence'] ?? 0) as num).toDouble(),
      normalizedRequestedWork:
      (map['normalizedRequestedWork'] ?? '').toString().trim(),
      shouldAskClarifyingQuestion:
      map['shouldAskClarifyingQuestion'] == true,
      clarifyingQuestion: (map['clarifyingQuestion'] ?? '').toString().trim(),
      suppressQuestionKeys: (map['suppressQuestionKeys'] is List)
          ? (map['suppressQuestionKeys'] as List)
          .map((e) => e.toString().trim())
          .where((e) => e.isNotEmpty)
          .toList()
          : const [],
      reasoningSummary: (map['reasoningSummary'] ?? '').toString().trim(),
    );
  }
}

class EstimateRuleResolutionService {
  EstimateRuleResolutionService._();

  static Future<EstimateRuleResolverResult> resolve({
    required String prompt,
    required Map<String, dynamic> guidedAnswers,
    required List<Map<String, dynamic>> candidates,
  }) async {
    final response = await Supabase.instance.client.functions.invoke(
      'resolve-estimate-rule',
      body: {
        'prompt': prompt,
        'guidedAnswers': guidedAnswers,
        'candidates': candidates,
      },
    );

    final data = response.data;
    if (data is! Map<String, dynamic>) {
      throw Exception('Invalid resolve-estimate-rule response');
    }

    return EstimateRuleResolverResult.fromMap(data);
  }
}