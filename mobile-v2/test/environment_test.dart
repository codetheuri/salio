import 'package:flutter_test/flutter_test.dart';
import 'package:salio/app/environment.dart';

void main() {
  test('each flavour has its own server', () {
    expect(
      AppEnvironment.resolve(flavorName: 'dev').apiBaseUrl.toString(),
      AppEnvironment.laptopServer,
    );
    for (final flavor in ['staging', 'prod']) {
      expect(
        AppEnvironment.resolve(flavorName: flavor).apiBaseUrl.toString(),
        AppEnvironment.liveServer,
      );
    }
  });

  test('no flavour, as in tests, is dev', () {
    expect(AppEnvironment.resolve(flavorName: null).flavor, Flavor.dev);
  });

  test('API_URL points a dev build at the live server', () {
    final env = AppEnvironment.resolve(
      flavorName: 'dev',
      apiUrl: AppEnvironment.liveServer,
    );
    expect(env.flavor, Flavor.dev);
    expect(env.apiBaseUrl.host, 'apis.salio.urizon.co.ke');
  });

  test('plain HTTP is refused outside dev', () {
    for (final flavor in ['staging', 'prod']) {
      expect(
        () => AppEnvironment.resolve(
          flavorName: flavor,
          apiUrl: 'http://192.168.1.10:8090',
        ),
        throwsArgumentError,
      );
    }
    expect(
      AppEnvironment.resolve(
        flavorName: 'dev',
        apiUrl: 'http://192.168.1.10:8090',
      ).apiBaseUrl.port,
      8090,
    );
  });

  test('an address without a scheme is refused', () {
    expect(
      () => AppEnvironment.resolve(
        flavorName: 'dev',
        apiUrl: 'apis.salio.urizon.co.ke',
      ),
      throwsArgumentError,
    );
  });
}
