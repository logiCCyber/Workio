import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/company_settings_model.dart';

class CompanySettingsService {
  static final SupabaseClient _supabase = Supabase.instance.client;

  static const String _table = 'company_settings';
  static const String _bucket = 'company-assets';

  static Future<CompanySettingsModel?> getSettings() async {
    final user = _supabase.auth.currentUser;
    if (user == null) return null;

    final response = await _supabase
        .from(_table)
        .select()
        .eq('admin_auth_id', user.id)
        .maybeSingle();

    if (response == null) return null;

    return CompanySettingsModel.fromMap(response);
  }

  static Future<CompanySettingsModel> upsertSettings(
      CompanySettingsModel settings,
      ) async {
    final user = _supabase.auth.currentUser;
    if (user == null) {
      throw Exception('User not authenticated');
    }

    final existing = await _supabase
        .from(_table)
        .select('id')
        .eq('admin_auth_id', user.id)
        .maybeSingle();

    final payload = <String, dynamic>{
      'admin_auth_id': user.id,
      'company_name': settings.companyName,
      'company_email': settings.companyEmail,
      'company_phone': settings.companyPhone,
      'company_website': settings.companyWebsite,
      'company_address': settings.companyAddress,
      'tax_label': settings.taxLabel,
      'default_tax_rate': settings.defaultTaxRate,
      'currency_code': settings.currencyCode,
      'logo_path': settings.logoPath,
      'logo_url': settings.logoUrl,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    };

    Map<String, dynamic> savedRow;

    if (existing == null) {
      savedRow = await _supabase
          .from(_table)
          .insert(payload)
          .select()
          .single();
    } else {
      savedRow = await _supabase
          .from(_table)
          .update(payload)
          .eq('id', existing['id'])
          .select()
          .single();
    }

    return CompanySettingsModel.fromMap(savedRow);
  }

  static Future<Map<String, String>> uploadLogoPng({
    required Uint8List bytes,
    required String fileName,
  }) async {
    final user = _supabase.auth.currentUser;
    if (user == null) {
      throw Exception('User not authenticated');
    }

    final safeName = fileName.toLowerCase().endsWith('.png')
        ? fileName.toLowerCase()
        : '$fileName.png';

    final path = 'company-logos/${user.id}/$safeName';

    await _supabase.storage.from(_bucket).uploadBinary(
      path,
      bytes,
      fileOptions: const FileOptions(
        contentType: 'image/png',
        upsert: true,
      ),
    );

    final publicUrl = _supabase.storage.from(_bucket).getPublicUrl(path);

    return {
      'path': path,
      'url': publicUrl,
    };
  }

  static Future<void> deleteLogo(String path) async {
    final trimmed = path.trim();
    if (trimmed.isEmpty) return;

    await _supabase.storage.from(_bucket).remove([trimmed]);
  }
}