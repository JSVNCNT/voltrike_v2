import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../../app/routes.dart';
import '../../../core/errors/domain_error_mapper.dart';
import '../../../data/models/booking.dart';
import '../../../data/models/booking_call_session.dart';
import '../../../data/repositories/booking_repository.dart';
import '../../../data/repositories/booking_voice_call_repository.dart';
import '../../common/services/ringtone_service.dart';
import 'call_participant_identity.dart';
import 'microphone_permission.dart';

class IncomingCallScreen extends StatefulWidget {
  const IncomingCallScreen({
    super.key,
    required this.bookingId,
    this.callId,
    this.repository,
  });

  final String bookingId;
  final String? callId;
  final BookingVoiceCallRepository? repository;

  @override
  State<IncomingCallScreen> createState() => _IncomingCallScreenState();
}

class _IncomingCallScreenState extends State<IncomingCallScreen> {
  late final BookingVoiceCallRepository _repository;
  late final BookingRepository _bookingRepository;
  StreamSubscription<BookingCallSession?>? _subscription;
  StreamSubscription<Booking?>? _bookingSubscription;
  Timer? _ticker;
  BookingCallSession? _session;
  CallParticipantIdentity _participant = const CallParticipantIdentity(
    name: 'Ride participant',
    roleLabel: 'Your current ride',
  );
  bool _responding = false;
  bool _ringtoneStarted = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _repository = widget.repository ?? BookingVoiceCallRepository();
    _bookingRepository = BookingRepository();
    _bookingSubscription = _bookingRepository
        .watchBooking(widget.bookingId)
        .listen(_onBookingChanged);
    _subscription = _repository
        .watchCall(widget.bookingId)
        .listen(
          _onCallChanged,
          onError: (Object error, StackTrace stackTrace) {
            if (!mounted) return;
            setState(() => _error = DomainErrorMapper.message(error));
          },
        );
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  void _onBookingChanged(Booking? booking) {
    if (!mounted || booking == null) return;
    setState(() {
      _participant = CallParticipantIdentity.fromBooking(
        booking: booking,
        currentUserId: FirebaseAuth.instance.currentUser?.uid,
      );
    });
  }

  void _onCallChanged(BookingCallSession? session) {
    if (!mounted || session == null) return;
    final currentUserId = FirebaseAuth.instance.currentUser?.uid;
    final expectedCallId = widget.callId;
    if (expectedCallId != null && !session.matches(expectedCallId)) {
      setState(() => _error = 'This call invitation is no longer current.');
      unawaited(RingtoneService.instance.stopIncomingCall());
      return;
    }
    if (currentUserId == null ||
        !session.isIncomingFor(currentUserId, expectedCallId: expectedCallId)) {
      unawaited(RingtoneService.instance.stopIncomingCall());
      setState(() {
        _session = null;
        _error = session.isCaller(currentUserId ?? '')
            ? 'You started this call. Returning to the calling screen.'
            : 'This call invitation is not for this account.';
      });
      WidgetsBinding.instance.addPostFrameCallback((_) => _close());
      return;
    }
    final status = session.effectiveStatus();
    setState(() {
      _session = session;
      _error = null;
    });
    if (status == BookingCallStatus.ringing && !_ringtoneStarted) {
      _ringtoneStarted = true;
      unawaited(RingtoneService.instance.startIncomingCall());
    } else if (status.isTerminal || status == BookingCallStatus.accepted) {
      unawaited(RingtoneService.instance.stopIncomingCall());
      if (!_responding) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _close());
      }
    }
  }

  void _tick() {
    if (!mounted) return;
    final session = _session;
    if (session != null &&
        session.effectiveStatus() == BookingCallStatus.expired &&
        !_responding) {
      unawaited(_expire(session));
    }
    setState(() {});
  }

  Future<void> _expire(BookingCallSession session) async {
    if (_responding) return;
    setState(() => _responding = true);
    await RingtoneService.instance.stopIncomingCall();
    try {
      await _repository.respondCall(
        bookingId: widget.bookingId,
        callId: session.callId,
        response: BookingCallStatus.expired,
      );
    } catch (_) {
      // expiresAt is still enforced by token issuance and backend cleanup.
    }
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('The incoming call expired.')));
    _close();
  }

  Future<void> _decline() async {
    final session = _session;
    if (_responding || session == null) return;
    setState(() => _responding = true);
    await RingtoneService.instance.stopIncomingCall();
    try {
      await _repository.respondCall(
        bookingId: widget.bookingId,
        callId: session.callId,
        response: BookingCallStatus.declined,
      );
      if (mounted) _close();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _responding = false;
        _error = DomainErrorMapper.message(error);
      });
    }
  }

  Future<void> _accept() async {
    final session = _session;
    if (_responding || session == null) return;
    setState(() => _responding = true);
    await RingtoneService.instance.stopIncomingCall();
    try {
      // Keep the server-authoritative call in ringing state when this device
      // cannot actually provide microphone audio.
      await ensureVoiceCallMicrophonePermission();
      if (!mounted) return;
      final result = await _repository.respondCallWithResult(
        bookingId: widget.bookingId,
        callId: session.callId,
        response: BookingCallStatus.accepted,
      );
      if (!mounted) return;
      context.pushReplacement(
        Uri(
          path: AppRoutes.bookingVoiceCall,
          queryParameters: <String, String>{
            'bookingId': widget.bookingId,
            'callId': result.session.callId,
          },
        ).toString(),
        extra: {
          'bookingId': widget.bookingId,
          'callId': result.session.callId,
          'outgoing': false,
          'serverUrl': result.serverUrl,
          'credentials': result.credentials,
        },
      );
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _responding = false;
        _error = error is StateError
            ? error.message.toString()
            : DomainErrorMapper.message(error);
      });
    }
  }

  void _close() {
    if (!mounted) return;
    if (context.canPop()) context.pop();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    unawaited(_subscription?.cancel());
    unawaited(_bookingSubscription?.cancel());
    unawaited(RingtoneService.instance.stopIncomingCall());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = _session;
    final secondsRemaining =
        (session?.invitationRemaining().inMilliseconds ?? 0) / 1000;
    final seconds = secondsRemaining.ceil().clamp(0, 30);
    final canRespond =
        session?.effectiveStatus() == BookingCallStatus.ringing && !_responding;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        systemNavigationBarColor: Color(0xFF071717),
        systemNavigationBarIconBrightness: Brightness.light,
      ),
      child: Scaffold(
        backgroundColor: const Color(0xFF071717),
        body: DecoratedBox(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFF123434), Color(0xFF071717)],
            ),
          ),
          child: SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                return SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(28, 28, 28, 36),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: constraints.maxHeight - 64,
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          children: [
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.electric_rickshaw_rounded,
                                  color: Theme.of(context).colorScheme.primary,
                                  size: 20,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  'VolTrike voice call',
                                  style: Theme.of(context).textTheme.titleSmall
                                      ?.copyWith(
                                        color: Colors.white70,
                                        fontWeight: FontWeight.w600,
                                      ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 44),
                            CallParticipantAvatar(
                              identity: _participant,
                              radius: 74,
                            ),
                            const SizedBox(height: 24),
                            Text(
                              _participant.name,
                              textAlign: TextAlign.center,
                              style: Theme.of(context).textTheme.headlineMedium
                                  ?.copyWith(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w600,
                                  ),
                            ),
                            const SizedBox(height: 7),
                            Text(
                              _participant.roleLabel,
                              style: Theme.of(context).textTheme.bodyMedium
                                  ?.copyWith(color: Colors.white60),
                            ),
                            const SizedBox(height: 28),
                            Text(
                              'Incoming voice call',
                              style: Theme.of(context).textTheme.titleLarge
                                  ?.copyWith(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w600,
                                  ),
                            ),
                            const SizedBox(height: 10),
                            Text(
                              _error ??
                                  (session == null
                                      ? 'Checking the call invitation...'
                                      : '${_participant.name} is calling about your current ride.'),
                              textAlign: TextAlign.center,
                              style: Theme.of(context).textTheme.bodyMedium
                                  ?.copyWith(
                                    color: _error == null
                                        ? Colors.white70
                                        : const Color(0xFFFFB4AB),
                                  ),
                            ),
                            if (session != null && canRespond) ...[
                              const SizedBox(height: 12),
                              Text(
                                'Expires in 0:${seconds.toString().padLeft(2, '0')}',
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(color: Colors.white54),
                              ),
                            ],
                          ],
                        ),
                        Padding(
                          padding: const EdgeInsets.only(top: 44),
                          child: Column(
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  _IncomingCallAction(
                                    tooltip: 'Decline call',
                                    label: 'Decline',
                                    icon: Icons.call_end_rounded,
                                    color: const Color(0xFFD92D20),
                                    onPressed: canRespond ? _decline : null,
                                  ),
                                  const SizedBox(width: 58),
                                  _IncomingCallAction(
                                    tooltip: 'Accept call',
                                    label: 'Accept',
                                    icon: Icons.call_rounded,
                                    color: const Color(0xFF16803C),
                                    onPressed: canRespond ? _accept : null,
                                  ),
                                ],
                              ),
                              if (_error != null) ...[
                                const SizedBox(height: 24),
                                TextButton.icon(
                                  onPressed: _close,
                                  icon: const Icon(Icons.close_rounded),
                                  label: const Text('Close'),
                                  style: TextButton.styleFrom(
                                    foregroundColor: Colors.white70,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _IncomingCallAction extends StatelessWidget {
  const _IncomingCallAction({
    required this.tooltip,
    required this.label,
    required this.icon,
    required this.color,
    required this.onPressed,
  });

  final String tooltip;
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton.filled(
          tooltip: tooltip,
          onPressed: onPressed,
          icon: Icon(icon),
          iconSize: 32,
          style: IconButton.styleFrom(
            fixedSize: const Size.square(72),
            backgroundColor: color,
            foregroundColor: Colors.white,
            disabledBackgroundColor: Colors.white.withValues(alpha: .06),
            disabledForegroundColor: Colors.white30,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          label,
          style: Theme.of(
            context,
          ).textTheme.labelLarge?.copyWith(color: Colors.white),
        ),
      ],
    );
  }
}
