/// Formats a backend money string such as "1234567.5" as "₹12,34,568", rounded to the nearest rupee.
///
/// Works on the string rather than a double so no precision is lost.
/// Indian digit grouping: the last three digits, then groups of two.
String formatInr(String amount) {
  final rupees = roundToRupees(amount);
  return '${rupees.isNegative ? '-' : ''}₹${_groupIndian(rupees.abs().toString())}';
}

/// Rounds a backend money string to the nearest whole rupee (halves round away from zero).
BigInt roundToRupees(String amount) {
  final trimmed = amount.trim();
  final negative = trimmed.startsWith('-');
  final unsigned = negative ? trimmed.substring(1) : trimmed;

  final parts = unsigned.split('.');
  var whole = BigInt.tryParse(parts[0].isEmpty ? '0' : parts[0]) ?? BigInt.zero;
  final roundUp = parts.length > 1 && parts[1].isNotEmpty && parts[1].codeUnitAt(0) >= 0x35; // '5'
  if (roundUp) whole += BigInt.one;

  return negative ? -whole : whole;
}

/// Formats a whole-rupee amount, e.g. 1234 as "₹1,234".
String formatRupees(int rupees) => formatInr(rupees.toString());

String _groupIndian(String digits) {
  if (digits.length <= 3) return digits;

  final last3 = digits.substring(digits.length - 3);
  var rest = digits.substring(0, digits.length - 3);
  final groups = <String>[];
  while (rest.length > 2) {
    groups.insert(0, rest.substring(rest.length - 2));
    rest = rest.substring(0, rest.length - 2);
  }
  if (rest.isNotEmpty) groups.insert(0, rest);
  return '${groups.join(',')},$last3';
}
