import 'package:flutter/material.dart';

import '../../../../data/models/ride_type.dart';

class RideTypeSelector extends StatelessWidget {
  const RideTypeSelector({
    super.key,
    required this.selectedType,
    required this.passengerCount,
    required this.eTrikeFare,
    required this.eTuktukFare,
    required this.eTrikeEnabled,
    required this.eTuktukEnabled,
    required this.onSelected,
  });

  final RideType selectedType;
  final int passengerCount;
  final String eTrikeFare;
  final String eTuktukFare;
  final bool eTrikeEnabled;
  final bool eTuktukEnabled;
  final ValueChanged<RideType>? onSelected;

  bool _isEnabled(RideType type) {
    final configured = switch (type) {
      RideType.eTrike => eTrikeEnabled,
      RideType.eTuktuk => eTuktukEnabled,
    };
    return configured && type.canCarry(passengerCount);
  }

  @override
  Widget build(BuildContext context) {
    final eTrikeAvailable = _isEnabled(RideType.eTrike);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Choose your ride',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 4),
        Text(
          'Select your E-Trike type. Your fare and matched driver follow this selection.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _RideTypeCard(
                type: RideType.eTrike,
                price: eTrikeFare,
                selected: selectedType == RideType.eTrike,
                enabled: eTrikeAvailable && onSelected != null,
                unavailableReason: eTrikeEnabled
                    ? 'For up to 2 riders'
                    : 'Unavailable',
                onTap: () => onSelected!(RideType.eTrike),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _RideTypeCard(
                type: RideType.eTuktuk,
                price: eTuktukFare,
                selected: selectedType == RideType.eTuktuk,
                enabled: _isEnabled(RideType.eTuktuk) && onSelected != null,
                unavailableReason: eTuktukEnabled
                    ? 'For up to 4 riders'
                    : 'Unavailable',
                onTap: () => onSelected!(RideType.eTuktuk),
              ),
            ),
          ],
        ),
        if (!eTrikeAvailable && passengerCount >= 3) ...[
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.info_outline_rounded,
                size: 16,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'E-Trike XL is selected for $passengerCount riders. '
                  'E-Trike Regular has a maximum capacity of 2.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

class _RideTypeCard extends StatelessWidget {
  const _RideTypeCard({
    required this.type,
    required this.price,
    required this.selected,
    required this.enabled,
    required this.unavailableReason,
    required this.onTap,
  });

  final RideType type;
  final String price;
  final bool selected;
  final bool enabled;
  final String unavailableReason;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final baseColor = colors.surfaceContainerHigh;
    final background = selected
        ? Color.alphaBlend(colors.primary.withValues(alpha: 0.10), baseColor)
        : baseColor;
    final borderColor = selected ? colors.primary : colors.outlineVariant;
    final assetPath = type.assetPathFor(Theme.of(context).brightness);

    return Semantics(
      button: true,
      selected: selected,
      enabled: enabled,
      label:
          '${type.label}, $price, maximum ${type.maximumPassengers} passengers',
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 180),
        opacity: enabled ? 1 : 0.52,
        child: Material(
          color: background,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: borderColor, width: selected ? 2 : 1.2),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: enabled ? onTap : null,
            child: SizedBox(
              height: 182,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            type.selectorLabel,
                            maxLines: 1,
                            style: Theme.of(context).textTheme.labelLarge,
                          ),
                        ),
                        AnimatedSwitcher(
                          duration: const Duration(milliseconds: 160),
                          child: selected
                              ? Icon(
                                  Icons.check_circle_rounded,
                                  key: const ValueKey('selected'),
                                  size: 19,
                                  color: colors.primary,
                                )
                              : Icon(
                                  Icons.radio_button_unchecked_rounded,
                                  key: const ValueKey('unselected'),
                                  size: 19,
                                  color: colors.onSurfaceVariant,
                                ),
                        ),
                      ],
                    ),
                    Expanded(
                      child: ClipRect(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: AnimatedScale(
                            scale: selected ? 1.03 : 1,
                            duration: const Duration(milliseconds: 180),
                            curve: Curves.easeOutCubic,
                            child: Image.asset(
                              assetPath,
                              key: ValueKey(assetPath),
                              width: double.infinity,
                              fit: BoxFit.contain,
                              semanticLabel: '${type.label} vehicle',
                              filterQuality: FilterQuality.medium,
                            ),
                          ),
                        ),
                      ),
                    ),
                    Text(
                      price,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: colors.onSurface,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        Icon(
                          Icons.people_outline_rounded,
                          size: 14,
                          color: colors.onSurfaceVariant,
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            unavailableReason,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
                                  fontSize: 10.5,
                                  color: colors.onSurfaceVariant,
                                ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
