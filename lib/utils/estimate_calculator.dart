import '../models/estimate_item_model.dart';

class EstimateTotals {
  final double subtotal;
  final double tax;
  final double discount;
  final double total;

  const EstimateTotals({
    required this.subtotal,
    required this.tax,
    required this.discount,
    required this.total,
  });

  EstimateTotals copyWith({
    double? subtotal,
    double? tax,
    double? discount,
    double? total,
  }) {
    return EstimateTotals(
      subtotal: subtotal ?? this.subtotal,
      tax: tax ?? this.tax,
      discount: discount ?? this.discount,
      total: total ?? this.total,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'subtotal': subtotal,
      'tax': tax,
      'discount': discount,
      'total': total,
    };
  }
}

class EstimateCalculator {
  const EstimateCalculator._();

  static double roundMoney(double value) {
    return double.parse(value.toStringAsFixed(2));
  }

  static double parseNumber(dynamic value) {
    if (value == null) return 0;
    if (value is num) return value.toDouble();

    final cleaned = value
        .toString()
        .replaceAll(',', '.')
        .replaceAll(RegExp(r'[^0-9.\-]'), '');

    return double.tryParse(cleaned) ?? 0;
  }

  static double normalizePositive(double value) {
    if (value.isNaN || value.isInfinite) return 0;
    if (value < 0) return 0;
    return value;
  }

  static double calculateLineTotal({
    required double quantity,
    required double unitPrice,
  }) {
    final safeQuantity = normalizePositive(quantity);
    final safeUnitPrice = normalizePositive(unitPrice);

    return roundMoney(safeQuantity * safeUnitPrice);
  }

  static EstimateItemModel recalculateItem(EstimateItemModel item) {
    final lineTotal = calculateLineTotal(
      quantity: item.quantity,
      unitPrice: item.unitPrice,
    );

    return item.copyWith(lineTotal: lineTotal);
  }

  static List<EstimateItemModel> recalculateItems(List<EstimateItemModel> items) {
    return items.map(recalculateItem).toList();
  }

  static double calculateSubtotal(List<EstimateItemModel> items) {
    double sum = 0;

    for (final item in items) {
      final lineTotal = item.lineTotal > 0
          ? item.lineTotal
          : calculateLineTotal(
        quantity: item.quantity,
        unitPrice: item.unitPrice,
      );

      sum += lineTotal;
    }

    return roundMoney(sum);
  }

  static double calculateTax({
    required double subtotal,
    required double taxRate,
  }) {
    final safeSubtotal = normalizePositive(subtotal);
    final safeTaxRate = normalizePositive(taxRate);

    return roundMoney(safeSubtotal * safeTaxRate);
  }

  static double calculateDiscountAmount({
    required double subtotal,
    required double discountValue,
    bool isPercentage = false,
  }) {
    final safeSubtotal = normalizePositive(subtotal);
    final safeDiscountValue = normalizePositive(discountValue);

    if (safeSubtotal <= 0 || safeDiscountValue <= 0) {
      return 0;
    }

    if (isPercentage) {
      final percent = safeDiscountValue > 100 ? 100 : safeDiscountValue;
      return roundMoney(safeSubtotal * (percent / 100));
    }

    if (safeDiscountValue > safeSubtotal) {
      return roundMoney(safeSubtotal);
    }

    return roundMoney(safeDiscountValue);
  }

  static double calculateGrandTotal({
    required double subtotal,
    required double tax,
    required double discount,
  }) {
    final safeSubtotal = normalizePositive(subtotal);
    final safeTax = normalizePositive(tax);
    final safeDiscount = normalizePositive(discount);

    final result = safeSubtotal + safeTax - safeDiscount;
    return roundMoney(result < 0 ? 0 : result);
  }

  static EstimateTotals calculateTotals({
    required List<EstimateItemModel> items,
    double taxRate = 0,
    double discountValue = 0,
    bool discountIsPercentage = false,
  }) {
    final normalizedItems = recalculateItems(items);
    final subtotal = calculateSubtotal(normalizedItems);

    final discount = calculateDiscountAmount(
      subtotal: subtotal,
      discountValue: discountValue,
      isPercentage: discountIsPercentage,
    );

    final taxableBase = roundMoney(subtotal - discount);
    final tax = calculateTax(
      subtotal: taxableBase < 0 ? 0 : taxableBase,
      taxRate: taxRate,
    );

    final total = calculateGrandTotal(
      subtotal: subtotal,
      tax: tax,
      discount: discount,
    );

    return EstimateTotals(
      subtotal: subtotal,
      tax: tax,
      discount: discount,
      total: total,
    );
  }
}