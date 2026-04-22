import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/property_model.dart';

class PropertyService {
  PropertyService._();

  static final SupabaseClient _supabase = Supabase.instance.client;
  static const String _table = 'properties';

  static String _requireUserId() {
    final user = _supabase.auth.currentUser;

    if (user == null) {
      throw Exception('User is not authenticated');
    }

    return user.id;
  }

  static List<PropertyModel> _mapPropertyList(dynamic response) {
    final list = response as List;

    return list
        .map((item) => PropertyModel.fromMap(item as Map<String, dynamic>))
        .toList();
  }

  static Future<List<PropertyModel>> getProperties({
    bool includeArchived = false,
    bool archivedOnly = false,
  }) async {
    final userId = _requireUserId();

    var query = _supabase
        .from(_table)
        .select()
        .eq('admin_auth_id', userId);

    if (archivedOnly) {
      query = query.eq('is_archived', true);
    } else if (!includeArchived) {
      query = query.eq('is_archived', false);
    }

    final response = await query.order('created_at', ascending: false);

    return _mapPropertyList(response);
  }

  static Future<List<PropertyModel>> getPropertiesByClient(
      String clientId, {
        bool includeArchived = false,
      }) async {
    final userId = _requireUserId();

    var query = _supabase
        .from(_table)
        .select()
        .eq('admin_auth_id', userId)
        .eq('client_id', clientId);

    if (!includeArchived) {
      query = query.eq('is_archived', false);
    }

    final response = await query.order('created_at', ascending: false);

    return _mapPropertyList(response);
  }

  static Future<PropertyModel?> getPropertyById(String propertyId) async {
    final userId = _requireUserId();

    final response = await _supabase
        .from(_table)
        .select()
        .eq('id', propertyId)
        .eq('admin_auth_id', userId)
        .limit(1)
        .maybeSingle();

    if (response == null) {
      return null;
    }

    return PropertyModel.fromMap(response);
  }

  static Future<List<PropertyModel>> searchProperties(
      String query, {
        bool includeArchived = false,
        bool archivedOnly = false,
      }) async {
    final userId = _requireUserId();
    final trimmedQuery = query.trim();

    if (trimmedQuery.isEmpty) {
      return getProperties(
        includeArchived: includeArchived,
        archivedOnly: archivedOnly,
      );
    }

    var request = _supabase
        .from(_table)
        .select()
        .eq('admin_auth_id', userId);

    if (archivedOnly) {
      request = request.eq('is_archived', true);
    } else if (!includeArchived) {
      request = request.eq('is_archived', false);
    }

    final response = await request
        .or(
      'address_line_1.ilike.%$trimmedQuery%,'
          'address_line_2.ilike.%$trimmedQuery%,'
          'city.ilike.%$trimmedQuery%,'
          'postal_code.ilike.%$trimmedQuery%,'
          'property_type.ilike.%$trimmedQuery%',
    )
        .order('created_at', ascending: false);

    return _mapPropertyList(response);
  }

  static Future<PropertyModel> archiveProperty(String propertyId) async {
    final userId = _requireUserId();

    final response = await _supabase
        .from(_table)
        .update({'is_archived': true})
        .eq('id', propertyId)
        .eq('admin_auth_id', userId)
        .select()
        .single();

    return PropertyModel.fromMap(response);
  }

  static Future<PropertyModel> restoreProperty(String propertyId) async {
    final userId = _requireUserId();

    final response = await _supabase
        .from(_table)
        .update({'is_archived': false})
        .eq('id', propertyId)
        .eq('admin_auth_id', userId)
        .select()
        .single();

    return PropertyModel.fromMap(response);
  }

  static Future<PropertyModel> createProperty(PropertyModel property) async {
    final userId = _requireUserId();

    final payload = property.toInsertMap()
      ..['admin_auth_id'] = userId;

    final response = await _supabase
        .from(_table)
        .insert(payload)
        .select()
        .single();

    return PropertyModel.fromMap(response);
  }

  static Future<PropertyModel> updateProperty(PropertyModel property) async {
    final userId = _requireUserId();

    if (property.id.trim().isEmpty) {
      throw Exception('Cannot update object without ID');
    }

    final payload = {
      'client_id': property.clientId,
      'address_line_1': property.addressLine1,
      'address_line_2': property.addressLine2,
      'city': property.city,
      'province': property.province,
      'postal_code': property.postalCode,
      'square_footage': property.squareFootage,
      'property_type': property.propertyType,
      'notes': property.notes,
    };

    final response = await _supabase
        .from(_table)
        .update(payload)
        .eq('id', property.id)
        .eq('admin_auth_id', userId)
        .select()
        .single();

    return PropertyModel.fromMap(response);
  }

  static Future<void> deleteProperty(String propertyId) async {
    final userId = _requireUserId();

    await _supabase
        .from(_table)
        .delete()
        .eq('id', propertyId)
        .eq('admin_auth_id', userId);
  }
}