import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

enum ExternalNavigationApp { googleMaps, waze, chooser }

class ExternalNavigationService {
  const ExternalNavigationService();

  Future<void> open({
    required ExternalNavigationApp app,
    required LatLng destination,
  }) async {
    if (!_valid(destination)) {
      throw const FormatException('The ride destination is invalid.');
    }
    final latitude = destination.latitude;
    final longitude = destination.longitude;
    final uri = switch (app) {
      ExternalNavigationApp.googleMaps =>
        Uri.parse('google.navigation:q=$latitude,$longitude&mode=d'),
      ExternalNavigationApp.waze =>
        Uri.parse('waze://?ll=$latitude,$longitude&navigate=yes'),
      ExternalNavigationApp.chooser => Uri.https(
          'www.google.com',
          '/maps/dir/',
          {'api': '1', 'destination': '$latitude,$longitude', 'travelmode': 'driving'},
        ),
    };
    final launched = await launchUrl(
      uri,
      mode: LaunchMode.externalApplication,
    );
    if (!launched) {
      throw StateError(
        app == ExternalNavigationApp.waze
            ? 'Waze is not installed.'
            : 'No navigation app is available.',
      );
    }
  }

  bool _valid(LatLng point) {
    return point.latitude.isFinite &&
        point.longitude.isFinite &&
        point.latitude >= -90 &&
        point.latitude <= 90 &&
        point.longitude >= -180 &&
        point.longitude <= 180;
  }
}
