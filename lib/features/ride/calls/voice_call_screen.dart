import 'dart:async';

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import 'voice_call_service.dart';
import '../../common/services/ringtone_service.dart';

class VoiceCallScreen extends StatefulWidget {
  const VoiceCallScreen({
    super.key,
    required this.connect,
    required this.endCall,
    required this.callStatus,
    required this.initiate,
    required this.incoming,
  });
  final Future<void> Function(VoiceCallService service) connect;
  final Future<void> Function() endCall;
  final Stream<String> callStatus;
  final Future<void> Function() initiate;
  final bool incoming;
  @override
  State<VoiceCallScreen> createState() => _VoiceCallScreenState();
}

class _VoiceCallScreenState extends State<VoiceCallScreen> {
  final _service = VoiceCallService();
  bool _muted = false;
  bool _expired = false;
  int _secondsRemaining = 120;
  String? _error;
  Timer? _callTimer;
  StreamSubscription<String>? _statusSubscription;
  String _remoteStatus = 'starting';
  bool _joining = false;

  @override
  void initState() {
    super.initState();
    unawaited(RingtoneService.instance.stopIncomingCall());
    _statusSubscription = widget.callStatus.listen((status) {
      if (!mounted) return;
      setState(() => _remoteStatus = status);
      if (status == 'accepted' && !_service.isConnected && !_joining) {
        unawaited(_join());
      }
      if (status == 'declined' || status == 'ended' || status == 'expired') {
        _callTimer?.cancel();
        unawaited(_service.disconnect());
      }
    });
    if (widget.incoming) {
      unawaited(_join());
    } else {
      unawaited(_initiate());
    }
  }

  Future<void> _initiate() async {
    try {
      await widget.initiate();
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    }
  }

  Future<void> _join() async {
    if (_joining || _service.isConnected) return;
    _joining = true;
    try {
      if (!(await Permission.microphone.request()).isGranted) {
        throw StateError('Microphone permission is required for a voice call.');
      }
      await widget.connect(_service);
      _startCallTimer();
      if (mounted) setState(() {});
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      _joining = false;
    }
  }

  void _startCallTimer() {
    _callTimer?.cancel();
    _callTimer = Timer.periodic(const Duration(seconds: 1), (timer) async {
      if (!mounted) return;
      if (_secondsRemaining <= 1) {
        timer.cancel();
        await _endCall(showTimeout: true);
        return;
      }
      setState(() => _secondsRemaining--);
    });
  }

  Future<void> _endCall({bool showTimeout = false}) async {
    _callTimer?.cancel();
    try {
      await widget.endCall();
    } catch (_) {
      // Local disconnect is still useful if the room was already removed or
      // the network is temporarily unavailable.
    }
    await _service.disconnect();
    if (mounted && showTimeout) {
      setState(() {
        _secondsRemaining = 0;
        _expired = true;
      });
    }
  }

  @override
  void dispose() {
    _callTimer?.cancel();
    _statusSubscription?.cancel();
    unawaited(RingtoneService.instance.stopIncomingCall());
    unawaited(_service.disconnect());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final minutes = _secondsRemaining ~/ 60;
    final seconds = (_secondsRemaining % 60).toString().padLeft(2, '0');
    return Scaffold(
      appBar: AppBar(title: const Text('Voice call')),
      body: Center(
        child: _error != null
            ? Text('Could not join call: $_error')
            : Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    _remoteStatus == 'declined'
                        ? Icons.call_end
                        : Icons.call,
                    size: 80,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    _remoteStatus == 'declined'
                        ? 'The other participant declined the call.'
                        : _remoteStatus == 'ended'
                        ? 'The call has ended.'
                        : _expired || _remoteStatus == 'expired'
                        ? 'This two-minute call has ended.'
                        : _remoteStatus == 'ringing'
                        ? 'Calling your ride participant...'
                        : !_service.isConnected
                        ? 'Connecting...'
                        : _service.hasRemoteParticipant
                        ? 'Connected to the other rider'
                        : 'Waiting for the other rider to tap Call...',
                    textAlign: TextAlign.center,
                  ),
                  if (_service.isConnected &&
                      !_service.hasRemoteParticipant &&
                      !_expired) ...[
                    const SizedBox(height: 8),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 24),
                      child: Text(
                        'Waiting for the other participant to accept.',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ],
                  if (!_expired &&
                      !['declined', 'ended', 'expired'].contains(_remoteStatus)) ...[
                    const SizedBox(height: 8),
                    Text('Call ends in $minutes:$seconds'),
                  ],
                  const SizedBox(height: 24),
                  IconButton(
                    iconSize: 56,
                    icon: Icon(_muted ? Icons.mic_off : Icons.mic),
                    onPressed: _expired ||
                            ['declined', 'ended', 'expired'].contains(_remoteStatus)
                        ? null
                        : () async {
                            await _service.setMuted(!_muted);
                            if (mounted) setState(() => _muted = !_muted);
                          },
                  ),
                  TextButton(
                    onPressed: () async {
                      await _endCall();
                      if (context.mounted) Navigator.pop(context);
                    },
                    child: Text(
                      _expired ||
                              ['declined', 'ended', 'expired'].contains(_remoteStatus)
                          ? 'Close'
                          : 'End call',
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
