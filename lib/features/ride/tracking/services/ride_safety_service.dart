import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../data/repositories/safety_repository.dart';

class RideSafetyService {
  RideSafetyService({SafetyRepository? repository})
    : _repository = repository ?? SafetyRepository();

  final SafetyRepository _repository;

  Future<MySafetyIncident?> load(String bookingId) {
    return _repository.getMyIncident(bookingId);
  }

  Future<MySafetyIncident?> record(
    BuildContext context, {
    required String bookingId,
  }) async {
    final action = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Emergency assistance'),
        content: const Text(
          'VolTrike can record this ride and its latest available location '
          'for authorized TODA and system administrators. Recording an SOS '
          'does not itself contact emergency services. If there is immediate '
          'danger, use “Call 911 and record” so the phone call is not delayed '
          'by internet or Firebase availability.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, 'accidental'),
            child: const Text('Accidental press'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, 'record'),
            child: const Text('Record SOS'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(context, 'call_and_record'),
            icon: const Icon(Icons.call),
            label: const Text('Call 911 and record'),
          ),
        ],
      ),
    );
    if (action == null || !context.mounted) return null;

    final accidental = action == 'accidental';
    final callImmediately = action == 'call_and_record';
    if (callImmediately) {
      await _open911(context);
    }

    SafetyIncidentResult? result;
    Object? recordError;
    try {
      result = await _repository.triggerSos(bookingId, accidental: accidental);
      if (!context.mounted) return null;
      final delivery = result.deliveryStatus;
      final message = result.idempotent
          ? 'This SOS is already recorded.'
          : accidental
          ? 'Accidental SOS press noted. No emergency call was started.'
          : delivery == 'delivered'
          ? 'SOS recorded and delivered to a registered administrator device.'
          : 'SOS recorded. Administrators can see it in Safety Incidents.';
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
      if (callImmediately && !accidental) {
        await _repository.updateMyIncident(
          bookingId,
          'emergency_call_attempted',
        );
      }
    } catch (error) {
      recordError = error;
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              callImmediately
                  ? 'The phone call was offered, but VolTrike could not save '
                        'the SOS record: $error'
                  : 'Could not save the SOS record: $error',
            ),
          ),
        );
      }
    }

    if (!accidental && !callImmediately && context.mounted) {
      final called = await _offer911(context, recordSaved: result != null);
      if (called && result != null) {
        await _repository.updateMyIncident(
          bookingId,
          'emergency_call_attempted',
        );
      }
    }
    if (recordError != null || accidental || result == null) return null;
    return _repository.getMyIncident(bookingId);
  }

  Future<MySafetyIncident?> showStatus(
    BuildContext context, {
    required String bookingId,
  }) async {
    final incident = await _repository.getMyIncident(bookingId);
    if (!context.mounted) return incident;
    if (incident == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No SOS is recorded for this ride.')),
      );
      return null;
    }
    final action = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Update your safety status'),
        content: Text(
          incident.isActive
              ? 'Your SOS remains active. Tell administrators if you are safe '
                    'or if you still need help. You can also call 911 without '
                    'changing the SOS status.'
              : 'This SOS is currently resolved. If danger returns, choose '
                    '“I still need help” to reopen and escalate it.',
        ),
        actions: [
          TextButton.icon(
            onPressed: () => Navigator.pop(context, 'call'),
            icon: const Icon(Icons.call),
            label: const Text('Call 911'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, 'safe'),
            child: const Text("I'm safe"),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, 'still_need_help'),
            child: const Text('I still need help'),
          ),
        ],
      ),
    );
    if (action == null || !context.mounted) return incident;
    if (action == 'call') {
      final called = await _open911(context);
      if (called) {
        await _repository.updateMyIncident(
          bookingId,
          'emergency_call_attempted',
        );
      }
    } else {
      await _repository.updateMyIncident(bookingId, action);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              action == 'safe'
                  ? 'Administrators were notified that you are safe.'
                  : 'Your SOS was reopened and escalated. Call 911 for '
                        'immediate danger.',
            ),
          ),
        );
      }
    }
    return _repository.getMyIncident(bookingId);
  }

  Future<bool> _offer911(
    BuildContext context, {
    required bool recordSaved,
  }) async {
    final shouldCall = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(recordSaved ? 'SOS recorded' : 'SOS was not saved'),
        content: Text(
          recordSaved
              ? 'Administrators can review the incident. Is there immediate '
                    'danger requiring a call to the Philippine Unified 911 '
                    'emergency hotline?'
              : 'The app could not save the incident, but you can still open '
                    'the phone dialer and call 911.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Not now'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Call 911'),
          ),
        ],
      ),
    );
    if (shouldCall != true || !context.mounted) return false;
    return _open911(context);
  }

  Future<bool> _open911(BuildContext context) async {
    final started = await launchUrl(Uri(scheme: 'tel', path: '911'));
    if (!started && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Unable to open the phone app. Dial 911 directly.'),
        ),
      );
    }
    return started;
  }
}

