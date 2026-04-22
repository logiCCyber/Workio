class AiHistorySuggestionModel {
  final String estimateId;
  final String title;
  final String? serviceType;
  final String sourceType;
  final String reason;
  final double score;
  final double total;
  final DateTime? createdAt;
  final bool isSameClient;
  final bool isSameProperty;
  final List<String> matchedFields;
  final String suggestedAction;

  const AiHistorySuggestionModel({
    required this.estimateId,
    required this.title,
    this.serviceType,
    required this.sourceType,
    required this.reason,
    required this.score,
    required this.total,
    this.createdAt,
    this.isSameClient = false,
    this.isSameProperty = false,
    this.matchedFields = const [],
    this.suggestedAction = 'use_as_baseline',
  });

  factory AiHistorySuggestionModel.fromMap(Map<String, dynamic> map) {
    return AiHistorySuggestionModel(
      estimateId: map['estimate_id']?.toString() ?? '',
      title: map['title']?.toString() ?? '',
      serviceType: map['service_type']?.toString(),
      sourceType: map['source_type']?.toString() ?? 'unknown',
      reason: map['reason']?.toString() ?? '',
      score: _toDouble(map['score']),
      total: _toDouble(map['total']),
      createdAt: map['created_at'] != null
          ? DateTime.tryParse(map['created_at'].toString())
          : null,
      isSameClient: _toBool(map['is_same_client']),
      isSameProperty: _toBool(map['is_same_property']),
      matchedFields: _toStringList(map['matched_fields']),
      suggestedAction:
      map['suggested_action']?.toString() ?? 'use_as_baseline',
    );
  }

  static double _toDouble(dynamic value) {
    if (value == null) return 0;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString()) ?? 0;
  }

  static bool _toBool(dynamic value) {
    if (value == null) return false;
    if (value is bool) return value;

    final normalized = value.toString().trim().toLowerCase();

    if (normalized == 'true' || normalized == '1' || normalized == 'yes') {
      return true;
    }

    if (normalized == 'false' || normalized == '0' || normalized == 'no') {
      return false;
    }

    return false;
  }

  static List<String> _toStringList(dynamic value) {
    if (value is List) {
      return value.map((item) => item.toString()).toList();
    }
    return const [];
  }

  bool get isStrongMatch => score >= 0.75;

  Map<String, dynamic> toMap() {
    return {
      'estimate_id': estimateId,
      'title': title,
      'service_type': serviceType,
      'source_type': sourceType,
      'reason': reason,
      'score': score,
      'total': total,
      'created_at': createdAt?.toIso8601String(),
      'is_same_client': isSameClient,
      'is_same_property': isSameProperty,
      'matched_fields': matchedFields,
      'suggested_action': suggestedAction,
    };
  }

  AiHistorySuggestionModel copyWith({
    String? estimateId,
    String? title,
    String? serviceType,
    String? sourceType,
    String? reason,
    double? score,
    double? total,
    DateTime? createdAt,
    bool? isSameClient,
    bool? isSameProperty,
    List<String>? matchedFields,
    String? suggestedAction,
  }) {
    return AiHistorySuggestionModel(
      estimateId: estimateId ?? this.estimateId,
      title: title ?? this.title,
      serviceType: serviceType ?? this.serviceType,
      sourceType: sourceType ?? this.sourceType,
      reason: reason ?? this.reason,
      score: score ?? this.score,
      total: total ?? this.total,
      createdAt: createdAt ?? this.createdAt,
      isSameClient: isSameClient ?? this.isSameClient,
      isSameProperty: isSameProperty ?? this.isSameProperty,
      matchedFields: matchedFields ?? this.matchedFields,
      suggestedAction: suggestedAction ?? this.suggestedAction,
    );
  }
}