import 'package:flutter/material.dart';

import '../../widgets/app_app_bar.dart';
import 'legal_document_versions.dart';

class PrivacyPolicyScreen extends StatelessWidget {
  const PrivacyPolicyScreen({super.key, this.acknowledgementRequired = false});

  final bool acknowledgementRequired;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const AppAppBar(title: 'Privacy Policy'),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
          children: [
            Text(
              'VolTrike Privacy Policy',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            const Text('Effective 29 July 2026'),
            const SizedBox(height: 24),
            const _PrivacySection(
              title: 'Why this notice matters',
              body:
                  'This notice explains what personal data VolTrike collects, '
                  'why it is needed, who may review it, and the choices '
                  'available to you. VolTrike processes personal data in line '
                  'with the Philippine Data Privacy Act of 2012 and the '
                  'principles of transparency, legitimate purpose, and '
                  'proportionality.',
            ),
            const _PrivacySection(
              title: 'Data we collect',
              body:
                  'Account data includes your name, phone number, email '
                  'address, account role, and profile photo. Trip data includes '
                  'pickup and destination details, route, fare, trip history, '
                  'ratings, reports, messages, and safety incidents. Location '
                  'data is used for booking, dispatch, navigation, live trip '
                  'tracking, and safety review.',
            ),
            const _PrivacySection(
              title: 'Driver verification data',
              body:
                  'Driver applicants also provide a date of birth, TODA and '
                  'address selection, driver licence images, a government ID, '
                  'Official Receipt, Certificate of Registration, and a '
                  'vehicle photo. These documents are required to verify age, '
                  'identity, driving eligibility, vehicle registration, and '
                  'TODA assignment before the account can carry passengers.',
            ),
            const _PrivacySection(
              title: 'How data is used',
              body:
                  'Data is used to create and secure accounts, verify drivers '
                  'and vehicles, calculate fares, match bookings with eligible '
                  'drivers, provide navigation and live tracking, process '
                  'support and safety reports, prevent abuse, and meet legal '
                  'or regulatory responsibilities.',
            ),
            const _PrivacySection(
              title: 'Online driver location and restricted areas',
              body:
                  'When a driver chooses Online, VolTrike continues using '
                  'location during idle availability and active trips for '
                  'dispatch, navigation, and restricted-area safety warnings. '
                  'A confirmed entry may create a safety case visible to the '
                  'driver, the assigned TODA administrator, and authorised '
                  'system administrators. Monitoring stops when the driver '
                  'goes Offline.',
            ),
            const _PrivacySection(
              title: 'Who can access data',
              body:
                  'Passengers and drivers receive only the trip information '
                  'needed to complete a booking. Assigned TODA administrators '
                  'may review driver applications, vehicles, trips, and safety '
                  'matters within their TODA. Authorised developer '
                  'administrators may perform platform security, audit, and '
                  'safety oversight. Personal documents are not intended for '
                  'public access.',
            ),
            const _PrivacySection(
              title: 'Storage, security, and retention',
              body:
                  'VolTrike uses access-controlled Firebase services and limits '
                  'registration image size and access. Data is retained only '
                  'for as long as needed for the stated purpose, account and '
                  'trip administration, safety review, dispute handling, or '
                  'applicable legal requirements, then deleted or anonymised '
                  'when appropriate.',
            ),
            const _PrivacySection(
              title: 'Your privacy rights',
              body:
                  'Subject to applicable law, you may ask to access or correct '
                  'your data, object to or withdraw consent for processing '
                  'based on consent, request deletion or restriction where '
                  'appropriate, and raise a privacy concern. Some data must be '
                  'kept while an account, trip, dispute, or legal obligation '
                  'remains active.',
            ),
            const _PrivacySection(
              title: 'Contact and policy changes',
              body:
                  'Use VolTrike support or contact the responsible VolTrike or '
                  'TODA administrator for privacy requests. Material policy '
                  'changes will be presented in the app, and renewed consent '
                  'will be requested when required.',
            ),
            const SizedBox(height: 8),
            Text(
              'Version ${LegalDocumentVersions.privacy}',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (acknowledgementRequired) ...[
              const SizedBox(height: 24),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('I have read this privacy policy'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _PrivacySection extends StatelessWidget {
  const _PrivacySection({required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Text(body),
        ],
      ),
    );
  }
}

