/// "Now" by the server's clock (docs/10, D8).
///
/// Cheap phones' clocks drift by minutes, and some are set to the wrong day.
/// Every sync answer carries the server's time; the difference from the
/// phone's clock is kept and added to it, so a debt recorded offline is
/// dated by the server's idea of now, not the phone's.
class ServerClock {
  final DateTime Function() _deviceNow;

  /// Server time minus phone time.
  Duration offset;

  ServerClock({DateTime Function()? deviceNow, this.offset = Duration.zero})
    : _deviceNow = deviceNow ?? DateTime.now;

  DateTime now() => _deviceNow().toUtc().add(offset);

  /// Learns the offset from [serverTime], taken as the moment halfway between
  /// sending the request ([sentAt]) and receiving the answer ([receivedAt]).
  void observe(DateTime serverTime, DateTime sentAt, DateTime receivedAt) {
    final midpoint = sentAt.add(receivedAt.difference(sentAt) ~/ 2);
    offset = serverTime.toUtc().difference(midpoint.toUtc());
  }

  /// The phone's own clock, for measuring how long a request took.
  DateTime deviceNow() => _deviceNow().toUtc();
}
