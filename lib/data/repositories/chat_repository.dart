import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:uuid/uuid.dart';

import '../../core/services/voltrike_api.dart';
import '../models/chat_message.dart';

class ChatRepository {
  ChatRepository({FirebaseFirestore? firestore, VoltrikeApi? api})
    : _firestore = firestore ?? FirebaseFirestore.instance,
      _api = api ?? VoltrikeApi.instance;
  final FirebaseFirestore _firestore;
  final VoltrikeApi _api;
  final Uuid _uuid = const Uuid();

  DocumentReference<Map<String, dynamic>> _conversation(String bookingId) =>
      _firestore.collection('chat').doc(bookingId);

  Stream<List<ChatMessage>> messages(String bookingId) =>
      _conversation(bookingId)
          .collection('messages')
          .orderBy('sentAt', descending: true)
          .limit(200)
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

  Future<void> send({required String bookingId, required String text}) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    await _api.operation('sendRideChatMessage', {
      'bookingId': bookingId,
      'text': trimmed,
    }, commandId: _uuid.v4());
  }

  Future<void> markSeen(String bookingId) async {
    await _api.operation('markRideChatSeen', {'bookingId': bookingId});
  }

  Future<void> setTyping({required String bookingId, required bool isTyping}) {
    return _api.operation('setRideChatTyping', {
      'bookingId': bookingId,
      'isTyping': isTyping,
    });
  }
}
