/// Quantities are held in whole thousandths, never as a double: "1.5" bags
/// is 1500. The rules copy server-v2's `quantity.Parse` and
/// `Quantity.String`, and testdata/shared/quantity.json pins both sides to
/// the same cases.
abstract final class Quantity {
  static const scale = 1000;
  static const _max = 0x7FFFFFFFFFFFFFFF;

  /// Reads a decimal string such as "2", "1.5" or "0.250". Throws
  /// [FormatException] for anything else, including four decimals.
  static int parse(String text) {
    var s = text.trim();
    if (s.isEmpty) throw const FormatException('empty quantity');
    var negative = false;
    if (s.startsWith('-') || s.startsWith('+')) {
      negative = s.startsWith('-');
      s = s.substring(1);
    }
    if (s.isEmpty) throw FormatException('a sign with no number', text);

    final dot = s.indexOf('.');
    final whole = dot < 0 ? s : s.substring(0, dot);
    var fraction = dot < 0 ? '' : s.substring(dot + 1);
    if (!_digits(whole.isEmpty ? '0' : whole) ||
        (dot >= 0 && !_digits(fraction))) {
      throw FormatException('not a valid number', text);
    }
    if (fraction.length > 3) {
      throw FormatException('more than three decimal places', text);
    }
    fraction = fraction.padRight(3, '0');

    final total =
        BigInt.parse(whole.isEmpty ? '0' : whole) * BigInt.from(scale) +
        BigInt.parse(fraction);
    if (total > BigInt.from(_max)) throw FormatException('out of range', text);
    return negative ? -total.toInt() : total.toInt();
  }

  /// The wire form the server reads and writes: "2", "1.5", "0.001".
  static String toWire(int thousandths) {
    final sign = thousandths < 0 ? '-' : '';
    final n = thousandths.abs();
    final frac = n % scale;
    final rest = frac == 0
        ? ''
        : '.${frac.toString().padLeft(3, '0').replaceFirst(RegExp(r'0+$'), '')}';
    return '$sign${n ~/ scale}$rest';
  }

  static bool _digits(String s) =>
      s.isNotEmpty && s.codeUnits.every((c) => c >= 0x30 && c <= 0x39);
}
