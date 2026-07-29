import 'package:flutter/material.dart';

@immutable
class AppSemanticColors extends ThemeExtension<AppSemanticColors> {
  const AppSemanticColors({
    required this.success,
    required this.onSuccess,
    required this.successContainer,
    required this.onSuccessContainer,
    required this.warning,
    required this.onWarning,
    required this.warningContainer,
    required this.onWarningContainer,
    required this.info,
    required this.onInfo,
    required this.infoContainer,
    required this.onInfoContainer,
    required this.rating,
    required this.callAction,
    required this.onCallAction,
    required this.chatAction,
    required this.onChatAction,
    required this.reportAction,
    required this.onReportAction,
    required this.safetyAction,
    required this.onSafetyAction,
  });

  final Color success;
  final Color onSuccess;
  final Color successContainer;
  final Color onSuccessContainer;
  final Color warning;
  final Color onWarning;
  final Color warningContainer;
  final Color onWarningContainer;
  final Color info;
  final Color onInfo;
  final Color infoContainer;
  final Color onInfoContainer;
  final Color rating;
  final Color callAction;
  final Color onCallAction;
  final Color chatAction;
  final Color onChatAction;
  final Color reportAction;
  final Color onReportAction;
  final Color safetyAction;
  final Color onSafetyAction;

  static AppSemanticColors of(BuildContext context) {
    final theme = Theme.of(context);
    return theme.extension<AppSemanticColors>() ??
        (theme.brightness == Brightness.dark ? dark : light);
  }

  static const light = AppSemanticColors(
    success: Color(0xFF2E7D32),
    onSuccess: Colors.white,
    successContainer: Color(0xFFE8F5E9),
    onSuccessContainer: Color(0xFF164A18),
    warning: Color(0xFF7A5600),
    onWarning: Colors.white,
    warningContainer: Color(0xFFFFF0C2),
    onWarningContainer: Color(0xFF3D2D00),
    info: Color(0xFF1565C0),
    onInfo: Colors.white,
    infoContainer: Color(0xFFE3F2FD),
    onInfoContainer: Color(0xFF0A3A69),
    rating: Color(0xFFB26A00),
    callAction: Color(0xFF2E7D32),
    onCallAction: Colors.white,
    chatAction: Color(0xFF0288D1),
    onChatAction: Colors.white,
    reportAction: Color(0xFFF57C00),
    onReportAction: Color(0xFF2E1600),
    safetyAction: Color(0xFF006F73),
    onSafetyAction: Colors.white,
  );

  static const dark = AppSemanticColors(
    success: Color(0xFF7DDC84),
    onSuccess: Color(0xFF062108),
    successContainer: Color(0xFF123B1D),
    onSuccessContainer: Color(0xFFB8F5BE),
    warning: Color(0xFFF5C76B),
    onWarning: Color(0xFF3D2B00),
    warningContainer: Color(0xFF4A370A),
    onWarningContainer: Color(0xFFFFE2A3),
    info: Color(0xFF82BFFF),
    onInfo: Color(0xFF002E52),
    infoContainer: Color(0xFF123A5A),
    onInfoContainer: Color(0xFFCBE6FF),
    rating: Color(0xFFFFD166),
    callAction: Color(0xFF7DDC84),
    onCallAction: Color(0xFF062108),
    chatAction: Color(0xFF82CFFF),
    onChatAction: Color(0xFF002433),
    reportAction: Color(0xFFF6B35C),
    onReportAction: Color(0xFF3D2200),
    safetyAction: Color(0xFF56C7C7),
    onSafetyAction: Color(0xFF002021),
  );

  @override
  AppSemanticColors copyWith({
    Color? success,
    Color? onSuccess,
    Color? successContainer,
    Color? onSuccessContainer,
    Color? warning,
    Color? onWarning,
    Color? warningContainer,
    Color? onWarningContainer,
    Color? info,
    Color? onInfo,
    Color? infoContainer,
    Color? onInfoContainer,
    Color? rating,
    Color? callAction,
    Color? onCallAction,
    Color? chatAction,
    Color? onChatAction,
    Color? reportAction,
    Color? onReportAction,
    Color? safetyAction,
    Color? onSafetyAction,
  }) {
    return AppSemanticColors(
      success: success ?? this.success,
      onSuccess: onSuccess ?? this.onSuccess,
      successContainer: successContainer ?? this.successContainer,
      onSuccessContainer: onSuccessContainer ?? this.onSuccessContainer,
      warning: warning ?? this.warning,
      onWarning: onWarning ?? this.onWarning,
      warningContainer: warningContainer ?? this.warningContainer,
      onWarningContainer: onWarningContainer ?? this.onWarningContainer,
      info: info ?? this.info,
      onInfo: onInfo ?? this.onInfo,
      infoContainer: infoContainer ?? this.infoContainer,
      onInfoContainer: onInfoContainer ?? this.onInfoContainer,
      rating: rating ?? this.rating,
      callAction: callAction ?? this.callAction,
      onCallAction: onCallAction ?? this.onCallAction,
      chatAction: chatAction ?? this.chatAction,
      onChatAction: onChatAction ?? this.onChatAction,
      reportAction: reportAction ?? this.reportAction,
      onReportAction: onReportAction ?? this.onReportAction,
      safetyAction: safetyAction ?? this.safetyAction,
      onSafetyAction: onSafetyAction ?? this.onSafetyAction,
    );
  }

  @override
  AppSemanticColors lerp(covariant AppSemanticColors? other, double t) {
    if (other == null) return this;
    return AppSemanticColors(
      success: Color.lerp(success, other.success, t)!,
      onSuccess: Color.lerp(onSuccess, other.onSuccess, t)!,
      successContainer: Color.lerp(
        successContainer,
        other.successContainer,
        t,
      )!,
      onSuccessContainer: Color.lerp(
        onSuccessContainer,
        other.onSuccessContainer,
        t,
      )!,
      warning: Color.lerp(warning, other.warning, t)!,
      onWarning: Color.lerp(onWarning, other.onWarning, t)!,
      warningContainer: Color.lerp(
        warningContainer,
        other.warningContainer,
        t,
      )!,
      onWarningContainer: Color.lerp(
        onWarningContainer,
        other.onWarningContainer,
        t,
      )!,
      info: Color.lerp(info, other.info, t)!,
      onInfo: Color.lerp(onInfo, other.onInfo, t)!,
      infoContainer: Color.lerp(infoContainer, other.infoContainer, t)!,
      onInfoContainer: Color.lerp(onInfoContainer, other.onInfoContainer, t)!,
      rating: Color.lerp(rating, other.rating, t)!,
      callAction: Color.lerp(callAction, other.callAction, t)!,
      onCallAction: Color.lerp(onCallAction, other.onCallAction, t)!,
      chatAction: Color.lerp(chatAction, other.chatAction, t)!,
      onChatAction: Color.lerp(onChatAction, other.onChatAction, t)!,
      reportAction: Color.lerp(reportAction, other.reportAction, t)!,
      onReportAction: Color.lerp(onReportAction, other.onReportAction, t)!,
      safetyAction: Color.lerp(safetyAction, other.safetyAction, t)!,
      onSafetyAction: Color.lerp(onSafetyAction, other.onSafetyAction, t)!,
    );
  }
}
