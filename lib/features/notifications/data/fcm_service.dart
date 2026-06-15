import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../../../../core/storage/secure_storage.dart';
import '../../dashboard/presentation/providers/dashboard_controller.dart';
import '../../orders/presentation/providers/orders_controller.dart';
import '../domain/models/notification_model.dart';
import '../presentation/providers/notifications_controller.dart';
import '../../../main.dart';
import '../../orders/presentation/screens/orders_screen.dart';

import 'package:firebase_messaging/firebase_messaging.dart';

final fcmServiceProvider = Provider<FCMService>((ref) {
  return FCMService(ref);
});

class FCMService {
  final Ref _ref;
  final FlutterLocalNotificationsPlugin _localNotifications = FlutterLocalNotificationsPlugin();
  
  FCMService(this._ref);

  FirebaseMessaging get _messaging => FirebaseMessaging.instance;

  Future<void> initialize() async {
    // 0. Initialize Local Notifications for foreground alerts
    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('ic_notification');
    const InitializationSettings initializationSettings =
        InitializationSettings(android: initializationSettingsAndroid);
    
    await _localNotifications.initialize(
      settings: initializationSettings,
      onDidReceiveNotificationResponse: (NotificationResponse response) {
        final orderIdStr = response.payload;
        _navigateToOrders(orderId: orderIdStr != null ? int.tryParse(orderIdStr) : null);
      },
    );

    // Create the persistent notification channel for background sounds
    const AndroidNotificationChannel channel = AndroidNotificationChannel(
      'sales_alerts_v2', // Incremented for fresh registration
      'Sales Alerts',
      description: 'Notifications for new store orders',
      importance: Importance.max,
      playSound: true,
      enableVibration: true,
      enableLights: true,
      showBadge: true,
      sound: RawResourceAndroidNotificationSound('cash_register'),
    );

    await _localNotifications
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);

    // 1. Request permission
    NotificationSettings settings = await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      provisional: false,
    );

    if (settings.authorizationStatus == AuthorizationStatus.authorized) {
      // 2. Token & Topic setup
      await reSyncNotifications();

      // 3. App opened from terminated state via notification
      RemoteMessage? initialMessage = await _messaging.getInitialMessage();
      if (initialMessage != null) {
        final orderIdStr = initialMessage.data['order_id'];
        _navigateToOrders(orderId: orderIdStr != null ? int.tryParse(orderIdStr.toString()) : null);
      }

      // 4. App in background but opened via notification tap
      FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
        final orderIdStr = message.data['order_id'];
        _navigateToOrders(orderId: orderIdStr != null ? int.tryParse(orderIdStr.toString()) : null);
      });

      // 5. Listen for foreground messages
      FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        HapticFeedback.heavyImpact();
        
        final title = message.notification?.title ?? message.data['title'] ?? "New Order Received";
        final body = message.notification?.body ?? message.data['body'] ?? "Check your dashboard for details.";
        final orderId = message.data['order_id']?.toString();

        final notificationModel = NotificationModel(
          id: message.messageId ?? DateTime.now().millisecondsSinceEpoch.toString(),
          title: title,
          body: body,
          timestamp: DateTime.now(),
          orderId: orderId,
        );

        _localNotifications.show(
          id: message.hashCode,
          title: title,
          body: body,
          payload: orderId,
          notificationDetails: const NotificationDetails(
            android: AndroidNotificationDetails(
              'sales_alerts_v2',
              'Sales Alerts',
              importance: Importance.max,
              priority: Priority.high,
              playSound: true,
              enableVibration: true,
              enableLights: true,
              icon: 'ic_notification',
            ),
          ),
        );

        Future.delayed(const Duration(milliseconds: 500), () {
          _ref.read(notificationsControllerProvider.notifier).addNotification(notificationModel);
          _ref.read(dashboardControllerProvider.notifier).refresh();
          _ref.read(ordersControllerProvider.notifier).refresh();
        });
      });

      // 6. Listen for Token Refreshes (CRITICAL FOR APP UPDATES)
      _messaging.onTokenRefresh.listen((newToken) async {
        debugPrint("FCM Token Refreshed. Triggering Auto-Sync.");
        await reSyncNotifications();
      });

    }
  }

  Future<void> reSyncNotifications() async {
    final storage = _ref.read(secureStorageProvider);
    try {
      final token = await _messaging.getToken();
      if (token != null) {
        await storage.write(key: 'fcm_token', value: token);
        
        String? baseUrl = await storage.read(key: 'baseUrl');
        if (baseUrl == null) {
          final domain = await storage.read(key: 'store_domain');
          if (domain != null) baseUrl = 'https://$domain';
        }
        
        if (baseUrl != null) {
          await subscribeToStore(baseUrl);
        } else {
          await storage.write(key: 'last_fcm_topic', value: 'ERROR: No Domain Found');
        }
      } else {
        await storage.write(key: 'last_fcm_topic', value: 'ERROR: Null FCM Token');
      }
    } catch (e) {
      final errorMsg = "ERROR: ${e.toString().split(':').last.trim()}";
      await storage.write(key: 'last_fcm_topic', value: errorMsg);
      debugPrint("FCM Sync Error: $e");
    }
  }

  /// Dynamically subscribe to a specific store's notification channel
  Future<void> subscribeToStore(String baseUrl) async {
    final storage = _ref.read(secureStorageProvider);
    try {
      // 1. Unsubscribe from the last known store topic
      final lastTopic = await storage.read(key: 'last_fcm_topic');
      if (lastTopic != null && !lastTopic.startsWith("ERROR")) {
        await _messaging.unsubscribeFromTopic(lastTopic).timeout(const Duration(seconds: 5));
        debugPrint("FCM Unsubscribed from: $lastTopic");
      }

      // 2. Robust Domain Extraction (Stripping www. for consistency)
      String domain = baseUrl;
      if (domain.contains("://")) {
        domain = Uri.parse(domain).host;
      } else {
        domain = domain.split('/')[0];
      }
      
      if (domain.startsWith("www.")) {
        domain = domain.substring(4);
      }
      
      if (domain.isEmpty) throw Exception("Invalid Store URL");

      final sanitizedTopic = "orders_" + domain.replaceAll('.', '_').replaceAll('-', '_');
      
      // 3. Subscribe to the new channel
      await _messaging.subscribeToTopic(sanitizedTopic).timeout(const Duration(seconds: 10));
      await storage.write(key: 'last_fcm_topic', value: sanitizedTopic);
      
      debugPrint("FCM Subscribed to Dynamic Topic: $sanitizedTopic");
    } catch (e) {
      final errorMsg = "ERROR: ${e.toString().split(':').last.trim()}";
      await storage.write(key: 'last_fcm_topic', value: errorMsg);
      debugPrint("FCM Subscription Error: $e");
    }
  }

  void _navigateToOrders({int? orderId}) {
    if (navigatorKey.currentState != null) {
      navigatorKey.currentState?.push(
        MaterialPageRoute(builder: (_) => OrdersScreen(openOrderId: orderId)),
      );
    } else {
      // Delay and retry if app is still booting
      Future.delayed(const Duration(milliseconds: 500), () {
        _navigateToOrders(orderId: orderId);
      });
    }
  }
}
