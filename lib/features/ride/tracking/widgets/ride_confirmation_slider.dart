import 'dart:async';

import 'package:flutter/material.dart';

import '../models/ride_action.dart';

/// A guarded driver transition control that requires a deliberate full swipe.
class RideConfirmationSlider extends StatefulWidget {
  const RideConfirmationSlider({
    super.key,
    required this.action,
    required this.onConfirmed,
    this.isLoading = false,
    this.enabled = true,
  });

  final RidePrimaryAction action;
  final FutureOr<void> Function() onConfirmed;
  final bool isLoading;
  final bool enabled;

  @override
  State<RideConfirmationSlider> createState() => _RideConfirmationSliderState();
}

class _RideConfirmationSliderState extends State<RideConfirmationSlider> {
  static const _thumbSize = 50.0;
  static const _completionThreshold = 0.88;

  double _progress = 0;
  bool _confirming = false;
  bool _dragging = false;

  bool get _enabled => widget.enabled && !widget.isLoading && !_confirming;

  void _setProgress(double localX, double width) {
    if (!_enabled || !_dragging) return;
    final travel = width - _thumbSize;
    if (travel <= 0) return;
    setState(() {
      _progress = ((localX - (_thumbSize / 2)) / travel).clamp(0.0, 1.0);
    });
  }

  void _startDrag(double localX, double width) {
    if (!_enabled || localX > _thumbSize + 12) return;
    _dragging = true;
    _setProgress(localX, width);
  }

  Future<void> _finishDrag() async {
    if (!_enabled || !_dragging) return;
    _dragging = false;
    if (_progress < _completionThreshold) {
      setState(() => _progress = 0);
      return;
    }
    await _confirm();
  }

  Future<void> _confirm() async {
    if (!_enabled) return;
    setState(() {
      _confirming = true;
      _progress = 1;
    });
    try {
      await widget.onConfirmed();
    } finally {
      if (mounted) {
        setState(() {
          _confirming = false;
          _progress = 0;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.action == RidePrimaryAction.none) {
      return const SizedBox.shrink();
    }

    final colorScheme = Theme.of(context).colorScheme;
    final label = _sliderLabel(widget.action);

    return Semantics(
      button: true,
      enabled: _enabled,
      label: label,
      hint: 'Swipe all the way to confirm',
      onTap: _enabled ? _confirm : null,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final thumbLeft = _progress * (width - _thumbSize);
          final fillWidth = _thumbSize + (_progress * (width - _thumbSize));

          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onHorizontalDragStart: _enabled
                ? (details) => _startDrag(details.localPosition.dx, width)
                : null,
            onHorizontalDragUpdate: _enabled
                ? (details) => _setProgress(details.localPosition.dx, width)
                : null,
            onHorizontalDragEnd: _enabled ? (_) => _finishDrag() : null,
            onHorizontalDragCancel: _enabled
                ? () {
                    _dragging = false;
                    setState(() => _progress = 0);
                  }
                : null,
            child: SizedBox(
              height: 58,
              child: Stack(
                alignment: Alignment.centerLeft,
                children: [
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(100),
                        border: Border.all(
                          color: colorScheme.primary.withValues(alpha: 0.24),
                        ),
                      ),
                    ),
                  ),
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 90),
                    width: fillWidth,
                    height: 58,
                    decoration: BoxDecoration(
                      color: colorScheme.primary.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(100),
                    ),
                  ),
                  Positioned.fill(
                    left: _thumbSize + 8,
                    right: 18,
                    child: Center(
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          color: colorScheme.onPrimaryContainer,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                  AnimatedPositioned(
                    duration: const Duration(milliseconds: 90),
                    curve: Curves.easeOut,
                    left: thumbLeft,
                    child: Container(
                      width: _thumbSize,
                      height: _thumbSize,
                      margin: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: _enabled
                            ? colorScheme.primary
                            : colorScheme.onSurface.withValues(alpha: 0.2),
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.16),
                            blurRadius: 7,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: widget.isLoading || _confirming
                          ? Padding(
                              padding: const EdgeInsets.all(14),
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: colorScheme.onPrimary,
                              ),
                            )
                          : Icon(
                              Icons.chevron_right_rounded,
                              color: colorScheme.onPrimary,
                              size: 30,
                            ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  String _sliderLabel(RidePrimaryAction action) {
    return switch (action) {
      RidePrimaryAction.arriveAtPickup => 'Slide to arrive at pickup',
      RidePrimaryAction.startTrip => 'Slide to start trip',
      RidePrimaryAction.dropOffPassenger => 'Slide at destination',
      RidePrimaryAction.completeTrip => 'Slide to confirm payment',
      _ => 'Slide to ${action.title.toLowerCase()}',
    };
  }
}
