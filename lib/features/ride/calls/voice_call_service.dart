import 'package:livekit_client/livekit_client.dart';

/// Voice-only LiveKit session. Tokens must be issued by a trusted backend.
class VoiceCallService {
  VoiceCallService({this.onChanged});

  final void Function()? onChanged;

  Room? _room;
  EventsListener<RoomEvent>? _listener;

  Room? get room => _room;
  bool get isConnected => _room?.connectionState == ConnectionState.connected;
  bool get isReconnecting =>
      _room?.connectionState == ConnectionState.reconnecting;
  bool get hasRemoteParticipant =>
      _room?.remoteParticipants.isNotEmpty ?? false;

  Future<void> connect({
    required String serverUrl,
    required String token,
  }) async {
    await disconnect();
    final room = Room();
    final listener = room.createListener()
      ..on<RoomConnectedEvent>((_) => onChanged?.call())
      ..on<RoomReconnectingEvent>((_) => onChanged?.call())
      ..on<RoomReconnectedEvent>((_) => onChanged?.call())
      ..on<RoomDisconnectedEvent>((_) => onChanged?.call())
      ..on<ParticipantConnectedEvent>((_) => onChanged?.call())
      ..on<ParticipantDisconnectedEvent>((_) => onChanged?.call());
    try {
      await room.connect(serverUrl, token);
      await room.localParticipant?.setMicrophoneEnabled(true);
      _room = room;
      _listener = listener;
      onChanged?.call();
    } catch (_) {
      await listener.dispose();
      await room.disconnect();
      rethrow;
    }
  }

  Future<void> setMuted(bool muted) async {
    await _room?.localParticipant?.setMicrophoneEnabled(!muted);
    onChanged?.call();
  }

  Future<void> disconnect() async {
    final room = _room;
    final listener = _listener;
    _room = null;
    _listener = null;
    await listener?.dispose();
    if (room != null) await room.disconnect();
    onChanged?.call();
  }
}
