import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/ride_action.dart';

/// Responsive swipe-to-confirm control for driver lifecycle transitions.
///
/// Dragging can only start from the thumb. Releasing before the completion
/// threshold returns it to the start, preventing accidental trip updates.
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
  static const _height = 60.0;
  static const _thumbSize = 50.0;
  static const _inset = 5.0;
  static const _completionThreshold = 0.9;

  double _progress = 0;
  bool _confirming = false;
  bool _confirmed = false;
  bool _failed = false;
  bool _dragging = false;
  bool _thresholdReached = false;

  bool get _enabled => widget.enabled && !widget.isLoading && !_confirming;

  @override
  void didUpdateWidget(covariant RideConfirmationSlider oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.action != widget.action) {
      _progress = 0;
      _confirming = false;
      _confirmed = false;
      _failed = false;
      _dragging = false;
      _thresholdReached = false;
    }
  }

  void _startDrag() {
    if (!_enabled) return;
    setState(() {
      _dragging = true;
      _failed = false;
      _confirmed = false;
    });
  }

  void _drag(DragUpdateDetails details, double travel) {
    if (!_enabled || travel <= 0) return;
    final nextProgress = (_progress + (details.delta.dx / travel)).clamp(
      0.0,
      1.0,
    );
    final reachedThreshold = nextProgress >= _completionThreshold;
    final shouldAnnounceThreshold = reachedThreshold && !_thresholdReached;
    setState(() {
      _progress = nextProgress;
      _thresholdReached = reachedThreshold;
    });
    if (shouldAnnounceThreshold) {
      unawaited(HapticFeedback.selectionClick());
    }
  }

  Future<void> _finishDrag() async {
    if (!_enabled) return;
    if (_progress < _completionThreshold) {
      setState(() {
        _dragging = false;
        _progress = 0;
        _thresholdReached = false;
      });
      return;
    }
    setState(() => _dragging = false);
    await _confirm();
  }

  Future<void> _confirm() async {
    if (!_enabled) return;
    setState(() {
      _confirming = true;
      _failed = false;
      _confirmed = false;
      _dragging = false;
      _thresholdReached = true;
      _progress = 1;
    });
    try {
      await widget.onConfirmed();
      if (!mounted) return;
      setState(() {
        _confirming = false;
        _confirmed = true;
      });
      unawaited(HapticFeedback.mediumImpact());
      await Future<void>.delayed(const Duration(milliseconds: 420));
      if (!mounted) return;
      setState(_reset);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _confirming = false;
        _confirmed = false;
        _failed = true;
        _progress = 0;
        _thresholdReached = false;
      });
      unawaited(HapticFeedback.vibrate());
    }
  }

  void _reset() {
    _progress = 0;
    _confirming = false;
    _confirmed = false;
    _failed = false;
    _dragging = false;
    _thresholdReached = false;
  }

  void _cancelDrag() {
    if (!mounted) return;
    setState(() {
      _dragging = false;
      _progress = 0;
      _thresholdReached = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (widget.action == RidePrimaryAction.none) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final label = _label(widget.action);
    final statusLabel = _failed
        ? 'Update failed - swipe to retry'
        : _confirmed
        ? 'Confirmed'
        : _confirming || widget.isLoading
        ? 'Confirming...'
        : label;
    final labelOpacity = _failed || _confirmed || _confirming
        ? 1.0
        : (1 - ((_progress - 0.38) / 0.4)).clamp(0.0, 1.0);
    final baseTrackColor = widget.enabled
        ? Color.alphaBlend(
            colorScheme.surface.withValues(alpha: 0.18),
            colorScheme.primary,
          )
        : colorScheme.onSurface.withValues(alpha: 0.22);
    final progressColor = widget.enabled
        ? colorScheme.primary
        : colorScheme.onSurface.withValues(alpha: 0.22);

    return Semantics(
      button: true,
      enabled: _enabled,
      label: label,
      hint: 'Swipe the arrow all the way to confirm',
      onTap: _enabled ? _confirm : null,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth.isFinite
              ? constraints.maxWidth
              : MediaQuery.sizeOf(context).width;
          final travel = (width - _thumbSize - (_inset * 2)).clamp(
            0.0,
            double.infinity,
          );
          final thumbLeft = _inset + (_progress * travel);

          return SizedBox(
            height: _height,
            child: Material(
              color: baseTrackColor,
              shape: const StadiumBorder(),
              clipBehavior: Clip.antiAlias,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Positioned.fill(
                    child: FractionallySizedBox(
                      widthFactor: _progress,
                      alignment: Alignment.centerLeft,
                      child: ColoredBox(color: progressColor),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 64),
                    child: AnimatedOpacity(
                      opacity: labelOpacity,
                      duration: const Duration(milliseconds: 90),
                      child: Text(
                        statusLabel,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: widget.enabled
                              ? colorScheme.onPrimary
                              : colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                  AnimatedPositioned(
                    duration: _dragging
                        ? Duration.zero
                        : const Duration(milliseconds: 240),
                    curve: Curves.easeOutCubic,
                    left: thumbLeft,
                    top: _inset,
                    child: GestureDetector(
                      key: const Key('ride-swipe-thumb'),
                      behavior: HitTestBehavior.opaque,
                      onHorizontalDragStart: _enabled
                          ? (_) => _startDrag()
                          : null,
                      onHorizontalDragUpdate: _enabled
                          ? (details) => _drag(details, travel)
                          : null,
                      onHorizontalDragEnd: _enabled
                          ? (_) => _finishDrag()
                          : null,
                      onHorizontalDragCancel: _enabled ? _cancelDrag : null,
                      child: Semantics(
                        label: 'Ride confirmation handle',
                        child: Material(
                          color: colorScheme.onPrimary,
                          elevation: 3,
                          shape: const CircleBorder(),
                          child: SizedBox.square(
                            dimension: _thumbSize,
                            child: Center(
                              child: _confirming || widget.isLoading
                                  ? SizedBox.square(
                                      dimension: 22,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2.4,
                                        color: colorScheme.primary,
                                      ),
                                    )
                                  : AnimatedSwitcher(
                                      duration: const Duration(
                                        milliseconds: 140,
                                      ),
                                      transitionBuilder: (child, animation) =>
                                          ScaleTransition(
                                            scale: animation,
                                            child: child,
                                          ),
                                      child: Icon(
                                        _confirmed || _thresholdReached
                                            ? Icons.check_rounded
                                            : _failed
                                            ? Icons.refresh_rounded
                                            : Icons.arrow_forward_rounded,
                                        key: ValueKey((
                                          _confirmed,
                                          _thresholdReached,
                                          _failed,
                                        )),
                                        color: colorScheme.primary,
                                        size: 30,
                                      ),
                                    ),
                            ),
                          ),
                        ),
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

  String _label(RidePrimaryAction action) {
    return switch (action) {
      RidePrimaryAction.arriveAtPickup => 'Swipe to arrive',
      RidePrimaryAction.startTrip => 'Swipe to start trip',
      RidePrimaryAction.dropOffPassenger => 'Swipe to confirm arrival',
      RidePrimaryAction.completeTrip => 'Swipe to confirm cash received',
      _ => 'Swipe to ${action.title.toLowerCase()}',
    };
  }
}
