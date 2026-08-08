import 'package:flutter/material.dart';

import '../../../../core/widgets/cards/app_card.dart';
import 'adaptive_participant_name.dart';

class ProfileIdentityHeader extends StatelessWidget {
  const ProfileIdentityHeader({
    super.key,
    required this.name,
    required this.subtitle,
    this.photoUrl,
    this.statusLabel,
    this.statusColor,
  });

  final String name;
  final String subtitle;
  final String? photoUrl;
  final String? statusLabel;
  final Color? statusColor;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final image = photoUrl?.trim();
    return AppCard(
      margin: EdgeInsets.zero,
      padding: const EdgeInsets.all(20),
      accentColor: colorScheme.primary,
      tintColor: colorScheme.primary,
      child: Column(
        children: [
          CircleAvatar(
            radius: 48,
            backgroundColor: colorScheme.primaryContainer,
            foregroundImage: image?.isNotEmpty == true
                ? NetworkImage(image!)
                : null,
            child: image?.isNotEmpty == true
                ? null
                : Icon(
                    Icons.person_outline_rounded,
                    size: 48,
                    color: colorScheme.onPrimaryContainer,
                  ),
          ),
          const SizedBox(height: 14),
          AdaptiveParticipantName(
            name: name,
            textAlign: TextAlign.center,
            style:
                Theme.of(context).textTheme.titleLarge?.copyWith(height: 1.2) ??
                const TextStyle(fontSize: 22, height: 1.2),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          if (statusLabel != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                color: (statusColor ?? colorScheme.primary).withValues(
                  alpha: 0.1,
                ),
                borderRadius: BorderRadius.circular(100),
                border: Border.all(
                  color: (statusColor ?? colorScheme.primary).withValues(
                    alpha: 0.78,
                  ),
                ),
              ),
              child: Text(
                statusLabel!,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: statusColor ?? colorScheme.primary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class ProfileSection extends StatelessWidget {
  const ProfileSection({
    super.key,
    required this.title,
    required this.children,
  });

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Text(title, style: Theme.of(context).textTheme.titleMedium),
        ),
        const SizedBox(height: 10),
        AppCard(
          margin: EdgeInsets.zero,
          padding: EdgeInsets.zero,
          accentColor: Theme.of(context).colorScheme.primary,
          accentEdge: AppCardAccentEdge.leading,
          tintColor: Theme.of(context).colorScheme.primary,
          child: Padding(
            padding: const EdgeInsets.only(left: 4),
            child: Column(
              children: [
                for (var index = 0; index < children.length; index++) ...[
                  children[index],
                  if (index < children.length - 1) const Divider(),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class ProfileInfoTile extends StatelessWidget {
  const ProfileInfoTile({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    this.iconColor,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    final resolvedIconColor =
        iconColor ?? Theme.of(context).colorScheme.primary;
    return ListTile(
      minTileHeight: 64,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: resolvedIconColor.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, color: resolvedIconColor, size: 21),
      ),
      title: Text(label),
      subtitle: Text(value),
    );
  }
}
