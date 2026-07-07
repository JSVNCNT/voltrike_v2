import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import 'screen_padding.dart';

class AppScaffold extends StatelessWidget {
  const AppScaffold({
    super.key,
    required this.body,
    this.title,
    this.appBar,
    this.floatingActionButton,
    this.bottomNavigationBar,
    this.backgroundColor,
    this.resizeToAvoidBottomInset = true,
    this.safeArea = true,
    this.padding = true,
    this.scrollable = true,
  });

  final Widget body;

  final String? title;

  final PreferredSizeWidget? appBar;

  final Widget? floatingActionButton;

  final Widget? bottomNavigationBar;

  final Color? backgroundColor;

  final bool resizeToAvoidBottomInset;

  final bool safeArea;

  final bool padding;

  final bool scrollable;

  @override
  Widget build(BuildContext context) {
    Widget page = body;

    if (padding) {
      page = ScreenPadding(
        child: page,
      );
    }

    if (scrollable) {
      page = SingleChildScrollView(
        keyboardDismissBehavior:
            ScrollViewKeyboardDismissBehavior.onDrag,
        child: page,
      );
    }

    if (safeArea) {
      page = SafeArea(
        child: page,
      );
    }

    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
        backgroundColor:
            backgroundColor ?? AppColors.scaffold,

        resizeToAvoidBottomInset:
            resizeToAvoidBottomInset,

        appBar: appBar,

        floatingActionButton:
            floatingActionButton,

        bottomNavigationBar:
            bottomNavigationBar,

        body: page,
      ),
    );
  }
}