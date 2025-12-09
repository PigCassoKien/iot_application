import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'app.dart';
import 'core/firebase_options.dart';
import 'features/clothesline/data/auto_controller.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'features/clothesline/data/firebase_service.dart';

// Background message handler must be a top-level function
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  // handle background message if needed
}

final FlutterLocalNotificationsPlugin _localNotifications = FlutterLocalNotificationsPlugin();
const AndroidNotificationChannel _channel = AndroidNotificationChannel(
  'clothesline_channel',
  'Clothesline Notifications',
  description: 'Thông báo từ hệ thống giàn phơi',
  importance: Importance.high,
);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (kIsWeb) {
    // If the web page already initialized Firebase (via `index.html`),
    // attaching to the existing app via `Firebase.app()` is the safest
    // option. If no app exists yet, initialize with concrete options
    // (provided by `DefaultFirebaseOptions`). This avoids creating a
    // default app with null options which causes assertion failures.
    try {
      // Prefer attaching to an existing default app.
      Firebase.app();
    } catch (e) {
      // If there is no existing app, initialize using the web options.
      await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
    }
  } else {
    await Firebase.initializeApp();
  }

  // Initialize local notification channel (Android)
  await _localNotifications.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(_channel);

  // Set background message handler
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

  runApp(const SmartClotheslineApp());

  // Start the auto controller to listen for sensor updates and act.
  AutoController().start();

  // FCM: request permission (iOS), get token, register
  final fcm = FirebaseMessaging.instance;
  await fcm.requestPermission();
  final token = await fcm.getToken();
  if (token != null) {
    await FirebaseService().registerDeviceToken(token);
  }

  // Foreground message handling -> show local notification
  FirebaseMessaging.onMessage.listen((RemoteMessage msg) {
    final notif = msg.notification;
    if (notif == null) return;
    _localNotifications.show(
      notif.hashCode,
      notif.title,
      notif.body,
      NotificationDetails(
        android: AndroidNotificationDetails(_channel.id, _channel.name, channelDescription: _channel.description, icon: '@mipmap/ic_launcher'),
      ),
    );
  });
  FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage msg) {
    // optionally navigate based on message
  });
}

// Firebase messaging helper (removed). The project already contains
// `lib/features/clothesline/data/firebase_service.dart` with
// `registerDeviceToken()`; restore client-side FCM logic when ready.