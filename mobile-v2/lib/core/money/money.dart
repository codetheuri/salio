/// Money is held in whole cents, never as a double (docs/10, D7): a ledger
/// must match the server to the cent, and doubles cannot hold 0.07.
///
/// The rules copy server-v2's `money.Parse` and `Amount.String`, and
/// testdata/shared/money.json pins both sides to the same cases.
abstract final class Money {
  static const _maxCents = 0x7FFFFFFFFFFFFFFF;

  /// Reads a decimal string such as "1500", "1500.5" or "1500.50".
  /// Throws [FormatException] for anything else, including three decimals:
  /// "1.005" is a precision shillings cannot hold.
  static int parse(String text) {
    var s = text.trim();
    if (s.isEmpty) throw const FormatException('empty amount');
    var negative = false;
    if (s.startsWith('-') || s.startsWith('+')) {
      negative = s.startsWith('-');
      s = s.substring(1);
    }
    if (s.isEmpty) throw FormatException('a sign with no amount', text);

    final dot = s.indexOf('.');
    final whole = dot < 0 ? s : s.substring(0, dot);
    var fraction = dot < 0 ? '' : s.substring(dot + 1);
    if (!_digits(whole.isEmpty ? '0' : whole) ||
        (dot >= 0 && !_digits(fraction))) {
      throw FormatException('not a valid amount', text);
    }
    if (fraction.length > 2) {
      throw FormatException('more than two decimal places', text);
    }
    fraction = fraction.padRight(2, '0');

    final major = BigInt.parse(whole.isEmpty ? '0' : whole);
    final cents = major * BigInt.from(100) + BigInt.parse(fraction);
    if (cents > BigInt.from(_maxCents)) {
      throw FormatException('out of range', text);
    }
    return negative ? -cents.toInt() : cents.toInt();
  }

  /// Like [parse], but null instead of an exception.
  static int? tryParse(String text) {
    try {
      return parse(text);
    } on FormatException {
      return null;
    }
  }

  /// The wire form the server reads: "1500.50", "-0.05".
  static String toWire(int cents) {
    final sign = cents < 0 ? '-' : '';
    final n = cents.abs();
    return '$sign${n ~/ 100}.${(n % 100).toString().padLeft(2, '0')}';
  }

  /// For people: "KES 1,250.50" (docs/10, §5). Whole shillings drop the
  /// cents when [compact]: "KES 1,250".
  static String format(int cents, {bool compact = false}) {
    final sign = cents < 0 ? '-' : '';
    final n = cents.abs();
    final shillings = _group((n ~/ 100).toString());
    final rest = n % 100;
    final decimals = compact && rest == 0
        ? ''
        : '.${rest.toString().padLeft(2, '0')}';
    return '${sign}KES $shillings$decimals';
  }

  static String _group(String digits) {
    final out = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) out.write(',');
      out.write(digits[i]);
    }
    return out.toString();
  }

  static bool _digits(String s) =>
      s.isNotEmpty && s.codeUnits.every((c) => c >= 0x30 && c <= 0x39);
}
