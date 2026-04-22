import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/client_model.dart';

class ClientService {
  ClientService._();

  static final SupabaseClient _supabase = Supabase.instance.client;
  static const String _table = 'clients';

  static String _requireUserId() {
    final user = _supabase.auth.currentUser;

    if (user == null) {
      throw Exception('User is not authenticated');
    }

    return user.id;
  }

  static List<ClientModel> _mapClientList(dynamic response) {
    final list = response as List;

    return list
        .map((item) => ClientModel.fromMap(item as Map<String, dynamic>))
        .toList();
  }

  static Future<List<ClientModel>> getClients({
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

    final response = await query.order('full_name');

    return _mapClientList(response);
  }

  static Future<ClientModel> restoreClient(String clientId) async {
    final userId = _requireUserId();

    final response = await _supabase
        .from(_table)
        .update({'is_archived': false})
        .eq('id', clientId)
        .eq('admin_auth_id', userId)
        .select()
        .single();

    return ClientModel.fromMap(response);
  }

  static Future<ClientModel> archiveClient(String clientId) async {
    final userId = _requireUserId();

    final response = await _supabase
        .from(_table)
        .update({'is_archived': true})
        .eq('id', clientId)
        .eq('admin_auth_id', userId)
        .select()
        .single();

    return ClientModel.fromMap(response);
  }

  static Future<List<ClientModel>> searchClients(
      String query, {
        bool includeArchived = false,
        bool archivedOnly = false,
      }) async {
    final userId = _requireUserId();
    final trimmedQuery = query.trim();

    if (trimmedQuery.isEmpty) {
      return getClients(
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
      'full_name.ilike.%$trimmedQuery%,'
          'company_name.ilike.%$trimmedQuery%,'
          'email.ilike.%$trimmedQuery%,'
          'phone.ilike.%$trimmedQuery%',
    )
        .order('full_name');

    return _mapClientList(response);
  }

  static Future<ClientModel?> getClientById(String clientId) async {
    final userId = _requireUserId();

    final response = await _supabase
        .from(_table)
        .select()
        .eq('id', clientId)
        .eq('admin_auth_id', userId)
        .limit(1)
        .maybeSingle();

    if (response == null) {
      return null;
    }

    return ClientModel.fromMap(response);
  }

  static Future<ClientModel> createClient(ClientModel client) async {
    final userId = _requireUserId();

    final payload = client.toInsertMap()
      ..['admin_auth_id'] = userId;

    final response = await _supabase
        .from(_table)
        .insert(payload)
        .select()
        .single();

    return ClientModel.fromMap(response);
  }

  static Future<ClientModel> updateClient(ClientModel client) async {
    final userId = _requireUserId();

    if (client.id.trim().isEmpty) {
      throw Exception('Cannot update client without id');
    }

    final payload = {
      'full_name': client.fullName,
      'phone': client.phone,
      'email': client.email,
      'company_name': client.companyName,
      'notes': client.notes,
    };

    final response = await _supabase
        .from(_table)
        .update(payload)
        .eq('id', client.id)
        .eq('admin_auth_id', userId)
        .select()
        .single();

    return ClientModel.fromMap(response);
  }

  static Future<void> deleteClient(String clientId) async {
    final userId = _requireUserId();

    await _supabase
        .from(_table)
        .delete()
        .eq('id', clientId)
        .eq('admin_auth_id', userId);
  }
}