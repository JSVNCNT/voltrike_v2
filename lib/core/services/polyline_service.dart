import 'package:voltrike_v2/core/maps/voltrike_map.dart';

class PolylineService {
  PolylineService._();
  static List<LatLng> decodePolyline(
    String encoded,
  ) {
    final List<LatLng> points = [];

    int index = 0;

    int latitude = 0;

    int longitude = 0;

    while (index < encoded.length) {
      int shift = 0;

      int result = 0;

      int byte;

      do {
        byte =
            encoded.codeUnitAt(index++) - 63;

        result |=
            (byte & 0x1F) << shift;

        shift += 5;
      } while (byte >= 0x20);

      final deltaLatitude =
          (result & 1) != 0
              ? ~(result >> 1)
              : (result >> 1);

      latitude += deltaLatitude;

      shift = 0;

      result = 0;

      do {
        byte =
            encoded.codeUnitAt(index++) - 63;

        result |=
            (byte & 0x1F) << shift;

        shift += 5;
      } while (byte >= 0x20);

      final deltaLongitude =
          (result & 1) != 0
              ? ~(result >> 1)
              : (result >> 1);

      longitude += deltaLongitude;

      points.add(
        LatLng(
          latitude / 1E5,
          longitude / 1E5,
        ),
      );
    }

    return points;
  }
}
