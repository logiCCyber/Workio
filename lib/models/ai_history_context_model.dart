import 'ai_history_suggestion_model.dart';

class AiHistoryContextModel {
  final String rawPrompt;
  final String normalizedPrompt;
  final String? clientId;
  final String? propertyId;
  final String? detectedServiceType;
  final List<AiHistorySuggestionModel> suggestions;

  const AiHistoryContextModel({
    required this.rawPrompt,
    required this.normalizedPrompt,
    this.clientId,
    this.propertyId,
    this.detectedServiceType,
    this.suggestions = const [],
  });

  factory AiHistoryContextModel.fromMap(Map<String, dynamic> map) {
    return AiHistoryContextModel(
      rawPrompt: map['raw_prompt']?.toString() ?? '',
      normalizedPrompt: map['normalized_prompt']?.toString() ?? '',
      clientId: map['client_id']?.toString(),
      propertyId: map['property_id']?.toString(),
      detectedServiceType: map['detected_service_type']?.toString(),
      suggestions: _toSuggestions(map['suggestions']),
    );
  }

  static List<AiHistorySuggestionModel> _toSuggestions(dynamic value) {
    if (value is! List) return const [];

    return value
        .whereType<Map>()
        .map(
          (item) => AiHistorySuggestionModel.fromMap(
        Map<String, dynamic>.from(item),
      ),
    )
        .toList();
  }

  AiHistorySuggestionModel? get bestSuggestion {
    if (suggestions.isEmpty) return null;

    final sorted = [...suggestions]
      ..sort((a, b) => b.score.compareTo(a.score));

    return sorted.first;
  }

  bool get hasSuggestions => suggestions.isNotEmpty;

  bool get hasStrongSuggestion {
    final best = bestSuggestion;
    if (best == null) return false;
    return best.score >= 0.75;
  }

  double? get lastSimilarPrice {
    final best = bestSuggestion;
    if (best == null || best.total <= 0) return null;
    return best.total;
  }

  String? get priceHint {
    final usable = suggestions
        .where((item) => item.score >= 0.40 && item.total > 0)
        .toList();

    if (usable.isEmpty) return null;

    final sorted = [...usable]..sort((a, b) => b.score.compareTo(a.score));
    final top = sorted.take(3).toList();

    if (top.length == 1) {
      return 'Earlier similar work was around \$${top.first.total.toStringAsFixed(0)}';
    }

    final totals = top.map((e) => e.total).toList()..sort();

    final low = totals.first;
    final high = totals.last;

    if ((high - low).abs() < 1) {
      return 'Earlier similar work was around \$${high.toStringAsFixed(0)}';
    }

    return 'Earlier similar work was usually \$${low.toStringAsFixed(0)}–\$${high.toStringAsFixed(0)}';
  }

  Map<String, dynamic> toMap() {
    return {
      'raw_prompt': rawPrompt,
      'normalized_prompt': normalizedPrompt,
      'client_id': clientId,
      'property_id': propertyId,
      'detected_service_type': detectedServiceType,
      'suggestions': suggestions.map((item) => item.toMap()).toList(),
    };
  }

  AiHistoryContextModel copyWith({
    String? rawPrompt,
    String? normalizedPrompt,
    String? clientId,
    String? propertyId,
    String? detectedServiceType,
    List<AiHistorySuggestionModel>? suggestions,
  }) {
    return AiHistoryContextModel(
      rawPrompt: rawPrompt ?? this.rawPrompt,
      normalizedPrompt: normalizedPrompt ?? this.normalizedPrompt,
      clientId: clientId ?? this.clientId,
      propertyId: propertyId ?? this.propertyId,
      detectedServiceType: detectedServiceType ?? this.detectedServiceType,
      suggestions: suggestions ?? this.suggestions,
    );
  }
}