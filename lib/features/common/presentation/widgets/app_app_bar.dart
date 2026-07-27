import 'package:flutter/material.dart';

/// ===========================================================================
/// App App Bar
///
/// Shared AppBar for the mobile application.
///
/// Used by:
/// • Passenger
/// • Driver
///
/// Can optionally display notification and profile actions.
/// ===========================================================================
class AppAppBar extends StatelessWidget
    implements PreferredSizeWidget {
  const AppAppBar({
    super.key,
    required this.title,
    this.showNotifications = false,
    this.showProfile = false,
    this.onNotificationPressed,
    this.onProfilePressed,
    this.leading,
    this.actions = const [],
    this.centerTitle = false,
  });

  final String title;

  final bool showNotifications;

  final bool showProfile;

  final VoidCallback? onNotificationPressed;

  final VoidCallback? onProfilePressed;
  final Widget? leading;
  final List<Widget> actions;
  final bool centerTitle;

  @override
  Size get preferredSize =>
      const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    return AppBar(
      centerTitle: centerTitle,
      elevation: 0,
      leading: leading,
      title: Text(title),
      actions: [
        if (showNotifications)
          IconButton(
            icon: const Icon(
              Icons.notifications_outlined,
            ),
            onPressed: onNotificationPressed,
          ),
        if (showProfile)
          IconButton(
            icon: const Icon(
              Icons.account_circle_outlined,
            ),
            onPressed: onProfilePressed,
          ),
        ...actions,
      ],
    );
  }
}
