import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/chat_message.dart';

class ChatRepository {
  ChatRepository({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;
  final FirebaseFirestore _firestore;

  DocumentReference<Map<String, dynamic>> _conversation(String bookingId) =>
      _firestore.collection('chat').doc(bookingId);

  Stream<List<ChatMessage>> messages(String bookingId) =>
      _conversation(bookingId)
          .collection('messages')
          .orderBy('sentAt', descending: true)
          .snapshots()
          .map(
            (snapshot) => snapshot.docs.map(ChatMessage.fromFirestore).toList(),
          );

  Stream<int> unreadCount({required String bookingId, required String userId}) {
    return messages(bookingId).map(
      (messages) => messages
          .where(
            (message) =>
                message.senderId != userId && !message.seenBy.contains(userId),
          )
          .length,
    );
  }

  Stream<List<String>> typingUsers(String bookingId, String currentUserId) =>
      _conversation(bookingId)
          .collection('typing')
          .snapshots()
          .map(
            (snapshot) => snapshot.docs
                .where(
                  (document) =>
                      document.id != currentUserId &&
                      document.data()['isTyping'] == true,
                )
                .map((document) => document.id)
                .toList(),
          );

  Future<void> send({
    required String bookingId,
    required String senderId,
    required List<String> members,
    required String text,
  }) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    final conversation = _conversation(bookingId);
    final message = conversation.collection('messages').doc();
    final batch = _firestore.batch();
    batch.set(conversation, {
      'bookingId': bookingId,
      'members': members,
      'lastMessage': trimmed,
      'lastMessageAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    batch.set(message, {
      'senderId': senderId,
      'text': trimmed,
      'sentAt': FieldValue.serverTimestamp(),
      'seenBy': [senderId],
    });
    await batch.commit();
  }

  Future<void> markSeen(String bookingId, String userId) async {
    final unread = await _conversation(bookingId)
        .collection('messages')
        .orderBy('sentAt', descending: true)
        .limit(50)
        .get();
    final batch = _firestore.batch();
    for (final message in unread.docs.where(
      (doc) => !(doc.data()['seenBy'] as List? ?? const []).contains(userId),
    )) {
      batch.update(message.reference, {
        'seenBy': FieldValue.arrayUnion([userId]),
      });
    }
    await batch.commit();
  }

  Future<void> setTyping({
    required String bookingId,
    required String userId,
    required bool isTyping,
  }) {
    return _conversation(bookingId).collection('typing').doc(userId).set({
      'isTyping': isTyping,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }
}
