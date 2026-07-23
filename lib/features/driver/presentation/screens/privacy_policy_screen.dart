import 'package:flutter/material.dart';

import '../../../common/presentation/widgets/app_app_bar.dart';

class PrivacyPolicyScreen extends StatelessWidget {
  const PrivacyPolicyScreen({
    super.key,
  });

  @override
  Widget build(
    BuildContext context,
  ) {
    return Scaffold(
      appBar: const AppAppBar(
        title: 'Privacy Policy',
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
                'Privacy Policy',
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
                'Voltrike values your privacy and is committed to protecting your personal information. This Privacy Policy explains what information we collect, how it is used, and how we protect it while you use the application.',
                textAlign:
                    TextAlign.justify,
              ),

              const SizedBox(
                height: 24,
              ),

              const Text(
                'Information We Collect',
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
                '• Name and account information\n'
                '• Email address\n'
                '• Driver registration details\n'
                '• Vehicle information\n'
                '• Profile photo\n'
                '• GPS location during active trips\n'
                '• Booking and trip history',
              ),

              const SizedBox(
                height: 24,
              ),

              const Text(
                'How We Use Your Information',
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
                'Your information is used to verify accounts, process bookings, connect passengers with drivers, display trip information, improve application performance, and maintain the safety and reliability of the Voltrike platform.',
                textAlign:
                    TextAlign.justify,
              ),

              const SizedBox(
                height: 24,
              ),

              const Text(
                'Location Information',
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
                'Location services are used only while providing booking and navigation services. Real-time location helps passengers track their assigned driver and enables the application to provide accurate trip information.',
                textAlign:
                    TextAlign.justify,
              ),

              const SizedBox(
                height: 24,
              ),

              const Text(
                'Data Security',
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
                'Voltrike uses secure Firebase services to store application data. Reasonable security measures are implemented to protect user information from unauthorized access.',
                textAlign:
                    TextAlign.justify,
              ),

              const SizedBox(
                height: 24,
              ),

              const Text(
                'Your Rights',
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
                'Users may request updates to their account information, report incorrect data, or contact the development team regarding questions about privacy and data handling.',
                textAlign:
                    TextAlign.justify,
              ),

              const SizedBox(
                height: 32,
              ),

              const Center(
                child: Text(
                  'Last Updated: July 2026',
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