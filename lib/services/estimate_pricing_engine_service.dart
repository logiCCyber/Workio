import '../models/ai_parsed_request_model.dart';
import '../models/estimate_item_model.dart';
import '../models/estimate_price_rule_model.dart';
import '../utils/estimate_calculator.dart';
import 'estimate_price_rules_service.dart';

class EstimatePricingEngineService {
  EstimatePricingEngineService._();

  static Future<List<EstimateItemModel>> buildItems(
      AiParsedRequestModel parsed,
      ) async {
    final serviceType = (parsed.serviceType ?? '').trim().toLowerCase();

    if (serviceType.isEmpty) return const [];

    if (serviceType == 'painting') {
      return await _buildPaintingItems(parsed);
    }

    return await _buildDynamicItems(parsed);
  }

  static Future<List<EstimateItemModel>> _buildDynamicItems(
      AiParsedRequestModel parsed,
      ) async {
    final serviceType = (parsed.serviceType ?? '').trim().toLowerCase();
    if (serviceType.isEmpty) return const [];

    final rule = await EstimatePriceRulesService.findMainRule(serviceType);
    if (rule == null) {
      return await _buildGeneralItems(parsed);
    }

    final items = <EstimateItemModel>[];
    final quantity = _resolveDynamicQuantity(parsed, rule.unit);
    final materialsIncluded = parsed.materialsIncluded == true;
    final rush = parsed.rush;
    final prep = parsed.prep;

    final serviceLabel = _serviceLabel(serviceType);

    final laborTitle = _pickText(
      rule.aiLaborTitle,
      '$serviceLabel Work',
    );
    final laborDescription = _pickText(
      rule.aiLaborDescription,
      'Labor for requested ${serviceLabel.toLowerCase()} work',
    );

    final materialsTitle = _pickText(
      rule.aiMaterialsTitle,
      '$serviceLabel Materials',
    );
    final materialsDescription = _pickText(
      rule.aiMaterialsDescription,
      'Materials and consumables',
    );

    final prepTitle = _pickText(
      rule.aiPrepTitle,
      'Prep Work',
    );
    final prepDescription = _pickText(
      rule.aiPrepDescription,
      'Preparation and setup before main work begins',
    );

    final rushTitle = _pickText(
      rule.aiRushTitle,
      'Rush Service',
    );
    final rushDescription = _pickText(
      rule.aiRushDescription,
      'Priority scheduling and rush handling',
    );

    items.add(
      _item(
        title: laborTitle,
        description: laborDescription,
        unit: rule.unit,
        quantity: quantity,
        unitPrice: rule.baseRate,
      ),
    );

    if (prep && (rule.prepFixedRate ?? 0) > 0) {
      items.add(
        _item(
          title: prepTitle,
          description: prepDescription,
          unit: 'fixed',
          quantity: 1,
          unitPrice: rule.prepFixedRate!,
        ),
      );
    }

    if (materialsIncluded) {
      if (parsed.parsedMaterials.isNotEmpty) {
        items.addAll(
          _buildParsedMaterialItems(
            parsedMaterials: parsed.parsedMaterials,
            fallbackTitle: materialsTitle,
            fallbackDescription: materialsDescription,
          ),
        );
      } else {
        final perSqftRate = rule.materialRatePerSqft ?? 0;
        final fixedRate = rule.materialFixedRate ?? 0;

        if (perSqftRate > 0 && rule.unit == 'sqft') {
          items.add(
            _item(
              title: materialsTitle,
              description: materialsDescription,
              unit: 'fixed',
              quantity: 1,
              unitPrice: quantity * perSqftRate,
            ),
          );
        } else if (fixedRate > 0) {
          items.add(
            _item(
              title: materialsTitle,
              description: materialsDescription,
              unit: 'fixed',
              quantity: 1,
              unitPrice: fixedRate,
            ),
          );
        }
      }
    }

    if (rush && (rule.rushFixedRate ?? 0) > 0) {
      items.add(
        _item(
          title: rushTitle,
          description: rushDescription,
          unit: 'fixed',
          quantity: 1,
          unitPrice: rule.rushFixedRate!,
        ),
      );
    }

    return _normalizeItems(items);
  }

  static String _pickText(String? value, String fallback) {
    final cleaned = value?.trim() ?? '';
    if (cleaned.isEmpty) return fallback;
    return cleaned;
  }

  static List<EstimateItemModel> _buildParsedMaterialItems({
    required List<Map<String, dynamic>> parsedMaterials,
    required String fallbackTitle,
    required String fallbackDescription,
  }) {
    final items = <EstimateItemModel>[];

    for (final material in parsedMaterials) {
      final rawName = (material['name'] ?? '').toString().trim();
      final quantity = _toPositiveDouble(material['quantity']) ?? 1;
      final unitPrice = _toPositiveDouble(material['unit_price']) ?? 0;
      final measureValue = _toPositiveDouble(material['measure_value']);
      final measureUnit = (material['measure_unit'] ?? '').toString().trim();
      final rawText = (material['raw_text'] ?? '').toString().trim();

      final title = rawName.isEmpty
          ? fallbackTitle
          : _toTitleCase(rawName);

      final description = _buildParsedMaterialDescription(
        rawName: rawName,
        measureValue: measureValue,
        measureUnit: measureUnit,
        rawText: rawText,
        fallbackDescription: fallbackDescription,
        hasUnitPrice: unitPrice > 0,
      );

      items.add(
        _item(
          title: title,
          description: description,
          unit: 'item',
          quantity: quantity,
          unitPrice: unitPrice,
        ),
      );
    }

    return items;
  }

  static String _buildParsedMaterialDescription({
    required String rawName,
    required double? measureValue,
    required String measureUnit,
    required String rawText,
    required String fallbackDescription,
    required bool hasUnitPrice,
  }) {
    final parts = <String>[];

    if (measureValue != null && measureValue > 0 && measureUnit.isNotEmpty) {
      final formattedValue = measureValue % 1 == 0
          ? measureValue.toStringAsFixed(0)
          : measureValue.toStringAsFixed(2);
      parts.add('Size: $formattedValue $measureUnit');
    }

    if (!hasUnitPrice) {
      parts.add('Price not specified in prompt');
    }

    if (parts.isEmpty && rawText.isNotEmpty) {
      parts.add('Parsed from prompt: $rawText');
    }

    if (parts.isEmpty) {
      return fallbackDescription;
    }

    return parts.join(' • ');
  }

  static double? _toPositiveDouble(dynamic value) {
    if (value == null) return null;
    if (value is num) {
      final result = value.toDouble();
      return result > 0 ? result : null;
    }

    final parsed = double.tryParse(value.toString().replaceAll(',', '.'));
    if (parsed == null || parsed <= 0) return null;
    return parsed;
  }

  static String _toTitleCase(String value) {
    return value
        .split(RegExp(r'\s+'))
        .where((part) => part.trim().isNotEmpty)
        .map(
          (part) => part[0].toUpperCase() + part.substring(1),
    )
        .join(' ');
  }

  static Future<List<EstimateItemModel>> _buildPaintingItems(
      AiParsedRequestModel parsed,
      ) async {
    final items = <EstimateItemModel>[];

    final wallsRule = await EstimatePriceRulesService.findPaintingWallsRule();
    final ceilingRule = await EstimatePriceRulesService.findPaintingCeilingRule();

    if (wallsRule == null && ceilingRule == null) {
      return const [];
    }

    final effectiveSqft = _resolvePaintingSqft(parsed);
    final coats = (parsed.coats ?? 2) <= 0 ? 2 : parsed.coats!;
    final materialsIncluded = parsed.materialsIncluded == true;
    final rush = parsed.rush;
    final prep = parsed.prep;

    final walls =
        parsed.walls == true || (parsed.walls == null && parsed.ceiling != true);
    final ceiling = parsed.ceiling == true;

    if (walls && wallsRule != null) {
      final wallRate = coats >= 2
          ? (wallsRule.multiCoatRate ?? wallsRule.baseRate)
          : (wallsRule.singleCoatRate ?? wallsRule.baseRate);

      items.add(
        _item(
          title: 'Painting Walls',
          description: 'Labor for wall painting',
          unit: wallsRule.unit,
          quantity: effectiveSqft,
          unitPrice: wallRate,
        ),
      );
    }

    if (ceiling && ceilingRule != null) {
      final ceilingRate = coats >= 2
          ? (ceilingRule.multiCoatRate ?? ceilingRule.baseRate)
          : (ceilingRule.singleCoatRate ?? ceilingRule.baseRate);

      items.add(
        _item(
          title: 'Painting Ceiling',
          description: 'Labor for ceiling painting',
          unit: ceilingRule.unit,
          quantity: effectiveSqft,
          unitPrice: ceilingRate,
        ),
      );
    }

    if (prep) {
      final prepPrice =
          wallsRule?.prepFixedRate ?? ceilingRule?.prepFixedRate ?? 0;

      if (prepPrice > 0) {
        items.add(
          _item(
            title: 'Surface Prep & Minor Repairs',
            description: 'Basic patching, sanding, and surface preparation',
            unit: 'fixed',
            quantity: 1,
            unitPrice: prepPrice,
          ),
        );
      }
    }

    if (materialsIncluded) {
      if (parsed.parsedMaterials.isNotEmpty) {
        items.addAll(
          _buildParsedMaterialItems(
            parsedMaterials: parsed.parsedMaterials,
            fallbackTitle: 'Painting Materials',
            fallbackDescription: 'Paint, tape, masking, and basic consumables',
          ),
        );
      } else {
        final materialRate =
            wallsRule?.materialRatePerSqft ??
                ceilingRule?.materialRatePerSqft ??
                0;

        if (materialRate > 0) {
          items.add(
            _item(
              title: 'Painting Materials',
              description: 'Paint, tape, masking, and basic consumables',
              unit: 'fixed',
              quantity: 1,
              unitPrice: effectiveSqft * materialRate,
            ),
          );
        }
      }
    }

    if (rush) {
      final rushPrice =
          wallsRule?.rushFixedRate ?? ceilingRule?.rushFixedRate ?? 0;

      if (rushPrice > 0) {
        items.add(
          _item(
            title: 'Rush Service',
            description: 'Priority scheduling and rush handling',
            unit: 'fixed',
            quantity: 1,
            unitPrice: rushPrice,
          ),
        );
      }
    }

    return _normalizeItems(items);
  }



  static double _resolveDynamicQuantity(
      AiParsedRequestModel parsed,
      String unit,
      ) {
    final normalizedUnit = unit.trim().toLowerCase();

    if (normalizedUnit == 'sqft') {
      if ((parsed.sqft ?? 0) > 0) return parsed.sqft!;
      if ((parsed.rooms ?? 0) > 0) return parsed.rooms! * 220.0;
      return 400.0;
    }

    if (normalizedUnit == 'room') {
      if ((parsed.rooms ?? 0) > 0) return parsed.rooms!.toDouble();
      if ((parsed.sqft ?? 0) > 0) return 1;
      return 1;
    }

    if (normalizedUnit == 'item') {
      return 1;
    }

    if (normalizedUnit == 'hour') {
      if ((parsed.hours ?? 0) > 0) return parsed.hours!;
      return 1;
    }

    return 1;
  }

  static String _serviceLabel(String serviceType) {
    return serviceType
        .trim()
        .split(RegExp(r'[_\-\s]+'))
        .where((e) => e.isNotEmpty)
        .map((part) => part[0].toUpperCase() + part.substring(1))
        .join(' ');
  }

  static Future<List<EstimateItemModel>> _buildGeneralItems(
      AiParsedRequestModel parsed,
      ) async {
    final rule = await EstimatePriceRulesService.findMainRule('general');
    if (rule == null) return const [];

    final items = <EstimateItemModel>[];

    final effectiveSqft = _resolveGeneralSqft(parsed);
    final materialsIncluded = parsed.materialsIncluded == true;
    final rush = parsed.rush;
    final prep = parsed.prep;

    items.add(
      _item(
        title: 'General Labor',
        description: 'General labor for requested work',
        unit: rule.unit,
        quantity: effectiveSqft,
        unitPrice: rule.baseRate,
      ),
    );

    if (prep && (rule.prepFixedRate ?? 0) > 0) {
      items.add(
        _item(
          title: 'Prep Work',
          description: 'Preparation and setup before main work',
          unit: 'fixed',
          quantity: 1,
          unitPrice: rule.prepFixedRate!,
        ),
      );
    }

    if (materialsIncluded && (rule.materialFixedRate ?? 0) > 0) {
      items.add(
        _item(
          title: 'Materials',
          description: 'General materials and consumables',
          unit: 'fixed',
          quantity: 1,
          unitPrice: rule.materialFixedRate!,
        ),
      );
    }

    if (rush && (rule.rushFixedRate ?? 0) > 0) {
      items.add(
        _item(
          title: 'Rush Service',
          description: 'Priority scheduling and rush handling',
          unit: 'fixed',
          quantity: 1,
          unitPrice: rule.rushFixedRate!,
        ),
      );
    }

    return _normalizeItems(items);
  }

  static double _resolvePaintingSqft(AiParsedRequestModel parsed) {
    if ((parsed.sqft ?? 0) > 0) {
      return parsed.sqft!;
    }

    if ((parsed.rooms ?? 0) > 0) {
      return parsed.rooms! * 250.0;
    }

    return 500.0;
  }

  static double _resolveGeneralSqft(AiParsedRequestModel parsed) {
    if ((parsed.sqft ?? 0) > 0) {
      return parsed.sqft!;
    }

    if ((parsed.rooms ?? 0) > 0) {
      return parsed.rooms! * 220.0;
    }

    return 400.0;
  }

  static EstimateItemModel _item({
    required String title,
    String? description,
    required String unit,
    required double quantity,
    required double unitPrice,
  }) {
    final safeQuantity = quantity <= 0 ? 1.0 : quantity;
    final safeUnitPrice = unitPrice < 0 ? 0.0 : unitPrice;

    return EstimateItemModel(
      id: '',
      estimateId: '',
      title: title,
      description: description,
      unit: unit,
      quantity: safeQuantity,
      unitPrice: double.parse(safeUnitPrice.toStringAsFixed(2)),
      lineTotal: EstimateCalculator.calculateLineTotal(
        quantity: safeQuantity,
        unitPrice: safeUnitPrice,
      ),
      sortOrder: 0,
      createdAt: null,
    );
  }

  static List<EstimateItemModel> _normalizeItems(
      List<EstimateItemModel> items,
      ) {
    return items.asMap().entries.map((entry) {
      final index = entry.key;
      final item = entry.value;

      return item.copyWith(
        sortOrder: index,
        lineTotal: EstimateCalculator.calculateLineTotal(
          quantity: item.quantity,
          unitPrice: item.unitPrice,
        ),
      );
    }).toList();
  }
}

