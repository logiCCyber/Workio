import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/estimate_template_model.dart';

class EstimateTemplateService {
  EstimateTemplateService._();

  static final SupabaseClient _supabase = Supabase.instance.client;
  static const String _table = 'estimate_templates';

  static String _requireUserId() {
    final user = _supabase.auth.currentUser;

    if (user == null) {
      throw Exception('User is not authenticated');
    }

    return user.id;
  }

  static List<EstimateTemplateModel> _mapTemplateList(dynamic response) {
    final list = response as List;

    return list
        .map((item) => EstimateTemplateModel.fromMap(item as Map<String, dynamic>))
        .toList();
  }

  static Future<List<EstimateTemplateModel>> getTemplates() async {
    final userId = _requireUserId();

    final response = await _supabase
        .from(_table)
        .select()
        .eq('admin_auth_id', userId)
        .order('created_at', ascending: false);

    return _mapTemplateList(response);
  }

  static Future<List<EstimateTemplateModel>> searchTemplates(String query) async {
    final userId = _requireUserId();
    final trimmed = query.trim();

    if (trimmed.isEmpty) {
      return getTemplates();
    }

    final response = await _supabase
        .from(_table)
        .select()
        .eq('admin_auth_id', userId)
        .ilike('name', '%$trimmed%')
        .order('created_at', ascending: false);

    return _mapTemplateList(response);
  }

  static Future<EstimateTemplateModel?> getTemplateById(String templateId) async {
    final userId = _requireUserId();

    final response = await _supabase
        .from(_table)
        .select()
        .eq('id', templateId)
        .eq('admin_auth_id', userId)
        .limit(1)
        .maybeSingle();

    if (response == null) return null;

    return EstimateTemplateModel.fromMap(response);
  }

  static Future<EstimateTemplateModel> createTemplate(
      EstimateTemplateModel template,
      ) async {
    final userId = _requireUserId();

    final payload = template.toInsertMap()
      ..['admin_auth_id'] = userId;

    final response = await _supabase
        .from(_table)
        .insert(payload)
        .select()
        .single();

    return EstimateTemplateModel.fromMap(response);
  }

  static Future<EstimateTemplateModel> updateTemplate(
      EstimateTemplateModel template,
      ) async {
    final userId = _requireUserId();

    if (template.id.trim().isEmpty) {
      throw Exception('Cannot update template without id');
    }

    final payload = {
      'name': template.name,
      'service_type': template.serviceType,
      'default_scope_text': template.defaultScopeText,
      'default_notes': template.defaultNotes,
    };

    final response = await _supabase
        .from(_table)
        .update(payload)
        .eq('id', template.id)
        .eq('admin_auth_id', userId)
        .select()
        .single();

    return EstimateTemplateModel.fromMap(response);
  }

  static Future<void> deleteTemplate(String templateId) async {
    final userId = _requireUserId();

    await _supabase
        .from(_table)
        .delete()
        .eq('id', templateId)
        .eq('admin_auth_id', userId);
  }
}