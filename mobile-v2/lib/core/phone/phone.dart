/// Phone numbers in one stored form, E.164, read as Kenyan unless they carry
/// a country code (B15). The same rule as server-v2's `phone.Normalize`;
/// testdata/shared/phone.json pins both to the same cases.
///
/// Before this, "0712 345 678" and "+254712345678" were two customers. Numbers
/// picked from contacts come in every form, so the form must not matter.
abstract final class Phone {
  /// The stored form, or null when [raw] cannot be read as a phone number.
  ///
  /// 0712345678, 712345678, 254712345678, +254712345678 and 00254712345678
  /// all become +254712345678. A bare nine digits is Kenyan only when it
  /// starts with 7 or 1, the mobile ranges. Other countries need their code.
  /// Spaces, dashes, dots and brackets are ignored; anything else makes the
  /// number unreadable.
  static String? normalize(String raw) {
    final b = StringBuffer();
    final t = raw.trim();
    for (var i = 0; i < t.length; i++) {
      final c = t[i];
      if (_isDigit(c) || (c == '+' && i == 0)) {
        b.write(c);
      } else if (!' -.()'.contains(c)) {
        return null;
      }
    }
    final d = b.toString();
    if (d.startsWith('+254')) return _kenyan(d.substring(4));
    if (d.startsWith('00254')) return _kenyan(d.substring(5));
    if (d.startsWith('254') && d.length == 12) return _kenyan(d.substring(3));
    if (d.startsWith('0') && !d.startsWith('00')) {
      return _kenyan(d.substring(1));
    }
    if (d.length == 9 && (d[0] == '7' || d[0] == '1')) return _kenyan(d);
    if (d.startsWith('+')) return _international(d.substring(1));
    if (d.startsWith('00')) return _international(d.substring(2));
    return null;
  }

  /// For people: a Kenyan number as "0712 345 678", which is how shops
  /// read and say them; any other number as stored. An unreadable number
  /// (an old record) is shown as it is.
  static String display(String stored) {
    if (stored.length == 13 && stored.startsWith('+254')) {
      final n = stored.substring(4);
      return '0${n.substring(0, 3)} ${n.substring(3, 6)} ${n.substring(6)}';
    }
    return stored;
  }

  /// What to look for in stored numbers when someone types [query] into a
  /// search: its digits without a leading 0 or 254, so "0712 3" finds
  /// +254712345678. Null when the query has too few digits to be a number
  /// search (fewer than 3), so "Mama 2" stays a name search.
  static String? searchDigits(String query) {
    var d = query.split('').where(_isDigit).join();
    if (d.startsWith('254')) {
      d = d.substring(3);
    } else if (d.startsWith('0')) {
      d = d.substring(1);
    }
    return d.length >= 3 ? d : null;
  }

  static String? _kenyan(String n) =>
      n.length == 9 && n[0] != '0' && _digits(n) ? '+254$n' : null;

  static String? _international(String n) =>
      n.length >= 8 && n.length <= 15 && n[0] != '0' && _digits(n)
      ? '+$n'
      : null;

  static bool _isDigit(String c) =>
      c.codeUnitAt(0) >= 0x30 && c.codeUnitAt(0) <= 0x39;

  static bool _digits(String s) => s.split('').every(_isDigit);
}
