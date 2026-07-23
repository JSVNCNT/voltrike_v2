import 'package:flutter/material.dart';

import '../../../common/presentation/widgets/app_app_bar.dart';

class TermsAndConditionsScreen
    extends StatelessWidget {
  const TermsAndConditionsScreen({
    super.key,
  });

  @override
  Widget build(
    BuildContext context,
  ) {
    return Scaffold(
      appBar: const AppAppBar(
        title: 'Terms & Conditions',
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding:
              const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment:
                CrossAxisAlignment.start,
            children: [
              const Text(
                'Terms & Conditions',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight:
                      FontWeight.bold,
                ),
              ),

              const SizedBox(
                height: 20,
              ),

              const Text(
                'By using Voltrike, you agree to comply with these Terms and Conditions. These terms are intended to ensure a safe, reliable, and fair experience for both passengers and drivers.',
                textAlign:
                    TextAlign.justify,
              ),

              const SizedBox(
                height: 24,
              ),

              const Text(
                'Driver Responsibilities',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight:
                      FontWeight.bold,
                ),
              ),

              const SizedBox(
                height: 10,
              ),

              const Text(
                '• Provide accurate registration information.\n'
                '• Maintain a valid driver\'s license.\n'
                '• Keep vehicle documents updated.\n'
                '• Follow local traffic laws and TODA regulations.\n'
                '• Treat passengers with respect and professionalism.\n'
                '• Maintain the cleanliness and safety of the vehicle.',
              ),

              const SizedBox(
                height: 24,
              ),

              const Text(
                'Passenger Responsibilities',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight:
                      FontWeight.bold,
                ),
              ),

              const SizedBox(
                height: 10,
              ),

              const Text(
                '• Provide accurate pickup and destination information.\n'
                '• Respect drivers and their vehicles.\n'
                '• Pay the appropriate fare.\n'
                '• Avoid abusive, illegal, or unsafe behavior during trips.',
              ),

              const SizedBox(
                height: 24,
              ),

              const Text(
                'Account Usage',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight:
                      FontWeight.bold,
                ),
              ),

              const SizedBox(
                height: 10,
              ),

              const Text(
                'Users are responsible for maintaining the confidentiality of their account credentials. Any activity performed using an account is the responsibility of the account owner.',
                textAlign:
                    TextAlign.justify,
              ),

              const SizedBox(
                height: 24,
              ),

              const Text(
                'Prohibited Activities',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight:
                      FontWeight.bold,
                ),
              ),

              const SizedBox(
                height: 10,
              ),

              const Text(
                'The following activities are prohibited:\n\n'
                '• Providing false information.\n'
                '• Using another person\'s account.\n'
                '• Harassing or threatening other users.\n'
                '• Attempting to misuse or disrupt the application.\n'
                '• Engaging in fraudulent booking activities.',
              ),

              const SizedBox(
                height: 24,
              ),

              const Text(
                'Account Suspension',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight:
                      FontWeight.bold,
                ),
              ),

              const SizedBox(
                height: 10,
              ),

              const Text(
                'Voltrike reserves the right to suspend or terminate accounts that violate these Terms and Conditions or engage in fraudulent, illegal, or unsafe activities.',
                textAlign:
                    TextAlign.justify,
              ),

              const SizedBox(
                height: 24,
              ),

              const Text(
                'Changes to These Terms',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight:
                      FontWeight.bold,
                ),
              ),

              const SizedBox(
                height: 10,
              ),

              const Text(
                'These Terms and Conditions may be updated as the application evolves. Continued use of Voltrike after updates constitutes acceptance of the revised terms.',
                textAlign:
                    TextAlign.justify,
              ),

              const SizedBox(
                height: 32,
              ),

              const Center(
                child: Text(
                  'Version 1.0.0',
                  style: TextStyle(
                    color: Colors.grey,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}