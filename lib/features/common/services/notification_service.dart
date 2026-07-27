import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../../../app/router.dart';
import '../../../app/routes.dart';
import '../../../config/firebase_options.dart';
import '../../../data/models/booking_call_session.dart';
import '../../../data/repositories/booking_voice_call_repository.dart';
import 'ringtone_service.dart';

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  // Notification payloads are displayed by Android. Durable state is read
  // from Firestore when the app is opened.
}

class NotificationService {
  NotificationService._();
  static final instance = NotificationService._();

  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();
  StreamSubscription<String>? _tokenSubscription;
  StreamSubscription<RemoteMessage>? _messageSubscription;
  StreamSubscription<RemoteMessage>? _tapSubscription;
  StreamSubscription<User?>? _authSubscription;
  StreamSubscription<BookingCallSession?>? _incomingCallSubscription;
  bool _initialized = false;
  String? _userId;
  String? _lastOpenedCallId;
  Map<Object?, Object?>? _pendingIncomingData;
  int _notificationId = 0;

  static const _bookingChannel = AndroidNotificationChannel(
    'booking_updates',
    'Booking updates',
    description: 'Booking and active ride updates',
    importance: Importance.high,
    sound: RawResourceAndroidNotificationSound('booking_ringtone'),
  );
  static const _chatChannel = AndroidNotificationChannel(
    'chat_messages',
    'Chat messages',
    description: 'Ride chat messages',
    importance: Importance.high,
    sound: RawResourceAndroidNotificationSound('chat_ringtone'),
  );
  static const _callChannel = AndroidNotificationChannel(
    'incoming_calls_v2',
    'Incoming calls',
    description: 'Incoming ride calls',
    importance: Importance.max,
    sound: RawResourceAndroidNotificationSound('call_ringtone'),
  );
  int? _activeIncomingNotificationId;

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;
    await _initializeLocalNotifications();
    await _messaging.requestPermission(alert: true, badge: true, sound: true);
    _messageSubscription = FirebaseMessaging.onMessage.listen(
      _showForegroundNotification,
    );
    _tapSubscription = FirebaseMessaging.onMessageOpenedApp.listen(_handleTap);
    final initial = await _messaging.getInitialMessage();
    if (initial != null) _handleTap(initial);
    _authSubscription = FirebaseAuth.instance.authStateChanges().listen((user) {
      if (user == null) {
        clearUser();
      } else {
        syncUser(user.uid);
      }
    });
    _tokenSubscription = _messaging.onTokenRefresh.listen((token) {
      final userId = _userId;
      if (userId != null) _saveToken(userId, token);
    });
  }

  Future<void> _initializeLocalNotifications() async {
    const settings = InitializationSettings(
      android: AndroidInitializationSettings('ic_stat_voltrike'),
    );
    await _localNotifications.initialize(
      settings: settings,
      onDidReceiveNotificationResponse: (response) {
        final payload = response.payload;
        if (payload == null || payload.isEmpty) return;
        final value = jsonDecode(payload);
        if (value is Map) {
          _scheduleData(Map<Object?, Object?>.from(value));
        }
      },
    );
    final android = _localNotifications
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    await android?.createNotificationChannel(_bookingChannel);
    await android?.createNotificationChannel(_chatChannel);
    await android?.createNotificationChannel(_callChannel);
    final launchDetails = await _localNotifications
        .getNotificationAppLaunchDetails();
    final payload = launchDetails?.notificationResponse?.payload;
    if (launchDetails?.didNotificationLaunchApp == true &&
        payload != null &&
        payload.isNotEmpty) {
      final value = jsonDecode(payload);
      if (value is Map) _scheduleData(Map<Object?, Object?>.from(value));
    }
  }

  Future<void> _showForegroundNotification(RemoteMessage message) async {
    final type = message.data['type'];
    if (type == 'booking_offer' || type == 'driverAssigned') {
      unawaited(RingtoneService.instance.playBooking());
    } else if (type == 'chat_message') {
      unawaited(RingtoneService.instance.playChat());
    }
    final notification = message.notification;
    final title = notification?.title ?? 'VolTrike update';
    final body = notification?.body ?? 'You have a ride update.';
    final notificationId = _notificationId++;
    if (type == 'incoming_call') {
      final previousId = _activeIncomingNotificationId;
      if (previousId != null) {
        await _localNotifications.cancel(id: previousId);
      }
      _activeIncomingNotificationId = notificationId;
    }
    await _localNotifications.show(
      id: notificationId,
      title: title,
      body: body,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          _channelFor(type).id,
          _channelFor(type).name,
          channelDescription: _channelFor(type).description,
          importance: Importance.high,
          priority: Priority.high,
          icon: 'ic_stat_voltrike',
          playSound: false,
        ),
      ),
      payload: jsonEncode(message.data),
    );
    if (type == 'incoming_call') {
      _scheduleData(message.data);
    }
  }

  Future<void> syncUser(String userId) async {
    _userId = userId;
    final pendingIncomingData = _pendingIncomingData;
    _pendingIncomingData = null;
    if (pendingIncomingData != null) {
      _scheduleData(pendingIncomingData);
    }
    final token = await _messaging.getToken();
    if (token != null) await _saveToken(userId, token);
    await _incomingCallSubscription?.cancel();
    _incomingCallSubscription = BookingVoiceCallRepository()
        .watchIncomingCall(userId)
        .listen(
          (session) {
            if (session == null ||
                session.effectiveStatus() != BookingCallStatus.ringing) {
              unawaited(_stopIncomingCallAlert());
              return;
            }
            _scheduleData({
              'bookingId': session.bookingId,
              'callId': session.callId,
              'type': 'incoming_call',
            });
          },
          onError: (_) {
            // FCM remains available while Firestore reconnects its listener.
          },
        );
  }

  Future<void> clearUser() async {
    final userId = _userId;
    await _incomingCallSubscription?.cancel();
    _incomingCallSubscription = null;
    await _stopIncomingCallAlert();
    _lastOpenedCallId = null;
    _pendingIncomingData = null;
    final token = await _messaging.getToken();
    if (userId != null && token != null) {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .collection('devices')
          .doc(token)
          .delete();
    }
    _userId = null;
  }

  Future<void> _saveToken(String userId, String token) {
    return FirebaseFirestore.instance
        .collection('users')
        .doc(userId)
        .collection('devices')
        .doc(token)
        .set({
          'token': token,
          'platform': 'android',
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
  }

  void _handleTap(RemoteMessage message) {
    _scheduleData(message.data);
  }

  void _scheduleData(Map<Object?, Object?> data) {
    WidgetsBinding.instance.addPostFrameCallback((_) => _navigateData(data));
  }

  void _navigateData(Map<Object?, Object?> data) {
    final bookingId = data['bookingId'] as String?;
    if (bookingId == null || bookingId.isEmpty) return;
    final target = data['target'] as String?;
    final type = data['type'] as String?;
    if (target == 'driver' && type == 'booking_offer') {
      appRouter.go(AppRoutes.driverHome);
      return;
    }
    if (type == 'incoming_call') {
      unawaited(_cancelIncomingCallNotification());
      if (_userId == null) {
        _pendingIncomingData = Map<Object?, Object?>.from(data);
        return;
      }
      final callId = data['callId'] as String?;
      if (callId != null && callId == _lastOpenedCallId) return;
      _lastOpenedCallId = callId;
      appRouter.push(
        AppRoutes.incomingBookingCall,
        extra: {'bookingId': bookingId, 'callId': callId},
      );
      return;
    }
    appRouter.go(
      target == 'driver'
          ? AppRoutes.driverBookingTracking
          : AppRoutes.driverTracking,
      extra: bookingId,
    );
  }

  Future<void> dispose() async {
    await _tokenSubscription?.cancel();
    await _messageSubscription?.cancel();
    await _tapSubscription?.cancel();
    await _authSubscription?.cancel();
    await _incomingCallSubscription?.cancel();
    await _stopIncomingCallAlert();
    await RingtoneService.instance.dispose();
  }

  Future<void> _cancelIncomingCallNotification() async {
    final notificationId = _activeIncomingNotificationId;
    _activeIncomingNotificationId = null;
    if (notificationId != null) {
      await _localNotifications.cancel(id: notificationId);
    }
  }

  Future<void> _stopIncomingCallAlert() async {
    await RingtoneService.instance.stopIncomingCall();
    await _cancelIncomingCallNotification();
  }

  AndroidNotificationChannel _channelFor(Object? type) {
    return switch (type) {
      'chat_message' => _chatChannel,
      'incoming_call' => _callChannel,
      _ => _bookingChannel,
    };
  }
}
