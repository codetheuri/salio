// The in-app updater: downloads that resume and are checked, the controller's
// decisions (Wi-Fi, rollout, required), and what the screens show. Ported
// from DairyGo, with Salio's rollout, sync-only blocking and self-resuming
// downloads added.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:salio/core/database/database_provider.dart';
import 'package:salio/core/network/api_provider.dart';
import 'package:salio/core/session/permissions.dart';
import 'package:salio/core/session/session_controller.dart';
import 'package:salio/core/sync/sync_controller.dart';
import 'package:salio/features/app_update/data/app_release.dart';
import 'package:salio/features/app_update/data/app_update_service.dart';
import 'package:salio/features/app_update/data/install_bucket.dart';
import 'package:salio/features/app_update/presentation/app_update_controller.dart';

import 'layout/harness.dart';
import 'support/fake_app_update.dart';
import 'support/fixtures.dart';

/// Serves one APK, like the API's /app/download.
class _ApkServer implements HttpClientAdapter {
  final List<int> apk;

  /// Honour Range requests (the API does; a proxy might not).
  bool resumes = true;

  /// Close the connection after this many bytes of the body.
  int? cutAfter;
  final List<String?> ranges = [];

  _ApkServer(this.apk);

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final range = options.headers['Range'] as String?;
    ranges.add(range);
    var start = 0;
    var status = 200;
    if (range != null && resumes) {
      start = int.parse(RegExp(r'bytes=(\d+)-').firstMatch(range)!.group(1)!);
      status = 206;
    }
    var body = apk.sublist(start);
    if (cutAfter != null) body = body.sublist(0, cutAfter);
    return ResponseBody(
      Stream.value(Uint8List.fromList(body)),
      status,
      headers: {
        Headers.contentTypeHeader: ['application/vnd.android.package-archive'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

AppRelease _releaseOf(List<int> apk, {String? sha}) => AppRelease(
  version: '2.0.1',
  build: 11,
  minBuild: 10,
  files: {
    'arm64': ReleaseFile(
      url: '/app/download/arm64',
      sha256: sha ?? sha256.convert(apk).toString(),
      size: apk.length,
    ),
  },
);

void main() {
  test('reads the release the server publishes', () {
    final r = AppRelease.fromJson({
      'version': '2.0.3',
      'build': 15,
      'min_build': 12,
      'rollout_percent': 10,
      'notes': {'en': 'Faster', 'sw': 'Haraka'},
      'files': {
        'arm64': {'url': '/app/download/arm64', 'sha256': 'ab', 'size': 9},
      },
    });
    expect(r.build, 15);
    expect(r.minBuild, 12);
    expect(r.rolloutPercent, 10);
    expect(r.notesIn('sw'), 'Haraka');
    expect(r.notesIn('fr'), 'Faster', reason: 'English when not translated');
    expect(
      AppRelease.fromJson({'version': '1', 'build': 1}).rolloutPercent,
      100,
      reason: 'no rollout means everyone',
    );
  });

  group('the rollout bucket', () {
    test('is chosen once and kept', () async {
      final dir = Directory.systemTemp.createTempSync('bucket');
      addTearDown(() => dir.deleteSync(recursive: true));
      final first = await InstallBucket(dir).read();
      expect(first, inInclusiveRange(0, 99));
      expect(await InstallBucket(dir).read(), first);
    });

    test('a release at N% reaches buckets below N, and widening only adds', () {
      expect(inRollout(0, 10), isTrue);
      expect(inRollout(9, 10), isTrue);
      expect(inRollout(10, 10), isFalse);
      expect(inRollout(99, 100), isTrue);
      expect(inRollout(0, 0), isFalse);
      for (var b = 0; b < 100; b++) {
        if (inRollout(b, 10)) expect(inRollout(b, 50), isTrue);
      }
    });
  });

  group('downloading an update', () {
    late Directory dir;
    late _ApkServer server;
    late AppUpdateService service;
    final apk = utf8.encode('APK' * 5000);

    setUp(() {
      dir = Directory.systemTemp.createTempSync('updates');
      server = _ApkServer(apk);
      service = AppUpdateService(
        Dio(BaseOptions(baseUrl: 'http://api'))..httpClientAdapter = server,
        FakeInstaller(dir: dir.path),
      );
    });
    tearDown(() => dir.deleteSync(recursive: true));

    test('saves the checked file and reports progress', () async {
      final seen = <int>[];
      final path = await service.download(
        _releaseOf(apk),
        'arm64',
        onProgress: (received, total) => seen.add(received),
      );
      expect(File(path).readAsBytesSync(), apk);
      expect(seen.last, apk.length);
      expect(File('$path.part').existsSync(), isFalse);
    });

    test('continues where a dropped download stopped', () async {
      server.cutAfter = 4000;
      await expectLater(
        service.download(_releaseOf(apk), 'arm64'),
        throwsA(
          isA<UpdateException>().having(
            (e) => e.failure,
            'failure',
            UpdateFailure.stopped,
          ),
        ),
      );
      expect(await service.partSize(_releaseOf(apk), 'arm64'), 4000);

      server.cutAfter = null;
      final path = await service.download(_releaseOf(apk), 'arm64');
      expect(server.ranges.last, 'bytes=4000-');
      expect(File(path).readAsBytesSync(), apk);
    });

    test('starts again when the server sends the whole file', () async {
      server.cutAfter = 4000;
      await expectLater(
        service.download(_releaseOf(apk), 'arm64'),
        throwsA(isA<UpdateException>()),
      );
      server
        ..cutAfter = null
        ..resumes = false;
      final path = await service.download(_releaseOf(apk), 'arm64');
      expect(File(path).readAsBytesSync(), apk);
    });

    test('throws away a damaged file', () async {
      final wrong = sha256.convert(utf8.encode('other')).toString();
      await expectLater(
        service.download(_releaseOf(apk, sha: wrong), 'arm64'),
        throwsA(
          isA<UpdateException>().having(
            (e) => e.failure,
            'failure',
            UpdateFailure.damaged,
          ),
        ),
      );
      expect(dir.listSync(), isEmpty, reason: 'nothing damaged is kept');
    });

    test('reuses a finished download without asking again', () async {
      await service.download(_releaseOf(apk), 'arm64');
      final requests = server.ranges.length;
      await service.download(_releaseOf(apk), 'arm64');
      expect(server.ranges.length, requests);
    });

    test('knows a finished download, and only a sound one', () async {
      final release = _releaseOf(apk);
      expect(await service.downloaded(release, 'arm64'), isNull);
      final path = await service.download(release, 'arm64');
      expect(await service.downloaded(release, 'arm64'), path);
      File(path).writeAsBytesSync(apk.sublist(1));
      expect(await service.downloaded(release, 'arm64'), isNull);
    });

    test('removes downloads of other versions', () async {
      final path = await service.download(_releaseOf(apk), 'arm64');
      File('${dir.path}/Salio-9-arm64.apk').writeAsStringSync('old');
      await service.removeOldDownloads(keepBuild: 11);
      expect(dir.listSync().map((f) => f.path), [path]);
    });
  });

  group('AppUpdateController', () {
    late FakeAppUpdateService service;
    late ProviderContainer container;
    AppUpdateController controller() =>
        container.read(appUpdateProvider.notifier);
    AppUpdateState state() => container.read(appUpdateProvider);

    void use(FakeAppUpdateService s, {int bucket = 0}) {
      service = s;
      container = ProviderContainer(overrides: fakeUpdateOverrides(s, bucket));
    }

    setUp(() => use(FakeAppUpdateService()));
    tearDown(() => container.dispose());

    test('finds a newer version', () async {
      service.latest = releaseForTests(build: 11, minBuild: 10);
      await controller().check();
      expect(state().available, isTrue);
      expect(state().required, isFalse);
    });

    test('requires the update when this version is too old', () async {
      service.latest = releaseForTests(build: 12, minBuild: 11);
      await controller().check();
      expect(state().required, isTrue);
      expect(state().available, isTrue);
    });

    test('nothing to do when up to date or nothing is published', () async {
      await controller().check(manual: true);
      expect(state().available, isFalse);
      expect(state().confirmedUpToDate, isTrue);

      service.latest = releaseForTests(build: 10, minBuild: 10);
      await controller().check(manual: true);
      expect(state().available, isFalse);
      expect(state().required, isFalse);
    });

    test('a staged release reaches only phones in its share', () async {
      container.dispose();
      use(
        FakeAppUpdateService(latest: releaseForTests(rollout: 10)),
        bucket: 42,
      );
      await controller().check(manual: true);
      expect(state().available, isFalse, reason: 'bucket 42 is not in 10%');
      expect(state().confirmedUpToDate, isTrue);

      container.dispose();
      use(
        FakeAppUpdateService(latest: releaseForTests(rollout: 50)),
        bucket: 42,
      );
      await controller().check();
      expect(state().available, isTrue, reason: 'bucket 42 is in 50%');
    });

    test(
      'a required update reaches every phone, whatever the rollout',
      () async {
        container.dispose();
        use(
          FakeAppUpdateService(
            latest: releaseForTests(build: 12, minBuild: 11, rollout: 0),
          ),
          bucket: 99,
        );
        await controller().check();
        expect(state().required, isTrue);
        expect(state().available, isTrue);
      },
    );

    test('checks automatically at most every few hours', () async {
      await controller().check();
      await controller().check();
      await controller().onResume();
      expect(service.checks, 1);
      await controller().check(manual: true);
      expect(service.checks, 2);
    });

    test('says so only when a check the user asked for fails', () async {
      service.checkError = Exception('offline');
      await controller().check();
      expect(state().error, isNull);
      await controller().check(manual: true);
      expect(state().error, UpdateError.checkFailed);
    });

    test('asks for permission, then installs on return to the app', () async {
      service.latest = releaseForTests();
      service.fakeInstaller.allowed = false;
      await controller().check();
      await controller().update();
      expect(state().step, UpdateStep.needsPermission);
      expect(service.fakeInstaller.installed, isEmpty);

      await controller().allowInstalls();
      expect(service.fakeInstaller.settingsOpened, 1);
      service.fakeInstaller.allowed = true;
      await controller().onResume();
      expect(state().step, UpdateStep.installing);
      expect(service.fakeInstaller.installed, ['/updates/Salio-11-arm64.apk']);
    });

    test('a download that keeps dropping carries on by itself', () {
      fakeAsync((async) {
        service
          ..latest = releaseForTests()
          ..dropsBeforeFinishing = 4;
        unawaited(controller().check());
        async.flushMicrotasks();
        unawaited(controller().update());
        async.elapse(const Duration(seconds: 30));
        expect(service.downloads, 5);
        expect(state().step, UpdateStep.installing);
      });
    });

    test('a failed download can be tried again', () async {
      service.latest = releaseForTests();
      service.downloadError = const UpdateException(UpdateFailure.damaged);
      await controller().check();
      await controller().update();
      expect(state().step, UpdateStep.failed);
      expect(state().error, UpdateError.damaged);

      service.downloadError = null;
      await controller().update();
      expect(state().step, UpdateStep.installing);
    });

    Future<void> settle() async {
      for (var i = 0; i < 5; i++) {
        await Future<void>.delayed(Duration.zero);
      }
    }

    test('on Wi-Fi it downloads by itself and waits for Restart', () async {
      service
        ..latest = releaseForTests()
        ..wifi = true;
      await controller().check();
      await settle();
      expect(service.downloads, 1);
      expect(state().step, UpdateStep.readyToInstall);
      expect(service.fakeInstaller.installed, isEmpty, reason: 'not asked');

      await controller().install();
      expect(state().step, UpdateStep.installing);
      expect(service.fakeInstaller.installed, ['/updates/Salio-11-arm64.apk']);
    });

    test('on mobile data nothing downloads until asked', () async {
      service.latest = releaseForTests();
      await controller().check();
      await settle();
      expect(service.downloads, 0);
      expect(state().step, UpdateStep.idle);
      expect(state().available, isTrue);
    });

    test('a download from before is ready at once, with no data', () async {
      service
        ..latest = releaseForTests()
        ..alreadyDownloaded = true;
      await controller().check();
      expect(service.downloads, 0);
      expect(state().step, UpdateStep.readyToInstall);
      await controller().install();
      expect(service.fakeInstaller.installed, hasLength(1));
    });

    test('a download on Wi-Fi that fails leaves the usual offer', () async {
      service
        ..latest = releaseForTests()
        ..wifi = true
        ..downloadError = const UpdateException(UpdateFailure.damaged);
      await controller().check();
      await settle();
      expect(state().step, UpdateStep.idle);
      expect(state().error, isNull);
      expect(state().available, isTrue);
    });

    test('follows what Android says about the install', () async {
      service
        ..latest = releaseForTests()
        ..alreadyDownloaded = true;
      await controller().check();
      final installer = service.fakeInstaller;

      await controller().install();
      installer.answer(const InstallResult(InstallOutcome.confirming));
      await settle();
      expect(state().step, UpdateStep.installing);

      // The user closed Android's confirm screen: offer Restart again.
      installer.answer(const InstallResult(InstallOutcome.cancelled));
      await settle();
      expect(state().step, UpdateStep.readyToInstall);

      await controller().install();
      installer.answer(
        const InstallResult(InstallOutcome.failed, 'INSTALL_FAILED_NO_SPACE'),
      );
      await settle();
      expect(state().step, UpdateStep.failed);
      expect(state().error, UpdateError.refused);
      expect(state().androidMessage, 'INSTALL_FAILED_NO_SPACE');

      // Try again reuses the file and installs.
      await controller().update();
      expect(state().step, UpdateStep.installing);
      expect(installer.installed, hasLength(3));
    });

    test('Android could not start the install', () async {
      container.dispose();
      use(
        FakeAppUpdateService(
          latest: releaseForTests(),
          installer: _RefusingInstaller(),
        )..alreadyDownloaded = true,
      );
      await controller().check();
      await controller().install();
      expect(state().step, UpdateStep.failed);
      expect(state().error, UpdateError.couldNotStart);
    });

    test('a phone type without an APK is not offered the update', () async {
      container.dispose();
      service = FakeAppUpdateService(latest: releaseForTests());
      container = ProviderContainer(
        overrides: fakeUpdateOverrides(service, 0, null),
      );
      await controller().check();
      expect(state().available, isFalse);
    });
  });

  test('a required update stops syncing, and touches nothing else', () async {
    final db = await seededDatabase();
    final requests = <String>[];
    final service = FakeAppUpdateService(
      latest: releaseForTests(build: 12, minBuild: 11),
    );
    final container = ProviderContainer(
      overrides: [
        ...fakeUpdateOverrides(service),
        sessionProvider.overrideWith(
          () => FixedSession(sessionFor(Role.owner)),
        ),
        databaseProvider.overrideWithValue(db),
        httpAdapterProvider.overrideWithValue(_Recorder(requests)),
      ],
    );
    addTearDown(() async {
      container.dispose();
      await db.close();
    });
    await container.read(sessionProvider.future);
    await container.read(appUpdateProvider.notifier).check();

    await container.read(syncProvider.notifier).syncNow();
    expect(container.read(syncProvider).blockedByUpdate, isTrue);
    expect(requests, isEmpty, reason: 'nothing sent to the server');
  });

  group('update screens', () {
    setUpAll(loadFonts);

    Future<AppUnderTest> openWith(
      WidgetTester tester,
      AppRelease release, {
      bool wifi = false,
      Locale locale = const Locale('en'),
    }) async {
      final app = await AppUnderTest.open(
        tester,
        role: Role.owner,
        route: '/customers',
        locale: locale,
        updates: FakeAppUpdateService(latest: release)..wifi = wifi,
      );
      await app.container.read(appUpdateProvider.notifier).check(manual: true);
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(milliseconds: 250));
      }
      return app;
    }

    testWidgets('a new version is offered and can be put off', (tester) async {
      final app = await openWith(tester, releaseForTests());
      try {
        expect(find.text('Version 2.0.11 is ready'), findsOneWidget);
        await tester.tap(find.text('Later'));
        await tester.pump(const Duration(milliseconds: 400));
        expect(find.text('Version 2.0.11 is ready'), findsNothing);
      } finally {
        await app.close();
      }
    });

    testWidgets('a required update keeps the app usable, with no Later', (
      tester,
    ) async {
      final app = await openWith(
        tester,
        releaseForTests(build: 12, minBuild: 11),
      );
      try {
        expect(find.text('Update to keep syncing'), findsOneWidget);
        expect(find.text('Later'), findsNothing);
        // The ledger is still there and usable.
        expect(find.text('Akinyi'), findsOneWidget);
        expect(find.byType(FloatingActionButton), findsOneWidget);
      } finally {
        await app.close();
      }
    });

    testWidgets('downloaded on Wi-Fi, one tap on Restart installs it', (
      tester,
    ) async {
      final service = FakeAppUpdateService(latest: releaseForTests())
        ..wifi = true;
      final app = await AppUnderTest.open(
        tester,
        role: Role.owner,
        route: '/customers',
        updates: service,
      );
      try {
        await app.container
            .read(appUpdateProvider.notifier)
            .check(manual: true);
        for (var i = 0; i < 4; i++) {
          await tester.pump(const Duration(milliseconds: 250));
        }
        expect(find.text('Version 2.0.11 is ready to install'), findsOneWidget);
        await tester.tap(find.text('Restart'));
        await tester.pump(const Duration(milliseconds: 400));
        expect(find.text('Updating Salio…'), findsOneWidget);
        expect(service.fakeInstaller.installed, hasLength(1));
      } finally {
        await app.close();
      }
    });

    testWidgets('in Swahili', (tester) async {
      final app = await openWith(
        tester,
        releaseForTests(),
        locale: const Locale('sw'),
      );
      try {
        expect(find.text('Toleo 2.0.11 liko tayari'), findsOneWidget);
        expect(find.text('Baadaye'), findsOneWidget);
      } finally {
        await app.close();
      }
    });

    testWidgets('More offers what the start-up check found, with notes', (
      tester,
    ) async {
      // A tall phone: the whole More page on screen at once.
      setView(tester, const Size(360, 1400));
      addTearDown(() => resetView(tester));
      final app = await AppUnderTest.open(
        tester,
        role: Role.owner,
        route: '/more',
        updates: FakeAppUpdateService(latest: releaseForTests()),
      );
      try {
        expect(find.text('App version 2.0.0'), findsOneWidget);
        expect(find.textContaining('Faster screens'), findsOneWidget);
        // One in the tile, one on the bar under the screen.
        expect(find.widgetWithText(FilledButton, 'Update'), findsNWidgets(2));
      } finally {
        await app.close();
      }
    });

    testWidgets('Check says when the app is up to date', (tester) async {
      setView(tester, const Size(360, 1400));
      addTearDown(() => resetView(tester));
      final app = await AppUnderTest.open(
        tester,
        role: Role.owner,
        route: '/more',
        updates: FakeAppUpdateService(),
      );
      try {
        await tester.tap(find.text('Check'));
        for (var i = 0; i < 4; i++) {
          await tester.pump(const Duration(milliseconds: 250));
        }
        expect(find.text('Up to date'), findsOneWidget);
      } finally {
        await app.close();
      }
    });
  });
}

/// Records requests and answers none, as if offline.
class _Recorder extends OfflineAdapter {
  final List<String> requests;

  _Recorder(this.requests);

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) {
    requests.add(options.path);
    return super.fetch(options, requestStream, cancelFuture);
  }
}

class _RefusingInstaller extends FakeInstaller {
  @override
  Future<bool> install(String path) async {
    installed.add(path);
    return false;
  }
}
