class AiMissingFieldModel {
  final String key;
  final String question;
  final bool isRequired;
  final String answerType;
  final List<String> options;
  final String? hint;

  const AiMissingFieldModel({
    required this.key,
    required this.question,
    this.isRequired = true,
    this.answerType = 'text',
    this.options = const [],
    this.hint,
  });

  factory AiMissingFieldModel.fromMap(Map<String, dynamic> map) {
    return AiMissingFieldModel(
      key: map['key']?.toString() ?? '',
      question: map['question']?.toString() ?? '',
      isRequired: _toBool(map['is_required'], fallback: true),
      answerType: map['answer_type']?.toString() ?? 'text',
      options: _toStringList(map['options']),
      hint: map['hint']?.toString(),
    );
  }

  static bool _toBool(dynamic value, {bool fallback = false}) {
    if (value == null) return fallback;
    if (value is bool) return value;

    final normalized = value.toString().trim().toLowerCase();

    if (normalized == 'true' || normalized == '1' || normalized == 'yes') {
      return true;
    }

    if (normalized == 'false' || normalized == '0' || normalized == 'no') {
      return false;
    }

    return fallback;
  }

  static List<String> _toStringList(dynamic value) {
    if (value is List) {
      return value.map((item) => item.toString()).toList();
    }
    return const [];
  }

  Map<String, dynamic> toMap() {
    return {
      'key': key,
      'question': question,
      'is_required': isRequired,
      'answer_type': answerType,
      'options': options,
      'hint': hint,
    };
  }

  AiMissingFieldModel copyWith({
    String? key,
    String? question,
    bool? isRequired,
    String? answerType,
    List<String>? options,
    String? hint,
  }) {
    return AiMissingFieldModel(
      key: key ?? this.key,
      question: question ?? this.question,
      isRequired: isRequired ?? this.isRequired,
      answerType: answerType ?? this.answerType,
      options: options ?? this.options,
      hint: hint ?? this.hint,
    );
  }
}