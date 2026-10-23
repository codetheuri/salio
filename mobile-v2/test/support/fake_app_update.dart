// Stand-ins for the in-app updater, so tests never reach the real server or
// Android's installer. From DairyGo.

import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:salio/features/app_update/data/app_release.dart';
import 'package:salio/features/app_update/data/app_update_service.dart';
import 'package:salio/features/app_update/presentation/app_update_controller.dart';

const installedForTests = InstalledApp(version: '2.0.0', build: 10);

AppRelease releaseForTests({
  int build = 11,
  int minBuild = 10,
  int rollout = 100,
}) => AppRelease(
  version: '2.0.$build',
  build: build,
  minBuild: minBuild,
  rolloutPercent: rollout,
  notes: const {'en': 'Faster screens', 'sw': 'Skrini za haraka'},
  files: const {
    'arm64': ReleaseFile(
      url: '/app/download/arm64',
      sha256: 'abc',
      size: 20 * 1024 * 1024,
    ),
  },
);

class FakeInstaller extends UpdateInstaller {
  bool allowed;
  final List<String> installed = [];
  int settingsOpened = 0;
  final String dir;
  final _results = StreamController<InstallResult>.broadcast();

  FakeInstaller({this.allowed = true, this.dir = '/nowhere'});

  /// Answers as Android would about the last install.
  void answer(InstallResult result) => _results.add(result);

  @override
  Stream<InstallResult> get results => _results.stream;

  @override
  Future<String> updatesDir() async => dir;

  @override
  Future<bool> canInstall() async => allowed;

  @override
  Future<bool> openSettings() async {
    settingsOpened++;
    return true;
  }

  @override
  Future<bool> install(String path) async {
    installed.add(path);
    return true;
  }
}

class FakeAppUpdateService extends AppUpdateService {
  AppRelease? latest;
  int checks = 0;
  Exception? checkError;

  /// Thrown by [download] instead of finishing, when set.
  Exception? downloadError;

  /// Downloads that stop part way, each bringing more bytes, before one
  /// finishes: a connection that keeps dropping.
  int dropsBeforeFinishing = 0;

  /// The phone is on Wi-Fi, so updates download by themselves.
  bool wifi = false;

  /// A finished download is already on the phone.
  bool alreadyDownloaded = false;
  int downloads = 0;
  int _part = 0;

  FakeAppUpdateService({this.latest, FakeInstaller? installer})
    : super(Dio(), installer ?? FakeInstaller());

  FakeInstaller get fakeInstaller => installer as FakeInstaller;

  @override
  Future<AppRelease?> fetchLatest() async {
    checks++;
    if (checkError != null) throw checkError!;
    return latest;
  }

  @override
  Future<bool> onWifi() async => wifi;

  @override
  Future<String?> downloaded(AppRelease release, String abi) async =>
      alreadyDownloaded ? '/updates/Salio-${release.build}-$abi.apk' : null;

  @override
  Future<int> partSize(AppRelease release, String abi) async => _part;

  @override
  Future<String> download(
    AppRelease release,
    String abi, {
    CancelToken? cancel,
    void Function(int received, int total)? onProgress,
  }) async {
    downloads++;
    final size = release.files[abi]!.size;
    if (dropsBeforeFinishing > 0) {
      dropsBeforeFinishing--;
      _part += size ~/ 10;
      onProgress?.call(_part, size);
      throw const UpdateException(UpdateFailure.stopped);
    }
    onProgress?.call(size ~/ 2, size);
    if (downloadError != null) throw downloadError!;
    onProgress?.call(size, size);
    return '/updates/Salio-${release.build}-$abi.apk';
  }

  @override
  Future<void> removeOldDownloads({int? keepBuild}) async {}
}

/// Overrides that put the updater on [service] (nothing published by
/// default), with this app at [installedForTests] on a phone of type [abi]
/// (null: one no APK is built for) in rollout bucket [bucket].
List<Override> fakeUpdateOverrides([
  FakeAppUpdateService? service,
  int bucket = 0,
  String? abi = 'arm64',
]) => [
  appUpdateServiceProvider.overrideWithValue(service ?? FakeAppUpdateService()),
  installedAppProvider.overrideWith((ref) async => installedForTests),
  deviceAbiProvider.overrideWithValue(abi),
  installBucketProvider.overrideWith((ref) async => bucket),
];
