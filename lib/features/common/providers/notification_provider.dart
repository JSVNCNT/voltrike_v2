import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

/// ===========================================================================
/// Notification Count Provider
///
/// Stores the unread notification count.
///
/// Later this will be synchronized with
/// Firebase Cloud Messaging.
/// ===========================================================================
final notificationCountProvider =
    StateProvider<int>(
  (ref) => 0,
);

/// ===========================================================================
/// Has Notifications Provider
///
/// Convenience provider used for badges.
/// ===========================================================================
final hasNotificationsProvider =
    Provider<bool>(
  (ref) =>
      ref.watch(notificationCountProvider) > 0,
);