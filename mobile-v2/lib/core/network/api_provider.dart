import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app_info.dart';
import '../session/session_controller.dart';
import 'api_client.dart';

/// Replaced in tests to answer without a network.
final httpAdapterProvider = Provider<HttpClientAdapter?>((ref) => null);

/// The client for server-v2. The token is read on each request, so signing
/// in, or the server ending a session, takes effect at once.
final apiClientProvider = Provider<ApiClient>((ref) {
  final info = ref.watch(packageInfoProvider).value;
  final env = ref.watch(appEnvironmentProvider);
  return ApiClient(
    origin: env.apiBaseUrl,
    token: () => ref.read(sessionProvider).value?.token,
    // Version, platform and channel, for support and, later, forced updates
    // (docs/10, §4.6, B6).
    appHeader:
        '${info?.version ?? '?'}+${info?.buildNumber ?? '?'}; android; direct',
    adapter: ref.watch(httpAdapterProvider),
  );
});
