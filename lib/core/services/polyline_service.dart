import 'package:voltrike_v2/core/maps/voltrike_map.dart';

class PolylineService {
  PolylineService._();

  static const int maximumEncodedBytes = 4 * 1000 * 1000;
  static const int maximumPoints = 200000;

  static List<LatLng> decodePolyline(
    String encoded, {
    int maxEncodedBytes = maximumEncodedBytes,
    int maxPoints = maximumPoints,
  }) {
    if (encoded.length > maxEncodedBytes) {
      throw const FormatException('Encoded polyline exceeds the safety limit.');
    }
    final points = <LatLng>[];
    var index = 0;
    var latitude = 0;
    var longitude = 0;

    int decodeDelta() {
      var shift = 0;
      var result = 0;
      while (true) {
        if (index >= encoded.length) {
          throw const FormatException(
            'Encoded polyline ended inside a coordinate.',
          );
        }
        final value = encoded.codeUnitAt(index++) - 63;
        if (value < 0 || value > 63) {
          throw const FormatException(
            'Encoded polyline contains an invalid character.',
          );
        }
        if (shift >= 63) {
          throw const FormatException(
            'Encoded polyline coordinate exceeds the safety limit.',
          );
        }
        result |= (value & 0x1f) << shift;
        if (value < 0x20) break;
        shift += 5;
      }
      final magnitude = result >> 1;
      return (result & 1) == 0 ? magnitude : -magnitude - 1;
    }

    while (index < encoded.length) {
      latitude += decodeDelta();
      longitude += decodeDelta();
      if (latitude < -9000000 ||
          latitude > 9000000 ||
          longitude < -18000000 ||
          longitude > 18000000) {
        throw const FormatException(
          'Encoded polyline contains an out-of-range coordinate.',
        );
      }

      points.add(LatLng(latitude / 1E5, longitude / 1E5));
      if (points.length > maxPoints) {
        throw const FormatException(
          'Encoded polyline exceeds the point safety limit.',
        );
      }
    }

    return points;
  }
}
