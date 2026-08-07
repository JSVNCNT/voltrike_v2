import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/errors/domain_error_mapper.dart';
import '../../../data/models/booking.dart';
import '../../../data/models/booking_call_session.dart';
import '../../../data/repositories/booking_repository.dart';
import '../../../data/repositories/booking_voice_call_repository.dart';
import '../../common/services/ringtone_service.dart';
import 'call_participant_identity.dart';
import 'microphone_permission.dart';
import 'voice_call_service.dart';

class VoiceCallScreen extends StatefulWidget {
  const VoiceCallScreen({
    super.key,
    required this.bookingId,
    required this.outgoing,
    this.callId,
    this.initialServerUrl,
    this.initialCredentials,
    this.repository,
  });

  final String bookingId;
  final bool outgoing;
  final String? callId;
  final String? initialServerUrl;
  final BookingVoiceCallCredentials? initialCredentials;
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
  bool _speakerOn = false;
  bool _nearbyFeedbackGuard = false;
  bool _mutedBeforeFeedbackGuard = false;
  bool _starting = false;
  bool _joining = false;
  bool _ending = false;
  bool _allowPop = false;
  bool _timedOut = false;
  bool _wasConnected = false;
  int _joinGeneration = 0;
  BookingVoiceCallCredentials? _credentials;

  @override
  void initState() {
    super.initState();
    _repository = widget.repository ?? BookingVoiceCallRepository();
    _bookingRepository = BookingRepository();
    _service = VoiceCallService(onChanged: _onLiveKitChanged);
    _callId = widget.callId;
    _credentials = widget.initialCredentials;
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
        if (_credentials?.isUsableFor(callId) ?? false) {
          unawaited(_join(callId));
        }
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
      // Do not create a durable ringing invitation if this device cannot
      // provide the microphone needed to complete it.
      await ensureVoiceCallMicrophonePermission();
      final result = await _repository.startCallWithResult(widget.bookingId);
      if (!mounted) return;
      final session = result.session;
      setState(() {
        _session = session;
        _callId = session.callId;
        _credentials = result.credentials;
      });
      final serverUrl =
          result.serverUrl ??
          result.credentials?.serverUrl ??
          widget.initialServerUrl;
      if (serverUrl != null && serverUrl.isNotEmpty) {
        unawaited(
          _service.prepareConnection(
            serverUrl: serverUrl,
            token: result.credentials?.token,
          ),
        );
      }
      _watchCall(session.callId);
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = switch (error) {
            StateError stateError => stateError.message.toString(),
            TimeoutException _ =>
              'The voice call service timed out. Please try again.',
            _ => DomainErrorMapper.message(error),
          };
        });
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
              _joinGeneration++;
              _joining = false;
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
              _joinGeneration++;
              _joining = false;
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
    final attempt = ++_joinGeneration;
    _joining = true;
    if (mounted) setState(() => _error = null);
    try {
      // The incoming ringtone owns the same device audio focus. Fully release
      // it before LiveKit enables the microphone and WebRTC audio processing.
      await RingtoneService.instance.stopIncomingCall();
      await ensureVoiceCallMicrophonePermission();
      if (!_isCurrentJoin(attempt, callId)) return;

      var credentials = _credentials;
      if (!(credentials?.isUsableFor(callId) ?? false)) {
        credentials = await _repository.createCredentials(
          bookingId: widget.bookingId,
          callId: callId,
        );
      }
      if (!_isCurrentJoin(attempt, callId)) return;
      final activeCredentials = credentials;
      if (activeCredentials == null || !activeCredentials.isUsableFor(callId)) {
        throw StateError('The call changed while connecting.');
      }
      _credentials = activeCredentials;
      await _service.connect(
        serverUrl: activeCredentials.serverUrl,
        token: activeCredentials.token,
      );
      if (!_isCurrentJoin(attempt, callId)) {
        await _service.disconnect();
        return;
      }
      _wasConnected = true;
      if (mounted) setState(() {});
    } on VoiceCallConnectionCancelled {
      // A terminal Firestore state, navigation, or a newer call invalidated
      // this connection attempt. Its Room has already been cleaned up.
    } catch (error) {
      if (!_isCurrentJoin(attempt, callId)) return;
      setState(() {
        _error = switch (error) {
          StateError stateError => stateError.message.toString(),
          TimeoutException _ =>
            'The secure call connection timed out. Please try again.',
          _ => DomainErrorMapper.message(error),
        };
      });
    } finally {
      if (attempt == _joinGeneration) {
        _joining = false;
        if (mounted) setState(() {});
      }
    }
  }

  bool _isCurrentJoin(int attempt, String callId) {
    return mounted &&
        attempt == _joinGeneration &&
        _callId == callId &&
        !_effectiveStatus.isTerminal &&
        !_ending;
  }

  void _onLiveKitChanged() {
    if (!mounted) return;
    if (_wasConnected &&
        !_service.isConnected &&
        !_service.isResuming &&
        !_service.isReconnecting &&
        !_ending &&
        _effectiveStatus == BookingCallStatus.accepted) {
      setState(() => _error = 'The call connection was lost.');
      return;
    }
    setState(() {
      if (_error == 'The call connection was lost.' &&
          (_service.isConnected ||
              _service.isResuming ||
              _service.isReconnecting)) {
        _error = null;
      }
    });
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
    _joinGeneration++;
    _joining = false;
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

  /// Nearby loudspeakers can form a physical feedback loop that no network
  /// service can remove. This deliberately uses the earpiece and pauses this
  /// phone's microphone until the rider turns the guard off.
  Future<void> _setNearbyFeedbackGuard(bool enabled) async {
    if (!_service.isConnected) return;
    try {
      if (enabled) {
        _mutedBeforeFeedbackGuard = _muted;
        await _service.setSpeakerOn(false);
        await _service.setMuted(true);
      } else {
        await _service.setMuted(_mutedBeforeFeedbackGuard);
      }
      if (mounted) {
        setState(() {
          _nearbyFeedbackGuard = enabled;
          _speakerOn = false;
          _muted = enabled ? true : _mutedBeforeFeedbackGuard;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'Could not change nearby feedback protection. Please try again.',
        );
      }
    }
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

  int get _elapsedSeconds {
    final session = _session;
    if (session == null) return 0;
    return session.callElapsed().inSeconds.clamp(0, 359999);
  }

  String get _statusText {
    if (_error != null) return _error!;
    final name = _participant.name;
    return switch (_effectiveStatus) {
      BookingCallStatus.starting => 'Starting the ride call...',
      BookingCallStatus.ringing => 'Calling $name...',
      BookingCallStatus.accepted when _service.isResuming =>
        'Restoring the secure connection...',
      BookingCallStatus.accepted when _service.isReconnecting =>
        'Reconnecting call audio...',
      BookingCallStatus.accepted when !_service.isConnected =>
        'Connecting securely...',
      BookingCallStatus.accepted when !_service.isMicrophonePublished =>
        'Securing your microphone...',
      BookingCallStatus.accepted when !_service.hasRemoteParticipant =>
        'Waiting for $name to connect...',
      BookingCallStatus.accepted when _service.remoteAudioSubscriptionFailed =>
        '$name joined, but audio could not connect.',
      BookingCallStatus.accepted when !_service.hasRemoteAudio =>
        '$name joined • connecting audio...',
      BookingCallStatus.accepted when _service.hasPoorConnection =>
        'Connected to $name • Poor connection',
      BookingCallStatus.accepted when _service.isMediaReady =>
        'Connected to $name',
      BookingCallStatus.accepted => 'Connecting call audio...',
      BookingCallStatus.declined => '$name declined the call.',
      BookingCallStatus.expired => 'The call invitation expired.',
      BookingCallStatus.ended when _timedOut => 'The call has ended.',
      BookingCallStatus.ended => 'The call has ended.',
    };
  }

  @override
  void dispose() {
    _joinGeneration++;
    _ticker?.cancel();
    unawaited(_statusSubscription?.cancel());
    unawaited(_bookingSubscription?.cancel());
    unawaited(RingtoneService.instance.stopIncomingCall());
    unawaited(_service.disconnect());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isRinging = _effectiveStatus == BookingCallStatus.ringing;
    final timerSeconds = isRinging ? _secondsRemaining : _elapsedSeconds;
    final minutes = timerSeconds ~/ 60;
    final seconds = (timerSeconds % 60).toString().padLeft(2, '0');
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
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: const SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.light,
          systemNavigationBarColor: Color(0xFF071717),
          systemNavigationBarIconBrightness: Brightness.light,
        ),
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
                                style: Theme.of(context)
                                    .textTheme
                                    .headlineMedium
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
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall
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
                              if (!terminal &&
                                  _effectiveStatus ==
                                      BookingCallStatus.accepted &&
                                  _service.isMediaReady) ...[
                                const SizedBox(height: 12),
                                _CallAudioState(
                                  remoteSpeaking:
                                      _service.remoteParticipantIsSpeaking,
                                  participantName: _participant.name,
                                ),
                              ],
                              if (showTimer) ...[
                                const SizedBox(height: 10),
                                Text(
                                  isRinging
                                      ? 'Invitation expires in 0:$seconds'
                                      : '$minutes:$seconds',
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
                                if (_error != null && !_joining) ...[
                                  const SizedBox(height: 10),
                                  TextButton.icon(
                                    onPressed: () {
                                      final callId = _callId;
                                      if (callId != null) {
                                        unawaited(_join(callId));
                                      }
                                    },
                                    icon: const Icon(Icons.refresh_rounded),
                                    label: const Text('Try again'),
                                    style: TextButton.styleFrom(
                                      foregroundColor: Colors.white70,
                                    ),
                                  ),
                                ],
                              ],
                            ],
                          ),
                          if (!terminal &&
                              _effectiveStatus == BookingCallStatus.accepted &&
                              _service.isConnected) ...[
                            const SizedBox(height: 22),
                            TextButton.icon(
                              onPressed: () => unawaited(
                                _setNearbyFeedbackGuard(!_nearbyFeedbackGuard),
                              ),
                              icon: Icon(
                                _nearbyFeedbackGuard
                                    ? Icons.hearing_rounded
                                    : Icons.volume_off_rounded,
                                size: 18,
                              ),
                              label: Text(
                                _nearbyFeedbackGuard
                                    ? 'Nearby Feedback Guard on — tap to resume mic'
                                    : 'Nearby phones? Enable Feedback Guard',
                              ),
                              style: TextButton.styleFrom(
                                foregroundColor: _nearbyFeedbackGuard
                                    ? const Color(0xFF9CF3D0)
                                    : Colors.white70,
                              ),
                            ),
                          ],
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
                                  onPressed:
                                      !_service.isConnected ||
                                          terminal ||
                                          _nearbyFeedbackGuard
                                      ? null
                                      : () async {
                                          try {
                                            await _service.setMuted(!_muted);
                                            if (mounted) {
                                              setState(() => _muted = !_muted);
                                            }
                                          } catch (_) {
                                            if (mounted) {
                                              setState(
                                                () => _error =
                                                    'Could not update the microphone. Please try again.',
                                              );
                                            }
                                          }
                                        },
                                  backgroundColor: _muted
                                      ? Theme.of(context).colorScheme.primary
                                      : Colors.white.withValues(alpha: .14),
                                  foregroundColor: Colors.white,
                                ),
                                const SizedBox(width: 20),
                                _CallControlButton(
                                  tooltip: _speakerOn
                                      ? 'Use earpiece'
                                      : 'Use speaker',
                                  label: _speakerOn ? 'Speaker' : 'Earpiece',
                                  icon: _speakerOn
                                      ? Icons.volume_up_rounded
                                      : Icons.hearing_rounded,
                                  onPressed:
                                      !_service.isConnected ||
                                          terminal ||
                                          _nearbyFeedbackGuard
                                      ? null
                                      : () async {
                                          try {
                                            await _service.setSpeakerOn(
                                              !_speakerOn,
                                            );
                                            if (mounted) {
                                              setState(
                                                () => _speakerOn = !_speakerOn,
                                              );
                                            }
                                          } catch (_) {
                                            if (mounted) {
                                              setState(
                                                () => _error =
                                                    'Could not change the call audio output. Please try again.',
                                              );
                                            }
                                          }
                                        },
                                  backgroundColor: _speakerOn
                                      ? Theme.of(context).colorScheme.primary
                                      : Colors.white.withValues(alpha: .14),
                                  foregroundColor: Colors.white,
                                ),
                                const SizedBox(width: 20),
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
      ),
    );
  }
}

class _CallAudioState extends StatelessWidget {
  const _CallAudioState({
    required this.remoteSpeaking,
    required this.participantName,
  });

  final bool remoteSpeaking;
  final String participantName;

  @override
  Widget build(BuildContext context) {
    final label = remoteSpeaking
        ? '$participantName is speaking'
        : 'Audio connected';
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: remoteSpeaking
            ? const Color(0xFF1A8D79).withValues(alpha: .32)
            : Colors.white.withValues(alpha: .1),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            remoteSpeaking ? Icons.graphic_eq_rounded : Icons.volume_up_rounded,
            color: remoteSpeaking ? const Color(0xFF9CF3D0) : Colors.white70,
            size: 17,
          ),
          const SizedBox(width: 7),
          Text(label, style: const TextStyle(color: Colors.white70)),
        ],
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
