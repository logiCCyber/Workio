class CompanySettingsModel {
  final String id;
  final String adminAuthId;
  final String companyName;
  final String? companyEmail;
  final String? companyPhone;
  final String? companyWebsite;
  final String? companyAddress;
  final String taxLabel;
  final double defaultTaxRate;
  final String currencyCode;
  final String? logoPath;
  final String? logoUrl;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const CompanySettingsModel({
    required this.id,
    required this.adminAuthId,
    required this.companyName,
    this.companyEmail,
    this.companyPhone,
    this.companyWebsite,
    this.companyAddress,
    required this.taxLabel,
    required this.defaultTaxRate,
    required this.currencyCode,
    this.logoPath,
    this.logoUrl,
    this.createdAt,
    this.updatedAt,
  });

  factory CompanySettingsModel.fromMap(Map<String, dynamic> map) {
    return CompanySettingsModel(
      id: map['id']?.toString() ?? '',
      adminAuthId: map['admin_auth_id']?.toString() ?? '',
      companyName: map['company_name']?.toString() ?? '',
      companyEmail: map['company_email']?.toString(),
      companyPhone: map['company_phone']?.toString(),
      companyWebsite: map['company_website']?.toString(),
      companyAddress: map['company_address']?.toString(),
      taxLabel: map['tax_label']?.toString() ?? 'Tax',
      defaultTaxRate: _toDouble(map['default_tax_rate'], fallback: 0.13),
      currencyCode: map['currency_code']?.toString() ?? 'CAD',
      logoPath: map['logo_path']?.toString(),
      logoUrl: map['logo_url']?.toString(),
      createdAt: map['created_at'] != null
          ? DateTime.tryParse(map['created_at'].toString())
          : null,
      updatedAt: map['updated_at'] != null
          ? DateTime.tryParse(map['updated_at'].toString())
          : null,
    );
  }

  static double _toDouble(dynamic value, {double fallback = 0}) {
    if (value == null) return fallback;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString()) ?? fallback;
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'admin_auth_id': adminAuthId,
      'company_name': companyName,
      'company_email': companyEmail,
      'company_phone': companyPhone,
      'company_website': companyWebsite,
      'company_address': companyAddress,
      'tax_label': taxLabel,
      'default_tax_rate': defaultTaxRate,
      'currency_code': currencyCode,
      'logo_path': logoPath,
      'logo_url': logoUrl,
      'created_at': createdAt?.toIso8601String(),
      'updated_at': updatedAt?.toIso8601String(),
    };
  }

  Map<String, dynamic> toInsertMap() {
    return {
      'company_name': companyName,
      'company_email': companyEmail,
      'company_phone': companyPhone,
      'company_website': companyWebsite,
      'company_address': companyAddress,
      'tax_label': taxLabel,
      'default_tax_rate': defaultTaxRate,
      'currency_code': currencyCode,
      'logo_path': logoPath,
      'logo_url': logoUrl,
    };
  }

  CompanySettingsModel copyWith({
    String? id,
    String? adminAuthId,
    String? companyName,
    String? companyEmail,
    String? companyPhone,
    String? companyWebsite,
    String? companyAddress,
    String? taxLabel,
    double? defaultTaxRate,
    String? currencyCode,
    String? logoPath,
    String? logoUrl,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return CompanySettingsModel(
      id: id ?? this.id,
      adminAuthId: adminAuthId ?? this.adminAuthId,
      companyName: companyName ?? this.companyName,
      companyEmail: companyEmail ?? this.companyEmail,
      companyPhone: companyPhone ?? this.companyPhone,
      companyWebsite: companyWebsite ?? this.companyWebsite,
      companyAddress: companyAddress ?? this.companyAddress,
      taxLabel: taxLabel ?? this.taxLabel,
      defaultTaxRate: defaultTaxRate ?? this.defaultTaxRate,
      currencyCode: currencyCode ?? this.currencyCode,
      logoPath: logoPath ?? this.logoPath,
      logoUrl: logoUrl ?? this.logoUrl,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}