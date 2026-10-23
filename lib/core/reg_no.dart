/// Uppercases and strips spaces, hyphens and any other separators.
String normalizeRegNo(String input) =>
    input.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');

final _standard = RegExp(r'^[A-Z]{2}\d{1,2}[A-Z]{0,3}\d{4}$');
final _bharat = RegExp(r'^\d{2}BH\d{4}[A-Z]{1,2}$');

/// Accepts standard plates (MH12AB1234, DL1CAB1234, KA03M1234) and BH-series (22BH1234AA).
bool isValidRegNo(String input) {
  final reg = normalizeRegNo(input);
  return _standard.hasMatch(reg) || _bharat.hasMatch(reg);
}

/// MH12AB1234 → MH12****34 (used in wallet transaction descriptions and logs).
String maskRegNo(String normalized) {
  if (normalized.length <= 6) return normalized;
  return '${normalized.substring(0, 4)}****${normalized.substring(normalized.length - 2)}';
}
