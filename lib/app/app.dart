import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/theme/app_theme.dart';
import 'router.dart';

class VolTrikeApp extends StatelessWidget {
  const VolTrikeApp({super.key});

  @override
  Widget build(BuildContext context) {
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
        value: SystemUiOverlayStyle.dark,

        child: MaterialApp.router(
          debugShowCheckedModeBanner: false,

          title: 'VolTrike',

          theme: AppTheme.lightTheme,

          // Reserved for future dark mode.
          darkTheme: AppTheme.darkTheme,

          themeMode: ThemeMode.light,

          routerConfig: appRouter,

        ),
      ),
    );
  }
}
