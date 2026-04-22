import '../models/estimate_item_model.dart';
import '../utils/estimate_calculator.dart';

class AiEstimateDraft {
  final String title;
  final String scope;
  final String notes;
  final List<EstimateItemModel> items;

  const AiEstimateDraft({
    required this.title,
    required this.scope,
    required this.notes,
    required this.items,
  });
}

class EstimateAiService {
  EstimateAiService._();

  static AiEstimateDraft generateDraft({
    required String prompt,
    String? propertyCity,
  }) {
    final normalized = prompt.trim();
    final lower = normalized.toLowerCase();

    final serviceType = _detectServiceType(lower);
    final sqft = _extractSquareFootage(lower);
    final rooms = _extractRooms(lower);
    final coats = _extractCoats(lower);
    final materialsIncluded = _hasAny(lower, [
      'materials included',
      'material included',
      'материал включен',
      'материалы включены',
      'with materials',
    ]);
    final walls = _hasAny(lower, ['walls', 'стены']);
    final ceiling = _hasAny(lower, ['ceiling', 'ceilings', 'потолок', 'потолки']);
    final rush = _hasAny(lower, ['rush', 'urgent', 'срочно', 'urgent job']);
    final prep = _hasAny(lower, [
      'prep',
      'repair',
      'patch',
      'patching',
      'подготовка',
      'ремонт',
      'шпаклевка',
    ]);

    final citySuffix =
    (propertyCity ?? '').trim().isEmpty ? '' : ' • ${propertyCity!.trim()}';

    final title = '${_capitalize(serviceType)} Estimate$citySuffix';

    final items = _buildItems(
      serviceType: serviceType,
      sqft: sqft,
      rooms: rooms,
      coats: coats,
      materialsIncluded: materialsIncluded,
      walls: walls,
      ceiling: ceiling,
      rush: rush,
      prep: prep,
    );

    final scope = _buildScope(
      serviceType: serviceType,
      sqft: sqft,
      rooms: rooms,
      coats: coats,
      materialsIncluded: materialsIncluded,
      walls: walls,
      ceiling: ceiling,
      prep: prep,
      rush: rush,
    );

    final notes = _buildNotes(
      materialsIncluded: materialsIncluded,
      rush: rush,
      coats: coats,
      prep: prep,
    );

    return AiEstimateDraft(
      title: title,
      scope: scope,
      notes: notes,
      items: items,
    );
  }

  static String _detectServiceType(String text) {
    if (_hasAny(text, ['paint', 'painting', 'покраска', 'красить'])) {
      return 'painting';
    }

    if (_hasAny(text, ['drywall', 'гипсокартон'])) {
      return 'drywall';
    }

    if (_hasAny(text, ['cleaning', 'clean', 'уборка'])) {
      return 'cleaning';
    }

    if (_hasAny(text, ['floor', 'flooring', 'пол', 'наполь'])) {
      return 'flooring';
    }

    return 'general';
  }

  static bool _hasAny(String source, List<String> patterns) {
    for (final pattern in patterns) {
      if (source.contains(pattern)) return true;
    }
    return false;
  }

  static double _extractSquareFootage(String text) {
    final match = RegExp(r'(\d+(?:[.,]\d+)?)\s*(sqft|sf|square feet|square foot)')
        .firstMatch(text);

    if (match == null) return 0;

    final raw = match.group(1)?.replaceAll(',', '.') ?? '0';
    return double.tryParse(raw) ?? 0;
  }

  static int _extractRooms(String text) {
    final match = RegExp(r'(\d+)\s*(room|rooms|bedroom|bedrooms)')
        .firstMatch(text);

    if (match == null) return 0;

    return int.tryParse(match.group(1) ?? '0') ?? 0;
  }

  static int _extractCoats(String text) {
    final match = RegExp(r'(\d+)\s*(coat|coats)').firstMatch(text);

    if (match == null) return 2;

    final value = int.tryParse(match.group(1) ?? '2') ?? 2;
    return value <= 0 ? 2 : value;
  }

  static List<EstimateItemModel> _buildItems({
    required String serviceType,
    required double sqft,
    required int rooms,
    required int coats,
    required bool materialsIncluded,
    required bool walls,
    required bool ceiling,
    required bool rush,
    required bool prep,
  }) {
    switch (serviceType) {
      case 'painting':
        return _buildPaintingItems(
          sqft: sqft,
          rooms: rooms,
          coats: coats,
          materialsIncluded: materialsIncluded,
          walls: walls,
          ceiling: ceiling,
          rush: rush,
          prep: prep,
        );
      case 'drywall':
        return _buildDrywallItems(
          sqft: sqft,
          rooms: rooms,
          materialsIncluded: materialsIncluded,
          rush: rush,
          prep: prep,
        );
      case 'cleaning':
        return _buildCleaningItems(
          sqft: sqft,
          rooms: rooms,
          materialsIncluded: materialsIncluded,
          rush: rush,
        );
      case 'flooring':
        return _buildFlooringItems(
          sqft: sqft,
          rooms: rooms,
          materialsIncluded: materialsIncluded,
          rush: rush,
          prep: prep,
        );
      default:
        return _buildGeneralItems(
          sqft: sqft,
          rooms: rooms,
          materialsIncluded: materialsIncluded,
          rush: rush,
          prep: prep,
        );
    }
  }

  static List<EstimateItemModel> _buildPaintingItems({
    required double sqft,
    required int rooms,
    required int coats,
    required bool materialsIncluded,
    required bool walls,
    required bool ceiling,
    required bool rush,
    required bool prep,
  }) {
    final items = <EstimateItemModel>[];
    final effectiveSqft = sqft > 0 ? sqft : (rooms > 0 ? rooms * 250.0 : 500.0);

    final wallsOnly = walls || !ceiling;
    final wallRate = coats >= 2 ? 1.80 : 1.45;
    final ceilingRate = coats >= 2 ? 0.85 : 0.65;

    items.add(
      _item(
        title: wallsOnly ? 'Painting Walls' : 'Painting Walls',
        unit: 'sqft',
        quantity: effectiveSqft,
        unitPrice: wallRate,
      ),
    );

    if (ceiling) {
      items.add(
        _item(
          title: 'Painting Ceiling',
          unit: 'sqft',
          quantity: effectiveSqft,
          unitPrice: ceilingRate,
        ),
      );
    }

    if (prep) {
      items.add(
        _item(
          title: 'Surface Prep & Minor Repairs',
          unit: 'fixed',
          quantity: 1,
          unitPrice: 180,
        ),
      );
    }

    if (materialsIncluded) {
      items.add(
        _item(
          title: 'Materials',
          unit: 'fixed',
          quantity: 1,
          unitPrice: effectiveSqft * 0.22,
        ),
      );
    }

    if (rush) {
      items.add(
        _item(
          title: 'Rush Service',
          unit: 'fixed',
          quantity: 1,
          unitPrice: 175,
        ),
      );
    }

    return _normalizeItems(items);
  }

  static List<EstimateItemModel> _buildDrywallItems({
    required double sqft,
    required int rooms,
    required bool materialsIncluded,
    required bool rush,
    required bool prep,
  }) {
    final items = <EstimateItemModel>[];
    final effectiveSqft = sqft > 0 ? sqft : (rooms > 0 ? rooms * 200.0 : 400.0);

    items.add(
      _item(
        title: 'Drywall Repair / Installation',
        unit: 'sqft',
        quantity: effectiveSqft,
        unitPrice: 2.35,
      ),
    );

    if (prep) {
      items.add(
        _item(
          title: 'Sanding & Surface Prep',
          unit: 'fixed',
          quantity: 1,
          unitPrice: 140,
        ),
      );
    }

    if (materialsIncluded) {
      items.add(
        _item(
          title: 'Drywall Materials',
          unit: 'fixed',
          quantity: 1,
          unitPrice: effectiveSqft * 0.28,
        ),
      );
    }

    if (rush) {
      items.add(
        _item(
          title: 'Rush Service',
          unit: 'fixed',
          quantity: 1,
          unitPrice: 180,
        ),
      );
    }

    return _normalizeItems(items);
  }

  static List<EstimateItemModel> _buildCleaningItems({
    required double sqft,
    required int rooms,
    required bool materialsIncluded,
    required bool rush,
  }) {
    final items = <EstimateItemModel>[];
    final effectiveSqft = sqft > 0 ? sqft : (rooms > 0 ? rooms * 220.0 : 450.0);

    items.add(
      _item(
        title: 'Standard Cleaning',
        unit: 'sqft',
        quantity: effectiveSqft,
        unitPrice: 0.34,
      ),
    );

    if (materialsIncluded) {
      items.add(
        _item(
          title: 'Cleaning Supplies',
          unit: 'fixed',
          quantity: 1,
          unitPrice: 45,
        ),
      );
    }

    if (rush) {
      items.add(
        _item(
          title: 'Rush Service',
          unit: 'fixed',
          quantity: 1,
          unitPrice: 95,
        ),
      );
    }

    return _normalizeItems(items);
  }

  static List<EstimateItemModel> _buildFlooringItems({
    required double sqft,
    required int rooms,
    required bool materialsIncluded,
    required bool rush,
    required bool prep,
  }) {
    final items = <EstimateItemModel>[];
    final effectiveSqft = sqft > 0 ? sqft : (rooms > 0 ? rooms * 220.0 : 450.0);

    items.add(
      _item(
        title: 'Flooring Installation',
        unit: 'sqft',
        quantity: effectiveSqft,
        unitPrice: 2.95,
      ),
    );

    if (prep) {
      items.add(
        _item(
          title: 'Subfloor Prep',
          unit: 'fixed',
          quantity: 1,
          unitPrice: 160,
        ),
      );
    }

    if (materialsIncluded) {
      items.add(
        _item(
          title: 'Materials',
          unit: 'fixed',
          quantity: 1,
          unitPrice: effectiveSqft * 0.55,
        ),
      );
    }

    if (rush) {
      items.add(
        _item(
          title: 'Rush Service',
          unit: 'fixed',
          quantity: 1,
          unitPrice: 175,
        ),
      );
    }

    return _normalizeItems(items);
  }

  static List<EstimateItemModel> _buildGeneralItems({
    required double sqft,
    required int rooms,
    required bool materialsIncluded,
    required bool rush,
    required bool prep,
  }) {
    final items = <EstimateItemModel>[];
    final effectiveSqft = sqft > 0 ? sqft : (rooms > 0 ? rooms * 220.0 : 400.0);

    items.add(
      _item(
        title: 'General Labor',
        unit: 'sqft',
        quantity: effectiveSqft,
        unitPrice: 1.25,
      ),
    );

    if (prep) {
      items.add(
        _item(
          title: 'Prep Work',
          unit: 'fixed',
          quantity: 1,
          unitPrice: 120,
        ),
      );
    }

    if (materialsIncluded) {
      items.add(
        _item(
          title: 'Materials',
          unit: 'fixed',
          quantity: 1,
          unitPrice: 95,
        ),
      );
    }

    if (rush) {
      items.add(
        _item(
          title: 'Rush Service',
          unit: 'fixed',
          quantity: 1,
          unitPrice: 120,
        ),
      );
    }

    return _normalizeItems(items);
  }

  static String _buildScope({
    required String serviceType,
    required double sqft,
    required int rooms,
    required int coats,
    required bool materialsIncluded,
    required bool walls,
    required bool ceiling,
    required bool prep,
    required bool rush,
  }) {
    final details = <String>[];

    switch (serviceType) {
      case 'painting':
        details.add('Prepare and protect work areas before painting.');
        if (prep) {
          details.add('Complete minor patching and surface preparation as needed.');
        }
        if (walls || !ceiling) {
          details.add('Apply $coats coat${coats > 1 ? 's' : ''} of paint to walls.');
        }
        if (ceiling) {
          details.add('Apply $coats coat${coats > 1 ? 's' : ''} of paint to ceiling areas.');
        }
        break;
      case 'drywall':
        details.add('Prepare work area and complete drywall-related work as specified.');
        if (prep) {
          details.add('Include sanding and surface preparation where required.');
        }
        break;
      case 'cleaning':
        details.add('Complete detailed cleaning of all required areas.');
        break;
      case 'flooring':
        details.add('Prepare floor surfaces and complete flooring installation.');
        if (prep) {
          details.add('Include subfloor preparation where needed.');
        }
        break;
      default:
        details.add('Complete requested work as discussed.');
        break;
    }

    if (sqft > 0) {
      details.add('Estimated size: ${sqft.toStringAsFixed(0)} sqft.');
    } else if (rooms > 0) {
      details.add('Estimated project size based on $rooms room${rooms > 1 ? 's' : ''}.');
    }

    if (materialsIncluded) {
      details.add('Materials are included in this estimate.');
    }

    if (rush) {
      details.add('Rush scheduling is included.');
    }

    details.add('Final cleaning of the work area upon completion.');

    return details.join(' ');
  }

  static String _buildNotes({
    required bool materialsIncluded,
    required bool rush,
    required int coats,
    required bool prep,
  }) {
    final notes = <String>[
      'Final price may change if additional hidden repairs are discovered.',
      'Final color and material selections to be confirmed by client before work begins.',
    ];

    if (materialsIncluded) {
      notes.add('Materials are included in the current estimate.');
    } else {
      notes.add('Materials are not included unless specifically listed.');
    }

    if (coats > 0) {
      notes.add('Estimate is based on $coats coat${coats > 1 ? 's' : ''}.');
    }

    if (prep) {
      notes.add('Minor prep work is included where specified.');
    }

    if (rush) {
      notes.add('Rush timeline may affect scheduling availability.');
    }

    return notes.join(' ');
  }

  static EstimateItemModel _item({
    required String title,
    required String unit,
    required double quantity,
    required double unitPrice,
  }) {
    return EstimateItemModel(
      id: '',
      estimateId: '',
      title: title,
      description: null,
      unit: unit,
      quantity: quantity <= 0 ? 1 : quantity,
      unitPrice: unitPrice,
      lineTotal: EstimateCalculator.calculateLineTotal(
        quantity: quantity <= 0 ? 1 : quantity,
        unitPrice: unitPrice,
      ),
      sortOrder: 0,
      createdAt: null,
    );
  }

  static List<EstimateItemModel> _normalizeItems(List<EstimateItemModel> items) {
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

  static String _capitalize(String value) {
    if (value.isEmpty) return value;
    return value[0].toUpperCase() + value.substring(1);
  }
}