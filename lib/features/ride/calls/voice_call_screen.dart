import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../core/errors/domain_error_mapper.dart';
import '../../../data/models/booking.dart';
import '../../../data/models/booking_call_session.dart';
import '../../../data/repositories/booking_repository.dart';
import '../../../data/repositories/booking_voice_call_repository.dart';
import '../../common/services/ringtone_service.dart';
import 'call_participant_identity.dart';
import 'voice_call_service.dart';

class VoiceCallScreen extends StatefulWidget {
  const VoiceCallScreen({
    super.key,
    required this.bookingId,
    required this.outgoing,
    this.callId,
    this.repository,
  });

  final String bookingId;
  final bool outgoing;
  final String? callId;
  final BookingVoiceCallRepository? repository;

  @override
  State<VoiceCallScreen> createState() => _VoiceCallScreenState();
}

class _VoiceCallScreenState extends State<VoiceCallScreen> {
  late final BookingVoiceCallRepository _repository;
  late final BookingRepository _bookingRepository;
  late final VoiceCallService _service;

  StreamSubscription<BookingCallSession?>? _statusSubscription;
  StreamSubscription<Booking?>? _bookingSubscription;
  Timer? _ticker;
  BookingCallSession? _session;
  CallParticipantIdentity _participant = const CallParticipantIdentity(
    name: 'Ride participant',
    roleLabel: 'Your current ride',
  );
  String? _callId;
  String? _error;
  bool _muted = false;
  bool _starting = false;
  bool _joining = false;
  bool _ending = false;
  bool _allowPop = false;
  bool _timedOut = false;
  bool _wasConnected = false;

  @override
  void initState() {
    super.initState();
    _repository = widget.repository ?? BookingVoiceCallRepository();
    _bookingRepository = BookingRepository();
    _service = VoiceCallService(onChanged: _onLiveKitChanged);
    _callId = widget.callId;
    unawaited(RingtoneService.instance.stopIncomingCall());
    _bookingSubscription = _bookingRepository
        .watchBooking(widget.bookingId)
        .listen(_onBookingChanged);
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
    if (widget.outgoing) {
      unawaited(_startOutgoingCall());
    } else {
      final callId = _callId;
      if (callId == null || callId.isEmpty) {
        _error = 'This call invitation is no longer available.';
      } else {
        _watchCall(callId);
      }
    }
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

  Future<void> _startOutgoingCall() async {
    if (_starting) return;
    _starting = true;
    try {
      final session = await _repository.startCall(widget.bookingId);
      if (!mounted) return;
      setState(() {
        _session = session;
        _callId = session.callId;
      });
      _watchCall(session.callId);
    } catch (error) {
      if (mounted) {
        setState(() => _error = DomainErrorMapper.message(error));
      }
    } finally {
      _starting = false;
    }
  }

  void _watchCall(String callId) {
    unawaited(_statusSubscription?.cancel());
    _statusSubscription = _repository
        .watchCall(widget.bookingId)
        .listen(
          (session) {
            if (!mounted || session == null) return;
            if (!session.matches(callId)) {
              setState(() {
                _error = 'A newer ride call replaced this call.';
              });
              unawaited(_service.disconnect());
              return;
            }
            final status = session.effectiveStatus();
            setState(() {
              _session = session;
              _error = null;
              if (status == BookingCallStatus.ended &&
                  session.status == BookingCallStatus.accepted) {
                _timedOut = true;
              }
            });
            if (status == BookingCallStatus.accepted &&
                !_service.isConnected &&
                !_joining) {
              unawaited(_join(callId));
            } else if (status.isTerminal) {
              unawaited(_service.disconnect());
            }
          },
          onError: (Object error, StackTrace stackTrace) {
            if (!mounted) return;
            setState(() => _error = DomainErrorMapper.message(error));
          },
        );
  }

  Future<void> _join(String callId) async {
    if (_joining || _service.isConnected) return;
    _joining = true;
    try {
      // The incoming ringtone owns the same device audio focus. Fully release
      // it before LiveKit enables the microphone and WebRTC audio processing.
      await RingtoneService.instance.stopIncomingCall();
      final permission = await Permission.microphone.request();
      if (!permission.isGranted) {
        throw StateError(
          permission.isPermanentlyDenied
              ? 'Microphone access is disabled in system settings.'
              : 'Microphone permission is required for a voice call.',
        );
      }
      final credentials = await _repository.createCredentials(
        bookingId: widget.bookingId,
        callId: callId,
      );
      if (credentials.callId != callId) {
        throw StateError('The call changed while connecting.');
      }
      await _service.connect(
        serverUrl: credentials.serverUrl,
        token: credentials.token,
      );
      _wasConnected = true;
      if (mounted) setState(() {});
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error is StateError
            ? error.message.toString()
            : DomainErrorMapper.message(error);
      });
    } finally {
      _joining = false;
    }
  }

  void _onLiveKitChanged() {
    if (!mounted) return;
    if (_wasConnected &&
        !_service.isConnected &&
        !_service.isReconnecting &&
        !_ending &&
        _effectiveStatus == BookingCallStatus.accepted) {
      setState(() => _error = 'The call connection was lost.');
      return;
    }
    setState(() {});
  }

  void _tick() {
    if (!mounted) return;
    final session = _session;
    if (session == null) {
      setState(() {});
      return;
    }
    final status = session.effectiveStatus();
    if (status == BookingCallStatus.expired &&
        session.status == BookingCallStatus.ringing &&
        !_ending) {
      unawaited(_expireInvitation(session));
    } else if (status == BookingCallStatus.ended &&
        session.status == BookingCallStatus.accepted &&
        !_ending) {
      _timedOut = true;
      unawaited(_endCall());
    }
    setState(() {});
  }

  Future<void> _expireInvitation(BookingCallSession session) async {
    if (_ending) return;
    _ending = true;
    try {
      await _repository.respondCall(
        bookingId: widget.bookingId,
        callId: session.callId,
        response: BookingCallStatus.expired,
      );
    } catch (_) {
      // The server also derives expiration from expiresAt and cleans it up.
    } finally {
      _ending = false;
      if (mounted) setState(() {});
    }
  }

  Future<void> _endCall() async {
    final callId = _callId;
    if (_ending || callId == null || callId.isEmpty) {
      await _service.disconnect();
      return;
    }
    _ending = true;
    try {
      await _repository.endCall(bookingId: widget.bookingId, callId: callId);
    } catch (_) {
      // The Firestore timeout and backend cleanup remain authoritative.
    } finally {
      await _service.disconnect();
      _ending = false;
      if (mounted) setState(() {});
    }
  }

  Future<void> _close() async {
    if (!_effectiveStatus.isTerminal) await _endCall();
    _allowPop = true;
    if (mounted) Navigator.pop(context);
  }

  Future<void> _handlePopAttempt() async {
    if (_allowPop) return;
    if (!_effectiveStatus.isTerminal) await _endCall();
    _allowPop = true;
    if (mounted) Navigator.pop(context);
  }

  BookingCallStatus get _effectiveStatus =>
      _session?.effectiveStatus() ?? BookingCallStatus.starting;

  int get _secondsRemaining {
    final session = _session;
    if (session == null) return 0;
    final duration = _effectiveStatus == BookingCallStatus.ringing
        ? session.invitationRemaining()
        : session.callRemaining();
    return (duration.inMilliseconds / 1000).ceil().clamp(0, 120);
  }

  String get _statusText {
    if (_error != null) return _error!;
    final name = _participant.name;
    return switch (_effectiveStatus) {
      BookingCallStatus.starting => 'Starting the ride call...',
      BookingCallStatus.ringing => 'Calling $name...',
      BookingCallStatus.accepted when _service.isReconnecting =>
        'Reconnecting...',
      BookingCallStatus.accepted when !_service.isConnected =>
        'Connecting securely...',
      BookingCallStatus.accepted when _service.hasRemoteParticipant =>
        'Connected to $name',
      BookingCallStatus.accepted => 'Waiting for $name to connect...',
      BookingCallStatus.declined => '$name declined the call.',
      BookingCallStatus.expired => 'The call invitation expired.',
      BookingCallStatus.ended when _timedOut =>
        'This two-minute call has ended.',
      BookingCallStatus.ended => 'The call has ended.',
    };
  }

  @override
  void dispose() {
    _ticker?.cancel();
    unawaited(_statusSubscription?.cancel());
    unawaited(_bookingSubscription?.cancel());
    unawaited(RingtoneService.instance.stopIncomingCall());
    unawaited(_service.disconnect());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final secondsRemaining = _secondsRemaining;
    final minutes = secondsRemaining ~/ 60;
    final seconds = (secondsRemaining % 60).toString().padLeft(2, '0');
    final terminal = _effectiveStatus.isTerminal;
    final showTimer =
        !terminal &&
        (_effectiveStatus == BookingCallStatus.ringing ||
            _effectiveStatus == BookingCallStatus.accepted);

    return PopScope<void>(
      canPop: _allowPop || terminal,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) unawaited(_handlePopAttempt());
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF071717),
        appBar: AppBar(
          centerTitle: true,
          backgroundColor: Colors.transparent,
          foregroundColor: Colors.white,
          leading: IconButton(
            tooltip: terminal ? 'Close' : 'End call and go back',
            onPressed: _ending ? null : _close,
            icon: Icon(
              terminal ? Icons.close_rounded : Icons.arrow_back_rounded,
            ),
          ),
          title: const Text('Voice call'),
        ),
        body: DecoratedBox(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFF123434), Color(0xFF071717)],
            ),
          ),
          child: SafeArea(
            top: false,
            child: LayoutBuilder(
              builder: (context, constraints) {
                return SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(24, 28, 24, 32),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: constraints.maxHeight - 60,
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          children: [
                            CallParticipantAvatar(identity: _participant),
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
                            const SizedBox(height: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 7,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: .1),
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    _participant.roleLabel == 'Your driver'
                                        ? Icons.electric_rickshaw_rounded
                                        : Icons.person_rounded,
                                    size: 17,
                                    color: Colors.white70,
                                  ),
                                  const SizedBox(width: 7),
                                  Text(
                                    _participant.roleLabel,
                                    style: Theme.of(context).textTheme.bodySmall
                                        ?.copyWith(color: Colors.white70),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 28),
                            AnimatedSwitcher(
                              duration: const Duration(milliseconds: 220),
                              child: Text(
                                _statusText,
                                key: ValueKey(_statusText),
                                textAlign: TextAlign.center,
                                style: Theme.of(context).textTheme.titleMedium
                                    ?.copyWith(
                                      color: _error == null
                                          ? Colors.white
                                          : const Color(0xFFFFB4AB),
                                      fontWeight: FontWeight.w500,
                                    ),
                              ),
                            ),
                            if (showTimer) ...[
                              const SizedBox(height: 10),
                              Text(
                                _effectiveStatus == BookingCallStatus.ringing
                                    ? 'Invitation expires in 0:$seconds'
                                    : 'Call ends in $minutes:$seconds',
                                style: Theme.of(context).textTheme.bodyMedium
                                    ?.copyWith(color: Colors.white60),
                              ),
                            ],
                            if (!terminal &&
                                _effectiveStatus ==
                                    BookingCallStatus.accepted) ...[
                              const SizedBox(height: 16),
                              const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.lock_rounded,
                                    color: Colors.white54,
                                    size: 15,
                                  ),
                                  SizedBox(width: 6),
                                  Text(
                                    'Secure ride call',
                                    style: TextStyle(color: Colors.white54),
                                  ),
                                ],
                              ),
                            ],
                          ],
                        ),
                        Padding(
                          padding: const EdgeInsets.only(top: 42),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              _CallControlButton(
                                tooltip: _muted ? 'Unmute' : 'Mute',
                                label: _muted ? 'Unmute' : 'Mute',
                                icon: _muted
                                    ? Icons.mic_off_rounded
                                    : Icons.mic_rounded,
                                onPressed: !_service.isConnected || terminal
                                    ? null
                                    : () async {
                                        await _service.setMuted(!_muted);
                                        if (mounted) {
                                          setState(() => _muted = !_muted);
                                        }
                                      },
                                backgroundColor: _muted
                                    ? Theme.of(context).colorScheme.primary
                                    : Colors.white.withValues(alpha: .14),
                                foregroundColor: Colors.white,
                              ),
                              const SizedBox(width: 36),
                              _CallControlButton(
                                tooltip: terminal ? 'Close' : 'End call',
                                label: terminal ? 'Close' : 'End call',
                                icon: terminal
                                    ? Icons.close_rounded
                                    : Icons.call_end_rounded,
                                onPressed: _ending ? null : _close,
                                backgroundColor: const Color(0xFFD92D20),
                                foregroundColor: Colors.white,
                              ),
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

class _CallControlButton extends StatelessWidget {
  const _CallControlButton({
    required this.tooltip,
    required this.label,
    required this.icon,
    required this.onPressed,
    required this.backgroundColor,
    required this.foregroundColor,
  });

  final String tooltip;
  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
  final Color backgroundColor;
  final Color foregroundColor;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton.filled(
          tooltip: tooltip,
          onPressed: onPressed,
          icon: Icon(icon),
          iconSize: 31,
          style: IconButton.styleFrom(
            fixedSize: const Size.square(68),
            backgroundColor: backgroundColor,
            foregroundColor: foregroundColor,
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
