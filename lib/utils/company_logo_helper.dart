import '../models/company_settings_model.dart';

class CompanyLogoHelper {
  static const String defaultLogoUrl =
      'https://mnycxmpofeajhjecsvhk.supabase.co/storage/v1/object/public/company-assets/defaults/default_logo.png';

  static String resolvedLogoUrl(CompanySettingsModel? settings) {
    final customUrl = settings?.logoUrl?.trim() ?? '';

    if (customUrl.isNotEmpty) {
      return customUrl;
    }

    return defaultLogoUrl;
  }
}
