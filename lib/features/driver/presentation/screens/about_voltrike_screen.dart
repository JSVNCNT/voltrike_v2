import 'package:flutter/material.dart';

import '../../../common/presentation/widgets/app_app_bar.dart';

class AboutVoltrikeScreen extends StatelessWidget {
  const AboutVoltrikeScreen({
    super.key,
  });

  @override
  Widget build(
    BuildContext context,
  ) {
    return Scaffold(
      appBar: const AppAppBar(
        title: 'About Voltrike',
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding:
              const EdgeInsets.all(24),
          child: Column(
            children: [
              //----------------------------------------------------------------
              // Logo
              //----------------------------------------------------------------

              CircleAvatar(
                radius: 55,
                backgroundColor:
                    Theme.of(context)
                        .colorScheme
                        .primaryContainer,
                child: const Icon(
                  Icons.electric_rickshaw,
                  size: 60,
                ),
              ),

              const SizedBox(
                height: 20,
              ),

              const Text(
                'Voltrike',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight:
                      FontWeight.bold,
                ),
              ),

              const SizedBox(
                height: 8,
              ),

              const Text(
                'Community Tricycle Booking System',
                textAlign:
                    TextAlign.center,
                style: TextStyle(
                  color: Colors.grey,
                ),
              ),

              const SizedBox(
                height: 32,
              ),

              Card(
                child: Padding(
                  padding:
                      const EdgeInsets.all(
                    20,
                  ),
                  child: Column(
                    crossAxisAlignment:
                        CrossAxisAlignment
                            .start,
                    children: [

                                           const Text(
                        'About',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight:
                              FontWeight.bold,
                        ),
                      ),

                      const SizedBox(
                        height: 12,
                      ),

                      const Text(
                        'Voltrike is a community-based tricycle booking application designed to provide passengers with a convenient way to book rides while helping drivers manage bookings efficiently. The application aims to improve accessibility, safety, and transportation services within local TODA communities.',
                        textAlign:
                            TextAlign.justify,
                      ),

                      const SizedBox(
                        height: 24,
                      ),

                      const Divider(),

                      const SizedBox(
                        height: 16,
                      ),

                      const Text(
                        'Developed By',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight:
                              FontWeight.bold,
                        ),
                      ),

                      const SizedBox(
                        height: 12,
                      ),

                      const ListTile(
                        leading: Icon(
                          Icons.person,
                        ),
                        title: Text(
                          'Jose Vincent Bayoguing, Denro Maban',
                        ),
                        subtitle: Text(
                          'Developers',
                        ),
                      ),

                      const ListTile(
                        leading: Icon(
                          Icons.people,
                        ),
                        title: Text(
                          'Capstone Project Team',
                        ),
                        subtitle: Text(
                          'BS Information Technology',
                        ),
                      ),

                      const SizedBox(
                        height: 24,
                      ),

                      const Divider(),

                      const SizedBox(
                        height: 16,
                      ),

                      const Center(
                        child: Column(
                          children: [
                            Text(
                              'Version 1.0.0',
                              style: TextStyle(
                                fontWeight:
                                    FontWeight.bold,
                              ),
                            ),
                            SizedBox(
                              height: 8,
                            ),
                            Text(
                              '© 2026 Voltrike',
                              style: TextStyle(
                                color:
                                    Colors.grey,
                              ),
                            ),
                            SizedBox(
                              height: 4,
                            ),
                            Text(
                              'All Rights Reserved',
                              style: TextStyle(
                                color:
                                    Colors.grey,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
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