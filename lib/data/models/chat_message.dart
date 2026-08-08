import 'package:cloud_firestore/cloud_firestore.dart';

class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.senderId,
    required this.text,
    required this.sentAt,
    required this.seenBy,
    this.messageType = 'text',
    this.mediaPath,
    this.mediaExpiresAt,
    this.hidden = false,
    this.moderated = false,
  });

  final String id;
  final String senderId;
  final String text;
  final DateTime sentAt;
  final List<String> seenBy;
  final String messageType;
  final String? mediaPath;
  final DateTime? mediaExpiresAt;
  final bool hidden;
  final bool moderated;

  bool get hasImage =>
      messageType == 'image' &&
      !hidden &&
      mediaPath != null &&
      mediaPath!.isNotEmpty &&
      (mediaExpiresAt == null || mediaExpiresAt!.isAfter(DateTime.now()));

  bool get imageExpired =>
      messageType == 'image' &&
      (mediaExpiresAt?.isBefore(DateTime.now()) ?? false);

  factory ChatMessage.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data()!;
    return ChatMessage(
      id: doc.id,
      senderId: data['senderId'] as String,
      text: data['text'] as String? ?? '',
      sentAt: (data['sentAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      seenBy: List<String>.from(data['seenBy'] as List? ?? const []),
      messageType: data['messageType'] as String? ?? 'text',
      mediaPath: data['mediaPath'] as String?,
      mediaExpiresAt: (data['mediaExpiresAt'] as Timestamp?)?.toDate(),
      hidden: data['hidden'] == true,
      moderated: data['moderated'] == true,
    );
  }
}
