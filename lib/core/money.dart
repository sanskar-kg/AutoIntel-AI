import 'package:intl/intl.dart';

/// Money is always handled as integer paise; formatting happens only at the edge.
String formatPaise(int paise, {String locale = 'en_IN'}) {
  final whole = paise % 100 == 0;
  return NumberFormat.currency(
    locale: locale,
    symbol: '₹',
    decimalDigits: whole ? 0 : 2,
  ).format(paise / 100);
}

/// Rupees → paise for user-typed amounts (whole rupees only).
int rupeesToPaise(int rupees) => rupees * 100;
