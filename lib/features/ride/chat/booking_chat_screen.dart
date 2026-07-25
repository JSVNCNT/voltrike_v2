import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/models/chat_message.dart';
import '../../../data/repositories/auth_repository.dart';
import '../../../data/repositories/chat_repository.dart';

class BookingChatScreen extends ConsumerStatefulWidget {
  const BookingChatScreen({super.key, required this.bookingId, required this.members});
  final String bookingId;
  final List<String> members;
  @override ConsumerState<BookingChatScreen> createState() => _BookingChatScreenState();
}

class _BookingChatScreenState extends ConsumerState<BookingChatScreen> {
  final _controller = TextEditingController();
  final _repository = ChatRepository();
  String? _lastSeenMessageId;
  Timer? _typingTimer;
  bool _typing = false;

  @override
  void dispose() {
    _typingTimer?.cancel();
    final userId = AuthRepository().currentUser?.uid;
    if (userId != null) {
      unawaited(_repository.setTyping(
        bookingId: widget.bookingId,
        userId: userId,
        isTyping: false,
      ));
    }
    _controller.dispose();
    super.dispose();
  }
  @override
  Widget build(BuildContext context) {
    final user = AuthRepository().currentUser;
    if (user == null) return const Scaffold(body: Center(child: Text('Not signed in.')));
    return Scaffold(appBar: AppBar(title: const Text('Ride chat')), body: Column(children: [
      Expanded(child: StreamBuilder<List<ChatMessage>>(
        stream: _repository.messages(widget.bookingId),
        builder: (context, snapshot) {
          final messages = snapshot.data ?? const <ChatMessage>[];
          if (messages.isNotEmpty && _lastSeenMessageId != messages.first.id) {
            _lastSeenMessageId = messages.first.id;
            WidgetsBinding.instance.addPostFrameCallback((_) => _repository.markSeen(widget.bookingId, user.uid));
          }
          return ListView.builder(reverse: true, padding: const EdgeInsets.all(12), itemCount: messages.length, itemBuilder: (_, index) {
            final message = messages[index]; final mine = message.senderId == user.uid;
            return Align(alignment: mine ? Alignment.centerRight : Alignment.centerLeft, child: Container(margin: const EdgeInsets.symmetric(vertical: 4), padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: mine ? Theme.of(context).colorScheme.primary : Colors.grey.shade200, borderRadius: BorderRadius.circular(14)), child: Text(message.text, style: TextStyle(color: mine ? Colors.white : null))));
          });
        },
      )),
      StreamBuilder<List<String>>(
        stream: _repository.typingUsers(widget.bookingId, user.uid),
        builder: (context, snapshot) {
          final count = snapshot.data?.length ?? 0;
          return AnimatedSize(
            duration: const Duration(milliseconds: 150),
            child: count == 0
                ? const SizedBox.shrink()
                : const Padding(
                    padding: EdgeInsets.fromLTRB(16, 0, 16, 6),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text('Typing…'),
                    ),
                  ),
          );
        },
      ),
      SafeArea(child: Padding(padding: const EdgeInsets.all(12), child: Row(children: [Expanded(child: TextField(controller: _controller, textInputAction: TextInputAction.send, onChanged: (_) => _onChanged(user.uid), onSubmitted: (_) => _send(user.uid), decoration: const InputDecoration(hintText: 'Message', border: OutlineInputBorder()))), IconButton(icon: const Icon(Icons.send), onPressed: () => _send(user.uid))]))),
    ]));
  }
  void _onChanged(String userId) {
    if (!_typing && _controller.text.trim().isNotEmpty) {
      _typing = true;
      unawaited(_repository.setTyping(
        bookingId: widget.bookingId,
        userId: userId,
        isTyping: true,
      ));
    }
    _typingTimer?.cancel();
    _typingTimer = Timer(const Duration(seconds: 2), () {
      _setNotTyping(userId);
    });
  }

  void _setNotTyping(String userId) {
    if (!_typing) return;
    _typing = false;
    unawaited(_repository.setTyping(
      bookingId: widget.bookingId,
      userId: userId,
      isTyping: false,
    ));
  }

  Future<void> _send(String userId) async {
    _setNotTyping(userId);
    await _repository.send(bookingId: widget.bookingId, senderId: userId, members: widget.members, text: _controller.text);
    _controller.clear();
  }
}
