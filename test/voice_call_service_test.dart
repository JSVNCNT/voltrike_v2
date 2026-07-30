import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:voltrike_v2/features/ride/calls/voice_call_service.dart';

void main() {
  group('VoiceCallService', () {
    test(
      'reuses the prewarmed room and requires both audio directions',
      () async {
        final client = _FakeVoiceCallRoomClient();
        var factoryCalls = 0;
        final service = VoiceCallService(
          roomClientFactory: () {
            factoryCalls++;
            return client;
          },
        );

        await service.prepareConnection(
          serverUrl: 'wss://example.livekit.cloud',
        );
        await service.connect(
          serverUrl: 'wss://example.livekit.cloud',
          token: 'token',
        );

        expect(factoryCalls, 1);
        expect(client.prepareCalls, 1);
        expect(client.connectCalls, 1);
        expect(service.isConnected, isTrue);
        expect(service.isMicrophonePublished, isTrue);
        expect(service.isMediaReady, isFalse);

        client
          ..hasRemoteParticipantValue = true
          ..remoteAudioSubscribedValue = true
          ..emit(VoiceCallRoomEvent.remoteAudioChanged);

        expect(service.hasRemoteParticipant, isTrue);
        expect(service.hasRemoteAudio, isTrue);
        expect(service.isMediaReady, isTrue);

        await service.disconnect();
        expect(client.disconnectCalls, 1);
        expect(client.disposeCalls, 1);
      },
    );

    test(
      'distinguishes signal resume, full reconnect, and poor quality',
      () async {
        final client = _FakeVoiceCallRoomClient();
        final service = VoiceCallService(roomClientFactory: () => client);
        await service.connect(
          serverUrl: 'wss://example.livekit.cloud',
          token: 'token',
        );

        client
          ..reconnectPhaseValue = VoiceCallReconnectPhase.resuming
          ..emit(VoiceCallRoomEvent.stateChanged);
        expect(service.isResuming, isTrue);
        expect(service.isReconnecting, isFalse);

        client
          ..reconnectPhaseValue = VoiceCallReconnectPhase.reconnecting
          ..emit(VoiceCallRoomEvent.stateChanged);
        expect(service.isResuming, isFalse);
        expect(service.isReconnecting, isTrue);

        client
          ..reconnectPhaseValue = VoiceCallReconnectPhase.none
          ..remoteConnectionQualityValue = VoiceCallConnectionQuality.poor
          ..emit(VoiceCallRoomEvent.connectionQualityChanged);
        expect(service.hasPoorConnection, isTrue);

        await service.disconnect();
      },
    );

    test('disconnect invalidates and disposes an in-flight connect', () async {
      final connectGate = Completer<void>();
      final client = _FakeVoiceCallRoomClient(connectGate: connectGate);
      final service = VoiceCallService(roomClientFactory: () => client);

      final connecting = service.connect(
        serverUrl: 'wss://example.livekit.cloud',
        token: 'token',
      );
      await client.connectStarted.future;

      await service.disconnect();
      connectGate.complete();

      await expectLater(
        connecting,
        throwsA(isA<VoiceCallConnectionCancelled>()),
      );
      expect(service.isConnected, isFalse);
      expect(client.disconnectCalls, greaterThanOrEqualTo(1));
      expect(client.disposeCalls, greaterThanOrEqualTo(1));
    });
  });
}

class _FakeVoiceCallRoomClient implements VoiceCallRoomClient {
  _FakeVoiceCallRoomClient({this.connectGate});

  final Completer<void>? connectGate;
  final Completer<void> connectStarted = Completer<void>();
  final StreamController<VoiceCallRoomEvent> _events =
      StreamController<VoiceCallRoomEvent>.broadcast(sync: true);

  bool connectedValue = false;
  VoiceCallReconnectPhase reconnectPhaseValue = VoiceCallReconnectPhase.none;
  bool hasRemoteParticipantValue = false;
  bool microphonePublishedValue = false;
  bool remoteAudioSubscribedValue = false;
  bool remoteAudioSubscriptionFailedValue = false;
  VoiceCallConnectionQuality remoteConnectionQualityValue =
      VoiceCallConnectionQuality.unknown;
  int prepareCalls = 0;
  int connectCalls = 0;
  int disconnectCalls = 0;
  int disposeCalls = 0;

  @override
  Stream<VoiceCallRoomEvent> get events => _events.stream;

  @override
  bool get isConnected => connectedValue;

  @override
  VoiceCallReconnectPhase get reconnectPhase => reconnectPhaseValue;

  @override
  bool get hasRemoteParticipant => hasRemoteParticipantValue;

  @override
  bool get microphonePublished => microphonePublishedValue;

  @override
  bool get remoteAudioSubscribed => remoteAudioSubscribedValue;

  @override
  bool get remoteAudioSubscriptionFailed => remoteAudioSubscriptionFailedValue;

  @override
  VoiceCallConnectionQuality get remoteConnectionQuality =>
      remoteConnectionQualityValue;

  @override
  Future<void> prepareConnection(String serverUrl, String? token) async {
    prepareCalls++;
  }

  @override
  Future<void> connect({
    required String serverUrl,
    required String token,
  }) async {
    connectCalls++;
    if (!connectStarted.isCompleted) connectStarted.complete();
    await connectGate?.future;
    connectedValue = true;
    microphonePublishedValue = true;
    emit(VoiceCallRoomEvent.stateChanged);
  }

  @override
  Future<void> setMuted(bool muted) async {}

  @override
  Future<void> disconnect() async {
    disconnectCalls++;
    connectedValue = false;
  }

  @override
  Future<void> dispose() async {
    disposeCalls++;
  }

  void emit(VoiceCallRoomEvent event) {
    if (!_events.isClosed) _events.add(event);
  }
}
