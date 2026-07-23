class Destination {
  const Destination({
    required this.placeId,
    required this.name,
    required this.address,
    required this.latitude,
    required this.longitude,
  });

  final String placeId;

  final String name;

  final String address;

  final double latitude;

  final double longitude;

  Destination copyWith({
    String? placeId,
    String? name,
    String? address,
    double? latitude,
    double? longitude,
  }) {
    return Destination(
      placeId: placeId ?? this.placeId,
      name: name ?? this.name,
      address: address ?? this.address,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
    );
  }
}