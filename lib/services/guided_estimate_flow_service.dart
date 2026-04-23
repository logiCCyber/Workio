import '../models/estimate_price_rule_model.dart';

class GuidedEstimateFlowService {
  GuidedEstimateFlowService._();

  static String serviceLabel(EstimatePriceRuleModel? rule) {
    if (rule == null) return '';

    final displayName = (rule.displayName ?? '').trim();
    if (displayName.isNotEmpty) return displayName;

    return rule.serviceType.trim();
  }

  static String unit(EstimatePriceRuleModel? rule) {
    return (rule?.unit ?? '').trim().toLowerCase();
  }

  static bool isSizeBasedUnit(EstimatePriceRuleModel? rule) {
    final value = unit(rule);
    return value == 'sqft' || value == 'room';
  }

  static bool requiresQuantity(EstimatePriceRuleModel? rule) {
    final value = unit(rule);
    return value == 'item' || value == 'sqft' || value == 'room';
  }

  static String quantityLabel(EstimatePriceRuleModel? rule) {
    switch (unit(rule)) {
      case 'item':
        return 'Quantity';
      case 'sqft':
        return 'Square Footage';
      case 'room':
        return 'Rooms';
      default:
        return 'Size';
    }
  }

  static String quantityHint(EstimatePriceRuleModel? rule) {
    switch (unit(rule)) {
      case 'item':
        return '2';
      case 'sqft':
        return '1200';
      case 'room':
        return '3';
      default:
        return 'Enter value';
    }
  }

  static List<Map<String, dynamic>> followupQuestions(
      EstimatePriceRuleModel? rule,
      ) {
    if (rule == null || rule.aiFollowupQuestions.isEmpty) {
      return const [];
    }

    final currentUnit = unit(rule);
    final isNonSizeUnit =
        currentUnit == 'fixed' || currentUnit == 'item' || currentUnit == 'hour';

    final seen = <String>{};
    final result = <Map<String, dynamic>>[];

    for (final raw in rule.aiFollowupQuestions) {
      final item = Map<String, dynamic>.from(raw);

      final key = (item['key'] ?? '').toString().trim().toLowerCase();
      final question = (item['question'] ?? '').toString().trim();
      final answerType =
      (item['answerType'] ?? '').toString().trim().toLowerCase();

      if (key.isEmpty || question.isEmpty) continue;
      if (seen.contains(key)) continue;

      if (answerType != 'text' && answerType != 'single_select') {
        continue;
      }

      if (isNonSizeUnit &&
          RegExp(r'(project_size|sqft|rooms|quantity_rooms)')
              .hasMatch(key)) {
        continue;
      }

      seen.add(key);
      result.add(item);
    }

    return result;
  }

  static bool canGenerate({
    required EstimatePriceRuleModel? rule,
    required Map<String, dynamic> answers,
  }) {
    if (rule == null) return false;

    final requestedWork = (answers['requested_work'] ?? '').toString().trim();
    if (requestedWork.isEmpty) return false;

    final materialsMode = (answers['materials_mode'] ?? '').toString().trim();
    if (materialsMode.isEmpty) return false;

    if (materialsMode == 'detailed_list') {
      final materialsList = (answers['materials_list'] ?? '').toString().trim();
      if (materialsList.isEmpty) return false;
    }

    if (requiresQuantity(rule)) {
      final quantityValue = (answers['quantity_value'] ?? '').toString().trim();
      if (quantityValue.isEmpty) return false;
    }

    final questions = followupQuestions(rule);
    for (final question in questions) {
      final key = (question['key'] ?? '').toString().trim();
      final isRequired = question['isRequired'] == true;

      if (!isRequired || key.isEmpty) continue;

      final value = (answers[key] ?? '').toString().trim();
      if (value.isEmpty) return false;
    }

    return true;
  }

  static String buildPrompt({
    required EstimatePriceRuleModel? rule,
    required Map<String, dynamic> answers,
  }) {
    if (rule == null) return '';

    final parts = <String>[];
    parts.add(serviceLabel(rule));

    final requestedWork = (answers['requested_work'] ?? '').toString().trim();
    if (requestedWork.isNotEmpty) {
      parts.add(requestedWork);
    }

    final quantityValue = (answers['quantity_value'] ?? '').toString().trim();
    final currentUnit = unit(rule);

    if (quantityValue.isNotEmpty) {
      if (currentUnit == 'item') {
        parts.add('$quantityValue item${quantityValue == '1' ? '' : 's'}');
      } else if (currentUnit == 'sqft') {
        parts.add('$quantityValue sqft');
      } else if (currentUnit == 'room') {
        parts.add('$quantityValue room${quantityValue == '1' ? '' : 's'}');
      }
    }

    final materialsMode = (answers['materials_mode'] ?? '').toString().trim();

    switch (materialsMode) {
      case 'labor_only':
        parts.add('labor only');
        break;
      case 'materials_included':
        parts.add('materials included');
        break;
      case 'customer_provides':
        parts.add('customer provides materials');
        break;
      case 'after_inspection':
        parts.add('materials/parts after inspection');
        break;
      case 'detailed_list':
        parts.add('materials included');
        break;
    }

    final materialsList = (answers['materials_list'] ?? '').toString().trim();
    if (materialsMode == 'detailed_list' && materialsList.isNotEmpty) {
      parts.add(materialsList);
    }

    final questions = followupQuestions(rule);
    for (final question in questions) {
      final key = (question['key'] ?? '').toString().trim();
      if (key.isEmpty) continue;

      final value = (answers[key] ?? '').toString().trim();
      if (value.isEmpty) continue;

      parts.add(value);
    }

    return parts
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .join(', ');
  }
}