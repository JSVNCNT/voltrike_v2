import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:uuid/uuid.dart';

import '../../core/services/voltrike_api.dart';
import '../models/driver_violation_case.dart';

class DriverViolationRepository {
  DriverViolationRepository({FirebaseFirestore? firestore, VoltrikeApi? api})
    : _firestore = firestore ?? FirebaseFirestore.instance,
      _api = api ?? VoltrikeApi.instance;

  static const int contractVersion = 1;

  final FirebaseFirestore _firestore;
  final VoltrikeApi _api;
  final Uuid _uuid = const Uuid();

  Future<DriverRestrictionReportResult> reportPublishedPosition({
    String? bookingId,
  }) async {
    final data = await _api.operation('driverReportRestrictionPosition', {
      'contractVersion': contractVersion,
      'operationId': _uuid.v4(),
      'bookingId': bookingId,
    });
    return DriverRestrictionReportResult(
      activeRestrictionIds: _strings(data['activeRestrictionIds']),
      createdViolationIds: _strings(data['createdViolationIds']),
      exitedViolationIds: _strings(data['exitedViolationIds']),
      pendingRestrictionIds: _strings(data['pendingRestrictionIds']),
    );
  }

  Future<List<DriverViolationCase>> listMyViolations() async {
    final data = await _api.operation('listMyDriverViolations', {
      'contractVersion': contractVersion,
      'includeClosed': true,
    });
    final rows = data['items'] ?? data['violations'] ?? data['cases'] ?? data;
    if (rows is! Iterable) return const [];
    final parsed = <DriverViolationCase>[];
    for (final row in rows) {
      final map = _map(row);
      final id = _text(map['id'] ?? map['violationId'] ?? map['caseId']);
      if (id == null) continue;
      parsed.add(DriverViolationCase.fromMap(id: id, data: map));
    }
    parsed.sort((left, right) => right.createdAt.compareTo(left.createdAt));
    return parsed;
  }

  Stream<DriverViolationCase?> watchViolation(String violationId) {
    return _firestore
        .collection('driverViolations')
        .doc(violationId)
        .snapshots()
        .map(
          (document) => document.exists
              ? DriverViolationCase.fromFirestore(document)
              : null,
        );
  }

  Stream<List<DriverViolationMessage>> watchMessages(String violationId) {
    return _firestore
        .collection('driverViolations')
        .doc(violationId)
        .collection('messages')
        .orderBy('createdAt')
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map(DriverViolationMessage.fromFirestore)
              .toList(growable: false),
        );
  }

  Future<void> sendMessage({
    required String violationId,
    required String text,
  }) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    await _api.operation('sendDriverViolationMessage', {
      'contractVersion': contractVersion,
      'operationId': _uuid.v4(),
      'messageId': _uuid.v4(),
      'violationId': violationId,
      'message': trimmed,
    });
  }

  Future<void> markMessagesRead(String violationId) async {
    try {
      await _api.operation('markDriverViolationMessagesRead', {
        'contractVersion': contractVersion,
        'violationId': violationId,
      });
    } on VoltrikeApiException catch (error) {
      // This acknowledgement is optional in contract v1.
      if (error.code != 'invalid_argument' && error.code != 'not_found') {
        rethrow;
      }
    }
  }
}

class DriverRestrictionReportResult {
  const DriverRestrictionReportResult({
    this.activeRestrictionIds = const [],
    this.createdViolationIds = const [],
    this.exitedViolationIds = const [],
    this.pendingRestrictionIds = const [],
  });

  final List<String> activeRestrictionIds;
  final List<String> createdViolationIds;
  final List<String> exitedViolationIds;
  final List<String> pendingRestrictionIds;
}

Map<String, dynamic> _map(Object? value) {
  if (value is! Map) return const {};
  return value.map((key, item) => MapEntry(key.toString(), item));
}

String? _text(Object? value) {
  if (value is! String || value.trim().isEmpty) return null;
  return value.trim();
}

List<String> _strings(Object? value) {
  if (value is! Iterable) return const [];
  return value
      .whereType<String>()
      .map((item) => item.trim())
      .where((item) => item.isNotEmpty)
      .toList(growable: false);
}
