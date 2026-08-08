import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:uuid/uuid.dart';

import '../../core/services/voltrike_api.dart';
import '../models/chat_message.dart';

class ChatMessageBlockedException implements Exception {
  const ChatMessageBlockedException();

  @override
  String toString() =>
      'This message was not sent because it contains blocked language.';
}

class ChatRepository {
  ChatRepository({
    FirebaseFirestore? firestore,
    FirebaseStorage? storage,
    FirebaseAuth? auth,
    VoltrikeApi? api,
  }) : _firestore = firestore ?? FirebaseFirestore.instance,
       _storage = storage ?? FirebaseStorage.instance,
       _auth = auth ?? FirebaseAuth.instance,
       _api = api ?? VoltrikeApi.instance;
  final FirebaseFirestore _firestore;
  final FirebaseStorage _storage;
  final FirebaseAuth _auth;
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
    final result = await _api.operation('sendRideChatMessage', {
      'bookingId': bookingId,
      'messageType': 'text',
      'text': trimmed,
    }, commandId: _uuid.v4());
    if (result['blocked'] == true) throw const ChatMessageBlockedException();
  }

  Future<void> sendImage({
    required String bookingId,
    required File file,
    String caption = '',
  }) async {
    const maximumBytes = 2 * 1024 * 1024;
    if (await file.length() > maximumBytes) {
      throw const FileSystemException(
        'The compressed ride photo must be 2 MB or smaller.',
      );
    }
    final user = _auth.currentUser;
    if (user == null) throw StateError('Sign in before sending a ride photo.');
    final messageId = _uuid.v4();
    final stagingPath = 'staging/${user.uid}/${_uuid.v4()}/ride_photo.jpg';
    final uploaded = await _storage
        .ref(stagingPath)
        .putFile(
          file,
          SettableMetadata(
            contentType: 'image/jpeg',
            cacheControl: 'private, max-age=3600',
            customMetadata: const {'source': 'voltrike-ride-chat-camera'},
          ),
        );
    final finalized = await _api.operation('finalizeMedia', {
      'stagingPath': uploaded.ref.fullPath,
      'generation': int.tryParse(uploaded.metadata?.generation ?? ''),
      'targetType': 'chat_image',
      'targetId': bookingId,
      'field': messageId,
    });
    final mediaPath = finalized['path'];
    if (mediaPath is! String || mediaPath.isEmpty) {
      throw StateError('Chat image finalization returned no protected path.');
    }
    final result = await _api.operation('sendRideChatMessage', {
      'bookingId': bookingId,
      'messageType': 'image',
      'text': caption.trim(),
      'mediaPath': mediaPath,
    }, commandId: messageId);
    if (result['blocked'] == true) throw const ChatMessageBlockedException();
  }

  Future<void> reportMessage({
    required String bookingId,
    required String messageId,
    String category = 'inappropriate_chat',
  }) async {
    await _api.operation('reportRideChatMessage', {
      'bookingId': bookingId,
      'messageId': messageId,
      'category': category,
    });
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
