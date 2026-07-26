import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../app/routes.dart';
import '../../../data/repositories/booking_voice_call_repository.dart';
import '../../common/services/ringtone_service.dart';

class IncomingCallScreen extends StatefulWidget {
  const IncomingCallScreen({super.key, required this.bookingId});

  final String bookingId;

  @override
  State<IncomingCallScreen> createState() => _IncomingCallScreenState();
}

class _IncomingCallScreenState extends State<IncomingCallScreen> {
  bool _responding = false;
  Timer? _expiry;

  @override
  void initState() {
    super.initState();
    unawaited(RingtoneService.instance.startIncomingCall());
    _expiry = Timer(const Duration(seconds: 30), _expire);
  }

  Future<void> _expire() async {
    await _decline(expired: true);
  }

  Future<void> _decline({bool expired = false}) async {
    if (_responding) return;
    setState(() => _responding = true);
    _expiry?.cancel();
    await RingtoneService.instance.stopIncomingCall();
    try {
      await BookingVoiceCallRepository().declineCall(
        widget.bookingId,
        expired: expired,
      );
    } catch (_) {
      // Closing locally remains valid when the invitation already expired.
    }
    if (!mounted) return;
    if (expired) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('The incoming call expired.')),
      );
    }
    context.pop();
  }

  Future<void> _accept() async {
    if (_responding) return;
    setState(() => _responding = true);
    _expiry?.cancel();
    await RingtoneService.instance.stopIncomingCall();
    if (!mounted) return;
    context.pushReplacement(
      AppRoutes.bookingVoiceCall,
      extra: {'bookingId': widget.bookingId, 'accepting': true},
    );
  }

  @override
  void dispose() {
    _expiry?.cancel();
    unawaited(RingtoneService.instance.stopIncomingCall());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const CircleAvatar(
                  radius: 54,
                  child: Icon(Icons.person, size: 58),
                ),
                const SizedBox(height: 24),
                Text(
                  'Incoming ride call',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 8),
                const Text(
                  'Your current ride participant is calling.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 48),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    FilledButton.tonalIcon(
                      onPressed: _responding ? null : _decline,
                      icon: const Icon(Icons.call_end),
                      label: const Text('Decline'),
                    ),
                    FilledButton.icon(
                      onPressed: _responding ? null : _accept,
                      icon: const Icon(Icons.call),
                      label: const Text('Accept'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
