import 'package:flutter/material.dart';

import '../../../../../core/constants/app_assets.dart';
import '../../widgets/app_app_bar.dart';

class AboutVoltrikeScreen extends StatelessWidget {
  const AboutVoltrikeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const AppAppBar(title: 'About VolTrike'),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Image.asset(AppAssets.logoDark, height: 112),
            const SizedBox(height: 16),
            Text(
              'VolTrike',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 4),
            const Text('Clean Community Mobility', textAlign: TextAlign.center),
            const SizedBox(height: 28),
            const Card(
              child: Padding(
                padding: EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'About',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    SizedBox(height: 12),
                    Text(
                      'VolTrike is a community transport booking service that '
                      'helps passengers request electric tricycle rides and '
                      'helps accredited drivers and TODAs manage safe, local '
                      'transport operations.',
                    ),
                    SizedBox(height: 24),
                    Divider(),
                    SizedBox(height: 16),
                    Text(
                      'Developed by',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.people_outline),
                      title: Text('Jose Vincent Bayoguing and Denro Maban'),
                      subtitle: Text('Capstone project team'),
                    ),
                    Divider(),
                    SizedBox(height: 16),
                    Center(child: Text('Version 1.0.0')),
                    SizedBox(height: 4),
                    Center(child: Text('© 2026 VolTrike')),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
