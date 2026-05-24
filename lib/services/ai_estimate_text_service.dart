import 'dart:async';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/ai_generated_text_model.dart';
import '../models/estimate_item_model.dart';
import '../models/estimate_price_rule_model.dart';

/// Ошибки разделены чтобы вызывающий слой мог реагировать по-разному.
sealed class AiEstimateTextException implements Exception {
  final String message;
  const AiEstimateTextException(this.message);
  @override
  String toString() => 'AiEstimateTextException: $message';
}

class AiTextNetworkException extends AiEstimateTextException {
  const AiTextNetworkException(super.message);
}

class AiTextParseException extends AiEstimateTextException {
  const AiTextParseException(super.message);
}

class AiEstimateTextService {
  AiEstimateTextService._();

  static const Duration _timeout = Duration(seconds: 45);

  /// Генерирует профессиональный текст estimate (scope, inclusions, exclusions, etc).
  ///
  /// При любой ошибке возвращает [AiGeneratedTextModel.empty] — вызывающий
  /// код сам решает, показать ли fallback или попросить повторить.
  static Future<AiGeneratedTextModel> generate({
    required List<EstimateItemModel> items,
    required EstimatePriceRuleModel? selectedRule,
    required String originalPrompt,
    required String intent,
    required bool hasRush,
    required String materialsMode,
    String? clientName,
    String? propertyAddress,
    String? propertyCity,
    List<String> historyHints = const [],
  }) async {
    if (items.isEmpty) {
      return AiGeneratedTextModel.empty();
    }

    final serviceLabel = (selectedRule?.displayName?.trim().isNotEmpty == true
        ? selectedRule!.displayName!.trim()
        : selectedRule?.serviceType.trim() ?? '')
        .trim();

    final tradeCategory = (selectedRule?.category ?? '').trim();

    final itemsPayload = items.map((item) {
      return {
        'title': item.title,
        'quantity': item.quantity,
        'unitPrice': item.unitPrice,
        'unit': item.unit,
        'description': item.description,
      };
    }).toList();

    try {
      final response = await Supabase.instance.client.functions
          .invoke(
        'generate-estimate-content-v2',
        body: {
          'items': itemsPayload,
          'serviceLabel': serviceLabel,
          'tradeCategory': tradeCategory,
          'intent': intent,
          'hasRush': hasRush,
          'materialsMode': materialsMode,
          'originalPrompt': originalPrompt,
          'clientName': (clientName ?? '').trim(),
          'propertyAddress': (propertyAddress ?? '').trim(),
          'propertyCity': (propertyCity ?? '').trim(),
          'historyHints': historyHints,
        },
      )
          .timeout(_timeout);

      final data = response.data;
      if (data is! Map) {
        throw const AiTextParseException('Response is not a map');
      }

      if (data['error'] != null) {
        throw AiTextNetworkException(data['error'].toString());
      }

      final raw = AiGeneratedTextModel.fromMap(
        Map<String, dynamic>.from(data),
      );

      return _postProcessAiText(raw);
    } on TimeoutException {
      throw const AiTextNetworkException(
        'generate-estimate-content-v2 timed out after 45s',
      );
    } on AiEstimateTextException {
      rethrow;
    } catch (e) {
      throw AiTextNetworkException('Failed to call edge function: $e');
    }
  }

  /// Safety net: чистит output AI от типичных ошибок которые иногда проскакивают
  /// несмотря на правила в промпте.
  static AiGeneratedTextModel _postProcessAiText(AiGeneratedTextModel raw) {
    return AiGeneratedTextModel(
      title: raw.title,
      scopeOfWork: _cleanProfessionalText(raw.scopeOfWork, title: raw.title),
      inclusions: raw.inclusions.map(_cleanProfessionalText).toList(),
      exclusions: raw.exclusions.map(_cleanProfessionalText).toList(),
      assumptions: raw.assumptions.map(_cleanProfessionalText).toList(),
      notes: _cleanProfessionalText(raw.notes, title: raw.title),
      terms: raw.terms,
      reasoning: raw.reasoning,
    );
  }

  static String _cleanProfessionalText(String input, {String? title}) {
    if (input.trim().isEmpty) return input;

    var text = input.trim();

    // 1. Удаляем дублированный title из начала текста
    if (title != null && title.trim().isNotEmpty) {
      final cleanTitle = title.trim();
      // Универсальный pattern: title + любой whitespace (включая \n, пробелы, переносы)
      final pattern = RegExp(
        '^' + RegExp.escape(cleanTitle) + r'\s+',
        caseSensitive: false,
      );
      text = text.replaceFirst(pattern, '');

// Также пробуем с точкой/двоеточием после title
      final patternWithPunct = RegExp(
        '^' + RegExp.escape(cleanTitle) + r'[.:]+\s*',
        caseSensitive: false,
      );
      text = text.replaceFirst(patternWithPunct, '');
    }

    // 2. Заменяем разговорные формы на формальные
    // 2. Заменяем разговорные формы на формальные
    final replacements = <RegExp, String>{
      // "We'll be doing X" → удаляем целиком (фраза должна пересобраться)
      RegExp(r"\bWe['\u2019]ll\s+be\s+\w+ing\s+", caseSensitive: false): '',

      // "We will / We'll / We're / We"
      RegExp(r"\bWe['\u2019]ll\s+", caseSensitive: false): '',
      RegExp(r"\bWe\s+will\s+", caseSensitive: false): '',
      RegExp(r"\bWe['\u2019]re\s+", caseSensitive: false): '',
      RegExp(r"\bWe\s+", caseSensitive: false): '',

      // "Our X" → "The X"
      RegExp(r"\bOur\s+focus\s+will\s+be\s+on\s+", caseSensitive: false):
      'Focus will be placed on ',
      RegExp(r"\bOur\s+team\s+will\s+", caseSensitive: false): '',
      RegExp(r"\bOur\s+", caseSensitive: false): 'The ',

      // "I will / I'll"
      RegExp(r"\bI['\u2019]ll\s+", caseSensitive: false): '',
      RegExp(r"\bI\s+will\s+", caseSensitive: false): '',

      // "Your" → "the"
      RegExp(r"\bof\s+your\s+", caseSensitive: false): ' of the ',
      RegExp(r"\bto\s+your\s+", caseSensitive: false): ' to the ',
      RegExp(r"\byour\s+new\s+", caseSensitive: false): 'the new ',
      RegExp(r"\byour\s+existing\s+", caseSensitive: false): 'the existing ',
      RegExp(r"\byour\s+", caseSensitive: false): 'the ',

      // "it's" → "the unit is"
      RegExp(r"\bit['\u2019]s\s+", caseSensitive: false): 'the unit is ',
    };

    for (final entry in replacements.entries) {
      text = text.replaceAll(entry.key, entry.value);
    }

    for (final entry in replacements.entries) {
      if (entry.value is String) {
        text = text.replaceAll(entry.key, entry.value as String);
      }
    }

    // 3. Чистим двойные пробелы / точки / запятые
    text = text
        .replaceAll(RegExp(r'\s{2,}'), ' ')
        .replaceAll(RegExp(r'\.\s*\.'), '.')
        .replaceAll(RegExp(r'\s+([.,;:])'), r'$1')
        .replaceAll(RegExp(r'^\s*[,.;:]\s*'), '')
        .trim();

    // 4. Капитализация первой буквы
    if (text.isNotEmpty) {
      text = text[0].toUpperCase() + text.substring(1);
    }

    return text;
  }
}

