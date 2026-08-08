import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:uuid/uuid.dart';

import 'voltrike_api.dart';

/// Device-local, encrypted queue for durable domain commands.
///
/// Telemetry, heartbeats, locations, and expiring offers intentionally never
/// enter this queue. Entries are bound to both the signed-in Firebase UID and
/// this installation and are replayed with their original command id.
class DurableCommandOutbox {
  DurableCommandOutbox({
    FlutterSecureStorage? storage,
    FirebaseAuth? auth,
    VoltrikeApi? api,
  }) : _storage = storage ?? const FlutterSecureStorage(),
       _auth = auth ?? FirebaseAuth.instance,
       _api = api ?? VoltrikeApi.instance;

  static final DurableCommandOutbox instance = DurableCommandOutbox();

  static const _queueKey = 'voltrike.v2.command_outbox';
  static const _installationKey = 'voltrike.v2.installation_id';
  static const _maximumEntries = 64;
  static const _uuid = Uuid();

  final FlutterSecureStorage _storage;
  final FirebaseAuth _auth;
  final VoltrikeApi _api;
  Future<void> _serial = Future<void>.value();

  Future<String> installationId() async {
    final existing = await _storage.read(key: _installationKey);
    if (existing != null && existing.isNotEmpty) return existing;
    final value = _uuid.v4();
    await _storage.write(key: _installationKey, value: value);
    return value;
  }

  Future<void> enqueue({
    required String key,
    required String kind,
    required Map<String, dynamic> payload,
    Duration expiresAfter = const Duration(hours: 24),
  }) {
    return _synchronized(() async {
      final user = _auth.currentUser;
      if (user == null) {
        throw StateError('A signed-in user is required to queue a command.');
      }
      final deviceId = await installationId();
      final now = DateTime.now().toUtc();
      final entries = await _read();
      entries.removeWhere(
        (entry) =>
            entry.expiresAt.isBefore(now) ||
            (entry.uid == user.uid &&
                entry.deviceId == deviceId &&
                entry.key == key),
      );
      entries.add(
        _QueuedCommand(
          key: key,
          kind: kind,
          uid: user.uid,
          deviceId: deviceId,
          payload: payload,
          createdAt: now,
          expiresAt: now.add(expiresAfter),
          blocked: false,
        ),
      );
      if (entries.length > _maximumEntries) {
        entries.removeRange(0, entries.length - _maximumEntries);
      }
      await _write(entries);
    });
  }

  Future<void> complete(String key) {
    return _synchronized(() async {
      final entries = await _read();
      entries.removeWhere((entry) => entry.key == key);
      await _write(entries);
    });
  }

  Future<void> replayForCurrentUser() {
    return _synchronized(() async {
      final user = _auth.currentUser;
      if (user == null) return;
      final deviceId = await installationId();
      final now = DateTime.now().toUtc();
      final entries = await _read();
      final originalLength = entries.length;
      entries.removeWhere((entry) => entry.expiresAt.isBefore(now));
      var changed = entries.length != originalLength;
      for (var index = 0; index < entries.length; index++) {
        final entry = entries[index];
        if (entry.uid != user.uid ||
            entry.deviceId != deviceId ||
            entry.blocked) {
          continue;
        }
        try {
          await _send(entry);
          entries.removeAt(index--);
          changed = true;
        } on VoltrikeApiException catch (error) {
          if (_requiresReconciliation(error)) {
            entries[index] = entry.copyWith(blocked: true);
            changed = true;
            continue;
          }
          // Preserve ordering after a transient network/dependency failure.
          break;
        }
      }
      if (changed) await _write(entries);
    });
  }

  Future<void> _send(_QueuedCommand entry) async {
    switch (entry.kind) {
      case 'booking.create':
        await _api.createBooking(entry.payload);
        return;
      case 'booking.transition':
        final bookingId = entry.payload['bookingId'] as String?;
        final command = entry.payload['command'];
        if (bookingId == null || command is! Map) {
          throw const VoltrikeApiException(
            'Stored booking command is invalid.',
            code: 'INVALID_ARGUMENT',
          );
        }
        await _api.transitionBooking(
          bookingId,
          command.map((key, value) => MapEntry(key.toString(), value)),
        );
        return;
      default:
        throw VoltrikeApiException(
          'Stored command type ${entry.kind} is unsupported.',
          code: 'INVALID_ARGUMENT',
        );
    }
  }

  bool _requiresReconciliation(VoltrikeApiException error) {
    final code = error.code?.toUpperCase();
    return code == 'STALE_REVISION' ||
        code == 'POLICY_CHANGED' ||
        code == 'CONFLICT' ||
        code == 'FAILED_PRECONDITION' ||
        code == 'INVALID_ARGUMENT' ||
        code == 'FORBIDDEN' ||
        code == 'NOT_FOUND';
  }

  Future<List<_QueuedCommand>> _read() async {
    final raw = await _storage.read(key: _queueKey);
    if (raw == null || raw.isEmpty) return <_QueuedCommand>[];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return <_QueuedCommand>[];
      return decoded
          .whereType<Map>()
          .map((value) => _QueuedCommand.fromJson(value))
          .toList();
    } on FormatException {
      return <_QueuedCommand>[];
    }
  }

  Future<void> _write(List<_QueuedCommand> entries) async {
    if (entries.isEmpty) {
      await _storage.delete(key: _queueKey);
      return;
    }
    await _storage.write(
      key: _queueKey,
      value: jsonEncode(entries.map((entry) => entry.toJson()).toList()),
    );
  }

  Future<void> _synchronized(Future<void> Function() operation) {
    final result = _serial.then((_) => operation());
    _serial = result.catchError((_) {});
    return result;
  }
}

class _QueuedCommand {
  const _QueuedCommand({
    required this.key,
    required this.kind,
    required this.uid,
    required this.deviceId,
    required this.payload,
    required this.createdAt,
    required this.expiresAt,
    required this.blocked,
  });

  factory _QueuedCommand.fromJson(Map<dynamic, dynamic> value) {
    final payload = value['payload'];
    return _QueuedCommand(
      key: value['key']?.toString() ?? '',
      kind: value['kind']?.toString() ?? '',
      uid: value['uid']?.toString() ?? '',
      deviceId: value['deviceId']?.toString() ?? '',
      payload: payload is Map
          ? payload.map((key, item) => MapEntry(key.toString(), item))
          : <String, dynamic>{},
      createdAt:
          DateTime.tryParse(value['createdAt']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      expiresAt:
          DateTime.tryParse(value['expiresAt']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      blocked: value['blocked'] == true,
    );
  }

  final String key;
  final String kind;
  final String uid;
  final String deviceId;
  final Map<String, dynamic> payload;
  final DateTime createdAt;
  final DateTime expiresAt;
  final bool blocked;

  _QueuedCommand copyWith({bool? blocked}) => _QueuedCommand(
    key: key,
    kind: kind,
    uid: uid,
    deviceId: deviceId,
    payload: payload,
    createdAt: createdAt,
    expiresAt: expiresAt,
    blocked: blocked ?? this.blocked,
  );

  Map<String, dynamic> toJson() => <String, dynamic>{
    'key': key,
    'kind': kind,
    'uid': uid,
    'deviceId': deviceId,
    'payload': payload,
    'createdAt': createdAt.toIso8601String(),
    'expiresAt': expiresAt.toIso8601String(),
    'blocked': blocked,
  };
}
