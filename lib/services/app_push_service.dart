import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AppPushService {
  AppPushService._();

  static final SupabaseClient _supabase = Supabase.instance.client;

  static Future<void> send({
    required String toUserId,
    required String role, // admin | worker
    required String title,
    required String body,
    Map<String, dynamic>? data,
  }) async {
    final cleanToUserId = toUserId.trim();
    final cleanRole = role.trim().toLowerCase();
    final cleanTitle = title.trim();
    final cleanBody = body.trim();

    if (cleanToUserId.isEmpty || cleanTitle.isEmpty || cleanBody.isEmpty) {
      return;
    }

    if (cleanRole != 'admin' && cleanRole != 'worker') {
      throw Exception('Invalid push role: $role');
    }

    try {
      final res = await _supabase.functions.invoke(
        'send-app-push',
        body: {
          'to_user_id': cleanToUserId,
          'role': cleanRole,
          'title': cleanTitle,
          'body': cleanBody,
          'data': data ?? const <String, dynamic>{},
        },
      );

      debugPrint('APP PUSH STATUS: ${res.status}');
      debugPrint('APP PUSH DATA: ${res.data}');
    } catch (e) {
      debugPrint('APP PUSH ERROR: $e');
    }
  }
}