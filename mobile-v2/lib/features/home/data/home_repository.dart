import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../../customers/data/customer_repository.dart';

/// A customer with a positive balance, as the server's summary lists them.
class Debtor {
  final String customerId;
  final String name;
  final String? phone;
  final int balanceCents;

  /// When anything was last recorded on their account.
  final DateTime lastActivity;

  const Debtor({
    required this.customerId,
    required this.name,
    this.phone,
    required this.balanceCents,
    required this.lastActivity,
  });
}

/// The shop's figures, computed on the phone exactly as server-v2's
/// `/reports/summary` computes them (`reports.Repository.Summary`), so Home
/// works offline and the live tests can hold the two equal:
/// - [owedCents] and [advancesCents] split each customer's balance by sign,
///   over live entries of live customers, never netted across customers;
/// - [collected30Cents] is payments recorded in the last 30 × 24 hours, by
///   when they were recorded, including those of customers since deleted
///   (the server's query does not join customers);
/// - a customer is *quiet* (the server's "overdue debtors") when they owe
///   something and nothing has been recorded on their account for 30 days.
///   That is not "past an agreed due date", which the app calls overdue.
class ShopFigures {
  final int totalCustomers;
  final int owedCents;
  final int advancesCents;
  final int customersInCredit;
  final int collected30Cents;
  final int quietCount;

  /// The ten largest balances, largest first.
  final List<Debtor> topDebtors;

  /// The ten quietest accounts still owing, longest quiet first.
  final List<Debtor> quietDebtors;

  const ShopFigures({
    required this.totalCustomers,
    required this.owedCents,
    required this.advancesCents,
    required this.customersInCredit,
    required this.collected30Cents,
    required this.quietCount,
    required this.topDebtors,
    required this.quietDebtors,
  });
}

/// Money that came in today: payments, and sales paid on the spot (not on
/// credit), by method and by who recorded them.
class TodayMoney {
  final Map<String, int> byMethod;
  final Map<String, int> byUser;
  final int paymentsCents;
  final int salesCents;

  const TodayMoney({
    required this.byMethod,
    required this.byUser,
    required this.paymentsCents,
    required this.salesCents,
  });

  int get totalCents => paymentsCents + salesCents;

  /// Only what [userId] took.
  int of(String userId) => byUser[userId] ?? 0;
}

/// One line of the Today list: a customer with money overdue or due today.
class TodayItem {
  final CustomerBalance customer;

  const TodayItem(this.customer);

  int get overdueCents => customer.dues.overdueCents;

  /// With the list's window of 0 days, "due soon" is due today.
  int get dueTodayCents => customer.dues.dueSoonCents;

  int get urgentCents => overdueCents + dueTodayCents;
}

/// Home, read from this phone's database: works offline, and updates as
/// syncs bring other phones' records.
class HomeRepository {
  final AppDatabase db;
  final CustomerRepository customers;

  HomeRepository(this.db, this.customers);

  /// How many debtors the server's summary lists at most.
  static const listLimit = 10;

  /// As the server: 30 × 24 hours before [now], not 30 calendar days.
  static const window = Duration(days: 30);

  static const _balances = '''
    SELECT c.id, c.name, c.phone,
      SUM(CASE WHEN e.type = 'debt' THEN e.amount_cents
               ELSE -e.amount_cents END) AS balance,
      MAX(julianday(e.created_at)) AS last_activity
    FROM ledger_entries e
    JOIN customers c ON c.id = e.customer_id
    WHERE e.is_deleted = 0 AND c.is_deleted = 0
    GROUP BY c.id
  ''';

  /// A Julian day number, as SQLite's `julianday()` gives it, as UTC.
  static DateTime _fromJulian(double day) =>
      DateTime.fromMillisecondsSinceEpoch(
        ((day - 2440587.5) * Duration.millisecondsPerDay).round(),
        isUtc: true,
      );

  Stream<ShopFigures> watchFigures(DateTime now) => db
      .customSelect(_balances, readsFrom: {db.customers, db.ledgerEntries})
      .watch()
      .asyncMap((rows) async {
        final since = now.subtract(window);
        var owed = 0, advances = 0, inCredit = 0;
        final debtors = <Debtor>[];
        for (final r in rows) {
          final balance = r.read<int>('balance');
          if (balance < 0) {
            advances -= balance;
            inCredit++;
          }
          if (balance <= 0) continue;
          owed += balance;
          debtors.add(
            Debtor(
              customerId: r.read<String>('id'),
              name: r.read<String>('name'),
              phone: r.readNullable<String>('phone'),
              balanceCents: balance,
              lastActivity: _fromJulian(r.read<double>('last_activity')),
            ),
          );
        }
        final top = [...debtors]
          ..sort((a, b) => b.balanceCents.compareTo(a.balanceCents));
        final quiet =
            debtors.where((d) => d.lastActivity.isBefore(since)).toList()
              ..sort((a, b) => a.lastActivity.compareTo(b.lastActivity));

        final customerCount =
            await (db.selectOnly(db.customers)
                  ..addColumns([db.customers.id.count()])
                  ..where(db.customers.isDeleted.not()))
                .map((r) => r.read(db.customers.id.count())!)
                .getSingle();
        final collected = await db
            .customSelect(
              'SELECT COALESCE(SUM(amount_cents), 0) AS total '
              "FROM ledger_entries WHERE type = 'payment' "
              'AND is_deleted = 0 AND julianday(created_at) >= julianday(?)',
              variables: [Variable.withDateTime(since)],
            )
            .getSingle();

        return ShopFigures(
          totalCustomers: customerCount,
          owedCents: owed,
          advancesCents: advances,
          customersInCredit: inCredit,
          collected30Cents: collected.read<int>('total'),
          quietCount: quiet.length,
          topDebtors: top.take(listLimit).toList(),
          quietDebtors: quiet.take(listLimit).toList(),
        );
      });

  /// Money in since [dayStart], the instant the shop's day began.
  Stream<TodayMoney> watchTodayMoney(DateTime dayStart) {
    final since = Variable.withDateTime(dayStart);
    return db
        .customSelect(
          "SELECT 'payment' AS kind, COALESCE(payment_method, '') AS method, "
          'user_id, SUM(amount_cents) AS total FROM ledger_entries '
          "WHERE type = 'payment' AND is_deleted = 0 "
          'AND julianday(created_at) >= julianday(?1) '
          'GROUP BY method, user_id '
          'UNION ALL '
          "SELECT 'sale', payment_method, user_id, SUM(amount_cents) "
          "FROM sales WHERE payment_method != 'credit' AND is_deleted = 0 "
          'AND julianday(sale_date) >= julianday(?1) '
          'GROUP BY payment_method, user_id',
          variables: [since],
          readsFrom: {db.ledgerEntries, db.sales},
        )
        .watch()
        .map((rows) {
          final byMethod = <String, int>{};
          final byUser = <String, int>{};
          var payments = 0, sales = 0;
          for (final r in rows) {
            final cents = r.read<int>('total');
            final method = r.read<String>('method');
            final user = r.read<String>('user_id');
            byMethod[method] = (byMethod[method] ?? 0) + cents;
            byUser[user] = (byUser[user] ?? 0) + cents;
            if (r.read<String>('kind') == 'payment') {
              payments += cents;
            } else {
              sales += cents;
            }
          }
          return TodayMoney(
            byMethod: byMethod,
            byUser: byUser,
            paymentsCents: payments,
            salesCents: sales,
          );
        });
  }

  /// Customers with money overdue or due today, largest first: the day's
  /// plan, by the same first-in, first-out rule as the server's
  /// `/reports/due`.
  Stream<List<TodayItem>> watchToday(DateTime today) => customers
      .watchList(today: today, dueWithinDays: 0)
      .map(
        (list) =>
            [
              for (final c in list)
                if (c.dues.overdueCents > 0 || c.dues.dueSoonCents > 0)
                  TodayItem(c),
            ]..sort((a, b) {
              final byAmount = b.urgentCents.compareTo(a.urgentCents);
              return byAmount != 0
                  ? byAmount
                  : a.customer.customer.name.compareTo(
                      b.customer.customer.name,
                    );
            }),
      );
}
