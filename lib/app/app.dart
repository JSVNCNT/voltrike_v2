import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/providers/theme_provider.dart';
import '../core/theme/app_theme.dart';
import 'router.dart';

class VolTrikeApp extends ConsumerWidget {
  const VolTrikeApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);

    return GestureDetector(
      // Dismiss keyboard when tapping outside text fields.
      onTap: () {
        final currentFocus = FocusScope.of(context);

        if (!currentFocus.hasPrimaryFocus &&
            currentFocus.focusedChild != null) {
          currentFocus.unfocus();
        }
      },

      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: AppTheme.systemUiOverlayStyleFor(themeMode),

        child: MaterialApp.router(
          debugShowCheckedModeBanner: false,

          title: 'VolTrike',

          theme: AppTheme.lightTheme,

          darkTheme: AppTheme.darkTheme,

          themeMode: themeMode,

          routerConfig: appRouter,
        ),
      ),
    );
  }
}
