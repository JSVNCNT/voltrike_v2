import 'package:flutter_test/flutter_test.dart';
import 'package:voltrike_v2/data/models/chat_message.dart';

void main() {
  test('active trip photo remains available before its expiry', () {
    final message = ChatMessage(
      id: 'message-1',
      senderId: 'driver-1',
      text: 'Photo',
      sentAt: DateTime.now(),
      seenBy: const ['driver-1'],
      messageType: 'image',
      mediaPath: 'final/chat/booking-1/message-1/photo.jpg',
      mediaExpiresAt: DateTime.now().add(const Duration(hours: 1)),
    );

    expect(message.hasImage, isTrue);
    expect(message.imageExpired, isFalse);
  });

  test('expired or hidden trip photo is unavailable', () {
    final expired = ChatMessage(
      id: 'message-2',
      senderId: 'passenger-1',
      text: 'Photo',
      sentAt: DateTime.now(),
      seenBy: const ['passenger-1'],
      messageType: 'image',
      mediaPath: 'final/chat/booking-1/message-2/photo.jpg',
      mediaExpiresAt: DateTime.now().subtract(const Duration(seconds: 1)),
    );
    final hidden = ChatMessage(
      id: 'message-3',
      senderId: 'passenger-1',
      text: 'Message hidden by System Admin.',
      sentAt: DateTime.now(),
      seenBy: const ['passenger-1'],
      messageType: 'image',
      mediaPath: 'final/chat/booking-1/message-3/photo.jpg',
      mediaExpiresAt: DateTime.now().add(const Duration(hours: 1)),
      hidden: true,
    );

    expect(expired.hasImage, isFalse);
    expect(expired.imageExpired, isTrue);
    expect(hidden.hasImage, isFalse);
  });
}
