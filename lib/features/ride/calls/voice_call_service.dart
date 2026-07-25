import 'package:livekit_client/livekit_client.dart';

/// Voice-only LiveKit session. Tokens must be issued by a trusted backend.
class VoiceCallService {
  Room? _room;
  Room? get room => _room;
  bool get isConnected => _room?.connectionState == ConnectionState.connected;

  Future<void> connect({required String serverUrl, required String token}) async {
    await disconnect();
    final room = Room();
    await room.connect(serverUrl, token);
    await room.localParticipant?.setMicrophoneEnabled(true);
    _room = room;
  }

  Future<void> setMuted(bool muted) async {
    await _room?.localParticipant?.setMicrophoneEnabled(!muted);
  }

  Future<void> disconnect() async {
    final room = _room;
    _room = null;
    if (room != null) await room.disconnect();
  }
}
