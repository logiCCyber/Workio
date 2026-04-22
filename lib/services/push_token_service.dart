import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class PushTokenService {
  final _db = Supabase.instance.client;

  Future<void> syncAdminPushToken() async {
    final user = _db.auth.currentUser;
    if (user == null) return;

    final messaging = FirebaseMessaging.instance;

    await messaging.requestPermission();

    final token = await messaging.getToken();
    if (token == null || token.isEmpty) return;

    await _db.from('admin_push_tokens').upsert({
      'admin_id': user.id,
      'token': token,
      'platform': 'android',
    }, onConflict: 'token');
  }
}