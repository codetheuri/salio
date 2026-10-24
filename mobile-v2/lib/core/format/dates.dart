import 'package:intl/intl.dart';

/// "Tue 14 Oct, 10:15" in the phone's time zone and the app's language
/// (docs/10, §5). The shop's own time zone replaces the phone's in M3.
String formatDateTime(DateTime t, String locale) =>
    DateFormat('EEE d MMM, HH:mm', locale).format(t.toLocal());
