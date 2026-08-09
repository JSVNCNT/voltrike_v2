import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../../../core/errors/domain_error_mapper.dart';
import '../../../data/models/chat_message.dart';
import '../../../data/repositories/auth_repository.dart';
import '../../../data/repositories/chat_repository.dart';
import '../../common/presentation/widgets/app_app_bar.dart';
import '../../common/services/ringtone_service.dart';

class BookingChatScreen extends ConsumerStatefulWidget {
  const BookingChatScreen({super.key, required this.bookingId});

  final String bookingId;

  @override
  ConsumerState<BookingChatScreen> createState() => _BookingChatScreenState();
}

class _BookingChatScreenState extends ConsumerState<BookingChatScreen> {
  static const _quickActions = <String>[
    'I’m here.',
    'Please wait a moment.',
    'I can’t find you.',
    'I’m at the pickup pin.',
  ];

  final _controller = TextEditingController();
  final _repository = ChatRepository();
  final _picker = ImagePicker();
  String? _lastSeenMessageId;
  Timer? _typingTimer;
  bool _typing = false;
  bool _messagesReady = false;
  bool _sending = false;

  @override
  void dispose() {
    _typingTimer?.cancel();
    final userId = AuthRepository().currentUser?.uid;
    if (userId != null) {
      unawaited(
        _repository.setTyping(bookingId: widget.bookingId, isTyping: false),
      );
    }
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final mediaQuery = MediaQuery.of(context);
    final keyboardVisible = mediaQuery.viewInsets.bottom > 0;
    final user = AuthRepository().currentUser;
    if (user == null) {
      return const Scaffold(body: Center(child: Text('Not signed in.')));
    }

    return Scaffold(
      appBar: const AppAppBar(title: 'Ride chat'),
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              colorScheme.primaryContainer.withValues(alpha: .22),
              colorScheme.surface,
            ],
          ),
        ),
        child: Column(
          children: [
            if (!keyboardVisible) _RideChatNotice(colorScheme: colorScheme),
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
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    padding: const EdgeInsets.fromLTRB(14, 10, 14, 16),
                    itemCount: messages.length,
                    itemBuilder: (context, index) {
                      final message = messages[index];
                      final mine = message.senderId == user.uid;
                      return _MessageBubble(
                        message: message,
                        mine: mine,
                        onReport: mine ? null : () => _report(message),
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
                      : Padding(
                          padding: const EdgeInsets.fromLTRB(18, 0, 18, 6),
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              'Ride participant is typing…',
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                            ),
                          ),
                        ),
                );
              },
            ),
            if (!keyboardVisible)
              _QuickRideActions(
                actions: _quickActions,
                enabled: !_sending,
                onSelected: _sendQuickAction,
              ),
            SafeArea(
              top: false,
              child: Container(
                padding: const EdgeInsets.fromLTRB(10, 9, 8, 10),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainer,
                  border: Border(
                    top: BorderSide(color: colorScheme.outline, width: 1.2),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: colorScheme.shadow.withValues(alpha: .08),
                      blurRadius: 14,
                      offset: const Offset(0, -3),
                    ),
                  ],
                ),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final compact = constraints.maxWidth < 360;
                    final actionSize = compact ? 42.0 : 48.0;
                    final gap = compact ? 4.0 : 8.0;
                    final actionConstraints = BoxConstraints.tightFor(
                      width: actionSize,
                      height: actionSize,
                    );

                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        IconButton.filledTonal(
                          tooltip: 'Take a ride photo',
                          constraints: actionConstraints,
                          visualDensity: compact
                              ? VisualDensity.compact
                              : VisualDensity.standard,
                          onPressed: _sending ? null : _captureAndSend,
                          icon: const Icon(Icons.photo_camera_rounded),
                        ),
                        SizedBox(width: gap),
                        Expanded(
                          child: TextField(
                            controller: _controller,
                            enabled: !_sending,
                            minLines: 1,
                            maxLines: 4,
                            textInputAction: TextInputAction.send,
                            textCapitalization: TextCapitalization.sentences,
                            onChanged: (_) => _onChanged(),
                            onSubmitted: (_) => _send(),
                            decoration: InputDecoration(
                              hintText: compact
                                  ? 'Message'
                                  : 'Message your ride participant',
                              filled: true,
                              fillColor: colorScheme.surface,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(24),
                              ),
                              contentPadding: EdgeInsets.symmetric(
                                horizontal: compact ? 12 : 16,
                                vertical: 11,
                              ),
                            ),
                          ),
                        ),
                        SizedBox(width: gap),
                        IconButton.filled(
                          tooltip: 'Send message',
                          constraints: actionConstraints,
                          visualDensity: compact
                              ? VisualDensity.compact
                              : VisualDensity.standard,
                          onPressed: _sending ? null : _send,
                          icon: _sending
                              ? const SizedBox.square(
                                  dimension: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.3,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(Icons.send_rounded),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _processLatestMessage(List<ChatMessage> messages, String userId) {
    if (messages.isEmpty || _lastSeenMessageId == messages.first.id) return;
    final latest = messages.first;
    final isNewIncoming = _messagesReady && latest.senderId != userId;
    _messagesReady = true;
    _lastSeenMessageId = latest.id;
    if (isNewIncoming) unawaited(RingtoneService.instance.playInsideChat());
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _repository.markSeen(widget.bookingId),
    );
  }

  void _onChanged() {
    if (!_typing && _controller.text.trim().isNotEmpty) {
      _typing = true;
      unawaited(
        _repository.setTyping(bookingId: widget.bookingId, isTyping: true),
      );
    }
    _typingTimer?.cancel();
    _typingTimer = Timer(const Duration(seconds: 2), _setNotTyping);
  }

  void _setNotTyping() {
    if (!_typing) return;
    _typing = false;
    unawaited(
      _repository.setTyping(bookingId: widget.bookingId, isTyping: false),
    );
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (_sending || text.isEmpty) return;
    _setNotTyping();
    setState(() => _sending = true);
    try {
      await _repository.send(bookingId: widget.bookingId, text: text);
      _controller.clear();
    } catch (error) {
      _showError(error);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _sendQuickAction(String text) async {
    if (_sending) return;
    setState(() => _sending = true);
    try {
      await _repository.send(bookingId: widget.bookingId, text: text);
    } catch (error) {
      _showError(error);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _captureAndSend() async {
    if (_sending) return;
    try {
      final capture = await _picker.pickImage(
        source: ImageSource.camera,
        preferredCameraDevice: CameraDevice.rear,
        maxWidth: 1280,
        maxHeight: 1280,
        imageQuality: 76,
      );
      if (capture == null || !mounted) return;
      final file = File(capture.path);
      final approved = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Send this ride photo?'),
          content: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(dialogContext).height * .45,
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: Image.file(file, fit: BoxFit.contain),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Retake'),
            ),
            FilledButton.icon(
              onPressed: () => Navigator.pop(dialogContext, true),
              icon: const Icon(Icons.send_rounded),
              label: const Text('Send photo'),
            ),
          ],
        ),
      );
      if (approved != true || !mounted) return;
      setState(() => _sending = true);
      await _repository.sendImage(bookingId: widget.bookingId, file: file);
    } catch (error) {
      _showError(error);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _report(ChatMessage message) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Report this ride message?'),
        content: const Text(
          'A System Admin will review the message in its ride context. False reports may be dismissed.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Report'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await _repository.reportMessage(
        bookingId: widget.bookingId,
        messageId: message.id,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Message sent for safety review.')),
        );
      }
    } catch (error) {
      _showError(error);
    }
  }

  void _showError(Object error) {
    if (!mounted) return;
    final message = error is ChatMessageBlockedException
        ? error.toString()
        : DomainErrorMapper.message(error);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}

class _RideChatNotice extends StatelessWidget {
  const _RideChatNotice({required this.colorScheme});

  final ColorScheme colorScheme;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(14, 12, 14, 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.primaryContainer.withValues(alpha: .68),
        border: Border.all(color: colorScheme.primary.withValues(alpha: .55)),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(Icons.shield_outlined, color: colorScheme.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Trip-scoped chat • Photos expire after 48 hours • Messages may be filtered for safety',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: colorScheme.onPrimaryContainer,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _QuickRideActions extends StatelessWidget {
  const _QuickRideActions({
    required this.actions,
    required this.enabled,
    required this.onSelected,
  });

  final List<String> actions;
  final bool enabled;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        itemCount: actions.length,
        separatorBuilder: (_, _) => const SizedBox(width: 7),
        itemBuilder: (context, index) => ActionChip(
          avatar: const Icon(Icons.bolt_rounded, size: 17),
          label: Text(actions[index]),
          onPressed: enabled ? () => onSelected(actions[index]) : null,
        ),
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({
    required this.message,
    required this.mine,
    this.onReport,
  });

  final ChatMessage message;
  final bool mine;
  final VoidCallback? onReport;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final foreground = mine ? colorScheme.onPrimary : colorScheme.onSurface;
    return LayoutBuilder(
      builder: (context, constraints) => Align(
        alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
        child: Semantics(
          label: mine ? 'Your message' : 'Ride participant message',
          child: Container(
            constraints: BoxConstraints(maxWidth: constraints.maxWidth * .84),
            margin: const EdgeInsets.symmetric(vertical: 5),
            padding: const EdgeInsets.fromLTRB(10, 9, 10, 7),
            decoration: BoxDecoration(
              color: mine
                  ? colorScheme.primary
                  : colorScheme.surfaceContainerHigh,
              border: Border.all(
                color: mine
                    ? colorScheme.primaryContainer.withValues(alpha: .85)
                    : colorScheme.outline,
              ),
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(18),
                topRight: const Radius.circular(18),
                bottomLeft: Radius.circular(mine ? 18 : 5),
                bottomRight: Radius.circular(mine ? 5 : 18),
              ),
              boxShadow: [
                BoxShadow(
                  color: colorScheme.shadow.withValues(alpha: .08),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (message.messageType == 'image')
                  _ProtectedChatImage(message: message),
                if (message.text.isNotEmpty &&
                    !(message.messageType == 'image' &&
                        message.text == 'Photo'))
                  Padding(
                    padding: const EdgeInsets.fromLTRB(4, 4, 4, 1),
                    child: Text(
                      message.text,
                      style: Theme.of(
                        context,
                      ).textTheme.bodyLarge?.copyWith(color: foreground),
                    ),
                  ),
                if (message.moderated)
                  Padding(
                    padding: const EdgeInsets.only(top: 3, right: 4),
                    child: Text(
                      'Filtered for safety',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: foreground.withValues(alpha: .74),
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ),
                Wrap(
                  alignment: WrapAlignment.end,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      DateFormat('h:mm a').format(message.sentAt),
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: foreground.withValues(alpha: .76),
                      ),
                    ),
                    if (onReport != null)
                      SizedBox.square(
                        dimension: 34,
                        child: IconButton(
                          padding: EdgeInsets.zero,
                          tooltip: 'Report message',
                          onPressed: onReport,
                          icon: Icon(
                            Icons.flag_outlined,
                            size: 17,
                            color: foreground.withValues(alpha: .82),
                          ),
                        ),
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

class _ProtectedChatImage extends StatefulWidget {
  const _ProtectedChatImage({required this.message});

  final ChatMessage message;

  @override
  State<_ProtectedChatImage> createState() => _ProtectedChatImageState();
}

class _ProtectedChatImageState extends State<_ProtectedChatImage> {
  Future<Uint8List?>? _bytes;

  @override
  void initState() {
    super.initState();
    final path = widget.message.mediaPath;
    if (widget.message.hasImage && path != null) {
      _bytes = FirebaseStorage.instance.ref(path).getData(2 * 1024 * 1024);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    if (widget.message.imageExpired || widget.message.hidden) {
      return _ExpiredPhoto(colorScheme: colorScheme);
    }
    final source = _bytes;
    if (source == null) return _ExpiredPhoto(colorScheme: colorScheme);
    return FutureBuilder<Uint8List?>(
      future: source,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const AspectRatio(
            aspectRatio: 4 / 3,
            child: Center(child: CircularProgressIndicator()),
          );
        }
        final bytes = snapshot.data;
        if (bytes == null || snapshot.hasError) {
          return _ExpiredPhoto(colorScheme: colorScheme, unavailable: true);
        }
        return Semantics(
          button: true,
          label: 'Open ride photo',
          child: InkWell(
            onTap: () => showDialog<void>(
              context: context,
              builder: (context) => Dialog.fullscreen(
                backgroundColor: Colors.black,
                child: Stack(
                  children: [
                    Center(
                      child: InteractiveViewer(
                        minScale: .8,
                        maxScale: 4,
                        child: Image.memory(bytes, fit: BoxFit.contain),
                      ),
                    ),
                    SafeArea(
                      child: IconButton.filled(
                        tooltip: 'Close photo',
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            borderRadius: BorderRadius.circular(12),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: AspectRatio(
                aspectRatio: 4 / 3,
                child: Image.memory(bytes, fit: BoxFit.cover),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _ExpiredPhoto extends StatelessWidget {
  const _ExpiredPhoto({required this.colorScheme, this.unavailable = false});

  final ColorScheme colorScheme;
  final bool unavailable;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLowest.withValues(alpha: .72),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Row(
        children: [
          const Icon(Icons.image_not_supported_outlined),
          const SizedBox(width: 10),
          Expanded(
            child: Text(unavailable ? 'Photo unavailable' : 'Photo expired'),
          ),
        ],
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
            Icon(
              Icons.chat_bubble_outline_rounded,
              size: 48,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 14),
            Text(
              'Coordinate your pickup',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 5),
            Text(
              'Send a quick update or take a current ride photo. This conversation is limited to this trip.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }
}
