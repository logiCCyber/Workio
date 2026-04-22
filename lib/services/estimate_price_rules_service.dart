import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/estimate_price_rule_model.dart';

class EstimatePriceRulesService {
  EstimatePriceRulesService._();

  static final _client = Supabase.instance.client;
  static const _table = 'estimate_price_rules';

  static List<EstimatePriceRuleModel> _defaultRules(String adminAuthId) {
    return [
      EstimatePriceRuleModel(
        id: 'painting_walls',
        adminAuthId: adminAuthId,
        serviceType: 'painting',
        category: 'walls',
        unit: 'sqft',
        baseRate: 1.80,
        singleCoatRate: 1.45,
        multiCoatRate: 1.80,
        materialRatePerSqft: 0.22,
        prepFixedRate: 180,
        rushFixedRate: 175,
      ),
      EstimatePriceRuleModel(
        id: 'painting_ceiling',
        adminAuthId: adminAuthId,
        serviceType: 'painting',
        category: 'ceiling',
        unit: 'sqft',
        baseRate: 0.85,
        singleCoatRate: 0.65,
        multiCoatRate: 0.85,
        materialRatePerSqft: 0.22,
        prepFixedRate: 180,
        rushFixedRate: 175,
      ),
      EstimatePriceRuleModel(
        id: 'drywall_main',
        adminAuthId: adminAuthId,
        serviceType: 'drywall',
        category: 'main',
        unit: 'sqft',
        baseRate: 2.35,
        materialRatePerSqft: 0.28,
        prepFixedRate: 140,
        rushFixedRate: 180,
      ),
      EstimatePriceRuleModel(
        id: 'cleaning_main',
        adminAuthId: adminAuthId,
        serviceType: 'cleaning',
        category: 'main',
        unit: 'sqft',
        baseRate: 0.34,
        materialFixedRate: 45,
        rushFixedRate: 95,
      ),
      EstimatePriceRuleModel(
        id: 'flooring_main',
        adminAuthId: adminAuthId,
        serviceType: 'flooring',
        category: 'main',
        unit: 'sqft',
        baseRate: 2.95,
        materialRatePerSqft: 0.55,
        prepFixedRate: 160,
        rushFixedRate: 175,
      ),
      EstimatePriceRuleModel(
        id: 'general_main',
        adminAuthId: adminAuthId,
        serviceType: 'general',
        category: 'main',
        unit: 'sqft',
        baseRate: 1.25,
        materialFixedRate: 95,
        prepFixedRate: 120,
        rushFixedRate: 120,
      ),
    ];
  }

  static String _requireAdminAuthId() {
    final user = _client.auth.currentUser;
    if (user == null) {
      throw Exception('User not authenticated');
    }
    return user.id;
  }

  static Future<void> _seedDefaultsIfEmpty() async {
    final adminAuthId = _requireAdminAuthId();

    final existing = await _client
        .from(_table)
        .select('id')
        .eq('admin_auth_id', adminAuthId);

    if ((existing as List).isNotEmpty) return;

    final defaults = _defaultRules(adminAuthId)
        .map((rule) => rule.toMap()..remove('created_at')..remove('updated_at'))
        .toList();

    await _client.from(_table).insert(defaults);
  }

  static Future<List<EstimatePriceRuleModel>> getRules() async {
    await _seedDefaultsIfEmpty();

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

  static Future<EstimatePriceRuleModel?> findPaintingWallsRule() async {
    return findRule(
      serviceType: 'painting',
      category: 'walls',
    );
  }

  static Future<EstimatePriceRuleModel?> findPaintingCeilingRule() async {
    return findRule(
      serviceType: 'painting',
      category: 'ceiling',
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

  static Future<void> resetDefaults() async {
    final adminAuthId = _requireAdminAuthId();

    await _client.from(_table).delete().eq('admin_auth_id', adminAuthId);

    final defaults = _defaultRules(adminAuthId)
        .map((rule) => rule.toMap()..remove('created_at')..remove('updated_at'))
        .toList();

    await _client.from(_table).insert(defaults);
  }
}