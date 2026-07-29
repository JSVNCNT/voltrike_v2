import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/errors/domain_error_mapper.dart';
import '../../../core/theme/app_semantic_colors.dart';
import '../../../data/models/driver_violation_case.dart';
import '../../../data/repositories/driver_violation_repository.dart';
import '../../common/presentation/widgets/app_app_bar.dart';

class DriverViolationDetailScreen extends StatefulWidget {
  const DriverViolationDetailScreen({
    super.key,
    required this.violationId,
    this.repository,
  });

  final String violationId;
  final DriverViolationRepository? repository;

  @override
  State<DriverViolationDetailScreen> createState() =>
      _DriverViolationDetailScreenState();
}

class _DriverViolationDetailScreenState
    extends State<DriverViolationDetailScreen> {
  late final DriverViolationRepository _repository =
      widget.repository ?? DriverViolationRepository();
  final TextEditingController _messageController = TextEditingController();
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    unawaited(_markRead());
  }

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _messageController.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      await _repository.sendMessage(
        violationId: widget.violationId,
        text: text,
      );
      _messageController.clear();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(DomainErrorMapper.message(error))),
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _markRead() async {
    try {
      await _repository.markMessagesRead(widget.violationId);
    } catch (_) {
      // Reading the conversation remains available while acknowledgement
      // retries on the next message snapshot.
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const AppAppBar(title: 'Restriction case'),
      body: StreamBuilder<DriverViolationCase?>(
        stream: _repository.watchViolation(widget.violationId),
        builder: (context, caseSnapshot) {
          if (caseSnapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (caseSnapshot.hasError) {
            return Center(
              child: Text(DomainErrorMapper.message(caseSnapshot.error!)),
            );
          }
          final violation = caseSnapshot.data;
          if (violation == null) {
            return const Center(child: Text('This case is not available.'));
          }
          return Column(
            children: [
              Expanded(
                child: StreamBuilder<List<DriverViolationMessage>>(
                  stream: _repository.watchMessages(widget.violationId),
                  builder: (context, messageSnapshot) {
                    if (messageSnapshot.hasError) {
                      return Center(
                        child: Text(
                          DomainErrorMapper.message(messageSnapshot.error!),
                        ),
                      );
                    }
                    final messages = messageSnapshot.data ?? const [];
                    if (messages.isNotEmpty) {
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        unawaited(_markRead());
                      });
                    }
                    return ListView(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
                      children: [
                        _CaseSummary(violation: violation),
                        const SizedBox(height: 16),
                        Text(
                          'Case chat',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 8),
                        if (messageSnapshot.connectionState ==
                            ConnectionState.waiting)
                          const LinearProgressIndicator()
                        else if (messages.isEmpty)
                          const Card(
                            child: Padding(
                              padding: EdgeInsets.all(16),
                              child: Text(
                                'No messages yet. Ask the TODA or developer '
                                'administrator about this case.',
                              ),
                            ),
                          )
                        else
                          for (final message in messages)
                            _MessageBubble(message: message),
                      ],
                    );
                  },
                ),
              ),
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 8, 10),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _messageController,
                          minLines: 1,
                          maxLines: 4,
                          maxLength: 1000,
                          decoration: const InputDecoration(
                            hintText: 'Message TODA and developer admins',
                            counterText: '',
                          ),
                          onSubmitted: (_) => _send(),
                        ),
                      ),
                      IconButton.filled(
                        tooltip: 'Send message',
                        onPressed: _sending ? null : _send,
                        icon: _sending
                            ? const SizedBox.square(
                                dimension: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.send_rounded),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _CaseSummary extends StatelessWidget {
  const _CaseSummary({required this.violation});

  final DriverViolationCase violation;

  @override
  Widget build(BuildContext context) {
    final semantic = AppSemanticColors.of(context);
    return Card(
      color: violation.isOpen
          ? Theme.of(context).colorScheme.errorContainer
          : semantic.successContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              violation.restrictionName,
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(
              'Status: ${violation.status}\n'
              'Detected: ${DateFormat('MMM d, y • h:mm a').format(violation.createdAt)}\n'
              'Context: ${_contextLabel(violation.context)}\n'
              'Location: ${violation.eventLocation.latitude.toStringAsFixed(6)}, '
              '${violation.eventLocation.longitude.toStringAsFixed(6)}'
              '${violation.accuracyMeters == null ? '' : '\nGPS accuracy: ±${violation.accuracyMeters!.round()} m'}',
            ),
            const SizedBox(height: 10),
            const Text(
              'This safety case is separate from passenger ride chat and is '
              'visible only to authorised driver, TODA, and developer roles.',
            ),
          ],
        ),
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.message});

  final DriverViolationMessage message;

  @override
  Widget build(BuildContext context) {
    final mine = message.senderId == FirebaseAuth.instance.currentUser?.uid;
    final colors = Theme.of(context).colorScheme;
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 320),
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
        decoration: BoxDecoration(
          color: mine ? colors.primaryContainer : colors.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              mine
                  ? 'You'
                  : message.senderName ?? _roleLabel(message.senderRole),
              style: Theme.of(
                context,
              ).textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 3),
            Text(message.text),
            const SizedBox(height: 3),
            Text(
              DateFormat('h:mm a').format(message.createdAt),
              style: Theme.of(context).textTheme.labelSmall,
            ),
          ],
        ),
      ),
    );
  }
}

String _roleLabel(String role) {
  return switch (role) {
    'toda_admin' => 'TODA Admin',
    'developer_admin' => 'Developer Admin',
    _ => 'Safety Admin',
  };
}

String _contextLabel(String context) {
  return switch (context) {
    'to_pickup' => 'Driving to pickup',
    'active_trip' || 'active_booking' => 'Active trip',
    _ => 'Online idle',
  };
}
