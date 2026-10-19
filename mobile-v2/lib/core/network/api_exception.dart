/// Why a request to the server failed, in terms a screen can act on.
enum ApiFailure {
  /// No answer: no signal, no bundle, or the server is unreachable.
  offline,

  /// The server took too long; the request may or may not have arrived.
  timeout,

  /// 401: signed out by the server (deactivated, or the password changed).
  unauthorized,

  /// 403: not allowed, or a reset password must be changed first.
  forbidden,

  /// 400 or 422: the server named what is wrong; see `fieldErrors`.
  invalid,

  notFound,

  /// 409.
  conflict,

  /// 5xx, or an answer that was not the server's (a proxy's error page).
  server,
}

/// A failed request. [message] is the server's own message when it sent one;
/// screens fall back to their own text for [kind] when it is empty, so no
/// error is ever shown blank (docs/08 §8, C1).
class ApiException implements Exception {
  final ApiFailure kind;
  final int? status;
  final String message;

  /// The Tusk envelope's `errors`: field name to what is wrong with it.
  final Map<String, String> fieldErrors;

  const ApiException(
    this.kind, {
    this.status,
    this.message = '',
    this.fieldErrors = const {},
  });

  /// Whether trying again later might work without changing anything.
  bool get isTransient =>
      kind == ApiFailure.offline ||
      kind == ApiFailure.timeout ||
      kind == ApiFailure.server;

  @override
  String toString() =>
      'ApiException(${kind.name}${status == null ? '' : ' $status'}: $message)';
}
