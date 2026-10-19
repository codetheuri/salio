import '../../app/l10n/generated/app_localizations.dart';
import '../network/api_exception.dart';

/// What to tell the user about a failed request. The server's own message
/// when it sent one, otherwise the app's words for the kind of failure, so
/// no error is ever blank (docs/08 §8, C1).
String describeFailure(AppLocalizations l10n, Object error) {
  if (error is! ApiException) return l10n.errorUnexpected;
  return switch (error.kind) {
    ApiFailure.offline => l10n.errorOffline,
    ApiFailure.timeout => l10n.errorTimeout,
    ApiFailure.server => l10n.errorServer,
    _ => error.message.isNotEmpty ? error.message : l10n.errorUnexpected,
  };
}
