import 'package:firebase_messaging/firebase_messaging.dart';

/// ===========================================================================
/// Notification Service
///
/// Wrapper around Firebase Cloud Messaging.
///
/// Responsibilities:
/// • Request notification permission
/// • Retrieve FCM token
/// • Refresh FCM token
/// • Listen for foreground notifications
/// • Background notifications (configured elsewhere)
/// ===========================================================================
class NotificationService {
  NotificationService._();

  static final NotificationService instance =
      NotificationService._();

  final FirebaseMessaging _messaging =
      FirebaseMessaging.instance;

  /// =========================================================================
  /// Initialize Notifications
  /// =========================================================================

  Future<void> initialize() async {
    await _messaging.requestPermission();

    await _messaging.getToken();

    FirebaseMessaging.onMessage.listen(
      _handleForegroundMessage,
    );

    FirebaseMessaging.onMessageOpenedApp.listen(
      _handleNotificationTap,
    );
  }

  /// =========================================================================
  /// Current FCM Token
  /// =========================================================================

  Future<String?> getToken() {
    return _messaging.getToken();
  }

  /// =========================================================================
  /// Token Refresh
  /// =========================================================================

  Stream<String> get tokenRefreshStream =>
      _messaging.onTokenRefresh;

  /// =========================================================================
  /// Foreground Notification
  /// =========================================================================

  void _handleForegroundMessage(
    RemoteMessage message,
  ) {
    // Show in-app notification/snackbar.
  }

  /// =========================================================================
  /// Notification Tap
  /// =========================================================================

  void _handleNotificationTap(
    RemoteMessage message,
  ) {

    // Navigate to the appropriate screen.
  }
} 