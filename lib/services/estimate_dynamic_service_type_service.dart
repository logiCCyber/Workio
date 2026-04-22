import '../models/ai_parsed_request_model.dart';
import '../models/estimate_price_rule_model.dart';
import 'estimate_price_rules_service.dart';

class EstimateDynamicServiceTypeService {
  EstimateDynamicServiceTypeService._();

  static const Set<String> _builtInServiceTypes = {
    'painting',
    'drywall',
    'cleaning',
    'flooring',
    'general',
  };

  static const Set<String> _stopWords = {
    'and',
    'for',
    'the',
    'with',
    'main',
    'job',
    'work',
    'service',
    'repair',
    'issue',
    'problem',
    'help',
    'need',
  };

  static Future<AiParsedRequestModel> apply(
      AiParsedRequestModel parsed,
      ) async {
    final rules = await EstimatePriceRulesService.getRules();

    if (rules.isEmpty) {
      return parsed;
    }

    final detected = _detectFromRules(
      normalizedPrompt: parsed.normalizedPrompt,
      rules: rules,
    );

    if ((detected ?? '').trim().isEmpty) {
      return parsed;
    }

    final current = (parsed.serviceType ?? '').trim().toLowerCase();

    final shouldOverride = current.isEmpty ||
        current == 'general' ||
        !_builtInServiceTypes.contains(current);

    if (!shouldOverride && current == detected) {
      return parsed;
    }

    if (!shouldOverride) {
      return parsed;
    }

    return parsed.copyWith(
      serviceType: detected,
    );
  }

  static String? _detectFromRules({
    required String normalizedPrompt,
    required List<EstimatePriceRuleModel> rules,
  }) {
    final prompt = _normalizeText(normalizedPrompt);
    if (prompt.isEmpty) return null;

    final Map<String, double> scores = {};

    for (final rule in rules) {
      final serviceType = _normalizeText(rule.serviceType);
      if (serviceType.isEmpty) continue;

      double score = 0;

      final phrases = <String>{
        serviceType,
        _normalizeText(rule.displayName ?? ''),
        _normalizeText(rule.category),
        ...rule.aliases.map(_normalizeText),
        ...rule.aiKeywords.map(_normalizeText),
      }.where((e) => e.isNotEmpty).toList();

      for (final phrase in phrases) {
        score += _scorePhraseAgainstPrompt(
          prompt: prompt,
          phrase: phrase,
          isCategory: phrase == _normalizeText(rule.category),
        );
      }

      if (score <= 0) continue;

      scores[serviceType] = (scores[serviceType] ?? 0) + score;
    }

    if (scores.isEmpty) return null;

    final sorted = scores.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    final best = sorted.first;
    final second = sorted.length > 1 ? sorted[1].value : 0.0;

    if (best.value >= 1.35 && best.value >= second + 0.20) {
      return best.key;
    }

    return null;
  }

  static double _scorePhraseAgainstPrompt({
    required String prompt,
    required String phrase,
    required bool isCategory,
  }) {
    if (phrase.isEmpty) return 0;

    double score = 0;

    if (prompt.contains(phrase)) {
      if (isCategory && phrase == 'main') {
        score += 0;
      } else if (phrase.contains(' ')) {
        score += isCategory ? 1.6 : 3.6;
      } else {
        score += isCategory ? 0.8 : 2.4;
      }
    }

    final phraseTokens = _meaningfulTokens(phrase);
    if (phraseTokens.isEmpty) return score;

    for (final token in phraseTokens) {
      if (_containsWord(prompt, token)) {
        score += isCategory ? 0.35 : 0.75;
      } else {
        final similarity = _bestTokenSimilarity(token, _meaningfulTokens(prompt));
        if (similarity >= 0.90) {
          score += isCategory ? 0.22 : 0.55;
        } else if (similarity >= 0.84) {
          score += isCategory ? 0.10 : 0.28;
        }
      }
    }

    return score;
  }

  static double _bestTokenSimilarity(String token, List<String> promptTokens) {
    double best = 0;

    for (final promptToken in promptTokens) {
      final score = _tokenSimilarity(token, promptToken);
      if (score > best) best = score;
    }

    return best;
  }

  static double _tokenSimilarity(String a, String b) {
    if (a == b) return 1.0;
    if (a.isEmpty || b.isEmpty) return 0;

    final maxLen = a.length > b.length ? a.length : b.length;
    final distance = _levenshtein(a, b);

    if (distance == 1) return 0.92;
    if (distance == 2 && maxLen >= 7) return 0.86;

    return 1 - (distance / maxLen);
  }

  static int _levenshtein(String a, String b) {
    final aLen = a.length;
    final bLen = b.length;

    if (aLen == 0) return bLen;
    if (bLen == 0) return aLen;

    final matrix = List.generate(
      aLen + 1,
          (_) => List<int>.filled(bLen + 1, 0),
    );

    for (int i = 0; i <= aLen; i++) {
      matrix[i][0] = i;
    }

    for (int j = 0; j <= bLen; j++) {
      matrix[0][j] = j;
    }

    for (int i = 1; i <= aLen; i++) {
      for (int j = 1; j <= bLen; j++) {
        final cost = a[i - 1] == b[j - 1] ? 0 : 1;

        final deletion = matrix[i - 1][j] + 1;
        final insertion = matrix[i][j - 1] + 1;
        final substitution = matrix[i - 1][j - 1] + cost;

        int value = deletion < insertion ? deletion : insertion;
        if (substitution < value) value = substitution;

        matrix[i][j] = value;
      }
    }

    return matrix[aLen][bLen];
  }

  static String _normalizeText(String value) {
    return value
        .trim()
        .toLowerCase()
        .replaceAll('_', ' ')
        .replaceAll('-', ' ')
        .replaceAll(RegExp(r'[^a-z0-9\s]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  static List<String> _meaningfulTokens(String value) {
    return _normalizeText(value)
        .split(' ')
        .map((part) => part.trim())
        .where((part) => part.isNotEmpty)
        .where((part) => part.length >= 3)
        .where((part) => !_stopWords.contains(part))
        .toList();
  }

  static bool _containsWord(String source, String word) {
    return RegExp(r'\b' + RegExp.escape(word) + r'\b').hasMatch(source);
  }
}