import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

/// ===========================================================================
/// Profile Avatar
///
/// Shared avatar widget used throughout the application.
///
/// Used by:
/// • Passenger
/// • Driver
/// • Profile
/// • Drawer
/// • Booking
/// • Trip
/// ===========================================================================
class ProfileAvatar extends StatelessWidget {
  const ProfileAvatar({
    super.key,
    this.imageUrl,
    this.radius = 28,
    this.showBorder = false,
    this.onTap,
  });

  final String? imageUrl;

  final double radius;

  final bool showBorder;

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    Widget avatar = CircleAvatar(
      radius: radius,
      backgroundColor:
          Theme.of(context).colorScheme.surfaceContainerHighest,
      backgroundImage: imageUrl != null &&
              imageUrl!.isNotEmpty
          ? CachedNetworkImageProvider(
              imageUrl!,
            )
          : null,
      child: imageUrl == null || imageUrl!.isEmpty
          ? Icon(
              Icons.person,
              size: radius,
            )
          : null,
    );

    if (showBorder) {
      avatar = Container(
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: Theme.of(context)
                .colorScheme
                .primary,
            width: 2,
          ),
        ),
        child: avatar,
      );
    }

    if (onTap != null) {
      avatar = InkWell(
        borderRadius:
            BorderRadius.circular(radius * 2),
        onTap: onTap,
        child: avatar,
      );
    }

    return avatar;
  }
}