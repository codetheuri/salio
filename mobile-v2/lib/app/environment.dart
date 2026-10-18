import 'package:flutter/services.dart' show appFlavor;

/// Which server family a build talks to. It is the Android flavour the APK
/// was built with (`--flavor dev`), so a build cannot be pointed at the
/// wrong place by a forgotten setting (docs/10, §4.6).
enum Flavor { dev, staging, prod }

/// Where this build sends its requests.
class AppEnvironment {
  final Flavor flavor;

  /// The server's origin, for example `https://apis.salio.urizon.co.ke`.
  /// The API itself is under `/api/v1` on it.
  final Uri apiBaseUrl;

  const AppEnvironment._(this.flavor, this.apiBaseUrl);

  /// The live server. Staging uses it too until a separate staging server
  /// exists, before the beta (docs/10, M8).
  static const liveServer = 'https://apis.salio.urizon.co.ke';

  /// server-v2 on the laptop. On an emulator or a phone plugged in by USB,
  /// `adb reverse tcp:8090 tcp:8090` makes the phone's 127.0.0.1:8090 reach
  /// the laptop's (see README.md).
  static const laptopServer = 'http://127.0.0.1:8090';

  /// This build's environment, from its flavour and the values given with
  /// `--dart-define=API_URL=...`.
  static final AppEnvironment current = resolve(
    flavorName: appFlavor,
    apiUrl: const String.fromEnvironment('API_URL'),
  );

  /// Works out the environment. [apiUrl] replaces the flavour's server when
  /// given, so a dev build can use the live server:
  /// `--dart-define=API_URL=https://apis.salio.urizon.co.ke`.
  ///
  /// Throws [ArgumentError] for plain HTTP outside dev: Android would refuse
  /// the connection anyway, and this says why at start instead of on every
  /// request.
  static AppEnvironment resolve({
    required String? flavorName,
    String apiUrl = '',
  }) {
    // Tests and tools run without a flavour.
    final flavor = Flavor.values.asNameMap()[flavorName] ?? Flavor.dev;
    final url = Uri.parse(
      apiUrl.isNotEmpty
          ? apiUrl
          : switch (flavor) {
              Flavor.dev => laptopServer,
              Flavor.staging || Flavor.prod => liveServer,
            },
    );
    if (!url.hasScheme || url.host.isEmpty) {
      throw ArgumentError.value(apiUrl, 'API_URL', 'is not a full address');
    }
    if (url.scheme != 'https' && flavor != Flavor.dev) {
      throw ArgumentError.value(
        apiUrl,
        'API_URL',
        'must be https outside the dev flavour',
      );
    }
    return AppEnvironment._(flavor, url);
  }
}
