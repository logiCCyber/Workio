import 'dart:async';
import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';


import 'ui/app_toast.dart';

import 'screens/login_screen.dart';
import 'screens/reset_password_screen.dart';
import 'app_keys.dart';
import 'screens/admin_panel.dart';

final FlutterLocalNotificationsPlugin localNotifications =
FlutterLocalNotificationsPlugin();

const AndroidNotificationChannel highChannel = AndroidNotificationChannel(
  'high_importance_channel',
  'High Importance Notifications',
  description: 'Used for reminders and alerts',
  importance: Importance.max,
);



Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp();

  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

  const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');

  await localNotifications.initialize(
    const InitializationSettings(android: androidInit),
  );

  await localNotifications
      .resolvePlatformSpecificImplementation<
      AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(highChannel);

  await FirebaseMessaging.instance.requestPermission();

  await localNotifications
      .resolvePlatformSpecificImplementation<
      AndroidFlutterLocalNotificationsPlugin>()
      ?.requestNotificationsPermission();

  FirebaseMessaging.onMessage.listen((RemoteMessage message) async {
    final notification = message.notification;

    if (notification != null) {
      await localNotifications.show(
        notification.hashCode,
        notification.title ?? 'Reminder',
        notification.body ?? '',
        NotificationDetails(
          android: AndroidNotificationDetails(
            highChannel.id,
            highChannel.name,
            channelDescription: highChannel.description,
            importance: Importance.max,
            priority: Priority.high,
            icon: '@mipmap/ic_launcher',
          ),
        ),
      );
    }
  });

  await Supabase.initialize(
    url: 'https://mnycxmpofeajhjecsvhk.supabase.co',
    anonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im1ueWN4bXBvZmVhamhqZWNzdmhrIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjUwNjA3MjgsImV4cCI6MjA4MDYzNjcyOH0.XTcZlVfmeB6nJBoAkzbhtDjQpUQ7ifxzKfKXDlDM_DU',
    authOptions: const FlutterAuthClientOptions(
      authFlowType: AuthFlowType.pkce,
    ),
  );

  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});
  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  final AppLinks _links = AppLinks();
  StreamSubscription<Uri>? _sub;
  StreamSubscription<AuthState>? _authSub;

  bool _resetOpened = false;

  @override
  void initState() {
    super.initState();
    _listenSupabaseEvents();
    _initDeepLinks();
  }

  void _listenSupabaseEvents() {
    _authSub = Supabase.instance.client.auth.onAuthStateChange.listen((data) {
      if (data.event == AuthChangeEvent.passwordRecovery) {
        _openResetAsRoot();
      }
    });
  }

  Future<void> _initDeepLinks() async {
    final Uri? initial = await _links.getInitialLink();
    if (initial != null) {
      await _handleUri(initial);
    }

    _sub = _links.uriLinkStream.listen((uri) async {
      await _handleUri(uri);
    });
  }

  Future<void> _handleUri(Uri uri) async {
    debugPrint('DEEPLINK => $uri');
    debugPrint('scheme=${uri.scheme} host=${uri.host} path=${uri.path}');
    debugPrint('query=${uri.query}');
    debugPrint('fragment=${uri.fragment}');

    final isReset = uri.scheme == 'workio' &&
        (uri.host == 'reset-password' || uri.pathSegments.contains('reset-password'));

    final isConfirmed = uri.scheme == 'workio' &&
        (uri.host == 'confirmed' || uri.pathSegments.contains('confirmed'));

    // ✅ если это НЕ reset и НЕ confirmed — выходим
    if (!isReset && !isConfirmed) return;

    final supa = Supabase.instance.client;

    bool ok = false;

    try {
      // ✅ PKCE: workio://... ?code=...
      if (uri.queryParameters.containsKey('code')) {
        final res = await supa.auth.getSessionFromUrl(uri);
        ok = res.session != null;
      } else {
        // ✅ fallback (если вдруг прилетит не PKCE)
        final params = <String, String>{};
        params.addAll(uri.queryParameters);
        if (uri.fragment.isNotEmpty) {
          params.addAll(Uri.splitQueryString(uri.fragment));
        }

        final type = params['type']; // 'recovery' может быть
        final refreshToken = params['refresh_token'];

        if (type == 'recovery' && refreshToken != null && refreshToken.isNotEmpty) {
          final res = await supa.auth.setSession(refreshToken);
          ok = res.session != null;
        }
      }
    } catch (e) {
      debugPrint('DEEPLINK session error => $e');
      ok = false;
    }

    debugPrint('DEEPLINK ok=$ok');

    if (!ok) {
      AppToast.warning('Link is invalid or has expired');
      return;
    }

    // ✅ ВАЖНО: reset открываем только если это reset-link
    if (isReset) {
      _openResetAsRoot();
      return;
    }

    // ✅ Confirm email -> НЕ reset. Тут открываем нормальный вход / админку
    if (isConfirmed) {
      _openAfterConfirm();
      return;
    }
  }


  void _openResetAsRoot() {
    if (_resetOpened) return;        // ✅ если уже открывали — больше не открываем
    _resetOpened = true;             // ✅ помечаем что reset уже открыт

    WidgetsBinding.instance.addPostFrameCallback((_) {
      navigatorKey.currentState?.pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const ResetPasswordScreen()),
            (_) => false,
      );
    });
  }

  void _openAfterConfirm() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final user = Supabase.instance.client.auth.currentUser;

      // Если сессия есть — можно сразу в AdminPanel
      // (если вдруг нет — просто на Login)
      if (user != null) {
        navigatorKey.currentState?.pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const AdminPanel()),
              (_) => false,
        );
      } else {
        navigatorKey.currentState?.pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const LoginScreen()),
              (_) => false,
        );
      }
    });
  }


  @override
  void dispose() {
    _sub?.cancel();
    _authSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey,
      scaffoldMessengerKey: rootMessengerKey,
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(useMaterial3: true),
      home: const LoginScreen(),
    );
  }
}
