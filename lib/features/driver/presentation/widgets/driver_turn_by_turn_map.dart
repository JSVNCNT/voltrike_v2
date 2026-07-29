import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_navigation_flutter/google_navigation_flutter.dart'
    as navigation;

import '../../../../core/maps/voltrike_map.dart' as app_map;
import '../../../../core/services/navigation_service.dart';
import '../../../../core/services/route_restriction_service.dart';
import '../../../../core/services/routes_service.dart';
import '../../providers/driver_navigation_provider.dart';

/// Android driver guidance backed by Google Navigation SDK for Flutter.
///
/// A route is requested only when the booking leg changes. Native rerouting,
/// traffic-aware ETA, maneuver indicators, voice guidance, and camera following
/// are then managed by the Navigation SDK rather than by REST polling.
class DriverTurnByTurnMap extends ConsumerStatefulWidget {
  const DriverTurnByTurnMap({
    super.key,
    required this.origin,
    required this.destination,
    required this.destinationLabel,
    required this.legKey,
  });

  final app_map.LatLng origin;
  final app_map.LatLng destination;
  final String destinationLabel;
  final String legKey;

  @override
  ConsumerState<DriverTurnByTurnMap> createState() =>
      _DriverTurnByTurnMapState();
}

class _DriverTurnByTurnMapState extends ConsumerState<DriverTurnByTurnMap> {
  navigation.GoogleNavigationViewController? _viewController;
  final List<StreamSubscription<dynamic>> _subscriptions = [];

  bool _sessionReady = false;
  bool _disposed = false;
  bool _hasSdkLocation = false;
  app_map.LatLng? _roadSnappedLocation;
  String? _routedLegKey;
  bool _validatedReroutePending = false;
  int _routeEpoch = 0;
  Brightness? _brightness;

  navigation.NavigationForceNightMode get _forceNightMode =>
      _brightness == Brightness.dark
      ? navigation.NavigationForceNightMode.forceNight
      : navigation.NavigationForceNightMode.forceDay;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_initializeSession());
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final brightness = Theme.of(context).brightness;
    if (_brightness == brightness) return;
    _brightness = brightness;
    final controller = _viewController;
    if (controller != null) {
      unawaited(controller.setForceNightMode(_forceNightMode));
    }
  }

  @override
  void didUpdateWidget(covariant DriverTurnByTurnMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.legKey != widget.legKey ||
        oldWidget.destination != widget.destination) {
      _routedLegKey = null;
      unawaited(_setDestinationWhenReady());
    }
  }

  Future<void> _initializeSession() async {
    final stateController = ref.read(
      driverNavigationControllerProvider.notifier,
    );
    stateController.markSdkStarting();

    try {
      await NavigationService.instance.ensurePermission();

      var termsAccepted =
          await navigation.GoogleMapsNavigator.areTermsAccepted();
      if (!termsAccepted) {
        termsAccepted =
            await navigation.GoogleMapsNavigator.showTermsAndConditionsDialog(
              'VolTrike driver navigation',
              'VolTrike',
            );
      }
      if (!termsAccepted) {
        throw StateError(
          'Accept the Google Navigation terms to use in-app guidance.',
        );
      }

      await navigation.GoogleMapsNavigator.initializeNavigationSession(
        taskRemovedBehavior: navigation.TaskRemovedBehavior.quitService,
      );
      if (!mounted || _disposed) {
        await navigation.GoogleMapsNavigator.cleanup();
        return;
      }

      _registerNavigationListeners();
      final locationSubscription =
          await navigation
              .GoogleMapsNavigator.setRoadSnappedLocationUpdatedListener((
            event,
          ) {
            _roadSnappedLocation = app_map.LatLng(
              event.location.latitude,
              event.location.longitude,
            );
            if (_hasSdkLocation) return;
            _hasSdkLocation = true;
            unawaited(_setDestinationWhenReady());
          });
      _subscriptions.add(locationSubscription);

      setState(() => _sessionReady = true);
    } catch (error) {
      stateController.setSdkError(_friendlyError(error));
      if (mounted) setState(() => _sessionReady = false);
    }
  }

  void _registerNavigationListeners() {
    _subscriptions
      ..add(
        navigation
            .GoogleMapsNavigator.setOnRemainingTimeOrDistanceChangedListener(
          (event) {
            if (!mounted) return;
            ref
                .read(driverNavigationControllerProvider.notifier)
                .updateSdkProgress(
                  remainingTimeSeconds: event.remainingTime,
                  remainingDistanceMeters: event.remainingDistance,
                );
          },
          remainingTimeThresholdSeconds: 5,
          remainingDistanceThresholdMeters: 25,
        ),
      )
      ..add(
        navigation.GoogleMapsNavigator.setNavInfoListener((event) {
          if (!mounted) return;
          final current = event.navInfo.currentStep;
          final remaining = event.navInfo.remainingSteps;
          ref
              .read(driverNavigationControllerProvider.notifier)
              .updateSdkInstructions(
                instruction: current?.fullInstructions,
                nextInstruction: remaining.isEmpty
                    ? null
                    : remaining.first.fullInstructions,
                maneuver: current?.maneuver.name,
              );
        }, numNextStepsToPreview: 1),
      )
      ..add(
        navigation.GoogleMapsNavigator.setOnReroutingListener(() {
          if (!mounted) return;
          ref
              .read(driverNavigationControllerProvider.notifier)
              .markSdkRerouting();
          unawaited(_replaceAutomaticReroute());
        }),
      )
      ..add(
        navigation.GoogleMapsNavigator.setOnRouteChangedListener(() {
          if (!mounted) return;
          ref.read(driverNavigationControllerProvider.notifier).markSdkReady();
        }),
      )
      ..add(
        navigation.GoogleMapsNavigator.setOnArrivalListener((_) {
          if (!mounted) return;
          ref
              .read(driverNavigationControllerProvider.notifier)
              .markSdkArrival(widget.destinationLabel);
        }),
      );
  }

  Future<void> _onViewCreated(
    navigation.GoogleNavigationViewController controller,
  ) async {
    _viewController = controller;
    try {
      await Future.wait([
        controller.setMyLocationEnabled(true),
        controller.setNavigationUIEnabled(true),
        controller.setNavigationHeaderEnabled(true),
        controller.setNavigationFooterEnabled(true),
        controller.setRecenterButtonEnabled(true),
        controller.setSpeedometerEnabled(true),
        // Speed-limit coverage is not available for this pilot area.
        controller.setSpeedLimitIconEnabled(false),
        controller.setTrafficIncidentCardsEnabled(true),
        controller.setTrafficPromptsEnabled(true),
        controller.setForceNightMode(_forceNightMode),
      ]);
      await controller.followMyLocation(navigation.CameraPerspective.tilted);
      await _setDestinationWhenReady();
    } catch (error) {
      if (!mounted) return;
      ref
          .read(driverNavigationControllerProvider.notifier)
          .setSdkError(_friendlyError(error));
    }
  }

  Future<void> _setDestinationWhenReady() async {
    if (!_sessionReady ||
        !_hasSdkLocation ||
        _viewController == null ||
        _routedLegKey == widget.legKey ||
        _disposed) {
      return;
    }

    final epoch = ++_routeEpoch;
    final stateController = ref.read(
      driverNavigationControllerProvider.notifier,
    );
    stateController.markSdkStarting();

    try {
      final route = await RoutesService.computeRoute(
        origin: _roadSnappedLocation ?? widget.origin,
        destination: widget.destination,
      );
      final routeToken = route?.routeToken;
      if (route == null || routeToken == null || routeToken.isEmpty) {
        throw StateError(
          'No permitted e-trike route is available for this trip.',
        );
      }
      stateController.applyValidatedRoute(route);
      final status = await navigation.GoogleMapsNavigator.setDestinations(
        navigation.Destinations(
          waypoints: [
            navigation.NavigationWaypoint.withLatLngTarget(
              title: widget.destinationLabel,
              target: widget.destination.toNavigation(),
            ),
          ],
          displayOptions: navigation.NavigationDisplayOptions(
            showDestinationMarkers: true,
          ),
          routeTokenOptions: navigation.RouteTokenOptions(
            routeToken: routeToken,
            travelMode: navigation.NavigationTravelMode.driving,
          ),
        ),
      );
      if (!mounted || _disposed || epoch != _routeEpoch) return;
      if (status != navigation.NavigationRouteStatus.statusOk) {
        throw StateError('Route unavailable (${status.name}).');
      }

      _routedLegKey = widget.legKey;
      await navigation.GoogleMapsNavigator.startGuidance();
      await _viewController?.followMyLocation(
        navigation.CameraPerspective.tilted,
      );
      stateController.markSdkReady();
    } catch (error) {
      if (!mounted || _disposed || epoch != _routeEpoch) return;
      stateController.setSdkError(_friendlyError(error));
    }
  }

  Future<void> _replaceAutomaticReroute() async {
    if (_validatedReroutePending || _disposed) return;
    _validatedReroutePending = true;
    try {
      // Native automatic rerouting does not expose a route shape that can be
      // checked against developer polygons. Stop it and install a fresh
      // Routes API token selected by the same polygon/highway policy.
      await navigation.GoogleMapsNavigator.stopGuidance();
      _routedLegKey = null;
      await _setDestinationWhenReady();
    } finally {
      _validatedReroutePending = false;
    }
  }

  String _friendlyError(Object error) {
    final message = error.toString();
    if (message.contains(
      'No permitted e-trike route is available for this trip.',
    )) {
      final conflict = RouteRestrictionService.instance.lastConflict;
      return conflict == null
          ? 'No permitted e-trike route is available for this trip.'
          : 'No permitted e-trike route is available for this trip. '
                'Route blocked by ${conflict.name}.';
    }
    if (message.contains('apiKeyNotAuthorized')) {
      return 'In-app navigation is not authorized for this development key.';
    }
    if (message.contains('quotaExceeded') ||
        message.contains('quotaCheckFailed')) {
      return 'The daily in-app navigation limit has been reached.';
    }
    if (message.contains('locationUnavailable') ||
        message.contains('Location services')) {
      return 'Waiting for an accurate GPS location.';
    }
    if (message.contains('terms')) {
      return 'Accept the Google Navigation terms to use in-app guidance.';
    }
    return 'In-app guidance is currently unavailable.';
  }

  @override
  Widget build(BuildContext context) {
    if (!_sessionReady) {
      return ColoredBox(
        color: Theme.of(context).colorScheme.surfaceContainer,
        child: const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 12),
              Text('Starting driver navigation…'),
            ],
          ),
        ),
      );
    }

    return navigation.GoogleMapsNavigationView(
      onViewCreated: _onViewCreated,
      initialCameraPosition: navigation.CameraPosition(
        target: widget.destination.toNavigation(),
        zoom: 16,
      ),
      initialNavigationUIEnabledPreference:
          navigation.NavigationUIEnabledPreference.automatic,
      initialMapToolbarEnabled: false,
      initialZoomControlsEnabled: false,
      initialForceNightMode: _forceNightMode,
    );
  }

  @override
  void dispose() {
    _disposed = true;
    _routeEpoch++;
    ref.read(driverNavigationControllerProvider.notifier).clearRoute();
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    _subscriptions.clear();
    _viewController = null;
    unawaited(_stopAndCleanup());
    super.dispose();
  }

  Future<void> _stopAndCleanup() async {
    try {
      await navigation.GoogleMapsNavigator.stopGuidance();
    } catch (_) {
      // The session may have failed before guidance started.
    }
    try {
      await navigation.GoogleMapsNavigator.cleanup();
    } catch (_) {
      // Cleanup is best-effort while the platform view is being disposed.
    }
  }
}
