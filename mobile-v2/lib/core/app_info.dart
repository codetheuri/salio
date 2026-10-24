import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../app/environment.dart';

/// This build's environment. A provider, so tests can choose one.
final appEnvironmentProvider = Provider<AppEnvironment>(
  (ref) => AppEnvironment.current,
);

/// The installed version and build number, read from Android.
final packageInfoProvider = FutureProvider<PackageInfo>(
  (ref) => PackageInfo.fromPlatform(),
);
