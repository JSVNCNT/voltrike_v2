import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/route_restriction_service.dart';
import '../../../data/models/route_restriction.dart';
import '../../../data/repositories/driver_violation_repository.dart';
import '../../common/services/notification_service.dart';
import '../controllers/driver_location_controller.dart';
import '../providers/driver_current_booking_provider.dart';
import '../providers/driver_location_controller_provider.dart';
import '../providers/driver_status_provider.dart';
import 'driver_restriction_monitor.dart';

class DriverRestrictionMonitorState {
  const DriverRestrictionMonitorState({
    this.phase = DriverRestrictionPhase.clear,
    this.restriction,
    this.distanceMeters = double.infinity,
    this.violationId,
    this.reporting = false,
    this.reportError,
  });

  final DriverRestrictionPhase phase;
  final RouteRestriction? restriction;
  final double distanceMeters;
  final String? violationId;
  final bool reporting;
  final String? reportError;

  bool get visible => phase != DriverRestrictionPhase.clear;

  String get message => switch (phase) {
    DriverRestrictionPhase.approaching =>
      'Restricted e-trike area ahead. Do not enter '
          '${restriction?.name ?? 'this area'}. Follow the alternate route.',
    DriverRestrictionPhase.inside =>
      'Restricted area entered. Leave '
          '${restriction?.name ?? 'this area'} using the nearest permitted '
          'street.',
    DriverRestrictionPhase.clear => '',
  };

  DriverRestrictionMonitorState copyWith({
    DriverRestrictionPhase? phase,
    RouteRestriction? restriction,
    bool clearRestriction = false,
    double? distanceMeters,
    String? violationId,
    bool clearViolationId = false,
    bool? reporting,
    String? reportError,
    bool clearReportError = false,
  }) {
    return DriverRestrictionMonitorState(
      phase: phase ?? this.phase,
      restriction: clearRestriction ? null : restriction ?? this.restriction,
      distanceMeters: distanceMeters ?? this.distanceMeters,
      violationId: clearViolationId ? null : violationId ?? this.violationId,
      reporting: reporting ?? this.reporting,
      reportError: clearReportError ? null : reportError ?? this.reportError,
    );
  }
}

class DriverRestrictionMonitorController
    extends StateNotifier<DriverRestrictionMonitorState> {
  DriverRestrictionMonitorController({
    DriverRestrictionTransitionEngine? engine,
    RouteRestrictionService? restrictionService,
    DriverViolationRepository? violationRepository,
    NotificationService? notificationService,
  }) : _engine = engine ?? DriverRestrictionTransitionEngine(),
       _restrictionService =
           restrictionService ?? RouteRestrictionService.instance,
       _violationRepository =
           violationRepository ?? DriverViolationRepository(),
       _notificationService =
           notificationService ?? NotificationService.instance,
       super(const DriverRestrictionMonitorState());

  final DriverRestrictionTransitionEngine _engine;
  final RouteRestrictionService _restrictionService;
  final DriverViolationRepository _violationRepository;
  final NotificationService _notificationService;

  bool _online = false;
  Future<void> _queue = Future.value();
  Future<void> _reportQueue = Future.value();
  DateTime? _lastReportedObservationAt;

  void setOnline(bool online) {
    _online = online;
    if (online) return;
    _engine.reset();
    _lastReportedObservationAt = null;
    unawaited(_notificationService.clearDriverRestrictionAlert());
    state = const DriverRestrictionMonitorState();
  }

  void addLocation(DriverLocationState locationState, {String? bookingId}) {
    if (!_online ||
        locationState.location == null ||
        locationState.accuracyMeters == null ||
        locationState.observedAt == null) {
      return;
    }
    _queue = _queue
        .then((_) => _processLocation(locationState, bookingId: bookingId))
        .catchError((Object _, StackTrace _) {
          if (!_online || !mounted) return;
          state = state.copyWith(
            reportError:
                'Restricted-area checks are temporarily unavailable. '
                'Follow posted restrictions and check your connection.',
          );
        });
  }

  Future<void> _processLocation(
    DriverLocationState locationState, {
    String? bookingId,
  }) async {
    if (!_online) return;
    final restrictions = await _restrictionService.activeRestrictions();
    if (!_online) return;
    final transition = _engine.evaluate(
      point: locationState.location!,
      accuracyMeters: locationState.accuracyMeters!,
      observedAt: locationState.observedAt!,
      now: DateTime.now(),
      restrictions: restrictions,
    );
    // RTDB writes already invoke the authoritative backend monitor. Keep the
    // callable as an immediate/backstop path only while locally inside a
    // restricted area or confirming an exit, instead of duplicating a
    // Functions invocation for every online-idle GPS update.
    if (_engine.current.phase == DriverRestrictionPhase.inside ||
        transition?.exited == true) {
      _reportQueue = _reportQueue
          .then((_) => _reportPublishedFix(locationState, bookingId: bookingId))
          .catchError((Object _, StackTrace _) {
            if (!_online || !mounted) return;
            state = state.copyWith(
              reporting: false,
              reportError:
                  'Safety administrators could not be alerted yet. Stay '
                  'outside the restricted area and check your connection.',
            );
          });
    }
    if (transition == null) return;

    final current = transition.current;
    state = state.copyWith(
      phase: current.phase,
      restriction: current.restriction,
      clearRestriction: current.restriction == null,
      distanceMeters: current.distanceMeters,
      clearViolationId: current.phase == DriverRestrictionPhase.clear,
      clearReportError: true,
    );

    if (current.phase == DriverRestrictionPhase.clear) {
      await _notificationService.clearDriverRestrictionAlert();
    } else if (transition.shouldAlert) {
      await _alert(current);
    }
  }

  Future<void> _alert(DriverRestrictionObservation observation) async {
    final restriction = observation.restriction;
    if (restriction == null) return;
    final inside = observation.phase == DriverRestrictionPhase.inside;
    if (inside) {
      await HapticFeedback.heavyImpact();
      await Future<void>.delayed(const Duration(milliseconds: 180));
      await HapticFeedback.heavyImpact();
    } else {
      await HapticFeedback.mediumImpact();
    }
    await _notificationService.showDriverRestrictionAlert(
      restrictionName: restriction.name,
      inside: inside,
    );
  }

  Future<void> _reportPublishedFix(
    DriverLocationState locationState, {
    String? bookingId,
  }) async {
    final observedAt = locationState.observedAt;
    final publishedObservedAt = locationState.lastPublishedObservedAt;
    final accuracy = locationState.accuracyMeters;
    if (!_online ||
        observedAt == null ||
        publishedObservedAt != observedAt ||
        _lastReportedObservationAt == observedAt ||
        accuracy == null ||
        !accuracy.isFinite ||
        accuracy < 0 ||
        accuracy > _engine.maximumAccuracyMeters) {
      return;
    }
    _lastReportedObservationAt = observedAt;
    if (state.visible) {
      state = state.copyWith(reporting: true, clearReportError: true);
    }
    try {
      final result = await _violationRepository.reportPublishedPosition(
        bookingId: bookingId,
      );
      if (mounted) {
        final newViolationId = result.createdViolationIds.firstOrNull;
        state = state.copyWith(
          reporting: false,
          violationId: newViolationId,
          clearReportError: true,
        );
      }
    } catch (_) {
      if (mounted) {
        state = state.copyWith(
          reporting: false,
          reportError:
              'Safety administrators could not be alerted yet. Stay outside '
              'the restricted area and check your connection.',
        );
      }
    }
  }
}

extension<T> on List<T> {
  T? get firstOrNull => isEmpty ? null : first;
}

final driverRestrictionMonitorProvider =
    StateNotifierProvider<
      DriverRestrictionMonitorController,
      DriverRestrictionMonitorState
    >((ref) {
      final controller = DriverRestrictionMonitorController();
      ref.listen<DriverStatus>(
        driverStatusProvider,
        (_, status) => controller.setOnline(status != DriverStatus.offline),
        fireImmediately: true,
      );
      ref.listen<DriverLocationState>(driverLocationControllerProvider, (
        _,
        location,
      ) {
        controller.addLocation(
          location,
          bookingId: ref.read(driverCurrentBookingProvider)?.bookingId,
        );
      }, fireImmediately: true);
      final authSubscription = ref
          .read(driverLocationAuthRepositoryProvider)
          .authStateChanges()
          .listen((user) {
            if (user != null) return;
            controller.setOnline(false);
            ref.read(driverStatusProvider.notifier).goOffline();
            final locationController = ref.read(
              driverLocationControllerProvider.notifier,
            );
            if (locationController.isTracking) {
              unawaited(
                locationController.stopTracking().catchError((_) {
                  // Auth-state shutdown must still end local monitoring even
                  // when server presence cleanup is unavailable.
                }),
              );
            }
          });
      ref.onDispose(() => authSubscription.cancel());
      return controller;
    });
