import 'ai_assumption_model.dart';
import 'ai_history_context_model.dart';
import 'ai_missing_field_model.dart';
import 'ai_parsed_request_model.dart';
import 'estimate_item_model.dart';

class AiEstimateResultModel {
  final String? title;
  final String? scope;
  final String? notes;
  final List<EstimateItemModel> items;

  final AiParsedRequestModel parsedRequest;
  final AiHistoryContextModel? historyContext;

  final List<AiAssumptionModel> assumptions;
  final List<AiMissingFieldModel> missingFields;

  final double confidence;

  const AiEstimateResultModel({
    this.title,
    this.scope,
    this.notes,
    this.items = const [],
    required this.parsedRequest,
    this.historyContext,
    this.assumptions = const [],
    this.missingFields = const [],
    this.confidence = 0,
  });

  factory AiEstimateResultModel.fromMap(Map<String, dynamic> map) {
    return AiEstimateResultModel(
      title: map['title']?.toString(),
      scope: map['scope']?.toString(),
      notes: map['notes']?.toString(),
      items: _toEstimateItems(map['items']),
      parsedRequest: AiParsedRequestModel.fromMap(
        Map<String, dynamic>.from(
          map['parsed_request'] as Map? ?? const {},
        ),
      ),
      historyContext: map['history_context'] != null
          ? AiHistoryContextModel.fromMap(
        Map<String, dynamic>.from(map['history_context'] as Map),
      )
          : null,
      assumptions: _toAssumptions(map['assumptions']),
      missingFields: _toMissingFields(map['missing_fields']),
      confidence: _toDouble(map['confidence']),
    );
  }

  static double _toDouble(dynamic value) {
    if (value == null) return 0;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString()) ?? 0;
  }

  static List<EstimateItemModel> _toEstimateItems(dynamic value) {
    if (value is! List) return const [];

    return value
        .whereType<Map>()
        .map((item) => EstimateItemModel.fromMap(
      Map<String, dynamic>.from(item),
    ))
        .toList();
  }

  static List<AiMissingFieldModel> _toMissingFields(dynamic value) {
    if (value is! List) return const [];

    return value
        .whereType<Map>()
        .map((item) => AiMissingFieldModel.fromMap(
      Map<String, dynamic>.from(item),
    ))
        .toList();
  }

  static List<AiAssumptionModel> _toAssumptions(dynamic value) {
    if (value is! List) return const [];

    return value
        .whereType<Map>()
        .map((item) => AiAssumptionModel.fromMap(
      Map<String, dynamic>.from(item),
    ))
        .toList();
  }

  bool get hasDraftContent {
    return (title ?? '').trim().isNotEmpty ||
        (scope ?? '').trim().isNotEmpty ||
        (notes ?? '').trim().isNotEmpty ||
        items.isNotEmpty;
  }

  bool get canAutoGenerate {
    return !missingFields.any((field) => field.isRequired);
  }

  Map<String, dynamic> toMap() {
    return {
      'title': title,
      'scope': scope,
      'notes': notes,
      'items': items.map((item) => item.toMap()).toList(),
      'parsed_request': parsedRequest.toMap(),
      'history_context': historyContext?.toMap(),
      'assumptions': assumptions.map((item) => item.toMap()).toList(),
      'missing_fields': missingFields.map((item) => item.toMap()).toList(),
      'confidence': confidence,
    };
  }

  AiEstimateResultModel copyWith({
    String? title,
    String? scope,
    String? notes,
    List<EstimateItemModel>? items,
    AiParsedRequestModel? parsedRequest,
    AiHistoryContextModel? historyContext,
    List<AiAssumptionModel>? assumptions,
    List<AiMissingFieldModel>? missingFields,
    double? confidence,
  }) {
    return AiEstimateResultModel(
      title: title ?? this.title,
      scope: scope ?? this.scope,
      notes: notes ?? this.notes,
      items: items ?? this.items,
      parsedRequest: parsedRequest ?? this.parsedRequest,
      historyContext: historyContext ?? this.historyContext,
      assumptions: assumptions ?? this.assumptions,
      missingFields: missingFields ?? this.missingFields,
      confidence: confidence ?? this.confidence,
    );
  }
}