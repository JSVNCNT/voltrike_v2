import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../../../core/native/route_restriction_engine.dart';
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
    this.highwayRestriction,
    this.distanceMeters = double.infinity,
    this.violationId,
    this.reporting = false,
    this.reportError,
  });

  final DriverRestrictionPhase phase;
  final RouteRestriction? restriction;
  final RouteRestriction? highwayRestriction;
  final double distanceMeters;
  final String? violationId;
  final bool reporting;
  final String? reportError;

  bool get visible =>
      phase != DriverRestrictionPhase.clear || highwayRestriction != null;

  String get message => switch (phase) {
    DriverRestrictionPhase.approaching =>
      'Restricted e-trike area ahead. Do not enter '
          '${restriction?.name ?? 'this area'}. Follow the alternate route.',
    DriverRestrictionPhase.inside =>
      'Restricted area entered. Leave '
          '${restriction?.name ?? 'this area'} using the nearest permitted '
          'street.',
    DriverRestrictionPhase.clear =>
      highwayRestriction == null
          ? ''
          : 'Possible prohibited highway travel on ${highwayRestriction!.name}. '
                'Leave the highway using the next permitted street.',
  };

  DriverRestrictionMonitorState copyWith({
    DriverRestrictionPhase? phase,
    RouteRestriction? restriction,
    RouteRestriction? highwayRestriction,
    bool clearHighwayRestriction = false,
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
      highwayRestriction: clearHighwayRestriction
          ? null
          : highwayRestriction ?? this.highwayRestriction,
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
    DriverHighwayTravelEngine? highwayEngine,
    RouteRestrictionService? restrictionService,
    DriverViolationRepository? violationRepository,
    NotificationService? notificationService,
  }) : _engine = engine ?? DriverRestrictionTransitionEngine(),
       _highwayEngine = highwayEngine ?? DriverHighwayTravelEngine(),
       _restrictionService =
           restrictionService ?? RouteRestrictionService.instance,
       _violationRepository =
           violationRepository ?? DriverViolationRepository(),
       _notificationService =
           notificationService ?? NotificationService.instance,
       super(const DriverRestrictionMonitorState());

  final DriverRestrictionTransitionEngine _engine;
  final DriverHighwayTravelEngine _highwayEngine;
  final RouteRestrictionService _restrictionService;
  final DriverViolationRepository _violationRepository;
  final NotificationService _notificationService;

  bool _online = false;
  int _onlineSession = 0;
  Future<void> _queue = Future.value();
  Future<void> _reportQueue = Future.value();
  DateTime? _lastReportedObservationAt;

  void setOnline(bool online) {
    _online = online;
    _onlineSession++;
    if (online) return;
    _engine.reset();
    _highwayEngine.reset();
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
    final onlineSession = _onlineSession;
    _queue = _queue
        .then(
          (_) => _processLocation(
            locationState,
            bookingId: bookingId,
            onlineSession: onlineSession,
          ),
        )
        .catchError((Object _, StackTrace _) {
          if (!_isCurrentOnlineSession(onlineSession) || !mounted) return;
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
    required int onlineSession,
  }) async {
    if (!_isCurrentOnlineSession(onlineSession)) return;
    final accuracyMeters = locationState.accuracyMeters!;
    final observedAt = locationState.observedAt!;
    if (!_engine.isSampleEligible(
      accuracyMeters: accuracyMeters,
      observedAt: observedAt,
      now: DateTime.now(),
    )) {
      return;
    }
    final restrictions = await _restrictionService.activeRestrictions();
    if (!_isCurrentOnlineSession(onlineSession)) return;
    final point = locationState.location!;
    final highwayAtCurrentLocation = restrictions
        .where(RouteRestrictionMatcher.isHighwayCorridor)
        .where(
          (restriction) =>
              RouteRestrictionMatcher.distanceToHighwayCorridorMeters(
                point,
                restriction,
              ) <=
              restriction.bufferMeters,
        )
        .firstOrNull;
    if (highwayAtCurrentLocation != null &&
        state.highwayRestriction?.id != highwayAtCurrentLocation.id) {
      state = state.copyWith(
        highwayRestriction: highwayAtCurrentLocation,
        clearReportError: true,
      );
      await HapticFeedback.selectionClick();
      await _notificationService.showDriverRestrictionAlert(
        restrictionName: highwayAtCurrentLocation.name,
        inside: false,
      );
    }
    final highwayWarning = _highwayEngine.evaluate(
      point: point,
      accuracyMeters: accuracyMeters,
      observedAt: observedAt,
      now: DateTime.now(),
      restrictions: restrictions,
    );
    if (highwayWarning != null &&
        state.highwayRestriction?.id != highwayWarning.id) {
      state = state.copyWith(
        highwayRestriction: highwayWarning,
        clearReportError: true,
      );
      await HapticFeedback.mediumImpact();
      await _notificationService.showDriverRestrictionAlert(
        restrictionName: highwayWarning.name,
        inside: false,
      );
    } else if (highwayWarning == null &&
        highwayAtCurrentLocation == null &&
        _highwayEngine.current == null &&
        state.highwayRestriction != null) {
      state = state.copyWith(clearHighwayRestriction: true);
      if (_engine.current.phase == DriverRestrictionPhase.clear) {
        await _notificationService.clearDriverRestrictionAlert();
      }
    }
    final proximity = await RouteRestrictionEngine.instance.pointProximity(
      point: point,
      restrictions: restrictions,
      preferredRestrictionId: _engine.current.restriction?.id,
    );
    if (!_isCurrentOnlineSession(onlineSession)) return;
    final transition = _engine.evaluate(
      point: point,
      accuracyMeters: accuracyMeters,
      observedAt: observedAt,
      now: DateTime.now(),
      restrictions: restrictions,
      proximity: proximity,
    );
    // RTDB writes already invoke the authoritative backend monitor. Keep the
    // callable as an immediate/backstop path only while locally inside a
    // restricted area or confirming an exit, instead of duplicating a
    // Functions invocation for every online-idle GPS update.
    if (_engine.current.phase == DriverRestrictionPhase.inside ||
        transition?.exited == true) {
      _reportQueue = _reportQueue
          .then(
            (_) => _reportPublishedFix(
              locationState,
              bookingId: bookingId,
              onlineSession: onlineSession,
            ),
          )
          .catchError((Object _, StackTrace _) {
            if (!_isCurrentOnlineSession(onlineSession) || !mounted) return;
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
      await _alert(current, onlineSession: onlineSession);
    }
  }

  Future<void> _alert(
    DriverRestrictionObservation observation, {
    required int onlineSession,
  }) async {
    if (!_isCurrentOnlineSession(onlineSession)) return;
    final restriction = observation.restriction;
    if (restriction == null) return;
    final inside = observation.phase == DriverRestrictionPhase.inside;
    if (inside) {
      await HapticFeedback.heavyImpact();
      await Future<void>.delayed(const Duration(milliseconds: 180));
      if (!_isCurrentOnlineSession(onlineSession)) return;
      await HapticFeedback.heavyImpact();
    } else {
      await HapticFeedback.mediumImpact();
    }
    if (!_isCurrentOnlineSession(onlineSession)) return;
    await _notificationService.showDriverRestrictionAlert(
      restrictionName: restriction.name,
      inside: inside,
    );
  }

  Future<void> _reportPublishedFix(
    DriverLocationState locationState, {
    String? bookingId,
    required int onlineSession,
  }) async {
    final observedAt = locationState.observedAt;
    final publishedObservedAt = locationState.lastPublishedObservedAt;
    final accuracy = locationState.accuracyMeters;
    if (!_isCurrentOnlineSession(onlineSession) ||
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
      if (mounted && _isCurrentOnlineSession(onlineSession)) {
        final newViolationId = result.createdViolationIds.firstOrNull;
        state = state.copyWith(
          reporting: false,
          violationId: newViolationId,
          clearReportError: true,
        );
      }
    } catch (_) {
      if (mounted && _isCurrentOnlineSession(onlineSession)) {
        state = state.copyWith(
          reporting: false,
          reportError:
              'Safety administrators could not be alerted yet. Stay outside '
              'the restricted area and check your connection.',
        );
      }
    }
  }

  bool _isCurrentOnlineSession(int onlineSession) {
    return _online && onlineSession == _onlineSession;
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
