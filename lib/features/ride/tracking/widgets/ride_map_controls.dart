import 'package:flutter/material.dart';

class RideMapControls extends StatelessWidget {
  const RideMapControls({
    super.key,
    this.onMyLocation,
    this.onFollowDriver,
    this.onZoomIn,
    this.onZoomOut,
    this.isFollowingDriver = true,
  });

  final VoidCallback? onMyLocation;
  final VoidCallback? onFollowDriver;
  final VoidCallback? onZoomIn;
  final VoidCallback? onZoomOut;

  final bool isFollowingDriver;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Align(
        alignment: Alignment.centerRight,
        child: Padding(
          padding: const EdgeInsets.only(right: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _MapControlButton(
                icon: Icons.my_location,
                tooltip: 'My Location',
                onPressed: onMyLocation,
              ),

              const SizedBox(height: 12),

              _MapControlButton(
                icon: isFollowingDriver
                    ? Icons.navigation
                    : Icons.navigation_outlined,
                tooltip: 'Follow Driver',
                onPressed: onFollowDriver,
              ),

              const SizedBox(height: 12),

              _MapControlButton(
                icon: Icons.add,
                tooltip: 'Zoom In',
                onPressed: onZoomIn,
              ),

              const SizedBox(height: 12),

              _MapControlButton(
                icon: Icons.remove,
                tooltip: 'Zoom Out',
                onPressed: onZoomOut,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MapControlButton extends StatelessWidget {
  const _MapControlButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 3,
      borderRadius: BorderRadius.circular(16),
      child: IconButton.filledTonal(
        tooltip: tooltip,
        onPressed: onPressed,
        icon: Icon(icon),
      ),
    );
  }
}