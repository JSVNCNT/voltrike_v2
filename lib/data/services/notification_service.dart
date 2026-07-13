import 'package:firebase_messaging/firebase_messaging.dart';

class NotificationService {
  NotificationService._();

  static final NotificationService instance =
      NotificationService._();

  final FirebaseMessaging _messaging =
      FirebaseMessaging.instance;

  Future<void> initialize() async {
    await requestPermission();
  }

  Future<NotificationSettings> requestPermission() {
    return _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );
  }

  Future<String?> getToken() {
    return _messaging.getToken();
  }

  Stream<RemoteMessage> get foregroundMessages =>
      FirebaseMessaging.onMessage;

  Stream<RemoteMessage> get openedAppMessages =>
      FirebaseMessaging.onMessageOpenedApp;

  Future<void> subscribe(
    String topic,
  ) {
    return _messaging.subscribeToTopic(topic);
  }

  Future<void> unsubscribe(
    String topic,
  ) {
    return _messaging.unsubscribeFromTopic(topic);
  }
}