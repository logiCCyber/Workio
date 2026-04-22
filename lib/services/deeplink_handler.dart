import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../screens/reset_password_screen.dart';

class DeepLinkHandler {
  DeepLinkHandler(this.navigatorKey);

  final GlobalKey<NavigatorState> navigatorKey;
  final AppLinks _appLinks = AppLinks();

  bool _inited = false;

  Future<void> init() async {
    if (_inited) return;
    _inited = true;

    // 1) cold start (когда приложение было закрыто)
    final initial = await _appLinks.getInitialLink();
    if (initial != null) {
      await _handle(initial);
    }

    // 2) runtime (когда приложение уже открыто/в фоне)
    _appLinks.uriLinkStream.listen((uri) async {
      await _handle(uri);
    });
  }

  Future<void> _handle(Uri uri) async {
    // ✅ ВАЖНО: отдаём ссылку Supabase (он вытащит access_token / refresh_token из URL)
    try {
      await Supabase.instance.client.auth.getSessionFromUrl(uri);
    } catch (_) {
      // не страшно — иногда токенов нет, но навигацию всё равно можно сделать
    }

    // ✅ ТВОЙ deep link: workio://reset-password
    if (uri.scheme == 'workio' && uri.host == 'reset-password') {
      navigatorKey.currentState?.pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const ResetPasswordScreen()),
            (_) => false,
      );
    }
  }
}
