import 'dart:async';

import 'package:livekit_client/livekit_client.dart';

enum VoiceCallReconnectPhase { none, resuming, reconnecting }

enum VoiceCallConnectionQuality { unknown, excellent, good, poor, lost }

enum VoiceCallRoomEvent {
  stateChanged,
  participantChanged,
  localAudioChanged,
  remoteAudioChanged,
  connectionQualityChanged,
}

/// Small adapter boundary that keeps the call lifecycle testable without
/// opening a native WebRTC room.
abstract interface class VoiceCallRoomClient {
  Stream<VoiceCallRoomEvent> get events;

  bool get isConnected;
  VoiceCallReconnectPhase get reconnectPhase;
  bool get hasRemoteParticipant;
  bool get microphonePublished;
  bool get remoteAudioSubscribed;
  bool get remoteAudioSubscriptionFailed;
  VoiceCallConnectionQuality get remoteConnectionQuality;

  Future<void> prepareConnection(String serverUrl, String? token);

  Future<void> connect({required String serverUrl, required String token});

  Future<void> setMuted(bool muted);
  Future<void> disconnect();
  Future<void> dispose();
}

typedef VoiceCallRoomClientFactory = VoiceCallRoomClient Function();

class VoiceCallConnectionCancelled implements Exception {
  const VoiceCallConnectionCancelled();
}

/// Voice-only LiveKit session. Tokens must be issued by a trusted backend.
class VoiceCallService {
  VoiceCallService({
    this.onChanged,
    VoiceCallRoomClientFactory? roomClientFactory,
    this.prewarmTimeout = const Duration(seconds: 4),
    this.connectTimeout = const Duration(seconds: 15),
    this.operationTimeout = const Duration(seconds: 5),
  }) : _roomClientFactory =
           roomClientFactory ?? _LiveKitVoiceCallRoomClient.new;

  final void Function()? onChanged;
  final VoiceCallRoomClientFactory _roomClientFactory;
  final Duration prewarmTimeout;
  final Duration connectTimeout;
  final Duration operationTimeout;

  VoiceCallRoomClient? _client;
  StreamSubscription<VoiceCallRoomEvent>? _eventSubscription;
  Future<void>? _prewarmFuture;
  String? _serverUrl;
  int _generation = 0;

  bool get isConnected => _client?.isConnected ?? false;
  bool get isResuming =>
      _client?.reconnectPhase == VoiceCallReconnectPhase.resuming;
  bool get isReconnecting =>
      _client?.reconnectPhase == VoiceCallReconnectPhase.reconnecting;
  bool get hasRemoteParticipant => _client?.hasRemoteParticipant ?? false;
  bool get isMicrophonePublished => _client?.microphonePublished ?? false;
  bool get hasRemoteAudio => _client?.remoteAudioSubscribed ?? false;
  bool get remoteAudioSubscriptionFailed =>
      _client?.remoteAudioSubscriptionFailed ?? false;
  VoiceCallConnectionQuality get remoteConnectionQuality =>
      _client?.remoteConnectionQuality ?? VoiceCallConnectionQuality.unknown;
  bool get hasPoorConnection =>
      remoteConnectionQuality == VoiceCallConnectionQuality.poor ||
      remoteConnectionQuality == VoiceCallConnectionQuality.lost;

  /// The media path is ready only after signalling, local publication, and a
  /// subscribed remote audio track are all present.
  bool get isMediaReady =>
      isConnected && isMicrophonePublished && hasRemoteAudio;

  /// Best-effort DNS/TLS/region prewarming. Failure never prevents the normal
  /// authenticated connection path.
  Future<void> prepareConnection({
    required String serverUrl,
    String? token,
  }) async {
    final normalizedUrl = serverUrl.trim();
    if (normalizedUrl.isEmpty) return;

    final client = await _useClient(normalizedUrl);
    final generation = _generation;
    final future = () async {
      try {
        await client
            .prepareConnection(normalizedUrl, token)
            .timeout(prewarmTimeout);
      } catch (_) {
        // prepareConnection is only a latency optimization. If it times out,
        // discard that Room so a still-running HTTP probe cannot race connect.
        if (_isCurrent(client, generation)) {
          await _clearCurrentClient(client);
        }
      }
    }();
    _prewarmFuture = future;
    await future;
    if (identical(_prewarmFuture, future)) _prewarmFuture = null;
  }

  Future<void> connect({
    required String serverUrl,
    required String token,
  }) async {
    final normalizedUrl = serverUrl.trim();
    final normalizedToken = token.trim();
    if (normalizedUrl.isEmpty || normalizedToken.isEmpty) {
      throw StateError('Voice service returned invalid call credentials.');
    }

    var client = await _useClient(normalizedUrl);
    final pendingPrewarm = _prewarmFuture;
    if (pendingPrewarm != null) await pendingPrewarm;

    // A timed-out prewarm deliberately clears its Room.
    client = await _useClient(normalizedUrl);
    final generation = _generation;
    try {
      await client
          .connect(serverUrl: normalizedUrl, token: normalizedToken)
          .timeout(connectTimeout);
      if (!_isCurrent(client, generation)) {
        await _safeCleanup(client);
        throw const VoiceCallConnectionCancelled();
      }
      onChanged?.call();
    } catch (_) {
      if (!_isCurrent(client, generation)) {
        throw const VoiceCallConnectionCancelled();
      }
      await _clearCurrentClient(client);
      rethrow;
    }
  }

  Future<void> setMuted(bool muted) async {
    final client = _client;
    if (client == null || !client.isConnected) return;
    await client.setMuted(muted).timeout(operationTimeout);
    if (identical(client, _client)) onChanged?.call();
  }

  Future<void> disconnect() async {
    _generation++;
    final client = _client;
    final subscription = _eventSubscription;
    _client = null;
    _eventSubscription = null;
    _prewarmFuture = null;
    _serverUrl = null;
    await subscription?.cancel();
    if (client != null) await _safeCleanup(client);
    onChanged?.call();
  }

  Future<VoiceCallRoomClient> _useClient(String serverUrl) async {
    final current = _client;
    if (current != null && _serverUrl == serverUrl) return current;
    if (current != null) await disconnect();

    // Recheck after awaiting cleanup in case another operation installed the
    // correct room while this one yielded.
    final replacement = _client;
    if (replacement != null && _serverUrl == serverUrl) return replacement;

    final client = _roomClientFactory();
    _generation++;
    _client = client;
    _serverUrl = serverUrl;
    _eventSubscription = client.events.listen((_) {
      if (identical(client, _client)) onChanged?.call();
    });
    return client;
  }

  bool _isCurrent(VoiceCallRoomClient client, int generation) {
    return generation == _generation && identical(client, _client);
  }

  Future<void> _clearCurrentClient(VoiceCallRoomClient client) async {
    if (!identical(client, _client)) {
      await _safeCleanup(client);
      return;
    }
    _generation++;
    final subscription = _eventSubscription;
    _client = null;
    _eventSubscription = null;
    _prewarmFuture = null;
    _serverUrl = null;
    await subscription?.cancel();
    await _safeCleanup(client);
    onChanged?.call();
  }

  Future<void> _safeCleanup(VoiceCallRoomClient client) async {
    try {
      await client.disconnect().timeout(operationTimeout);
    } catch (_) {
      // Continue to disposal so a failed signalling close cannot retain audio.
    }
    try {
      await client.dispose().timeout(operationTimeout);
    } catch (_) {
      // Cleanup is best effort after the local references have been cleared.
    }
  }
}

class _LiveKitVoiceCallRoomClient implements VoiceCallRoomClient {
  _LiveKitVoiceCallRoomClient()
    : _room = Room(
        roomOptions: const RoomOptions(
          defaultAudioCaptureOptions: AudioCaptureOptions(
            echoCancellation: true,
            noiseSuppression: true,
            autoGainControl: true,
          ),
        ),
      ) {
    _listener = _room.createListener()
      ..on<RoomConnectedEvent>((_) {
        _reconnectPhase = VoiceCallReconnectPhase.none;
        _emit(VoiceCallRoomEvent.stateChanged);
      })
      ..on<RoomResumingEvent>((_) {
        _reconnectPhase = VoiceCallReconnectPhase.resuming;
        _emit(VoiceCallRoomEvent.stateChanged);
      })
      ..on<RoomReconnectingEvent>((_) {
        _reconnectPhase = VoiceCallReconnectPhase.reconnecting;
        _emit(VoiceCallRoomEvent.stateChanged);
      })
      ..on<RoomReconnectedEvent>((_) {
        _reconnectPhase = VoiceCallReconnectPhase.none;
        _emit(VoiceCallRoomEvent.stateChanged);
      })
      ..on<RoomDisconnectedEvent>((_) {
        _reconnectPhase = VoiceCallReconnectPhase.none;
        _emit(VoiceCallRoomEvent.stateChanged);
      })
      ..on<ParticipantConnectedEvent>(
        (_) => _emit(VoiceCallRoomEvent.participantChanged),
      )
      ..on<ParticipantDisconnectedEvent>(
        (_) => _emit(VoiceCallRoomEvent.participantChanged),
      )
      ..on<LocalTrackPublishedEvent>(
        (_) => _emit(VoiceCallRoomEvent.localAudioChanged),
      )
      ..on<LocalTrackUnpublishedEvent>(
        (_) => _emit(VoiceCallRoomEvent.localAudioChanged),
      )
      ..on<TrackSubscribedEvent>((event) {
        if (event.track is RemoteAudioTrack) {
          _remoteAudioSubscriptionFailed = false;
          _emit(VoiceCallRoomEvent.remoteAudioChanged);
        }
      })
      ..on<TrackUnsubscribedEvent>((event) {
        if (event.track is RemoteAudioTrack) {
          _emit(VoiceCallRoomEvent.remoteAudioChanged);
        }
      })
      ..on<TrackSubscriptionExceptionEvent>((_) {
        _remoteAudioSubscriptionFailed = true;
        _emit(VoiceCallRoomEvent.remoteAudioChanged);
      })
      ..on<ParticipantConnectionQualityUpdatedEvent>(
        (_) => _emit(VoiceCallRoomEvent.connectionQualityChanged),
      );
  }

  final Room _room;
  final StreamController<VoiceCallRoomEvent> _events =
      StreamController<VoiceCallRoomEvent>.broadcast(sync: true);
  late final EventsListener<RoomEvent> _listener;
  VoiceCallReconnectPhase _reconnectPhase = VoiceCallReconnectPhase.none;
  bool _remoteAudioSubscriptionFailed = false;
  bool _disposed = false;

  @override
  Stream<VoiceCallRoomEvent> get events => _events.stream;

  @override
  bool get isConnected => _room.connectionState == ConnectionState.connected;

  @override
  VoiceCallReconnectPhase get reconnectPhase => _reconnectPhase;

  @override
  bool get hasRemoteParticipant => _room.remoteParticipants.isNotEmpty;

  @override
  bool get microphonePublished =>
      _room.localParticipant?.audioTrackPublications.isNotEmpty ?? false;

  @override
  bool get remoteAudioSubscribed {
    return _room.remoteParticipants.values.any(
      (participant) => participant.audioTrackPublications.any(
        (publication) => publication.subscribed && publication.track != null,
      ),
    );
  }

  @override
  bool get remoteAudioSubscriptionFailed => _remoteAudioSubscriptionFailed;

  @override
  VoiceCallConnectionQuality get remoteConnectionQuality {
    final qualities = _room.remoteParticipants.values
        .map((participant) => participant.connectionQuality)
        .toList(growable: false);
    if (qualities.contains(ConnectionQuality.lost)) {
      return VoiceCallConnectionQuality.lost;
    }
    if (qualities.contains(ConnectionQuality.poor)) {
      return VoiceCallConnectionQuality.poor;
    }
    if (qualities.contains(ConnectionQuality.good)) {
      return VoiceCallConnectionQuality.good;
    }
    if (qualities.contains(ConnectionQuality.excellent)) {
      return VoiceCallConnectionQuality.excellent;
    }
    return VoiceCallConnectionQuality.unknown;
  }

  @override
  Future<void> prepareConnection(String serverUrl, String? token) {
    return _room.prepareConnection(serverUrl, token);
  }

  @override
  Future<void> connect({required String serverUrl, required String token}) {
    return _room.connect(
      serverUrl,
      token,
      connectOptions: const ConnectOptions(
        autoSubscribe: true,
        timeouts: Timeouts.defaultTimeouts,
      ),
      fastConnectOptions: FastConnectOptions(
        microphone: const TrackOption<bool, LocalAudioTrack>(enabled: true),
      ),
    );
  }

  @override
  Future<void> setMuted(bool muted) async {
    await _room.localParticipant?.setMicrophoneEnabled(!muted);
    _emit(VoiceCallRoomEvent.localAudioChanged);
  }

  @override
  Future<void> disconnect() => _room.disconnect();

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _listener.dispose();
    await _room.dispose();
    await _events.close();
  }

  void _emit(VoiceCallRoomEvent event) {
    if (!_disposed && !_events.isClosed) _events.add(event);
  }
}
