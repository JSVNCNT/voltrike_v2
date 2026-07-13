import 'package:permission_handler/permission_handler.dart';

class PermissionService {
  const PermissionService._();

  static Future<bool> requestLocation() async {
    final status = await Permission.location.request();

    return status.isGranted;
  }

  static Future<bool> requestNotification() async {
    final status = await Permission.notification.request();

    return status.isGranted;
  }

  static Future<bool> openSettings() {
    return openAppSettings();
  }
}