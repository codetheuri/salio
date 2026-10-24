import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:timezone/data/latest_10y.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../session/session_controller.dart';
import 'clock_provider.dart';

/// Times as the shop reads them: in the shop's own time zone (the business
/// profile's), not the phone's. A phone set to the wrong zone must not move
/// a debt to the wrong day, and "today" for what is overdue is the shop's
/// today (docs/10, §5).
class ShopTime {
  /// The zone every shop starts in, and the fallback before the business
  /// profile has been read.
  static const defaultZone = 'Africa/Nairobi';

  final tz.Location location;

  ShopTime._(this.location);

  /// The shop's clock in [zone]; an unknown zone falls back to Nairobi.
  factory ShopTime(String? zone) {
    _load();
    try {
      return ShopTime._(tz.getLocation(zone ?? defaultZone));
    } on tz.LocationNotFoundException {
      return ShopTime._(tz.getLocation(defaultZone));
    }
  }

  static var _loaded = false;
  static void _load() {
    if (_loaded) return;
    // Ten years of rules: enough for every date a ledger shows, at a
    // fraction of the full database's size.
    tzdata.initializeTimeZones();
    _loaded = true;
  }

  /// [t] on the shop's wall clock.
  DateTime local(DateTime t) => tz.TZDateTime.from(t.toUtc(), location);

  /// The shop's calendar day for [t], as UTC midnight: how due dates are
  /// held, so the two compare as days.
  DateTime day(DateTime t) {
    final l = local(t);
    return DateTime.utc(l.year, l.month, l.day);
  }

  /// The instant the shop's calendar [day] (UTC midnight, as [day] gives)
  /// begins on its wall clock: where "today's sales" start.
  DateTime startOf(DateTime day) =>
      tz.TZDateTime(location, day.year, day.month, day.day).toUtc();

  /// "Tue 14 Oct, 10:15".
  String dateTime(DateTime t, String locale) =>
      DateFormat('EEE d MMM, HH:mm', locale).format(local(t));

  /// "Tue 14 Oct 2026", for a calendar day held as UTC midnight.
  static String date(DateTime day, String locale) =>
      DateFormat('EEE d MMM y', locale).format(day);
}

/// The signed-in shop's clock.
final shopTimeProvider = Provider<ShopTime>(
  (ref) => ShopTime(
    ref.watch(sessionProvider.select((s) => s.value?.account.timeZone)),
  ),
);

/// Today in the shop, by the server's clock: what is overdue is measured
/// from here.
final shopTodayProvider = Provider<DateTime>(
  (ref) =>
      ref.watch(shopTimeProvider).day(ref.watch(serverClockProvider).now()),
);
