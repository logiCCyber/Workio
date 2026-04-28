import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/estimate_price_rule_model.dart';

class EstimatePriceRulesService {
  EstimatePriceRulesService._();

  static final _client = Supabase.instance.client;
  static const _table = 'estimate_price_rules';

  static String _requireAdminAuthId() {
    final user = _client.auth.currentUser;
    if (user == null) {
      throw Exception('User not authenticated');
    }
    return user.id;
  }

  static Future<List<EstimatePriceRuleModel>> getRules() async {
    final adminAuthId = _requireAdminAuthId();

    final response = await _client
        .from(_table)
        .select()
        .eq('admin_auth_id', adminAuthId)
        .eq('is_active', true)
        .order('service_type')
        .order('category');

    return (response as List)
        .map((item) => EstimatePriceRuleModel.fromMap(
      Map<String, dynamic>.from(item),
    ))
        .toList();
  }

  static Future<void> deleteRule(String id) async {
    final adminAuthId = _requireAdminAuthId();

    await _client
        .from(_table)
        .delete()
        .eq('admin_auth_id', adminAuthId)
        .eq('id', id);
  }

  static Future<EstimatePriceRuleModel?> findRule({
    required String serviceType,
    required String category,
  }) async {
    final adminAuthId = _requireAdminAuthId();

    final response = await _client
        .from(_table)
        .select()
        .eq('admin_auth_id', adminAuthId)
        .eq('service_type', serviceType)
        .eq('category', category)
        .eq('is_active', true)
        .maybeSingle();

    if (response == null) return null;

    return EstimatePriceRuleModel.fromMap(
      Map<String, dynamic>.from(response),
    );
  }

  static Future<EstimatePriceRuleModel?> findMainRule(String serviceType) async {
    return findRule(
      serviceType: serviceType,
      category: 'main',
    );
  }

  static Future<EstimatePriceRuleModel?> getRuleById(String id) async {
    final adminAuthId = _requireAdminAuthId();

    final response = await _client
        .from(_table)
        .select()
        .eq('admin_auth_id', adminAuthId)
        .eq('id', id)
        .maybeSingle();

    if (response == null) return null;

    return EstimatePriceRuleModel.fromMap(
      Map<String, dynamic>.from(response),
    );
  }

  static Future<void> updateRule(EstimatePriceRuleModel updatedRule) async {
    final adminAuthId = _requireAdminAuthId();

    final payload = updatedRule
        .copyWith(adminAuthId: adminAuthId)
        .toMap()
      ..remove('created_at')
      ..remove('updated_at');

    await _client
        .from(_table)
        .update(payload)
        .eq('admin_auth_id', adminAuthId)
        .eq('id', updatedRule.id);
  }

  static Future<void> createRule(EstimatePriceRuleModel rule) async {
    final adminAuthId = _requireAdminAuthId();

    final payload = rule
        .copyWith(adminAuthId: adminAuthId)
        .toMap()
      ..remove('created_at')
      ..remove('updated_at');

    await _client.from(_table).insert(payload);
  }

  static Future<void> replaceAllRules(
      List<EstimatePriceRuleModel> rules,
      ) async {
    final adminAuthId = _requireAdminAuthId();

    final payload = rules
        .map(
          (rule) => rule.copyWith(adminAuthId: adminAuthId).toMap()
        ..remove('created_at')
        ..remove('updated_at'),
    )
        .toList();

    await _client.from(_table).upsert(payload);
  }

  static Future<void> deleteAllRules() async {
    final adminAuthId = _requireAdminAuthId();

    await _client
        .from(_table)
        .delete()
        .eq('admin_auth_id', adminAuthId);
  }
}