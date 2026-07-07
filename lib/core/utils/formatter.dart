import 'package:intl/intl.dart';

class Formatter {
  const Formatter._();

  // ===========================================================================
  // Currency
  // ===========================================================================

  static String currency(num value) {
    return NumberFormat.currency(
      locale: 'en_PH',
      symbol: '₱',
      decimalDigits: 2,
    ).format(value);
  }

  // ===========================================================================
  // Date
  // ===========================================================================

  static String date(DateTime date) {
    return DateFormat('MMMM d, yyyy').format(date);
  }

  // ===========================================================================
  // Time
  // ===========================================================================

  static String time(DateTime date) {
    return DateFormat('h:mm a').format(date);
  }

  // ===========================================================================
  // Date & Time
  // ===========================================================================

  static String dateTime(DateTime date) {
    return DateFormat('MMM d, yyyy • h:mm a').format(date);
  }

  // ===========================================================================
  // Ride Duration
  // ===========================================================================

  static String duration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);

    if (hours > 0) {
      return '${hours}h ${minutes}m';
    }

    return '${duration.inMinutes} min';
  }

  // ===========================================================================
  // Phone Number
  // ===========================================================================

  static String phone(String number) {
    if (number.length != 11) return number;

    return '${number.substring(0, 4)} '
        '${number.substring(4, 7)} '
        '${number.substring(7)}';
  }
}