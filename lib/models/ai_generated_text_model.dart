class AiGeneratedTextModel {
  final String title;
  final String scopeOfWork;
  final List<String> inclusions;
  final List<String> exclusions;
  final List<String> assumptions;
  final String notes;
  final String terms;
  final String reasoning;

  const AiGeneratedTextModel({
    required this.title,
    required this.scopeOfWork,
    required this.inclusions,
    required this.exclusions,
    required this.assumptions,
    required this.notes,
    required this.terms,
    required this.reasoning,
  });

  factory AiGeneratedTextModel.empty() {
    return const AiGeneratedTextModel(
      title: '',
      scopeOfWork: '',
      inclusions: [],
      exclusions: [],
      assumptions: [],
      notes: '',
      terms: '',
      reasoning: '',
    );
  }

  factory AiGeneratedTextModel.fromMap(Map<String, dynamic> map) {
    return AiGeneratedTextModel(
      title: (map['title'] ?? '').toString().trim(),
      scopeOfWork: (map['scopeOfWork'] ?? '').toString().trim(),
      inclusions: _stringList(map['inclusions']),
      exclusions: _stringList(map['exclusions']),
      assumptions: _stringList(map['assumptions']),
      notes: (map['notes'] ?? '').toString().trim(),
      terms: (map['terms'] ?? '').toString().trim(),
      reasoning: (map['reasoning'] ?? '').toString().trim(),
    );
  }

  bool get isEmpty =>
      title.isEmpty &&
          scopeOfWork.isEmpty &&
          inclusions.isEmpty &&
          exclusions.isEmpty &&
          assumptions.isEmpty &&
          notes.isEmpty;

  static List<String> _stringList(dynamic value) {
    if (value is! List) return const [];
    final result = <String>[];
    final seen = <String>{};
    for (final item in value) {
      final text = item?.toString().trim() ?? '';
      if (text.isEmpty) continue;
      final key = text.toLowerCase();
      if (seen.contains(key)) continue;
      seen.add(key);
      result.add(text);
    }
    return result;
  }

  Map<String, dynamic> toMap() {
    return {
      'title': title,
      'scopeOfWork': scopeOfWork,
      'inclusions': inclusions,
      'exclusions': exclusions,
      'assumptions': assumptions,
      'notes': notes,
      'terms': terms,
      'reasoning': reasoning,
    };
  }
}