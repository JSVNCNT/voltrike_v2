import 'dart:async';

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import 'voice_call_service.dart';

class VoiceCallScreen extends StatefulWidget {
  const VoiceCallScreen({
    super.key,
    required this.connect,
    required this.endCall,
  });
  final Future<void> Function(VoiceCallService service) connect;
  final Future<void> Function() endCall;
  @override State<VoiceCallScreen> createState() => _VoiceCallScreenState();
}

class _VoiceCallScreenState extends State<VoiceCallScreen> {
  final _service = VoiceCallService();
  bool _muted = false;
  bool _expired = false;
  int _secondsRemaining = 120;
  String? _error;
  Timer? _callTimer;

  @override
  void initState() {
    super.initState();
    _join();
  }

  Future<void> _join() async {
    try {
      if (!(await Permission.microphone.request()).isGranted) {
        throw StateError('Microphone permission is required for a voice call.');
      }
      await widget.connect(_service);
      _startCallTimer();
      if (mounted) setState(() {});
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
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
                  const Icon(Icons.call, size: 80),
                  const SizedBox(height: 16),
                  Text(_expired
                      ? 'This two-minute call has ended.'
                      : _service.isConnected
                          ? 'Connected'
                          : 'Connecting...'),
                  if (!_expired) ...[
                    const SizedBox(height: 8),
                    Text('Call ends in $minutes:$seconds'),
                  ],
                  const SizedBox(height: 24),
                  IconButton(
                    iconSize: 56,
                    icon: Icon(_muted ? Icons.mic_off : Icons.mic),
                    onPressed: _expired
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
                    child: Text(_expired ? 'Close' : 'End call'),
                  ),
                ],
              ),
      ),
    );
  }
}
