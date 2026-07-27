import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/errors/domain_error_mapper.dart';
import '../../../core/theme/app_colors.dart';
import '../../../data/models/chat_message.dart';
import '../../../data/repositories/auth_repository.dart';
import '../../../data/repositories/chat_repository.dart';
import '../../common/presentation/widgets/app_app_bar.dart';
import '../../common/services/ringtone_service.dart';

class BookingChatScreen extends ConsumerStatefulWidget {
  const BookingChatScreen({
    super.key,
    required this.bookingId,
    required this.members,
  });

  final String bookingId;
  final List<String> members;

  @override
  ConsumerState<BookingChatScreen> createState() => _BookingChatScreenState();
}

class _BookingChatScreenState extends ConsumerState<BookingChatScreen> {
  final _controller = TextEditingController();
  final _repository = ChatRepository();
  String? _lastSeenMessageId;
  Timer? _typingTimer;
  bool _typing = false;
  bool _messagesReady = false;

  @override
  void dispose() {
    _typingTimer?.cancel();
    final userId = AuthRepository().currentUser?.uid;
    if (userId != null) {
      unawaited(
        _repository.setTyping(
          bookingId: widget.bookingId,
          userId: userId,
          isTyping: false,
        ),
      );
    }
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final user = AuthRepository().currentUser;
    if (user == null) {
      return const Scaffold(body: Center(child: Text('Not signed in.')));
    }

    return Scaffold(
      appBar: const AppAppBar(title: 'Ride chat'),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<List<ChatMessage>>(
              stream: _repository.messages(widget.bookingId),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting &&
                    !snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        DomainErrorMapper.message(snapshot.error!),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  );
                }

                final messages = snapshot.data ?? const <ChatMessage>[];
                _processLatestMessage(messages, user.uid);
                if (messages.isEmpty) return const _EmptyChat();

                return ListView.builder(
                  reverse: true,
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
                  itemCount: messages.length,
                  itemBuilder: (context, index) {
                    final message = messages[index];
                    return _MessageBubble(
                      message: message,
                      mine: message.senderId == user.uid,
                    );
                  },
                );
              },
            ),
          ),
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
          SafeArea(
            top: false,
            child: Container(
              padding: const EdgeInsets.fromLTRB(12, 10, 8, 12),
              decoration: const BoxDecoration(
                color: AppColors.surface,
                border: Border(top: BorderSide(color: AppColors.border)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      textInputAction: TextInputAction.send,
                      textCapitalization: TextCapitalization.sentences,
                      onChanged: (_) => _onChanged(user.uid),
                      onSubmitted: (_) => _send(user.uid),
                      decoration: const InputDecoration(
                        labelText: 'Message',
                        hintText: 'Type a message',
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    tooltip: 'Send message',
                    style: IconButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: AppColors.textWhite,
                    ),
                    icon: const Icon(Icons.send_rounded),
                    onPressed: () => _send(user.uid),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _processLatestMessage(List<ChatMessage> messages, String userId) {
    if (messages.isEmpty || _lastSeenMessageId == messages.first.id) return;
    final latest = messages.first;
    final isNewIncoming = _messagesReady && latest.senderId != userId;
    _messagesReady = true;
    _lastSeenMessageId = latest.id;
    if (isNewIncoming) {
      unawaited(RingtoneService.instance.playInsideChat());
    }
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _repository.markSeen(widget.bookingId, userId),
    );
  }

  void _onChanged(String userId) {
    if (!_typing && _controller.text.trim().isNotEmpty) {
      _typing = true;
      unawaited(
        _repository.setTyping(
          bookingId: widget.bookingId,
          userId: userId,
          isTyping: true,
        ),
      );
    }
    _typingTimer?.cancel();
    _typingTimer = Timer(
      const Duration(seconds: 2),
      () => _setNotTyping(userId),
    );
  }

  void _setNotTyping(String userId) {
    if (!_typing) return;
    _typing = false;
    unawaited(
      _repository.setTyping(
        bookingId: widget.bookingId,
        userId: userId,
        isTyping: false,
      ),
    );
  }

  Future<void> _send(String userId) async {
    _setNotTyping(userId);
    await _repository.send(
      bookingId: widget.bookingId,
      senderId: userId,
      members: widget.members,
      text: _controller.text,
    );
    _controller.clear();
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.message, required this.mine});

  final ChatMessage message;
  final bool mine;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => Align(
        alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          constraints: BoxConstraints(maxWidth: constraints.maxWidth * 0.78),
          margin: const EdgeInsets.symmetric(vertical: 4),
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
          decoration: BoxDecoration(
            color: mine ? AppColors.primary : AppColors.surface,
            border: mine ? null : Border.all(color: AppColors.border),
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(16),
              topRight: const Radius.circular(16),
              bottomLeft: Radius.circular(mine ? 16 : 4),
              bottomRight: Radius.circular(mine ? 4 : 16),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                message.text,
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: mine
                      ? AppColors.textWhite
                      : AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                DateFormat('h:mm a').format(message.sentAt),
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: mine
                      ? AppColors.textWhite.withValues(alpha: 0.78)
                      : AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyChat extends StatelessWidget {
  const _EmptyChat();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.chat_bubble_outline_rounded,
              size: 48,
              color: AppColors.textSecondary,
            ),
            const SizedBox(height: 14),
            Text(
              'No messages yet',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 5),
            Text(
              'Use ride chat for pickup and trip coordination.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }
}
