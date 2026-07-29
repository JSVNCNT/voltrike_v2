import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/routes.dart';
import '../../../../core/config/booking_config.dart';
import '../../../../core/errors/domain_error_mapper.dart';
import '../../../../core/maps/voltrike_map.dart';
import '../../../../core/services/navigation_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../data/models/booking.dart';
import '../../../ride/routing/booking_route_coordinator.dart';
import '../../../ride/routing/booking_route_resolver.dart';
import '../../controllers/passenger_booking_flow_controller.dart';
import '../models/driver_search_presentation.dart';
import '../../providers/booking_controller_provider.dart';
import '../../providers/booking_listener_provider.dart';
import '../../providers/booking_session_provider.dart';

class SearchingDriverScreen extends ConsumerStatefulWidget {
  const SearchingDriverScreen({super.key, required this.bookingId});

  final String bookingId;

  @override
  ConsumerState<SearchingDriverScreen> createState() =>
      _SearchingDriverScreenState();
}

class _SearchingDriverScreenState extends ConsumerState<SearchingDriverScreen>
    with SingleTickerProviderStateMixin {
  static const _searchAccent = Color(0xFFFF8A00);

  late final AnimationController _radarController;
  ProviderSubscription<AsyncValue<Booking?>>? _bookingSubscription;
  Timer? _searchTimer;
  Timer? _timeoutRetryTimer;

  BookingStatus? _lastStatus;
  Booking? _latestBooking;
  String? _loadedRouteBookingId;
  List<LatLng> _routePoints = const [];
  int _remainingSeconds = BookingConfig.bookingTimeoutSeconds;
  bool _cancelling = false;
  bool _timingOut = false;
  bool _timedOut = false;
  String? _timeoutError;

  @override
  void initState() {
    super.initState();
    _radarController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat();

    _bookingSubscription = ref.listenManual<AsyncValue<Booking?>>(
      bookingListenerProvider(widget.bookingId),
      (previous, next) {
        next.whenData((booking) {
          _latestBooking = booking;
          if (booking == null) {
            ref.read(passengerBookingFlowProvider.notifier).clear();
            _stopSearchTimer();
            return;
          }

          ref
              .read(passengerBookingFlowProvider.notifier)
              .updateStatus(booking.status);
          unawaited(_loadRequestedRoute(booking));
          _syncSearchTimer(booking);
          _handleStatusChange(booking);
        });
      },
    );
  }

  Future<void> _loadRequestedRoute(Booking booking) async {
    if (_loadedRouteBookingId == booking.bookingId) return;
    _loadedRouteBookingId = booking.bookingId;
    try {
      final route = await NavigationService.instance.computeRouteInfo(
        origin: booking.pickup,
        destination: booking.destination,
      );
      final points = route == null || route.encodedPolyline.isEmpty
          ? <LatLng>[booking.pickup, booking.destination]
          : NavigationService.instance.decodePolyline(route.encodedPolyline);
      if (mounted) setState(() => _routePoints = points);
    } catch (_) {
      if (mounted) {
        setState(() {
          _routePoints = [booking.pickup, booking.destination];
        });
      }
    }
  }

  void _syncSearchTimer(Booking booking) {
    if (booking.status != BookingStatus.pending) {
      _stopSearchTimer();
      if (booking.cancellationCode == 'search_timeout' && mounted) {
        setState(() {
          _timedOut = true;
          _timingOut = false;
          _timeoutError = null;
          _remainingSeconds = 0;
        });
      }
      return;
    }

    final nextRemaining = DriverSearchPresentation.remainingSeconds(
      bookingCreatedAt: booking.createdAt,
      now: DateTime.now(),
    );
    if (mounted && nextRemaining != _remainingSeconds) {
      setState(() => _remainingSeconds = nextRemaining);
    }

    _searchTimer ??= Timer.periodic(
      const Duration(seconds: 1),
      (_) => _tickSearchTimer(),
    );
    if (nextRemaining == 0) {
      _stopSearchTimer();
      unawaited(_expireSearch(booking));
    }
  }

  void _tickSearchTimer() {
    final booking = _latestBooking;
    if (!mounted ||
        booking == null ||
        booking.status != BookingStatus.pending) {
      _stopSearchTimer();
      return;
    }

    final nextRemaining = DriverSearchPresentation.remainingSeconds(
      bookingCreatedAt: booking.createdAt,
      now: DateTime.now(),
    );
    if (nextRemaining != _remainingSeconds) {
      setState(() => _remainingSeconds = nextRemaining);
    }
    if (nextRemaining == 0) {
      _stopSearchTimer();
      unawaited(_expireSearch(booking));
    }
  }

  Future<void> _expireSearch(Booking booking) async {
    if (_timingOut ||
        _timedOut ||
        booking.status != BookingStatus.pending ||
        !mounted) {
      return;
    }

    setState(() {
      _timingOut = true;
      _timeoutError = null;
      _remainingSeconds = 0;
    });

    try {
      await ref
          .read(bookingControllerProvider.notifier)
          .cancelBooking(
            booking.bookingId,
            reasonCode: 'search_timeout',
            reasonDetail:
                'No driver accepted within '
                '${BookingConfig.bookingTimeoutSeconds} seconds.',
          );
      if (!mounted) return;
      setState(() {
        _timingOut = false;
        _timedOut = true;
        _timeoutError = null;
      });
    } catch (error) {
      if (!mounted) return;

      final current = _latestBooking;
      if (current != null && current.status != BookingStatus.pending) {
        setState(() {
          _timingOut = false;
          _timeoutError = null;
        });
        _handleStatusChange(current);
        return;
      }

      setState(() {
        _timingOut = false;
        _timeoutError = DomainErrorMapper.message(error);
      });
      _timeoutRetryTimer?.cancel();
      _timeoutRetryTimer = Timer(const Duration(seconds: 3), () {
        final latest = _latestBooking;
        if (latest != null) unawaited(_expireSearch(latest));
      });
    }
  }

  void _handleStatusChange(Booking booking) {
    if (_lastStatus == booking.status) return;
    _lastStatus = booking.status;

    if (booking.status == BookingStatus.pending) return;
    if (booking.status == BookingStatus.cancelled &&
        (_timedOut || booking.cancellationCode == 'search_timeout')) {
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      BookingRouteCoordinator.open(
        context,
        role: BookingParticipantRole.passenger,
        booking: booking,
      );
    });
  }

  Future<void> _cancelBooking() async {
    final booking = _latestBooking;
    if (_cancelling || booking?.status != BookingStatus.pending) return;

    setState(() => _cancelling = true);
    try {
      await ref
          .read(bookingControllerProvider.notifier)
          .cancelBooking(
            widget.bookingId,
            reasonCode: 'cancelled_by_passenger',
            reasonDetail: 'Passenger cancelled while searching for a driver.',
          );
      if (!mounted) return;
      ref.read(passengerBookingFlowProvider.notifier).clear();
      context.go(AppRoutes.passengerHome);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(DomainErrorMapper.message(error))));
      setState(() => _cancelling = false);
    }
  }

  void _returnHome() {
    ref.read(passengerBookingFlowProvider.notifier).clear();
    context.go(AppRoutes.passengerHome);
  }

  void _stopSearchTimer() {
    _searchTimer?.cancel();
    _searchTimer = null;
  }

  @override
  void dispose() {
    _searchTimer?.cancel();
    _timeoutRetryTimer?.cancel();
    _bookingSubscription?.close();
    _radarController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final booking = ref.watch(bookingListenerProvider(widget.bookingId));
    final routeAdvisory = ref.watch(
      bookingSessionProvider.select((session) => session.routeAdvisory),
    );

    return booking.when(
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (error, _) => Scaffold(
        appBar: AppBar(title: const Text('Finding a ride')),
        body: Center(child: Text(DomainErrorMapper.message(error))),
      ),
      data: (bookingData) {
        if (bookingData == null) {
          return const Scaffold(
            body: Center(child: Text('Booking not found.')),
          );
        }
        return _buildSearchScaffold(
          bookingData,
          routeAdvisory.isNotEmpty
              ? routeAdvisory
              : bookingData.routePolicy.passengerMessage,
        );
      },
    );
  }

  Widget _buildSearchScaffold(Booking booking, String routeAdvisory) {
    final timedOut =
        _timedOut ||
        (booking.status == BookingStatus.cancelled &&
            booking.cancellationCode == 'search_timeout');

    return PopScope<void>(
      canPop: timedOut,
      child: Scaffold(
        appBar: AppBar(
          title: Text(timedOut ? 'Search ended' : 'Finding a ride'),
          automaticallyImplyLeading: timedOut,
        ),
        body: Stack(
          children: [
            Positioned.fill(child: _buildMap(booking)),
            if (!timedOut)
              Positioned.fill(
                child: IgnorePointer(
                  child: Center(
                    child: Semantics(
                      label:
                          'Searching within '
                          '${BookingConfig.searchRadiusKm.toStringAsFixed(0)} '
                          'kilometers of pickup',
                      child: ExcludeSemantics(
                        child: AnimatedBuilder(
                          animation: _radarController,
                          builder: (context, _) => CustomPaint(
                            size: const Size.square(190),
                            painter: _RadarPainter(
                              progress: _radarController.value,
                              color: _searchAccent,
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
        bottomNavigationBar: _DriverSearchBottomSheet(
          booking: booking,
          remainingSeconds: _remainingSeconds,
          timedOut: timedOut,
          timingOut: _timingOut,
          cancelling: _cancelling,
          timeoutError: _timeoutError,
          routeAdvisory: routeAdvisory,
          onCancel: _cancelBooking,
          onReturnHome: _returnHome,
          onRetryTimeout: () => _expireSearch(booking),
        ),
      ),
    );
  }

  Widget _buildMap(Booking booking) {
    return GoogleMap(
      initialCameraPosition: CameraPosition(target: booking.pickup, zoom: 15),
      markers: {
        Marker(
          markerId: const MarkerId('destination'),
          position: booking.destination,
          infoWindow: const InfoWindow(title: 'Destination'),
        ),
      },
      polylines: {
        Polyline(
          polylineId: const PolylineId('requested_route'),
          points: _routePoints.isEmpty
              ? [booking.pickup, booking.destination]
              : _routePoints,
          color: AppColors.trafficRoute,
          width: 5,
        ),
      },
      trafficEnabled: true,
      zoomControlsEnabled: false,
      myLocationButtonEnabled: false,
    );
  }
}

class _DriverSearchBottomSheet extends StatelessWidget {
  const _DriverSearchBottomSheet({
    required this.booking,
    required this.remainingSeconds,
    required this.timedOut,
    required this.timingOut,
    required this.cancelling,
    required this.timeoutError,
    required this.routeAdvisory,
    required this.onCancel,
    required this.onReturnHome,
    required this.onRetryTimeout,
  });

  final Booking booking;
  final int remainingSeconds;
  final bool timedOut;
  final bool timingOut;
  final bool cancelling;
  final String? timeoutError;
  final String routeAdvisory;
  final VoidCallback onCancel;
  final VoidCallback onReturnHome;
  final VoidCallback onRetryTimeout;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Material(
      color: colors.surface,
      elevation: 18,
      surfaceTintColor: Colors.transparent,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      clipBehavior: Clip.antiAlias,
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 44,
                  height: 4,
                  decoration: BoxDecoration(
                    color: colors.outlineVariant,
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              if (timedOut)
                _buildTimedOut(context)
              else
                _buildSearching(context),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSearching(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final progress = remainingSeconds / BookingConfig.bookingTimeoutSeconds;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: colors.primaryContainer,
                shape: BoxShape.circle,
              ),
              child: timingOut
                  ? Padding(
                      padding: const EdgeInsets.all(13),
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: colors.onPrimaryContainer,
                      ),
                    )
                  : Icon(Icons.radar_rounded, color: colors.onPrimaryContainer),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    timingOut ? 'Search time ended' : 'Looking for a driver',
                    style: theme.textTheme.titleLarge,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    timingOut
                        ? 'Closing this request safely…'
                        : DriverSearchPresentation.searchingMessage(
                            additionalPassengers: booking.additionalPassengers,
                          ),
                    style: theme.textTheme.bodyMedium,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            _TimerBadge(seconds: remainingSeconds),
          ],
        ),
        const SizedBox(height: 18),
        if (routeAdvisory.isNotEmpty) ...[
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: colors.tertiaryContainer,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.warning_amber_rounded,
                  color: colors.onTertiaryContainer,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    routeAdvisory,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: colors.onTertiaryContainer,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
        ],
        ClipRRect(
          borderRadius: BorderRadius.circular(99),
          child: LinearProgressIndicator(
            minHeight: 7,
            value: progress.clamp(0, 1),
            backgroundColor: colors.surfaceContainerHighest,
          ),
        ),
        if (timeoutError != null) ...[
          const SizedBox(height: 12),
          Text(
            'We could not close the request yet. '
            'Check your connection while VolTrike retries.',
            style: theme.textTheme.bodyMedium?.copyWith(color: colors.error),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: timingOut ? null : onRetryTimeout,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Retry now'),
          ),
        ],
        const SizedBox(height: 18),
        FilledButton.icon(
          onPressed: cancelling || timingOut ? null : onCancel,
          style: FilledButton.styleFrom(
            backgroundColor: colors.error,
            foregroundColor: colors.onError,
            minimumSize: const Size.fromHeight(54),
          ),
          icon: cancelling
              ? SizedBox.square(
                  dimension: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: colors.onError,
                  ),
                )
              : const Icon(Icons.close_rounded),
          label: Text(cancelling ? 'Cancelling…' : 'Cancel request'),
        ),
      ],
    );
  }

  Widget _buildTimedOut(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: colors.errorContainer,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.no_transfer_rounded,
                color: colors.onErrorContainer,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'No drivers available',
                    style: theme.textTheme.titleLarge,
                  ),
                  const SizedBox(height: 5),
                  Text(
                    DriverSearchPresentation.unavailableMessage(
                      additionalPassengers: booking.additionalPassengers,
                      isOutsideToda: booking.isOutsideToda,
                    ),
                    style: theme.textTheme.bodyMedium,
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Text(
          'The request stopped automatically after '
          '${DriverSearchPresentation.formatCountdown(BookingConfig.bookingTimeoutSeconds)}.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: colors.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 18),
        FilledButton.icon(
          onPressed: onReturnHome,
          icon: const Icon(Icons.arrow_back_rounded),
          label: const Text('Back to home'),
        ),
      ],
    );
  }
}

class _TimerBadge extends StatelessWidget {
  const _TimerBadge({required this.seconds});

  final int seconds;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Semantics(
      liveRegion: true,
      label: '$seconds seconds remaining',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: colors.secondaryContainer,
          borderRadius: BorderRadius.circular(99),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.timer_outlined,
              size: 17,
              color: colors.onSecondaryContainer,
            ),
            const SizedBox(width: 5),
            Text(
              DriverSearchPresentation.formatCountdown(seconds),
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: colors.onSecondaryContainer,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RadarPainter extends CustomPainter {
  const _RadarPainter({required this.progress, required this.color});

  final double progress;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final maximumRadius = size.shortestSide / 2;

    for (var index = 0; index < 3; index++) {
      final ringProgress = (progress + (index / 3)) % 1;
      final radius = 24 + ((maximumRadius - 24) * ringProgress);
      final opacity = (1 - ringProgress) * 0.24;
      canvas.drawCircle(
        center,
        radius,
        Paint()..color = color.withValues(alpha: opacity),
      );
    }

    canvas.drawCircle(
      center,
      28,
      Paint()..color = color.withValues(alpha: 0.26),
    );
    canvas.drawCircle(center, 11, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant _RadarPainter oldDelegate) {
    return oldDelegate.progress != progress || oldDelegate.color != color;
  }
}
