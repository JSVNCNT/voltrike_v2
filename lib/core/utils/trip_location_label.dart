/// Produces one consistent human-readable trip endpoint label everywhere the
/// server-owned booking projection is rendered. Older bookings have no place
/// name and deliberately fall back to their persisted address.
String tripLocationLabel(String? placeName, String address) {
  final name = placeName?.trim() ?? '';
  final normalizedAddress = address.trim();
  if (name.isEmpty || normalizedAddress.isEmpty) {
    return normalizedAddress.isEmpty ? name : normalizedAddress;
  }
  if (normalizedAddress.toLowerCase().contains(name.toLowerCase())) {
    return normalizedAddress;
  }
  return '$name\n$normalizedAddress';
}
