/// How money came in: the three methods a payment can have.
enum PaymentMethod {
  cash,
  mpesa,
  bank;

  /// The server's name for it (`payment_method`).
  String get wire => name;
}

/// Why a payment's reference cannot be used.
enum ReferenceProblem { mpesaCode, tooLong, cashHasNone }

/// The server's rule for a payment's reference (`payment.Reference`), so a
/// mistyped M-Pesa code is caught as it is typed, before it becomes a
/// dispute nobody can settle: a code with a letter missing matches no SMS.
/// testdata/shared/payment_reference.json pins both sides.
abstract final class PaymentReference {
  static final _mpesa = RegExp(r'^[A-Z0-9]{10}$');
  static const maxLength = 30;

  /// The reference as stored, or null for none; [problem] says why it
  /// cannot be used instead.
  static ({String? stored, ReferenceProblem? problem}) check(
    PaymentMethod method,
    String text,
  ) {
    final t = text.trim();
    if (t.isEmpty) return (stored: null, problem: null);
    return switch (method) {
      PaymentMethod.mpesa when _mpesa.hasMatch(t.toUpperCase()) => (
        stored: t.toUpperCase(),
        problem: null,
      ),
      PaymentMethod.mpesa => (
        stored: null,
        problem: ReferenceProblem.mpesaCode,
      ),
      PaymentMethod.bank when t.runes.length > maxLength => (
        stored: null,
        problem: ReferenceProblem.tooLong,
      ),
      PaymentMethod.bank => (stored: t, problem: null),
      PaymentMethod.cash => (
        stored: null,
        problem: ReferenceProblem.cashHasNone,
      ),
    };
  }
}
