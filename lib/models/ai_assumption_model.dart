class AiAssumptionModel {
  final String key;
  final String label;
  final String value;
  final String? reason;

  const AiAssumptionModel({
    required this.key,
    required this.label,
    required this.value,
    this.reason,
  });

  factory AiAssumptionModel.fromMap(Map<String, dynamic> map) {
    return AiAssumptionModel(
      key: map['key']?.toString() ?? '',
      label: map['label']?.toString() ?? '',
      value: map['value']?.toString() ?? '',
      reason: map['reason']?.toString(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'key': key,
      'label': label,
      'value': value,
      'reason': reason,
    };
  }

  AiAssumptionModel copyWith({
    String? key,
    String? label,
    String? value,
    String? reason,
  }) {
    return AiAssumptionModel(
      key: key ?? this.key,
      label: label ?? this.label,
      value: value ?? this.value,
      reason: reason ?? this.reason,
    );
  }
}