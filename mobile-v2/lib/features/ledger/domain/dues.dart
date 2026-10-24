/// What a customer still owes, and when it falls due: the server's rule
/// (`reports/dues.go`), run on the phone so the filters and the customer
/// screen work offline. testdata/shared/dues.json pins both to the same
/// cases.
///
/// Every payment clears the oldest debt first (first in, first out). It is
/// the only method that answers "how long has this been owed" honestly:
/// applied any other way, someone who pays a little every week never looks
/// overdue, however old the debt they keep not quite clearing. A payment with
/// nothing left to clear is an advance, and clears the next debt.
library;

/// One entry of an account, in date order. [due] and the dates are calendar
/// days, held as UTC midnight.
class DueLine {
  final bool isDebt;
  final int cents;
  final DateTime? due;

  const DueLine({required this.isDebt, required this.cents, this.due});
}

class Dues {
  /// Everything still owed.
  final int totalCents;

  /// Owed and past its agreed day.
  final int overdueCents;

  /// Falling due today or within the window.
  final int dueSoonCents;

  /// The earliest agreed day still unpaid, late or not.
  final DateTime? earliestDue;

  /// The earliest agreed day not yet passed.
  final DateTime? nextDue;

  const Dues({
    this.totalCents = 0,
    this.overdueCents = 0,
    this.dueSoonCents = 0,
    this.earliestDue,
    this.nextDue,
  });

  static const none = Dues();

  bool get isOverdue => overdueCents > 0;

  /// Reads an account's [lines] as of the day [asOf], with a "due soon"
  /// window of [withinDays] days.
  static Dues of(List<DueLine> lines, DateTime asOf, {int withinDays = 7}) {
    final open = <({int cents, DateTime? due})>[];
    var advance = 0;
    for (final l in lines) {
      if (l.isDebt) {
        var amount = l.cents;
        if (advance > 0) {
          final used = advance < amount ? advance : amount;
          advance -= used;
          amount -= used;
        }
        if (amount > 0) open.add((cents: amount, due: l.due));
        continue;
      }
      var pay = l.cents;
      while (pay > 0 && open.isNotEmpty) {
        final first = open.first;
        final used = pay < first.cents ? pay : first.cents;
        pay -= used;
        if (used == first.cents) {
          open.removeAt(0);
        } else {
          open[0] = (cents: first.cents - used, due: first.due);
        }
      }
      advance += pay;
    }

    final horizon = asOf.add(Duration(days: withinDays));
    var total = 0, overdue = 0, soon = 0;
    DateTime? earliest, next;
    for (final o in open) {
      total += o.cents;
      final due = o.due;
      if (due == null) continue;
      if (earliest == null || due.isBefore(earliest)) earliest = due;
      if (due.isBefore(asOf)) {
        overdue += o.cents;
      } else {
        if (!due.isAfter(horizon)) soon += o.cents;
        if (next == null || due.isBefore(next)) next = due;
      }
    }
    return Dues(
      totalCents: total,
      overdueCents: overdue,
      dueSoonCents: soon,
      earliestDue: earliest,
      nextDue: next,
    );
  }
}
