import 'package:intl/intl.dart';

class EstimateFormatters {
  EstimateFormatters._();

  static final NumberFormat _currencyFormatter = NumberFormat.currency(
    locale: 'en_CA',
    symbol: '\$',
    decimalDigits: 2,
  );

  static final DateFormat _dateFormatter = DateFormat('MMM d, yyyy');
  static final DateFormat _shortDateFormatter = DateFormat('MMM d');
  static final DateFormat _fullDateTimeFormatter = DateFormat('MMM d, yyyy • h:mm a');

  static String formatCurrency(num? value) {
    final safeValue = (value ?? 0).toDouble();
    return _currencyFormatter.format(safeValue);
  }

  static String formatNumber(num? value, {int decimalDigits = 2}) {
    final safeValue = (value ?? 0).toDouble();
    return safeValue.toStringAsFixed(decimalDigits);
  }

  static String formatQuantity(num? value) {
    final safeValue = (value ?? 0).toDouble();

    if (safeValue == safeValue.truncateToDouble()) {
      return safeValue.toInt().toString();
    }

    return safeValue.toStringAsFixed(2);
  }

  static String formatDate(DateTime? date) {
    if (date == null) return '—';
    return _dateFormatter.format(date);
  }

  static String formatShortDate(DateTime? date) {
    if (date == null) return '—';
    return _shortDateFormatter.format(date);
  }

  static String formatDateTime(DateTime? date) {
    if (date == null) return '—';
    return _fullDateTimeFormatter.format(date);
  }

  static String formatStatus(String? status) {
    switch ((status ?? '').toLowerCase().trim()) {
      case 'draft':
        return 'Draft';
      case 'sent':
        return 'Sent';
      case 'approved':
        return 'Approved';
      case 'rejected':
        return 'Rejected';
      case 'archived':
        return 'Archived';
      default:
        return 'Unknown';
    }
  }

  static String formatUnit(String? unit) {
    switch ((unit ?? '').toLowerCase().trim()) {
      case 'sqft':
        return 'sqft';
      case 'room':
        return 'room';
      case 'wall':
        return 'wall';
      case 'hour':
        return 'hour';
      case 'fixed':
        return 'fixed';
      case 'item':
        return 'item';
      case 'day':
        return 'day';
      default:
        return unit?.trim().isNotEmpty == true ? unit!.trim() : 'unit';
    }
  }

  static String formatAddress({
    required String addressLine1,
    String? addressLine2,
    String? city,
    String? province,
    String? postalCode,
  }) {
    final parts = <String>[
      addressLine1.trim(),
      if ((addressLine2 ?? '').trim().isNotEmpty) addressLine2!.trim(),
      if ((city ?? '').trim().isNotEmpty) city!.trim(),
      if ((province ?? '').trim().isNotEmpty) province!.trim(),
      if ((postalCode ?? '').trim().isNotEmpty) postalCode!.trim(),
    ];

    return parts.join(', ');
  }

  static String buildEstimateTitle({
    String? serviceType,
    String? city,
  }) {
    final cleanService = (serviceType ?? '').trim();
    final cleanCity = (city ?? '').trim();

    if (cleanService.isEmpty && cleanCity.isEmpty) {
      return 'New Estimate';
    }

    if (cleanService.isNotEmpty && cleanCity.isNotEmpty) {
      return '$cleanService • $cleanCity';
    }

    return cleanService.isNotEmpty ? cleanService : cleanCity;
  }

  static String estimateSubtitle({
    String? estimateNumber,
    DateTime? createdAt,
  }) {
    final number = (estimateNumber ?? '').trim();
    final date = formatShortDate(createdAt);

    if (number.isEmpty) return date;
    return '$number • $date';
  }

  static String safeText(String? value, {String fallback = '—'}) {
    final text = value?.trim() ?? '';
    return text.isEmpty ? fallback : text;
  }
}