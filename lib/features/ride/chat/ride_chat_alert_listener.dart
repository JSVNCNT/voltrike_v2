import 'dart:async';

import 'package:flutter/material.dart';

import '../../../data/repositories/auth_repository.dart';
import '../../../data/repositories/chat_repository.dart';
import '../../common/services/ringtone_service.dart';

/// Watches a ride conversation while a tracking screen is visible. It keeps
/// chat unobtrusive: one sound and a five-second actionable popup per message.
class RideChatAlertListener extends StatefulWidget {
  const RideChatAlertListener({
    super.key,
    required this.bookingId,
    required this.onOpenChat,
    required this.child,
  });

  final String bookingId;
  final VoidCallback onOpenChat;
  final Widget child;

  @override
  State<RideChatAlertListener> createState() => _RideChatAlertListenerState();
}

class _RideChatAlertListenerState extends State<RideChatAlertListener> {
  final _repository = ChatRepository();
  StreamSubscription? _subscription;
  String? _latestMessageId;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    final userId = AuthRepository().currentUser?.uid;
    if (userId == null) return;
    _subscription = _repository.messages(widget.bookingId).listen((messages) {
      if (messages.isEmpty) return;
      final latest = messages.first;
      if (!_ready) {
        _ready = true;
        _latestMessageId = latest.id;
        return;
      }
      if (latest.id == _latestMessageId) return;
      _latestMessageId = latest.id;
      if (latest.senderId == userId || latest.seenBy.contains(userId)) return;
      unawaited(RingtoneService.instance.playChat());
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text('New message: ${latest.text}'),
            duration: const Duration(seconds: 5),
            action: SnackBarAction(label: 'Open', onPressed: widget.onOpenChat),
          ),
        );
    });
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
