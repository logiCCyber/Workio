import 'dart:async';
import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'dart:convert';

import 'screens/admin_chat_screen.dart';
import 'screens/worker_chat_screen.dart';
import 'screens/admin_tasks_screen.dart';
import 'screens/worker_tasks_screen.dart';


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

String _pushIconForType(Object? type) {
  final t = (type ?? '').toString().trim().toLowerCase();

  if (t == 'chat') return 'ic_push_chat';
  if (t == 'task') return 'ic_push_task';
  if (t == 'reminder') return 'ic_push_reminder';

  return 'ic_push_default';
}

String _pushTypeFromData(Map<String, dynamic> data) {
  final type = (data['type'] ?? '').toString().trim().toLowerCase();

  if (type == 'chat') return 'chat';
  if (type == 'task') return 'task';
  if (type == 'reminder') return 'reminder';

  if (!data.containsKey('thread_id') && !data.containsKey('task_id')) {
    return 'reminder';
  }

  return '';
}

String _pushTitleForForeground({
  required String rawTitle,
  required Map<String, dynamic> data,
}) {
  final title = rawTitle.trim();
  final type = _pushTypeFromData(data);

  if (type == 'reminder' && !title.startsWith('Reminder •')) {
    return 'Reminder • $title';
  }

  return title.isEmpty ? 'Workio' : title;
}

String _pushS(Object? v) => (v ?? '').toString().trim();

Future<String> _currentPushUserRole() async {
  final user = Supabase.instance.client.auth.currentUser;
  if (user == null) return '';

  try {
    final worker = await Supabase.instance.client
        .from('workers')
        .select('id, access_mode')
        .eq('auth_user_id', user.id)
        .maybeSingle();

    if (worker != null) return 'worker';
  } catch (_) {}

  return 'admin';
}

Future<bool> _currentWorkerIsViewOnly() async {
  final user = Supabase.instance.client.auth.currentUser;
  if (user == null) return false;

  try {
    final worker = await Supabase.instance.client
        .from('workers')
        .select('access_mode')
        .eq('auth_user_id', user.id)
        .maybeSingle();

    final mode = _pushS(worker?['access_mode']).toLowerCase();

    return mode == 'readonly' ||
        mode == 'viewonly' ||
        mode == 'view_only' ||
        mode == 'view-only' ||
        mode == 'view';
  } catch (_) {
    return false;
  }
}

Future<void> _openAdminChatFromPush(String threadId) async {
  if (threadId.isEmpty) return;

  final row = await Supabase.instance.client
      .from('message_threads')
      .select('''
        id,
        worker_auth_id,
        workers(
          id,
          name,
          email,
          avatar_url,
          auth_user_id
        )
      ''')
      .eq('id', threadId)
      .maybeSingle();

  if (row == null) return;

  final map = Map<String, dynamic>.from(row as Map);
  final worker = map['workers'] is Map
      ? Map<String, dynamic>.from(map['workers'] as Map)
      : <String, dynamic>{};

  navigatorKey.currentState?.push(
    MaterialPageRoute(
      builder: (_) => AdminChatScreen(
        threadId: threadId,
        workerName: _pushS(worker['name']).isEmpty
            ? 'Worker'
            : _pushS(worker['name']),
        workerEmail: _pushS(worker['email']),
        avatarUrl: _pushS(worker['avatar_url']),
        workerAuthId: _pushS(map['worker_auth_id']).isEmpty
            ? _pushS(worker['auth_user_id'])
            : _pushS(map['worker_auth_id']),
      ),
    ),
  );
}

Future<void> _openPushData(Map<String, dynamic> data) async {
  debugPrint('PUSH TAP DATA => $data');

  final user = Supabase.instance.client.auth.currentUser;
  if (user == null) {
    navigatorKey.currentState?.pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
          (_) => false,
    );
    return;
  }

  final type = _pushS(data['type']).toLowerCase();

  if (type == 'chat') {
    final senderRole = _pushS(data['sender_role']).toLowerCase();
    final threadId = _pushS(data['thread_id']);

    if (senderRole == 'admin') {
      final isViewOnly = await _currentWorkerIsViewOnly();

      navigatorKey.currentState?.push(
        MaterialPageRoute(
          builder: (_) => WorkerChatScreen(
            isViewOnly: isViewOnly,
          ),
        ),
      );
      return;
    }

    if (senderRole == 'worker') {
      await _openAdminChatFromPush(threadId);
      return;
    }
  }

  if (type == 'task') {
    final role = await _currentPushUserRole();

    if (role == 'worker') {
      final isViewOnly = await _currentWorkerIsViewOnly();

      navigatorKey.currentState?.push(
        MaterialPageRoute(
          builder: (_) => WorkerTasksScreen(
            isViewOnly: isViewOnly,
          ),
        ),
      );
      return;
    }

    navigatorKey.currentState?.push(
      MaterialPageRoute(
        builder: (_) => const AdminTasksScreen(),
      ),
    );
  }
}

void _handleLocalNotificationTap(NotificationResponse response) {
  final payload = response.payload;
  if (payload == null || payload.trim().isEmpty) return;

  try {
    final decoded = jsonDecode(payload);
    if (decoded is Map) {
      _openPushData(Map<String, dynamic>.from(decoded));
    }
  } catch (e) {
    debugPrint('LOCAL PUSH TAP ERROR: $e');
  }
}

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
    onDidReceiveNotificationResponse: _handleLocalNotificationTap,
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
    if (notification == null) return;

    final data = Map<String, dynamic>.from(message.data);
    final pushType = _pushTypeFromData(data);

    await localNotifications.show(
      notification.hashCode,
      _pushTitleForForeground(
        rawTitle: notification.title ?? 'Reminder',
        data: data,
      ),
      notification.body ?? '',
      NotificationDetails(
        android: AndroidNotificationDetails(
          highChannel.id,
          highChannel.name,
          channelDescription: highChannel.description,
          importance: Importance.max,
          priority: Priority.high,
          icon: _pushIconForType(pushType),
        ),
      ),
      payload: jsonEncode(data),
    );
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
    _initPushOpenHandlers();
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

  Future<void> _initPushOpenHandlers() async {
    final initialMessage = await FirebaseMessaging.instance.getInitialMessage();

    if (initialMessage != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _openPushData(initialMessage.data);
      });
    }

    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      _openPushData(message.data);
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
