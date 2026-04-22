import '../models/company_settings_model.dart';

class CompanyLogoHelper {
  static const String defaultLogoUrl =
      'https://mnycxmpofeajhjecsvhk.supabase.co/storage/v1/object/public/company-assets/defaults/default_logo.png';

  static String? customLogoUrl(CompanySettingsModel? settings) {
    final value = settings?.logoUrl?.trim() ?? '';
    return value.isEmpty ? null : value;
  }

  static String resolvedLogoUrl(CompanySettingsModel? settings) {
    final custom = customLogoUrl(settings);
    if (custom != null) return custom;
    return defaultLogoUrl;
  }

  static bool hasCustomLogo(CompanySettingsModel? settings) {
    return customLogoUrl(settings) != null;
  }
}