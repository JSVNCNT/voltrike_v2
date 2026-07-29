import 'package:flutter/material.dart';

import '../../theme/app_radius.dart';

class BookingCard extends StatelessWidget {
  const BookingCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.price,
    this.leading,
    this.trailing,
    this.footer,
    this.status,
    this.onTap,
  });

  final String title;
  final String subtitle;
  final String price;

  final Widget? leading;
  final Widget? trailing;
  final Widget? footer;

  final String? status;

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final leadingWidget = leading;
    final trailingWidget = trailing;
    final footerWidget = footer;
    final statusText = status;

    return Card(
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        side: BorderSide(color: colorScheme.outlineVariant),
      ),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  if (leadingWidget != null) ...[
                    leadingWidget,
                    const SizedBox(width: 14),
                  ],

                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: textTheme.titleMedium,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),

                        const SizedBox(height: 4),

                        Text(
                          subtitle,
                          style: textTheme.bodyMedium,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),

                  // ignore: use_null_aware_elements
                  if (trailingWidget != null) trailingWidget,
                ],
              ),

              if (statusText != null && statusText.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  statusText,
                  style: textTheme.bodyMedium?.copyWith(
                    color: colorScheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],

              const SizedBox(height: 18),

              Row(
                children: [
                  Text(
                    price,
                    style: textTheme.titleLarge?.copyWith(
                      color: colorScheme.primary,
                    ),
                  ),

                  const Spacer(),

                  Icon(
                    Icons.chevron_right_rounded,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ],
              ),

              if (footerWidget != null) ...[
                const SizedBox(height: 18),
                footerWidget,
              ],
            ],
          ),
        ),
      ),
    );
  }
}
