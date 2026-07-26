import 'package:audioplayers/audioplayers.dart';

/// Plays short foreground alerts. Background alerts are handled by Android's
/// notification channels using the matching raw sound resource.
class RingtoneService {
  RingtoneService._();

  static final instance = RingtoneService._();

  final AudioPlayer _booking = AudioPlayer();
  final AudioPlayer _chat = AudioPlayer();
  final AudioPlayer _insideChat = AudioPlayer();
  final AudioPlayer _call = AudioPlayer();
  final Map<String, DateTime> _lastPlayedAt = {};

  Future<void> playBooking() => _play(
    _booking,
    'ringtones/booking_ringtone.mp3',
    key: 'booking',
    volume: 1,
  );

  Future<void> playChat() =>
      _play(_chat, 'ringtones/chat_ringtone.mp3', key: 'chat', volume: 1);

  Future<void> playInsideChat() => _play(
    _insideChat,
    'ringtones/inside_chat_screen_ringtone.mp3',
    key: 'inside_chat',
    volume: .45,
  );

  Future<void> startIncomingCall() async {
    await _call.stop();
    await _call.setReleaseMode(ReleaseMode.loop);
    await _call.setVolume(.7);
    await _call.play(AssetSource('ringtones/inside_chat_screen_ringtone.mp3'));
  }

  Future<void> stopIncomingCall() async {
    await _call.stop();
    await _call.setReleaseMode(ReleaseMode.release);
  }

  Future<void> _play(
    AudioPlayer player,
    String asset, {
    required String key,
    required double volume,
  }) async {
    final now = DateTime.now();
    final previous = _lastPlayedAt[key];
    if (previous != null &&
        now.difference(previous) < const Duration(milliseconds: 800)) {
      return;
    }
    _lastPlayedAt[key] = now;
    await player.stop();
    await player.setReleaseMode(ReleaseMode.release);
    await player.setVolume(volume);
    await player.play(AssetSource(asset));
  }

  Future<void> dispose() async {
    await _booking.dispose();
    await _chat.dispose();
    await _insideChat.dispose();
    await _call.dispose();
  }
}
