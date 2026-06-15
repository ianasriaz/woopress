import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flex_color_scheme/flex_color_scheme.dart';
import 'core/router/app_router.dart';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

import 'features/notifications/data/fcm_service.dart';

import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'features/notifications/domain/models/notification_model.dart';

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  
  final title = message.notification?.title ?? message.data['title'] ?? "New Order Received";
  final body = message.notification?.body ?? message.data['body'] ?? "Check your dashboard for details.";
  final orderId = message.data['order_id']?.toString();

  final notification = NotificationModel(
    id: message.messageId ?? DateTime.now().millisecondsSinceEpoch.toString(),
    title: title,
    body: body,
    timestamp: DateTime.now(),
    orderId: orderId,
  );

  const storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );
  final data = await storage.read(key: 'notifications_history_v1');
  List<NotificationModel> list = [];
  if (data != null) {
    try {
      final List decoded = jsonDecode(data);
      list = decoded.map((e) => NotificationModel.fromJson(e)).toList();
    } catch (_) {}
  }
  
  // Prevent duplicate IDs
  if (!list.any((n) => n.id == notification.id)) {
    list.insert(0, notification);
    if (list.length > 50) list.removeLast();
    await storage.write(key: 'notifications_history_v1', value: jsonEncode(list.map((e) => e.toJson()).toList()));
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  try {
    await Firebase.initializeApp(
      options: const FirebaseOptions(
        apiKey: 'AIzaSyCmsdZtC_Uld2WuG4clHJA5DNmy_lsfUn0',
        appId: '1:340044289106:android:600b27e8c6a4f13446fb8b',
        messagingSenderId: '340044289106',
        projectId: 'wooexpress',
        databaseURL: 'https://wooexpress-default-rtdb.asia-southeast1.firebasedatabase.app',
      ),
    );
    if (!kIsWeb) {
      FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
    }
  } catch (e) {
    print('Firebase Init Error: $e');
  }

  final container = ProviderContainer();
  
  // Initialize FCM Service (Skip on Web)
  if (!kIsWeb) {
    container.read(fcmServiceProvider).initialize();
  }

  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const WooPressApp(),
    ),
  );
}

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

class WooPressApp extends ConsumerWidget {
  const WooPressApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    
    return MaterialApp.router(
      routerConfig: router,
      title: 'WooPress',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.light,
      theme: FlexThemeData.light(
        scheme: FlexScheme.blue,
        surfaceMode: FlexSurfaceMode.highSurfaceLowScaffold,
        blendLevel: 0,
        appBarStyle: FlexAppBarStyle.background,
        bottomAppBarElevation: 0.0,
        scaffoldBackground: const Color(0xFFF5F5F7), // Apple-like light gray
        surface: const Color(0xFFFFFFFF),
        onSurface: const Color(0xFF000000),
        primary: const Color(0xFF000000),
        onPrimary: const Color(0xFFFFFFFF),
        typography: Typography.material2021(),
        useMaterial3: true,
      ).copyWith(
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFFFFFFFF),
          elevation: 0,
          centerTitle: false,
          iconTheme: IconThemeData(color: Colors.black),
          titleTextStyle: TextStyle(
            color: Colors.black,
            fontSize: 28,
            fontWeight: FontWeight.w900,
            letterSpacing: -1.0,
          ),
        ),
      ),
    );
  }
}
