import 'package:flutter/material.dart';

import '../../widgets/app_app_bar.dart';
import 'legal_document_versions.dart';

class TermsAndConditionsScreen extends StatelessWidget {
  const TermsAndConditionsScreen({
    super.key,
    this.acknowledgementRequired = false,
  });

  final bool acknowledgementRequired;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const AppAppBar(title: 'Terms and Conditions'),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
          children: [
            Text(
              'VolTrike Terms and Conditions',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            const Text('Effective 29 July 2026'),
            const SizedBox(height: 24),
            const _LegalSection(
              title: 'Using VolTrike',
              body:
                  'VolTrike connects passengers with accredited community '
                  'transport drivers. You must provide accurate information, '
                  'keep your account secure, and use the service only for '
                  'lawful transportation purposes. A booking is subject to '
                  'driver availability, service coverage, vehicle capacity, '
                  'and applicable local transport rules.',
            ),
            const _LegalSection(
              title: 'Passenger responsibilities',
              body:
                  'Passengers must give accurate pickup, destination, and '
                  'passenger-count details; pay the fare shown in the app; '
                  'follow the driver’s reasonable safety instructions; and '
                  'treat drivers, vehicles, and other passengers respectfully. '
                  'Baggage must fit safely without blocking exits or creating '
                  'a hazard.',
            ),
            const _LegalSection(
              title: 'Driver eligibility and responsibilities',
              body:
                  'Driver applicants must be at least 18 years old and must '
                  'submit current, authentic identity, licence, vehicle, and '
                  'TODA documents. Registration does not guarantee approval. '
                  'Approved drivers must keep their licence and vehicle '
                  'documents valid, obey traffic and TODA rules, use only the '
                  'approved vehicle, and provide safe and professional service.',
            ),
            const _LegalSection(
              title: 'Fares and bookings',
              body:
                  'The fare estimate is calculated from the current city fare '
                  'configuration and the trip details selected by the '
                  'passenger. The final amount may change only when the route '
                  'or selected trip options change. Duplicate, fraudulent, or '
                  'abusive bookings may be cancelled or investigated.',
            ),
            const _LegalSection(
              title: 'Safety and emergencies',
              body:
                  'The SOS feature records an incident for review; it is not a '
                  'replacement for emergency services. In immediate danger, '
                  'contact 911 when it is safe to do so. Do not misuse safety '
                  'features or submit false reports.',
            ),
            const _LegalSection(
              title: 'Suspension and termination',
              body:
                  'VolTrike or the responsible TODA may restrict, suspend, or '
                  'close an account for fraud, false documents, unsafe '
                  'conduct, repeated misuse, legal or regulatory requirements, '
                  'or a serious breach of these terms. Where appropriate, the '
                  'account holder may be asked for an explanation.',
            ),
            const _LegalSection(
              title: 'Service availability',
              body:
                  'VolTrike may be unavailable because of connectivity, map '
                  'services, maintenance, emergencies, or circumstances beyond '
                  'reasonable control. Nothing in these terms removes rights '
                  'or remedies that cannot lawfully be excluded.',
            ),
            const _LegalSection(
              title: 'Changes to these terms',
              body:
                  'Material changes will be presented in the app. When renewed '
                  'acceptance is required, you must review and accept the new '
                  'version before continuing to use the affected service.',
            ),
            const SizedBox(height: 8),
            Text(
              'Version ${LegalDocumentVersions.terms}',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (acknowledgementRequired) ...[
              const SizedBox(height: 24),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('I have read these terms'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _LegalSection extends StatelessWidget {
  const _LegalSection({required this.title, required this.body});

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
