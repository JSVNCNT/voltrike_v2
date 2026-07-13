import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../../app/routes.dart';
import '../../../../../core/theme/app_spacing.dart';
import '../../../../../core/widgets/buttons/primary_button.dart';

import '../../widgets/auth_header.dart';
import '../../widgets/auth_logo.dart';
import '../../widgets/auth_scaffold.dart';

class DriverUnderReviewScreen extends ConsumerWidget {
  const DriverUnderReviewScreen({
    super.key,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AuthScaffold(
      child: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            children: [
              const SizedBox(
                height: AppSpacing.lg,
              ),

              const AuthLogo(
                logoSize: 90,
              ),

              const SizedBox(
                height: AppSpacing.xl,
              ),

              const AuthHeader(
                title: 'Registration Submitted',
                subtitle:
                    'Your driver application has been received.',
              ),

              const SizedBox(
                height: AppSpacing.xl,
              ),

              Image.asset(
                'assets/icons/under_review.png',
                height: 180,
              ),

              const SizedBox(
                height: AppSpacing.xl,
              ),

              Card(
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius:
                      BorderRadius.circular(16),
                ),
                child: Padding(
                  padding:
                      const EdgeInsets.all(20),
                  child: Column(
                    children: const [
                      Row(
                        children: [
                          Icon(
                            Icons.check_circle,
                            color: Colors.green,
                          ),
                          SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'Registration submitted successfully',
                            ),
                          ),
                        ],
                      ),

                      SizedBox(height: 16),

                      Row(
                        children: [
                          Icon(
                            Icons.email,
                            color: Colors.blue,
                          ),
                          SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'Verification email has been sent',
                            ),
                          ),
                        ],
                      ),

                      SizedBox(height: 16),

                      Row(
                        children: [
                          Icon(
                            Icons.description,
                            color: Colors.orange,
                          ),
                          SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'Your uploaded documents are under review',
                            ),
                          ),
                        ],
                      ),

                      SizedBox(height: 16),

                      Row(
                        children: [
                          Icon(
                            Icons.admin_panel_settings,
                            color: Colors.teal,
                          ),
                          SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'Waiting for TODA administrator approval',
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(
                height: AppSpacing.xl,
              ),
                            PrimaryButton(
                text: 'Go to Login',
                onPressed: () {
                  context.go(
                    AppRoutes.login,
                  );
                },
              ),

              const SizedBox(
                height: AppSpacing.md,
              ),

              OutlinedButton.icon(
                onPressed: () {
                  ScaffoldMessenger.of(context)
                      .showSnackBar(
                    const SnackBar(
                      content: Text(
                        'Verification email feature will be available soon.',
                      ),
                    ),
                  );
                },
                icon: const Icon(
                  Icons.mark_email_read_outlined,
                ),
                label: const Text(
                  'Resend Verification Email',
                ),
              ),

              const SizedBox(
                height: AppSpacing.xl,
              ),

              const Text(
                'Please verify your email address and wait for your TODA administrator '
                'to review your application. Once approved, you can log in and start '
                'accepting bookings.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.grey,
                  fontSize: 13,
                  height: 1.5,
                ),
              ),

              const SizedBox(
                height: AppSpacing.xxl,
              ),
            ],
          ),
        ),
      ),
    );
  }
}