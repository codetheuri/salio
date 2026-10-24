import 'account_store.dart';

/// The account in use. [token] is null when the server ended the session
/// (deactivated, or the password changed elsewhere): the shop's data stays
/// usable on the phone, and only syncing waits for a new sign-in
/// (docs/10, §4.5).
class Session {
  final Account account;
  final String? token;

  /// The server's reason, when it ended the session.
  final String? endedReason;

  const Session(this.account, this.token, {this.endedReason});

  bool get canSync => token != null;
}
