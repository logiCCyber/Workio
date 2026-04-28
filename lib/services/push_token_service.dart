import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class PushTokenService {
  final _db = Supabase.instance.client;

  static bool _refreshListenerAttached = false;

  Future<void> syncPushToken({
    required String role, // admin | worker
  }) async {
    final user = _db.auth.currentUser;
    if (user == null) return;

    final cleanRole = role.trim().toLowerCase();
    if (cleanRole != 'admin' && cleanRole != 'worker') {
      throw Exception('Invalid push token role: $role');
    }

    final messaging = FirebaseMessaging.instance;

    await messaging.requestPermission();

    final token = await messaging.getToken();
    if (token == null || token.isEmpty) return;

    await _saveToken(
      userAuthId: user.id,
      role: cleanRole,
      token: token,
    );

    if (!_refreshListenerAttached) {
      _refreshListenerAttached = true;

      FirebaseMessaging.instance.onTokenRefresh.listen((newToken) async {
        final currentUser = _db.auth.currentUser;
        if (currentUser == null) return;
        if (newToken.trim().isEmpty) return;

        await _saveToken(
          userAuthId: currentUser.id,
          role: cleanRole,
          token: newToken,
        );
      });
    }
  }

  Future<void> syncAdminPushToken() async {
    await syncPushToken(role: 'admin');
  }

  Future<void> syncWorkerPushToken() async {
    await syncPushToken(role: 'worker');
  }

  Future<void> _saveToken({
    required String userAuthId,
    required String role,
    required String token,
  }) async {
    await _db.from('app_push_tokens').upsert({
      'user_auth_id': userAuthId,
      'role': role,
      'token': token,
      'platform': 'android',
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }, onConflict: 'user_auth_id,role,token');
  }
}